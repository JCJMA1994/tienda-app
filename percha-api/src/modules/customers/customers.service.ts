import { ConflictException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { and, desc, eq, ilike, isNull, or, sql } from 'drizzle-orm';
import { z } from 'zod';
import type { AuthUser } from '../../common/auth-user';
import { DatabaseService, Tx } from '../../database/database.service';
import { customers, layaways, saleItems, sales, storeCredits, variants } from '../../database/schema';
import { EventBus } from '../../common/events';
import { AuditService } from '../audit/audit.service';

const docFields = {
  docType: z.enum(['dni', 'ruc', 'ce']).nullable().optional(),
  docNumber: z.string().trim().max(15).nullable().optional(),
};

const CustomerBase = z.object({
    ...docFields,
    name: z.string().trim().min(2).max(120),
    phone: z
      .string()
      .trim()
      .regex(/^\+?\d{6,15}$/)
      .nullable()
      .optional(),
    email: z.string().trim().email().max(120).nullable().optional(),
    birthday: z
      .string()
      .regex(/^(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/, 'Formato MM-DD')
      .nullable()
      .optional(),
    notes: z.string().trim().max(500).nullable().optional(),
    /** Permiso EXPLÍCITO del cliente para recibir WhatsApp de la tienda. */
    whatsappOptIn: z.boolean().optional(),
});

const docOk = (c: { docType?: string | null; docNumber?: string | null }) =>
  (c.docType ? Boolean(c.docNumber) : !c.docNumber) &&
  (c.docType !== 'dni' || /^\d{8}$/.test(c.docNumber ?? '')) &&
  (c.docType !== 'ruc' || /^\d{11}$/.test(c.docNumber ?? ''));
const DOC_MESSAGE = 'Documento inválido: DNI de 8 dígitos o RUC de 11, con su tipo';

export const CustomerSchema = CustomerBase.refine(docOk, DOC_MESSAGE);
export const UpdateCustomerSchema = CustomerBase.partial().refine(docOk, DOC_MESSAGE);

export const ListCustomersSchema = z.object({
  search: z.string().trim().max(60).optional(),
  limit: z.coerce.number().int().min(1).max(100).default(30),
});

/**
 * Clientes: ficha, historial y preferencias (talla habitual). Se crean solos cuando una venta
 * lleva DNI/RUC en el comprobante, o a mano desde el POS. Datos personales (Ley 29733): lo
 * mínimo, permiso explícito para WhatsApp y anonimización a pedido.
 */
@Injectable()
export class CustomersService {
  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(AuditService) private readonly audit: AuditService,
    @Inject(EventBus) bus: EventBus,
  ) {
    // Cliente de la venta: el elegido en el POS o el del comprobante identificado (DNI/RUC/CE).
    bus.on('sale.recorded', 'asociar cliente a la venta', async (tx, e) => {
      const c = e.document?.customer;
      const customerId =
        e.customerId ??
        (c?.docNumber && c.docType !== 'none' && c.name?.trim()
          ? await this.fromDocument(tx, e.user.tenantId, { docType: c.docType, docNumber: c.docNumber.trim(), name: c.name.trim() })
          : null);
      if (customerId) await tx.update(sales).set({ customerId }).where(eq(sales.id, e.saleId));
    });
  }

  list(user: AuthUser, q: z.infer<typeof ListCustomersSchema>) {
    return this.db.withTenant(user.tenantId, (tx) => {
      const term = q.search ? `%${q.search.replace(/[%_\\]/g, '\\$&')}%` : null;
      return tx
        .select({ id: customers.id, name: customers.name, docType: customers.docType, docNumber: customers.docNumber, phone: customers.phone, whatsappOptIn: customers.whatsappOptIn })
        .from(customers)
        .where(and(isNull(customers.anonymizedAt), term ? or(ilike(customers.name, term), ilike(customers.docNumber, term), ilike(customers.phone, term)) : undefined))
        .orderBy(desc(customers.updatedAt))
        .limit(q.limit);
    });
  }

  create(user: AuthUser, input: z.infer<typeof CustomerSchema>) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      if (input.docType && input.docNumber) {
        const [dup] = await tx.select({ id: customers.id }).from(customers).where(and(eq(customers.docType, input.docType), eq(customers.docNumber, input.docNumber)));
        if (dup) throw new ConflictException({ message: 'Ya existe un cliente con ese documento', code: 'CUSTOMER_EXISTS', customerId: dup.id });
      }
      const [row] = await tx
        .insert(customers)
        .values({ tenantId: user.tenantId, ...input, whatsappOptIn: input.whatsappOptIn ?? false, whatsappOptInAt: input.whatsappOptIn ? new Date() : null })
        .returning();
      return row;
    });
  }

  update(user: AuthUser, id: string, input: z.infer<typeof UpdateCustomerSchema>) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [current] = await tx.select().from(customers).where(eq(customers.id, id));
      if (!current || current.anonymizedAt) throw new NotFoundException('Cliente no encontrado');
      const optInChanged = input.whatsappOptIn !== undefined && input.whatsappOptIn !== current.whatsappOptIn;
      const [row] = await tx
        .update(customers)
        .set({ ...input, ...(optInChanged && { whatsappOptInAt: input.whatsappOptIn ? new Date() : null }), updatedAt: new Date() })
        .where(eq(customers.id, id))
        .returning();
      if (optInChanged) await this.audit.log(tx, user, input.whatsappOptIn ? 'customer.whatsapp_opt_in' : 'customer.whatsapp_opt_out', 'customer', id);
      return row;
    });
  }

  /** Ficha con estadísticas: compras, gasto neto, última visita y talla más comprada. */
  get(user: AuthUser, id: string) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [c] = await tx.select().from(customers).where(eq(customers.id, id));
      if (!c || c.anonymizedAt) throw new NotFoundException('Cliente no encontrado');
      const [stats] = await tx
        .select({
          purchases: sql<number>`count(*)::int`,
          spentCents: sql<number>`coalesce(sum(${sales.totalCents}), 0)::int`,
          lastPurchaseAt: sql<string | null>`max(${sales.createdAt})`,
        })
        .from(sales)
        .where(and(eq(sales.customerId, id), eq(sales.status, 'completed')));
      const sizes = await tx
        .select({ size: sql<string>`${variants.options}->>'Talla'`, units: sql<number>`sum(${saleItems.quantity})::int` })
        .from(saleItems)
        .innerJoin(sales, eq(sales.id, saleItems.saleId))
        .innerJoin(variants, eq(variants.id, saleItems.variantId))
        .where(and(eq(sales.customerId, id), eq(sales.status, 'completed'), sql`${variants.options} ? 'Talla'`))
        .groupBy(sql`${variants.options}->>'Talla'`)
        .orderBy(sql`sum(${saleItems.quantity}) desc`)
        .limit(3);
      const recent = await tx
        .select({ id: sales.id, number: sales.number, totalCents: sales.totalCents, status: sales.status, createdAt: sales.createdAt })
        .from(sales)
        .where(eq(sales.customerId, id))
        .orderBy(desc(sales.createdAt))
        .limit(20);
      // Saldo a favor vigente y apartados abiertos: lo que el vendedor debe recordarle al cliente.
      const [credit] = await tx
        .select({ c: sql<number>`coalesce(sum(${storeCredits.balanceCents}), 0)::int` })
        .from(storeCredits)
        .where(and(eq(storeCredits.customerId, id), sql`(${storeCredits.expiresAt} is null or ${storeCredits.expiresAt} > now())`));
      const [open] = await tx.select({ c: sql<number>`count(*)::int` }).from(layaways).where(and(eq(layaways.customerId, id), eq(layaways.status, 'open')));
      return { ...c, stats: { ...stats, topSizes: sizes.map((s) => s.size), creditBalanceCents: credit.c, openLayaways: open.c }, recentSales: recent };
    });
  }

  /**
   * Derecho de cancelación (ARCO): borra los datos personales y conserva las ventas (que son
   * registros contables) asociadas a un cliente anónimo. Irreversible.
   */
  anonymize(user: AuthUser, id: string) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [row] = await tx
        .update(customers)
        .set({ name: 'Cliente anonimizado', docType: null, docNumber: null, phone: null, email: null, birthday: null, notes: null, whatsappOptIn: false, whatsappOptInAt: null, anonymizedAt: new Date(), updatedAt: new Date() })
        .where(and(eq(customers.id, id), isNull(customers.anonymizedAt)))
        .returning({ id: customers.id });
      if (!row) throw new NotFoundException('Cliente no encontrado');
      await this.audit.log(tx, user, 'customer.anonymized', 'customer', id);
      return { ok: true };
    });
  }

  /**
   * Para ventas con comprobante identificado: busca el cliente por documento o lo crea con el
   * nombre del comprobante. No pisa datos que el equipo ya cargó.
   */
  async fromDocument(tx: Tx, tenantId: string, doc: { docType: string; docNumber: string | null; name: string }) {
    if (!doc.docNumber || !['dni', 'ruc', 'ce'].includes(doc.docType)) return null;
    const [existing] = await tx.select({ id: customers.id }).from(customers).where(and(eq(customers.docType, doc.docType), eq(customers.docNumber, doc.docNumber)));
    if (existing) {
      await tx.update(customers).set({ updatedAt: new Date() }).where(eq(customers.id, existing.id));
      return existing.id;
    }
    const [row] = await tx.insert(customers).values({ tenantId, docType: doc.docType, docNumber: doc.docNumber, name: doc.name }).returning({ id: customers.id });
    return row.id;
  }
}
