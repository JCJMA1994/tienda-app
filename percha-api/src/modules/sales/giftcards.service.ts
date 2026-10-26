import { eq } from 'drizzle-orm';
import { IdempotencyService } from '../../common/idempotency';
import { BadRequestException, Inject, Injectable } from '@nestjs/common';
import { z } from 'zod';
import { assertBranchAccess, AuthUser } from '../../common/auth-user';
import { cents } from '../../common/schemas';
import { DatabaseService } from '../../database/database.service';
import { payments, storeCredits } from '../../database/schema';
import { CreditsService } from '../credits/credits.service';
import { CashService } from './cash.service';
import { assertPaymentsMatch, PaymentSchema } from './sales.service';

export const SellGiftCardSchema = z.object({
  branchId: z.string().uuid(),
  amountCents: cents.refine((n) => n >= 1000 && n <= 500_000, 'Entre S/ 10 y S/ 5,000'),
  customerId: z.string().uuid().optional(),
  validDays: z.number().int().min(30).max(1095).default(365),
  payments: z.array(PaymentSchema.omit({ creditCode: true }).extend({ method: z.enum(['cash', 'card', 'wallet', 'transfer']) })).min(1).max(3),
});

/**
 * Venta de gift card: el dinero entra a caja ahora y el vale se usa después como medio de pago.
 * No se emite boleta al venderla (todavía no se vende mercadería): el comprobante sale cuando se
 * canjea, por las prendas que se lleva.
 */
@Injectable()
export class GiftCardsService {
  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(CashService) private readonly cash: CashService,
    @Inject(CreditsService) private readonly credits: CreditsService,
    @Inject(IdempotencyService) private readonly idem: IdempotencyService,
  ) {}

  sell(user: AuthUser, input: z.infer<typeof SellGiftCardSchema>, idempotencyKey?: string) {
    assertBranchAccess(user, input.branchId);
    return this.db.withTenant(user.tenantId, async (tx) =>
      this.idem.once(tx, user.tenantId, idempotencyKey, 'giftcard.sell', input, async () => {
      const session = await this.cash.requireOpen(tx, input.branchId);
      assertPaymentsMatch(input.payments, input.amountCents);
      if (input.payments.some((p) => p.amountCents <= 0)) throw new BadRequestException('Montos inválidos');
      const credit = await this.credits.issueTx(tx, user, { kind: 'gift', amountCents: input.amountCents, customerId: input.customerId, validDays: input.validDays, note: 'Gift card' });
      await tx.insert(payments).values(
        input.payments.map((p) => ({ tenantId: user.tenantId, cashSessionId: session.id, storeCreditId: credit.id, method: p.method, amountCents: p.amountCents, reference: `Gift card …${credit.last4}` })),
      );
      return credit;
    }, (c) => c.id, async (cid) => { const [c] = await tx.select().from(storeCredits).where(eq(storeCredits.id, cid)); return { id: c.id, kind: c.kind, last4: c.codeLast4, initialCents: c.initialCents, balanceCents: c.balanceCents, expiresAt: c.expiresAt, status: 'active', customerId: c.customerId, createdAt: c.createdAt, code: undefined as unknown as string, replayed: true }; }));
  }
}
