import { Inject, Injectable } from '@nestjs/common';
import { DomainError } from '../../common/domain-error';
import { and, desc, eq, gt, gte, isNull, or, sql } from 'drizzle-orm';
import { randomInt } from 'node:crypto';
import { z } from 'zod';
import type { AuthUser } from '../../common/auth-user';
import { cents } from '../../common/schemas';
import { DatabaseService, Tx } from '../../database/database.service';
import { customers, storeCreditMovements, storeCredits } from '../../database/schema';
import { AuditService } from '../audit/audit.service';
import { sha256 } from '../../common/crypto';

/** Sin letras confusas (0/O, 1/I/L): se dicta por teléfono o se copia de un ticket. */
const ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

export function newCreditCode() {
  const chars = Array.from({ length: 12 }, () => ALPHABET[randomInt(ALPHABET.length)]).join('');
  return `VALE-${chars.slice(0, 4)}-${chars.slice(4, 8)}-${chars.slice(8)}`;
}

/** Acepta mayúsculas/minúsculas, con o sin guiones o espacios, con o sin "VALE". */
export function normalizeCreditCode(raw: string) {
  const clean = raw.toUpperCase().replace(/[\s-]/g, '').replace(/^VALE/, '');
  return /^[2-9A-HJKMNP-Z]{12}$/.test(clean) ? `VALE-${clean.slice(0, 4)}-${clean.slice(4, 8)}-${clean.slice(8)}` : null;
}

export const IssueCreditSchema = z.object({
  kind: z.enum(['gift', 'courtesy']),
  amountCents: cents.refine((n) => n > 0 && n <= 1_000_000, 'Entre S/ 0.01 y S/ 10,000'),
  customerId: z.string().uuid().optional(),
  /** Días de vigencia (por defecto 365). */
  validDays: z.number().int().min(1).max(1095).default(365),
  note: z.string().trim().max(200).optional(),
});

/**
 * Vales y saldo a favor.
 *
 * - **refund**: devolución sin reembolso en dinero (la venta original ya tuvo su nota de crédito).
 * - **gift**: gift card pagada por el cliente (entra a caja; el comprobante se emite cuando se USA,
 *   porque recién ahí hay venta de mercadería).
 * - **courtesy**: cortesía de la tienda (requiere permiso de anular ventas y queda auditada).
 *
 * El código es un título al portador: se muestra UNA vez (para imprimirlo o enviarlo) y se guarda
 * solo su hash. Usar un vale es un UPDATE condicional (saldo suficiente, vigente) dentro de la
 * transacción de la venta: dos cajas no pueden gastar el mismo saldo.
 */
@Injectable()
export class CreditsService {
  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(AuditService) private readonly audit: AuditService,
  ) {}

  async issueTx(
    tx: Tx,
    user: AuthUser,
    p: { kind: 'refund' | 'gift' | 'courtesy'; amountCents: number; customerId?: string | null; validDays?: number; note?: string },
  ) {
    const code = newCreditCode();
    const [credit] = await tx
      .insert(storeCredits)
      .values({
        tenantId: user.tenantId,
        codeHash: sha256(code),
        codeLast4: code.slice(-4),
        kind: p.kind,
        customerId: p.customerId ?? null,
        initialCents: p.amountCents,
        balanceCents: p.amountCents,
        expiresAt: new Date(Date.now() + (p.validDays ?? 365) * 86_400_000),
        note: p.note,
        issuedBy: user.membershipId,
      })
      .returning();
    await tx.insert(storeCreditMovements).values({ tenantId: user.tenantId, creditId: credit.id, type: 'issue', deltaCents: p.amountCents, balanceAfter: p.amountCents, createdBy: user.membershipId });
    await this.audit.log(tx, user, 'store_credit.issued', 'store_credit', credit.id, { kind: p.kind, amountCents: p.amountCents });
    return { ...this.present(credit), code };
  }

  /** Cortesía (sin cobro). Las gift cards pagadas se venden con `sellGiftCard`. */
  issueCourtesy(user: AuthUser, input: z.infer<typeof IssueCreditSchema>) {
    return this.db.withTenant(user.tenantId, (tx) => this.issueTx(tx, user, { ...input, kind: 'courtesy' }));
  }

  /** Descuenta saldo de forma atómica. Devuelve el vale usado. */
  async redeemTx(tx: Tx, user: AuthUser, rawCode: string, amountCents: number, saleId: string) {
    const code = normalizeCreditCode(rawCode);
    if (!code) throw DomainError.invalid('CREDIT_INVALID', 'Código de vale inválido');
    const [credit] = await tx
      .update(storeCredits)
      .set({ balanceCents: sql`${storeCredits.balanceCents} - ${amountCents}` })
      .where(
        and(
          eq(storeCredits.codeHash, sha256(code)),
          gte(storeCredits.balanceCents, amountCents),
          or(isNull(storeCredits.expiresAt), gt(storeCredits.expiresAt, new Date())),
        ),
      )
      .returning();
    if (!credit) {
      // Mensaje preciso (ya validó el formato; el código no se adivina por fuerza bruta: 60 bits).
      const [existing] = await tx.select().from(storeCredits).where(eq(storeCredits.codeHash, sha256(code)));
      if (!existing) throw DomainError.rule('CREDIT_NOT_FOUND', 'Vale no encontrado');
      if (existing.expiresAt && existing.expiresAt <= new Date()) throw DomainError.rule('CREDIT_EXPIRED', 'El vale venció');
      throw DomainError.rule('CREDIT_INSUFFICIENT', `Saldo insuficiente en el vale (quedan ${(existing.balanceCents / 100).toFixed(2)})`, { balanceCents: existing.balanceCents });
    }
    await tx.insert(storeCreditMovements).values({ tenantId: user.tenantId, creditId: credit.id, type: 'redeem', deltaCents: -amountCents, balanceAfter: credit.balanceCents, saleId, createdBy: user.membershipId });
    return credit;
  }

  /** Al anular una venta pagada con vale, el saldo vuelve. */
  async restoreTx(tx: Tx, user: AuthUser, creditId: string, amountCents: number, saleId: string) {
    const [credit] = await tx
      .update(storeCredits)
      .set({ balanceCents: sql`${storeCredits.balanceCents} + ${amountCents}` })
      .where(eq(storeCredits.id, creditId))
      .returning();
    await tx.insert(storeCreditMovements).values({ tenantId: user.tenantId, creditId, type: 'restore', deltaCents: amountCents, balanceAfter: credit.balanceCents, saleId, createdBy: user.membershipId });
  }

  /** Consultar un vale antes de cobrar (saldo y vigencia). */
  lookup(user: AuthUser, rawCode: string) {
    const code = normalizeCreditCode(rawCode);
    if (!code) throw DomainError.invalid('CREDIT_INVALID', 'Código de vale inválido');
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [c] = await tx
        .select({ credit: storeCredits, customerName: customers.name })
        .from(storeCredits)
        .leftJoin(customers, eq(customers.id, storeCredits.customerId))
        .where(eq(storeCredits.codeHash, sha256(code)));
      if (!c) throw DomainError.notFound('CREDIT_NOT_FOUND', 'Vale no encontrado');
      return { ...this.present(c.credit), customerName: c.customerName };
    });
  }

  /** Vales de un cliente (para la ficha): sin códigos, solo últimos 4 y saldos. */
  forCustomer(user: AuthUser, customerId: string) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const rows = await tx.select().from(storeCredits).where(eq(storeCredits.customerId, customerId)).orderBy(desc(storeCredits.createdAt));
      return rows.map((r) => this.present(r));
    });
  }

  private present(c: typeof storeCredits.$inferSelect) {
    const expired = Boolean(c.expiresAt && c.expiresAt <= new Date());
    return {
      id: c.id,
      kind: c.kind,
      last4: c.codeLast4,
      initialCents: c.initialCents,
      balanceCents: c.balanceCents,
      expiresAt: c.expiresAt,
      status: expired ? 'expired' : c.balanceCents === 0 ? 'used' : 'active',
      customerId: c.customerId,
      createdAt: c.createdAt,
    };
  }
}
