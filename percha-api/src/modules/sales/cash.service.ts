import { ConflictException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { and, desc, eq, inArray, isNotNull, isNull, sql } from 'drizzle-orm';
import { z } from 'zod';
import { assertBranchAccess, AuthUser } from '../../common/auth-user';
import { cents } from '../../common/schemas';
import { DatabaseService, Tx } from '../../database/database.service';
import { branches, cashSessions, memberships, payments, returns, sales, users } from '../../database/schema';
import { AuditService } from '../audit/audit.service';

export const OpenCashSchema = z.object({ branchId: z.string().uuid(), openingCents: cents });
export const CloseCashSchema = z.object({ countedCashCents: cents });

/**
 * Turnos de caja. El efectivo esperado al cierre se CALCULA (apertura + pagos en efectivo
 * − reembolsos en efectivo); el cajero solo declara lo que contó. La diferencia queda registrada.
 */
@Injectable()
export class CashService {
  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(AuditService) private readonly audit: AuditService,
  ) {}

  open(user: AuthUser, input: z.infer<typeof OpenCashSchema>) {
    assertBranchAccess(user, input.branchId);
    return this.db.withTenant(user.tenantId, async (tx) => {
      // El índice único parcial (una abierta por sucursal) protege ante dos aperturas simultáneas.
      const [existing] = await tx
        .select({ id: cashSessions.id })
        .from(cashSessions)
        .where(and(eq(cashSessions.branchId, input.branchId), eq(cashSessions.status, 'open')));
      if (existing) throw new ConflictException('Ya hay una caja abierta en esta sucursal');
      const [row] = await tx
        .insert(cashSessions)
        .values({ tenantId: user.tenantId, branchId: input.branchId, openedBy: user.membershipId, openingCents: input.openingCents })
        .returning();
      return row;
    });
  }

  current(user: AuthUser, branchId: string) {
    assertBranchAccess(user, branchId);
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [row] = await tx
        .select()
        .from(cashSessions)
        .where(and(eq(cashSessions.branchId, branchId), eq(cashSessions.status, 'open')));
      if (!row) throw new NotFoundException('No hay caja abierta');
      return { ...row, summary: await this.summary(tx, row.id, row.openingCents) };
    });
  }

  close(user: AuthUser, id: string, input: z.infer<typeof CloseCashSchema>) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      // FOR UPDATE: espera a que terminen las ventas en curso (que toman FOR SHARE) antes de cerrar.
      const [session] = await tx.select().from(cashSessions).where(eq(cashSessions.id, id)).for('update');
      if (!session) throw new NotFoundException('Caja no encontrada');
      assertBranchAccess(user, session.branchId);
      if (session.status !== 'open') throw new ConflictException('La caja ya está cerrada');

      const summary = await this.summary(tx, id, session.openingCents);
      const difference = input.countedCashCents - summary.expectedCashCents;
      const [row] = await tx
        .update(cashSessions)
        .set({
          status: 'closed',
          closedBy: user.membershipId,
          closedAt: new Date(),
          expectedCashCents: summary.expectedCashCents,
          countedCashCents: input.countedCashCents,
          differenceCents: difference,
        })
        .where(eq(cashSessions.id, id))
        .returning();
      await this.audit.log(tx, user, 'cash.closed', 'cash_session', id, { expected: summary.expectedCashCents, counted: input.countedCashCents, difference });
      return { ...row, summary };
    });
  }

  /** Cajas recientes de una sucursal (para reimprimir cierres). */
  list(user: AuthUser, branchId: string, limit = 30) {
    assertBranchAccess(user, branchId);
    return this.db.withTenant(user.tenantId, (tx) =>
      tx.select().from(cashSessions).where(eq(cashSessions.branchId, branchId)).orderBy(desc(cashSessions.openedAt)).limit(Math.min(limit, 100)),
    );
  }

  /**
   * Reporte de cierre (o parcial, si sigue abierta): para imprimir en el ticket de 80 mm.
   * Medios de pago, ventas y anulaciones, devoluciones, abonos de apartados, y el arqueo.
   */
  report(user: AuthUser, id: string) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [session] = await tx.select().from(cashSessions).where(eq(cashSessions.id, id));
      if (!session) throw new NotFoundException('Caja no encontrada');
      assertBranchAccess(user, session.branchId);
      const summary = await this.summary(tx, id, session.openingCents);
      const [{ count, totalCents, voidedCount, voidedCents }] = await tx
        .select({
          count: sql<number>`count(*) filter (where ${sales.status} = 'completed')::int`,
          totalCents: sql<number>`coalesce(sum(${sales.totalCents}) filter (where ${sales.status} = 'completed'), 0)::int`,
          voidedCount: sql<number>`count(*) filter (where ${sales.status} = 'voided')::int`,
          voidedCents: sql<number>`coalesce(sum(${sales.totalCents}) filter (where ${sales.status} = 'voided'), 0)::int`,
        })
        .from(sales)
        .where(eq(sales.cashSessionId, id));
      const [ret] = await tx
        .select({ count: sql<number>`count(*)::int`, differenceCents: sql<number>`coalesce(sum(${returns.differenceCents}), 0)::int` })
        .from(returns)
        .where(eq(returns.cashSessionId, id));
      const [lay] = await tx
        .select({ count: sql<number>`count(*)::int`, totalCents: sql<number>`coalesce(sum(${payments.amountCents}), 0)::int` })
        .from(payments)
        .where(and(eq(payments.cashSessionId, id), isNotNull(payments.layawayId), isNull(payments.saleId)));
      const names = await tx
        .select({ id: memberships.id, name: users.name })
        .from(memberships)
        .innerJoin(users, eq(users.id, memberships.userId))
        .where(inArray(memberships.id, [session.openedBy, ...(session.closedBy ? [session.closedBy] : [])]));
      const [branch] = await tx.select({ name: branches.name }).from(branches).where(eq(branches.id, session.branchId));
      const nameOf = (mid: string | null) => names.find((n) => n.id === mid)?.name ?? null;
      return {
        id: session.id,
        branchName: branch?.name ?? '',
        status: session.status,
        openedAt: session.openedAt,
        openedBy: nameOf(session.openedBy),
        closedAt: session.closedAt,
        closedBy: nameOf(session.closedBy),
        openingCents: session.openingCents,
        byMethod: summary.byMethod,
        sales: { count, totalCents, voidedCount, voidedCents },
        returns: { count: ret.count, differenceCents: ret.differenceCents },
        layawayPayments: { count: lay.count, totalCents: lay.totalCents },
        expectedCashCents: session.expectedCashCents ?? summary.expectedCashCents,
        countedCashCents: session.countedCashCents,
        differenceCents: session.differenceCents,
      };
    });
  }

  /** Caja abierta de la sucursal, bloqueada en modo compartido mientras dura la venta. */
  async requireOpen(tx: Tx, branchId: string) {
    const [session] = await tx
      .select()
      .from(cashSessions)
      .where(and(eq(cashSessions.branchId, branchId), eq(cashSessions.status, 'open')))
      .for('share');
    if (!session) throw new ConflictException({ message: 'Abre la caja antes de vender', code: 'CASH_CLOSED' });
    return session;
  }

  private async summary(tx: Tx, sessionId: string, openingCents: number) {
    const byMethod = await tx
      .select({ method: payments.method, totalCents: sql<number>`coalesce(sum(${payments.amountCents}),0)::int` })
      .from(payments)
      .where(eq(payments.cashSessionId, sessionId))
      .groupBy(payments.method);
    const cash = byMethod.find((m) => m.method === 'cash')?.totalCents ?? 0;
    return { openingCents, byMethod, expectedCashCents: openingCents + cash };
  }
}
