import { BadRequestException, ConflictException, ForbiddenException, Inject, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { randomBytes } from 'node:crypto';
import { and, eq, isNotNull, isNull, or, sql } from 'drizzle-orm';
import { z } from 'zod';
import type { AuthUser } from '../../common/auth-user';
import { assertBranchAccess } from '../../common/auth-user';
import { DatabaseService, Tx } from '../../database/database.service';
import { branches, invitations, memberships, passwordResets, platformAdmins, recoveryCodes, tenants, users } from '../../database/schema';
import { ENV, Env } from '../../config/env';
import { EmailService } from '../email/email.service';
import { open, seal } from '../../common/crypto';
import { newTotpSecret, otpauthUri, verifyTotp } from './totp';
import { ROLE_PERMISSIONS } from '../../common/authz/permissions';
import { BillingService } from '../billing/billing.service';
import { EventBus } from '../../common/events';
import { AttemptsService, LOGIN_POLICY, PIN_POLICY } from '../security/attempts.service';
import { hashSecret, newOpaqueToken, normalizeEmail, sha256, verifySecret } from '../../common/crypto';
import { SessionMembership, TokenService } from './token.service';

export const RegisterSchema = z.object({
  storeName: z.string().trim().min(2).max(80),
  ownerName: z.string().trim().min(2).max(80),
  email: z.string().email(),
  password: z.string().min(8).max(128),
});

export const LoginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
  tenantId: z.string().uuid().optional(),
});

export const PinSchema = z.object({
  branchId: z.string().uuid(),
  pin: z.string().regex(/^\d{4,6}$/),
});

export const ChangePasswordSchema = z
  .object({
    currentPassword: z.string().min(1),
    newPassword: z
      .string()
      .min(8)
      .max(128)
      .regex(/[A-Za-z]/, 'Usa letras y números')
      .regex(/\d/, 'Usa letras y números'),
  })
  .refine((v) => v.currentPassword !== v.newPassword, 'La nueva contraseña debe ser distinta');

export const TwoFactorVerifySchema = z
  .object({
    challenge: z.string().min(20),
    code: z.string().regex(/^\d{6}$/).optional(),
    recoveryCode: z.string().trim().min(8).max(20).optional(),
    tenantId: z.string().uuid().optional(),
  });

export const TwoFactorDisableSchema = z.object({
  password: z.string().min(1),
  code: z.string().regex(/^\d{6}$/).optional(),
  recoveryCode: z.string().trim().min(8).max(20).optional(),
});

const newPassword = z.string().min(8).max(128).regex(/[A-Za-z]/, 'Usa letras y números').regex(/\d/, 'Usa letras y números');
export const ForgotPasswordSchema = z.object({ email: z.string().email() });
export const ResetPasswordSchema = z.object({ token: z.string().min(20), newPassword });

export const AcceptInvitationSchema = z.object({
  token: z.string().min(20),
  name: z.string().trim().min(2).max(80).optional(),
  password: z.string().min(8).max(128),
});

/** Comparación siempre costosa aunque el email no exista: evita enumerar usuarios por tiempo de respuesta. */
const DUMMY_HASH = hashSecret('percha-dummy-password');

@Injectable()
export class AuthService {
  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(TokenService) private readonly tokens: TokenService,
    @Inject(BillingService) private readonly billing: BillingService,
    @Inject(EventBus) private readonly events: EventBus,
    @Inject(AttemptsService) private readonly attempts: AttemptsService,
    @Inject(EmailService) private readonly email: EmailService,
    @Inject(JwtService) private readonly jwt: JwtService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  /** Crea tienda + sucursal principal + dueño en una sola transacción. */
  register(input: z.infer<typeof RegisterSchema>) {
    const email = normalizeEmail(input.email);
    return this.db.withSystem(async (tx) => {
      let user = await this.findUserByEmail(tx, email);
      if (user) {
        // Un usuario existente puede abrir otra tienda, pero debe probar que es él.
        if (!(await verifySecret(user.passwordHash, input.password))) {
          throw new ConflictException('Este correo ya está registrado. Inicia sesión para crear otra tienda.');
        }
      } else {
        [user] = await tx
          .insert(users)
          .values({ email, name: input.ownerName, passwordHash: await hashSecret(input.password) })
          .returning();
      }

      const [tenant] = await tx.insert(tenants).values({ name: input.storeName }).returning();
      await tx.insert(branches).values({ tenantId: tenant.id, name: 'Tienda principal', isDefault: true });
      // Cada tienda nueva arranca con su periodo de prueba (misma transacción: todo o nada).
      await this.billing.startTrial(tx, tenant.id);
      const [membership] = await tx
        .insert(memberships)
        .values({ tenantId: tenant.id, userId: user.id, role: 'owner' })
        .returning();

      // Cuenta existente con 2FA: no se emite sesión solo con la contraseña.
      if (user.totpEnabledAt) return { tenantId: tenant.id, ...this.twoFactorChallenge(user.id, tenant.id, false) };
      const tokens = await this.tokens.issue(tx, this.toSession(membership));
      return { tenantId: tenant.id, ...tokens };
    });
  }

  /**
   * Si el usuario pertenece a varias tiendas y no indicó cuál, devolvemos la lista
   * para que la app muestre el selector (la contraseña ya fue verificada).
   */
  async login(input: z.infer<typeof LoginSchema>) {
    const email = normalizeEmail(input.email);
    // El bloqueo es por correo (exista o no la cuenta): no revela qué correos están registrados.
    const key = `login:${email}`;
    await this.attempts.assertNotLocked(key);
    try {
      const result = await this.loginTx(email, input);
      await this.attempts.reset(key);
      return result;
    } catch (e) {
      if (e instanceof UnauthorizedException) await this.attempts.fail(key, LOGIN_POLICY);
      throw e;
    }
  }

  private loginTx(email: string, input: z.infer<typeof LoginSchema>) {
    return this.db.withSystem(async (tx) => {
      const user = await this.findUserByEmail(tx, email);
      const valid = await verifySecret(user?.passwordHash ?? (await DUMMY_HASH), input.password);
      if (!user || !valid) throw new UnauthorizedException('Correo o contraseña incorrectos');
      // Con verificación en dos pasos: la contraseña sola no basta; se pide el código.
      if (user.totpEnabledAt) return this.twoFactorChallenge(user.id, input.tenantId, false);
      return this.completeLogin(tx, user.id, input.tenantId);
    });
  }

  /** Elegir tienda y emitir sesión (después de contraseña y, si aplica, segundo factor). */
  private async completeLogin(tx: Tx, userId: string, tenantId: string | undefined, verified2fa = false) {
      const options = await tx
        .select({ membership: memberships, tenantName: tenants.name })
        .from(memberships)
        .innerJoin(tenants, eq(tenants.id, memberships.tenantId))
        .where(and(eq(memberships.userId, userId), eq(memberships.status, 'active'), eq(tenants.status, 'active')));

      if (!options.length) throw new ForbiddenException('No tienes acceso a ninguna tienda activa');

      const chosen = tenantId
        ? options.find((o) => o.membership.tenantId === tenantId)
        : options.length === 1
          ? options[0]
          : undefined;

      if (!chosen) {
        if (tenantId) throw new ForbiddenException('No perteneces a esa tienda');
        return {
          requiresTenantSelection: true as const,
          tenants: options.map((o) => ({ tenantId: o.membership.tenantId, name: o.tenantName, role: o.membership.role })),
          // Si ya pasó el segundo factor, puede elegir tienda sin volver a ingresar el código.
          ...(verified2fa && { challenge: this.twoFactorChallenge(userId, undefined, true).challenge }),
        };
      }
      return this.tokens.issue(tx, this.toSession(chosen.membership));
  }

  // ---------------------------------------------------------------- verificación en dos pasos

  /** Desafío firmado de 5 minutos (audiencia distinta: no sirve como sesión). */
  private twoFactorChallenge(userId: string, tenantId: string | undefined, verified: boolean) {
    const challenge = this.jwt.sign({ sub: userId, tid: tenantId, v: verified }, { audience: 'percha-2fa', expiresIn: 300 });
    return { requiresTwoFactor: !verified, challenge };
  }

  async verifyTwoFactor(input: z.infer<typeof TwoFactorVerifySchema>) {
    let payload: { sub: string; tid?: string; v: boolean };
    try {
      payload = await this.jwt.verifyAsync(input.challenge, { audience: 'percha-2fa' });
    } catch {
      throw new UnauthorizedException('El código venció: vuelve a iniciar sesión');
    }
    if (!payload.v) {
      const key = `2fa:${payload.sub}`;
      await this.attempts.assertNotLocked(key);
      const ok = await this.checkSecondFactor(payload.sub, input.code, input.recoveryCode);
      if (!ok) {
        await this.attempts.fail(key, LOGIN_POLICY);
        throw new UnauthorizedException('Código incorrecto');
      }
      await this.attempts.reset(key);
    }
    return this.db.withSystem((tx) => this.completeLogin(tx, payload.sub, input.tenantId ?? payload.tid, true));
  }

  private async checkSecondFactor(userId: string, code?: string, recovery?: string) {
    return this.db.withSystem(async (tx) => {
      const [u] = await tx.select().from(users).where(eq(users.id, userId));
      if (!u?.totpSecretEnc || !u.totpEnabledAt) return false;
      if (code) return verifyTotp(open(u.totpSecretEnc, this.secretsKey), code);
      if (recovery) {
        // Código de recuperación: un solo uso.
        const used = await tx
          .update(recoveryCodes)
          .set({ usedAt: new Date() })
          .where(and(eq(recoveryCodes.userId, userId), eq(recoveryCodes.codeHash, sha256(recovery.trim().toUpperCase())), isNull(recoveryCodes.usedAt)))
          .returning({ id: recoveryCodes.id });
        return used.length > 0;
      }
      return false;
    });
  }

  /** Paso 1: genera el secreto (aún no activo) y el enlace otpauth:// para la app autenticadora. */
  setupTwoFactor(user: AuthUser) {
    return this.db.withSystem(async (tx) => {
      const [u] = await tx.select().from(users).where(eq(users.id, user.userId));
      if (u.totpEnabledAt) throw new ConflictException('La verificación en dos pasos ya está activa');
      const secret = newTotpSecret();
      await tx.update(users).set({ totpSecretEnc: seal(secret, this.secretsKey) }).where(eq(users.id, user.userId));
      return { secret, otpauthUri: otpauthUri(secret, u.email) };
    });
  }

  /** Paso 2: confirma con un código y entrega 10 códigos de recuperación (se muestran UNA vez). */
  async enableTwoFactor(user: AuthUser, code: string) {
    return this.db.withSystem(async (tx) => {
      const [u] = await tx.select().from(users).where(eq(users.id, user.userId));
      if (!u.totpSecretEnc) throw new BadRequestException('Primero genera el código QR');
      if (u.totpEnabledAt) throw new ConflictException('La verificación en dos pasos ya está activa');
      if (!verifyTotp(open(u.totpSecretEnc, this.secretsKey), code)) throw new UnauthorizedException('Código incorrecto: revisa la hora del teléfono');
      const codes = Array.from({ length: 10 }, () => {
        const raw = randomBytes(5).toString('hex').toUpperCase();
        return `${raw.slice(0, 5)}-${raw.slice(5)}`;
      });
      await tx.delete(recoveryCodes).where(eq(recoveryCodes.userId, user.userId));
      await tx.insert(recoveryCodes).values(codes.map((c) => ({ userId: user.userId, codeHash: sha256(c) })));
      await tx.update(users).set({ totpEnabledAt: new Date() }).where(eq(users.id, user.userId));
      return { enabled: true, recoveryCodes: codes };
    });
  }

  /** Desactivar exige contraseña Y código (o un código de recuperación). */
  async disableTwoFactor(user: AuthUser, input: z.infer<typeof TwoFactorDisableSchema>) {
    const key = `2fa:${user.userId}`;
    await this.attempts.assertNotLocked(key);
    const [u] = await this.db.withSystem((tx) => tx.select().from(users).where(eq(users.id, user.userId)));
    const ok = (await verifySecret(u.passwordHash, input.password)) && (await this.checkSecondFactor(user.userId, input.code, input.recoveryCode));
    if (!ok) {
      await this.attempts.fail(key, LOGIN_POLICY);
      throw new UnauthorizedException('Contraseña o código incorrectos');
    }
    await this.db.withSystem(async (tx) => {
      await tx.update(users).set({ totpEnabledAt: null, totpSecretEnc: null }).where(eq(users.id, user.userId));
      await tx.delete(recoveryCodes).where(eq(recoveryCodes.userId, user.userId));
    });
    return { enabled: false };
  }

  private get secretsKey() {
    const k = this.env.SECRETS_ENC_KEY ?? this.env.EINVOICE_ENC_KEY;
    if (!k) throw new BadRequestException('El servidor no tiene SECRETS_ENC_KEY configurada');
    return k;
  }

  // ---------------------------------------------------------------- recuperar contraseña

  /**
   * Siempre responde lo mismo, exista o no el correo (no revela cuentas). El enlace dura 30 min,
   * es de un solo uso y solo se guarda su hash. Pedir uno nuevo invalida los anteriores.
   */
  async forgotPassword(emailRaw: string) {
    const email = normalizeEmail(emailRaw);
    const user = await this.db.withSystem((tx) => this.findUserByEmail(tx, email));
    if (!user) return { ok: true };
    const { token, hash } = newOpaqueToken();
    await this.db.withSystem(async (tx) => {
      await tx.update(passwordResets).set({ usedAt: new Date() }).where(and(eq(passwordResets.userId, user.id), isNull(passwordResets.usedAt)));
      await tx.insert(passwordResets).values({ userId: user.id, tokenHash: hash, expiresAt: new Date(Date.now() + 30 * 60_000) });
    });
    const link = `${this.env.APP_URL}/reset?token=${token}`;
    await this.email.send({
      to: user.email,
      subject: 'Restablece tu contraseña de Percha',
      text: `Hola ${user.name}:\n\nPara crear una nueva contraseña entra aquí (vence en 30 minutos):\n${link}\n\nSi no lo pediste, ignora este correo: tu contraseña sigue igual.`,
      html: `<p>Hola ${escapeHtml(user.name)}:</p><p>Para crear una nueva contraseña entra aquí (vence en 30 minutos):</p><p><a href="${link}">Restablecer contraseña</a></p><p>Si no lo pediste, ignora este correo: tu contraseña sigue igual.</p>`,
    });
    return { ok: true };
  }

  /** Cambia la contraseña, cierra TODAS las sesiones y desbloquea el login de esa cuenta. */
  async resetPassword(input: z.infer<typeof ResetPasswordSchema>) {
    const userId = await this.db.withSystem(async (tx) => {
      const [r] = await tx.select().from(passwordResets).where(eq(passwordResets.tokenHash, sha256(input.token))).for('update');
      if (!r || r.usedAt || r.expiresAt < new Date()) return null;
      await tx.update(passwordResets).set({ usedAt: new Date() }).where(eq(passwordResets.id, r.id));
      await tx.update(users).set({ passwordHash: await hashSecret(input.newPassword) }).where(eq(users.id, r.userId));
      return r.userId;
    });
    if (!userId) throw new UnauthorizedException('El enlace venció o ya se usó. Pide uno nuevo.');
    await this.tokens.revokeAll(userId);
    const [u] = await this.db.withSystem((tx) => tx.select({ email: users.email }).from(users).where(eq(users.id, userId)));
    await this.attempts.reset(`login:${normalizeEmail(u.email)}`);
    return { ok: true };
  }

  /**
   * Cambio rápido de vendedor en el POS: sobre una sesión ya abierta en la tablet,
   * el vendedor ingresa su PIN y obtiene su propia sesión. Las ventas quedan a su nombre.
   */
  async switchByPin(current: AuthUser, input: z.infer<typeof PinSchema>) {
    assertBranchAccess(current, input.branchId);
    const key = `pin:${current.tenantId}:${input.branchId}`;
    await this.attempts.assertNotLocked(key);
    const candidates = await this.db.withTenant(current.tenantId, (tx) =>
      tx
        .select()
        .from(memberships)
        .where(
          and(
            eq(memberships.status, 'active'),
            isNotNull(memberships.pinHash),
            or(isNull(memberships.branchId), eq(memberships.branchId, input.branchId)),
          ),
        ),
    );
    for (const m of candidates) {
      if (await verifySecret(m.pinHash!, input.pin)) {
        await this.attempts.reset(key);
        return this.tokens.issueStandalone(this.toSession(m));
      }
    }
    await this.attempts.fail(key, PIN_POLICY);
    throw new UnauthorizedException('PIN incorrecto');
  }

  acceptInvitation(input: z.infer<typeof AcceptInvitationSchema>) {
    return this.db.withSystem(async (tx) => {
      const [inv] = await tx
        .select()
        .from(invitations)
        .where(eq(invitations.tokenHash, sha256(input.token)))
        .for('update');
      if (!inv || inv.acceptedAt || inv.expiresAt < new Date()) {
        throw new UnauthorizedException('Invitación inválida o vencida');
      }

      let user = await this.findUserByEmail(tx, inv.email);
      if (user) {
        if (!(await verifySecret(user.passwordHash, input.password))) {
          throw new UnauthorizedException('Ya tienes cuenta: usa tu contraseña actual para aceptar');
        }
      } else {
        if (!input.name) throw new ConflictException('Indica tu nombre para crear la cuenta');
        [user] = await tx
          .insert(users)
          .values({ email: inv.email, name: input.name, passwordHash: await hashSecret(input.password) })
          .returning();
      }

      const [membership] = await tx
        .insert(memberships)
        .values({ tenantId: inv.tenantId, userId: user.id, role: inv.role, branchId: inv.branchId })
        .onConflictDoUpdate({
          target: [memberships.tenantId, memberships.userId],
          set: { role: inv.role, branchId: inv.branchId, status: 'active' },
        })
        .returning();
      await tx.update(invitations).set({ acceptedAt: new Date() }).where(eq(invitations.id, inv.id));
      await this.events.publish(tx, { type: 'team.member_joined', tenantId: inv.tenantId, membershipId: membership.id, name: user.name });

      // Cuenta existente con 2FA: aceptar no emite sesión solo con la contraseña.
      if (user.totpEnabledAt) return this.twoFactorChallenge(user.id, inv.tenantId, false);
      return this.tokens.issue(tx, this.toSession(membership));
    });
  }

  /**
   * Cambiar contraseña: exige la actual, cierra TODAS las demás sesiones (si alguien la
   * conocía, queda afuera) y devuelve una sesión nueva para este dispositivo.
   */
  async changePassword(user: AuthUser, input: z.infer<typeof ChangePasswordSchema>) {
    const key = `password:${user.userId}`;
    await this.attempts.assertNotLocked(key);
    const ok = await this.db.withSystem(async (tx) => {
      const [u] = await tx.select().from(users).where(eq(users.id, user.userId));
      if (!u || !(await verifySecret(u.passwordHash, input.currentPassword))) return false;
      await tx.update(users).set({ passwordHash: await hashSecret(input.newPassword) }).where(eq(users.id, user.userId));
      return true;
    });
    if (!ok) {
      await this.attempts.fail(key, LOGIN_POLICY);
      throw new UnauthorizedException('La contraseña actual no es correcta');
    }
    await this.attempts.reset(key);
    await this.tokens.revokeAll(user.userId);
    return this.tokens.issueStandalone(user);
  }

  /** "Cerrar sesión en todos los dispositivos" (p. ej. si perdiste el teléfono). */
  async logoutEverywhere(user: AuthUser) {
    await this.tokens.revokeAll(user.userId);
  }

  me(user: AuthUser) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [row] = await tx
        .select({ name: users.name, email: users.email, tenantName: tenants.name })
        .from(users)
        .innerJoin(tenants, eq(tenants.id, user.tenantId))
        .where(eq(users.id, user.userId));
      // Solo informativo para mostrar el backoffice en la app; los endpoints /admin lo
      // verifican de nuevo en la BD en cada request.
      const [admin] = await this.db.withSystem((sys) => sys.select().from(platformAdmins).where(eq(platformAdmins.userId, user.userId)));
      return {
        ...row,
        ...user,
        isPlatformAdmin: Boolean(admin),
        twoFactorEnabled: Boolean(await this.db.withSystem(async (sys) => (await sys.select({ on: users.totpEnabledAt }).from(users).where(eq(users.id, user.userId)))[0]?.on)),
        permissions: [...ROLE_PERMISSIONS[user.role]],
      };
    });
  }

  private async findUserByEmail(tx: Tx, email: string) {
    const [user] = await tx.select().from(users).where(sql`lower(${users.email}) = ${email}`);
    return user;
  }

  private toSession(m: typeof memberships.$inferSelect): SessionMembership {
    return { userId: m.userId, tenantId: m.tenantId, membershipId: m.id, role: m.role, branchId: m.branchId };
  }
}

const escapeHtml = (s: string) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);
