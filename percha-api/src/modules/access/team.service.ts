import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { and, eq, isNotNull, isNull, ne, or, sql } from 'drizzle-orm';
import { z } from 'zod';
import type { AuthUser } from '../../common/auth-user';
import { ENV, Env } from '../../config/env';
import { DatabaseService, Tx } from '../../database/database.service';
import { invitations, memberships, users } from '../../database/schema';
import { AuditService } from '../audit/audit.service';
import { LimitsService } from '../billing/limits.service';
import { hashSecret, newOpaqueToken, normalizeEmail, verifySecret } from '../../common/crypto';
import { ASSIGNABLE_ROLES, hasPermission, Role } from '../../common/authz/permissions';

const role = z.enum(['owner', 'manager', 'seller', 'stock']);

export const InviteSchema = z.object({
  email: z.string().email(),
  role,
  branchId: z.string().uuid().nullable().default(null),
});

export const UpdateMemberSchema = z
  .object({
    role: role.optional(),
    branchId: z.string().uuid().nullable().optional(),
    status: z.enum(['active', 'disabled']).optional(),
    /** Comisión en puntos básicos (300 = 3 %); null = sin comisión. */
    commissionBp: z.number().int().min(0).max(5000).nullable().optional(),
  })
  .refine((v) => Object.keys(v).length > 0, 'Nada que actualizar');

export const SetPinSchema = z.object({ pin: z.string().regex(/^\d{4,6}$/, 'El PIN debe tener 4 a 6 dígitos') });

@Injectable()
export class TeamService {
  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(AuditService) private readonly audit: AuditService,
    @Inject(ENV) private readonly env: Env,
    @Inject(LimitsService) private readonly limits: LimitsService,
  ) {}

  listMembers(user: AuthUser) {
    return this.db.withTenant(user.tenantId, (tx) =>
      tx
        .select({
          commissionBp: memberships.commissionBp,
          id: memberships.id,
          name: users.name,
          email: users.email,
          role: memberships.role,
          branchId: memberships.branchId,
          status: memberships.status,
          hasPin: sql<boolean>`${memberships.pinHash} is not null`,
        })
        .from(memberships)
        .innerJoin(users, eq(users.id, memberships.userId))
        .orderBy(memberships.createdAt),
    );
  }

  updateMember(actor: AuthUser, memberId: string, input: z.infer<typeof UpdateMemberSchema>) {
    const onlyCommission = Object.keys(input).every((k) => k === 'commissionBp');
    if (memberId === actor.membershipId && !onlyCommission) throw new ForbiddenException('No puedes cambiar tu propio rol o estado');
    return this.db.withTenant(actor.tenantId, async (tx) => {
      const target = await this.getManageable(tx, actor, memberId);
      if (input.role) this.assertAssignable(actor, input.role);
      if (input.branchId !== undefined) this.assertBranchAssignable(actor, input.branchId);

      const losesOwner = target.role === 'owner' && ((input.role && input.role !== 'owner') || input.status === 'disabled');
      if (losesOwner) await this.assertAnotherOwner(tx, target.id);

      const [updated] = await tx
        .update(memberships)
        .set({ role: input.role, branchId: input.branchId, status: input.status, commissionBp: input.commissionBp })
        .where(eq(memberships.id, memberId))
        .returning({ id: memberships.id, role: memberships.role, branchId: memberships.branchId, status: memberships.status, commissionBp: memberships.commissionBp });

      await this.audit.log(tx, actor, 'member.updated', 'membership', memberId, { before: { role: target.role, branchId: target.branchId, status: target.status }, after: input });
      return updated;
    });
  }

  /**
   * El PIN debe ser único entre quienes comparten sucursal: si dos vendedores tuvieran el
   * mismo PIN, el cambio rápido en el POS no sabría a quién asignar la venta.
   */
  setPin(actor: AuthUser, memberId: string, pin: string) {
    return this.db.withTenant(actor.tenantId, async (tx) => {
      const target =
        memberId === actor.membershipId
          ? (await tx.select().from(memberships).where(eq(memberships.id, memberId)))[0]
          : await this.getManageable(tx, actor, memberId);
      if (!target) throw new NotFoundException('Miembro no encontrado');

      const branchFilter = target.branchId
        ? or(isNull(memberships.branchId), eq(memberships.branchId, target.branchId))
        : undefined; // sin sucursal fija: coincide con todos
      const others = await tx
        .select({ pinHash: memberships.pinHash })
        .from(memberships)
        .where(and(ne(memberships.id, target.id), isNotNull(memberships.pinHash), branchFilter));
      for (const o of others) {
        if (await verifySecret(o.pinHash!, pin)) throw new ConflictException('Ese PIN ya está en uso, elige otro');
      }

      await tx.update(memberships).set({ pinHash: await hashSecret(pin) }).where(eq(memberships.id, target.id));
      await this.audit.log(tx, actor, 'member.pin_set', 'membership', target.id);
    });
  }

  invite(actor: AuthUser, input: z.infer<typeof InviteSchema>) {
    this.assertAssignable(actor, input.role);
    this.assertBranchAssignable(actor, input.branchId);
    const email = normalizeEmail(input.email);

    return this.db.withTenant(actor.tenantId, async (tx) => {
      const existing = await tx
        .select({ id: memberships.id })
        .from(memberships)
        .innerJoin(users, eq(users.id, memberships.userId))
        .where(and(sql`lower(${users.email}) = ${email}`, eq(memberships.status, 'active')));
      if (existing.length) throw new ConflictException('Esa persona ya es parte del equipo');
      // Una invitación pendiente ocupa un cupo de usuario del plan.
      await this.limits.assertCanAdd(tx, actor.tenantId, 'members');

      const { token, hash } = newOpaqueToken();
      const expiresAt = new Date(Date.now() + this.env.INVITATION_TTL_HOURS * 3_600_000);
      const [inv] = await tx
        .insert(invitations)
        .values({ tenantId: actor.tenantId, email, role: input.role, branchId: input.branchId, tokenHash: hash, invitedBy: actor.membershipId, expiresAt })
        .returning({ id: invitations.id, email: invitations.email, role: invitations.role, expiresAt: invitations.expiresAt });
      await this.audit.log(tx, actor, 'invitation.created', 'invitation', inv.id, { email, role: input.role });
      // El token se muestra UNA vez (para el enlace). En BD solo queda su hash.
      return { ...inv, token };
    });
  }

  listInvitations(actor: AuthUser) {
    return this.db.withTenant(actor.tenantId, (tx) =>
      tx
        .select({ id: invitations.id, email: invitations.email, role: invitations.role, branchId: invitations.branchId, expiresAt: invitations.expiresAt })
        .from(invitations)
        .where(isNull(invitations.acceptedAt)),
    );
  }

  revokeInvitation(actor: AuthUser, id: string) {
    return this.db.withTenant(actor.tenantId, async (tx) => {
      const deleted = await tx
        .delete(invitations)
        .where(and(eq(invitations.id, id), isNull(invitations.acceptedAt)))
        .returning({ id: invitations.id });
      if (!deleted.length) throw new NotFoundException('Invitación no encontrada');
    });
  }

  // ---- reglas -------------------------------------------------------------

  private async getManageable(tx: Tx, actor: AuthUser, memberId: string) {
    const [target] = await tx.select().from(memberships).where(eq(memberships.id, memberId));
    if (!target) throw new NotFoundException('Miembro no encontrado');
    if (!hasPermission(actor.role, 'team.manage')) throw new ForbiddenException('Permisos insuficientes');
    if (!ASSIGNABLE_ROLES[actor.role].includes(target.role)) {
      throw new ForbiddenException('No puedes gestionar a alguien con ese rol');
    }
    if (actor.branchId && target.branchId !== actor.branchId) {
      throw new ForbiddenException('Solo puedes gestionar al equipo de tu sucursal');
    }
    return target;
  }

  private assertAssignable(actor: AuthUser, role: Role) {
    if (!ASSIGNABLE_ROLES[actor.role].includes(role)) throw new ForbiddenException(`No puedes asignar el rol ${role}`);
  }

  private assertBranchAssignable(actor: AuthUser, branchId: string | null) {
    if (actor.branchId && branchId !== actor.branchId) {
      throw new BadRequestException('Solo puedes asignar personas a tu sucursal');
    }
  }

  private async assertAnotherOwner(tx: Tx, excludeId: string) {
    const [{ count }] = await tx
      .select({ count: sql<number>`count(*)::int` })
      .from(memberships)
      .where(and(eq(memberships.role, 'owner'), eq(memberships.status, 'active'), ne(memberships.id, excludeId)));
    if (count === 0) throw new ConflictException('La tienda debe tener al menos un dueño activo');
  }
}
