import { Inject, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { and, eq, isNull } from 'drizzle-orm';
import { ENV, Env } from '../../config/env';
import { DatabaseService, Tx } from '../../database/database.service';
import { memberships, refreshTokens, tenants } from '../../database/schema';
import type { AccessTokenPayload } from '../access/guards';
import type { Role } from '../../common/authz/permissions';
import { newOpaqueToken, sha256 } from '../../common/crypto';

export interface SessionMembership {
  userId: string;
  tenantId: string;
  membershipId: string;
  role: Role;
  branchId: string | null;
}

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
}

/**
 * Emisión y rotación de tokens.
 * - Access token (JWT) corto: no se consulta la BD en cada request.
 * - Refresh token opaco y rotativo: cada uso lo invalida y entrega uno nuevo.
 *   Si llega un refresh ya usado, asumimos robo y cerramos todas las sesiones del usuario.
 */
@Injectable()
export class TokenService {
  constructor(
    private readonly jwt: JwtService,
    private readonly db: DatabaseService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  async issue(tx: Tx, m: SessionMembership, replaces?: string): Promise<TokenPair> {
    const payload: AccessTokenPayload = { sub: m.userId, tid: m.tenantId, mid: m.membershipId, role: m.role, bid: m.branchId };
    const accessToken = await this.jwt.signAsync(payload, { expiresIn: this.env.JWT_ACCESS_TTL_SECONDS });
    const { token, hash } = newOpaqueToken();
    const expiresAt = new Date(Date.now() + this.env.REFRESH_TOKEN_TTL_DAYS * 86_400_000);
    const [row] = await tx
      .insert(refreshTokens)
      .values({ userId: m.userId, membershipId: m.membershipId, tokenHash: hash, expiresAt })
      .returning({ id: refreshTokens.id });
    if (replaces) {
      await tx.update(refreshTokens).set({ revokedAt: new Date(), replacedBy: row.id }).where(eq(refreshTokens.id, replaces));
    }
    return { accessToken, refreshToken: token, expiresIn: this.env.JWT_ACCESS_TTL_SECONDS };
  }

  /** Emite tokens en su propia transacción de sistema. */
  issueStandalone(m: SessionMembership) {
    return this.db.withSystem((tx) => this.issue(tx, m));
  }

  async rotate(refreshToken: string): Promise<TokenPair> {
    type Outcome = { kind: 'reused'; userId: string } | { kind: 'ok'; pair: TokenPair };
    const result = await this.db.withSystem<Outcome>(async (tx) => {
      const [current] = await tx
        .select()
        .from(refreshTokens)
        .where(eq(refreshTokens.tokenHash, sha256(refreshToken)))
        .for('update');
      if (!current) throw new UnauthorizedException('Sesión inválida');
      // Reuso de un token ya rotado: posible robo. Se maneja FUERA de esta transacción
      // porque lanzar el error aquí haría rollback de la revocación.
      if (current.revokedAt) return { kind: 'reused', userId: current.userId };
      if (current.expiresAt < new Date()) throw new UnauthorizedException('Sesión expirada');

      // Se relee la membresía: cambios de rol o bajas se reflejan al refrescar.
      const [m] = await tx
        .select({ membership: memberships, tenantStatus: tenants.status })
        .from(memberships)
        .innerJoin(tenants, eq(tenants.id, memberships.tenantId))
        .where(eq(memberships.id, current.membershipId));
      if (!m || m.membership.status !== 'active' || m.tenantStatus !== 'active') {
        throw new UnauthorizedException('Acceso desactivado');
      }

      const pair = await this.issue(
        tx,
        {
          userId: m.membership.userId,
          tenantId: m.membership.tenantId,
          membershipId: m.membership.id,
          role: m.membership.role,
          branchId: m.membership.branchId,
        },
        current.id,
      );
      return { kind: 'ok', pair };
    });

    if (result.kind === 'reused') {
      await this.db.withSystem((tx) =>
        tx
          .update(refreshTokens)
          .set({ revokedAt: new Date() })
          .where(and(eq(refreshTokens.userId, result.userId), isNull(refreshTokens.revokedAt))),
      );
      throw new UnauthorizedException('Sesión revocada por seguridad. Vuelve a iniciar sesión.');
    }
    return result.pair;
  }

  /** Revoca todas las sesiones activas de un usuario. */
  revokeAll(userId: string) {
    return this.db.withSystem((tx) =>
      tx.update(refreshTokens).set({ revokedAt: new Date() }).where(and(eq(refreshTokens.userId, userId), isNull(refreshTokens.revokedAt))),
    );
  }

  revoke(refreshToken: string) {
    return this.db.withSystem((tx) =>
      tx.update(refreshTokens).set({ revokedAt: new Date() }).where(eq(refreshTokens.tokenHash, sha256(refreshToken))),
    );
  }
}
