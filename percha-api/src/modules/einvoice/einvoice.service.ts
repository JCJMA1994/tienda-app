import { BadRequestException, ConflictException, Inject, Injectable, Logger, NotFoundException } from '@nestjs/common';
import { and, asc, desc, eq, inArray, lt, or, sql } from 'drizzle-orm';
import { z } from 'zod';
import type { AuthUser } from '../../common/auth-user';
import { ENV, Env } from '../../config/env';
import { DatabaseService, Tx } from '../../database/database.service';
import { nextNumber } from '../../database/sequences';
import { branches, einvoiceDocuments, einvoiceSeries, einvoiceSettings, products, tenants, variants } from '../../database/schema';
import { EventBus } from '../../common/events';
import { localDate } from '../../common/dates';
import { BOLETA_ANON_LIMIT_CENTS, buildItems, EDoc, EDocCustomer, LineInput, normalizeCustomer, totalsOf } from './document';
import { EGuide, Shipment, validateShipment } from './guide';

export type { LineInput };
import { EINVOICE_PROVIDERS, EInvoiceProvider, OseUnavailableError } from './providers/provider';
import { open, seal } from '../../common/crypto';

const serie = (prefix: 'B' | 'F' | 'T') => z.string().regex(new RegExp(`^${prefix}[A-Z0-9]{3}$`), `Serie de 4 caracteres que empiece con ${prefix}`);

export const SettingsSchema = z.object({
  enabled: z.boolean(),
  provider: z.string().min(2),
  legalName: z.string().trim().min(2).max(200),
  fiscalAddress: z.string().trim().min(5).max(300),
  apiUrl: z.string().url(),
  /** Solo se envía para cambiarlo; nunca se devuelve. */
  token: z.string().min(10).optional(),
  series: z
    .array(
      z.object({
        branchId: z.string().uuid(),
        boleta: serie('B'),
        factura: serie('F'),
        ncBoleta: serie('B'),
        ncFactura: serie('F'),
        /** Guía de remisión remitente (traslados entre sucursales). Empieza con T. */
        guia: serie('T').optional(),
      }),
    )
    .min(1),
});

export const DocumentRequestSchema = z.object({
  type: z.enum(['boleta', 'factura']),
  customer: z
    .object({
      docType: z.enum(['none', 'dni', 'ruc', 'ce']),
      docNumber: z.string().trim().max(15).optional(),
      name: z.string().trim().max(200).optional(),
      address: z.string().trim().max(300).optional(),
    })
    .optional(),
});

export const ListSchema = z.object({
  status: z.enum(['pending', 'accepted', 'rejected', 'error']).optional(),
  limit: z.coerce.number().int().min(1).max(200).default(50),
});

type DocRow = typeof einvoiceDocuments.$inferSelect;
export interface SaleLineRef {
  variantId: string;
  quantity: number;
  amountCents: number;
}

/**
 * Facturación electrónica SUNAT a través de un OSE/PSE (Nubefact u otro adaptador).
 *
 * Patrón "outbox": el comprobante se NUMERA y GUARDA en la misma transacción de la venta
 * (correlativo sin huecos, nunca se pierde), y se ENVÍA al OSE después del commit. Si el OSE
 * está caído, la venta igual se completa y el envío se reintenta (job + botón "Reintentar").
 *
 * Correcciones siempre con NOTA DE CRÉDITO (anulación → motivo 01, devolución → motivo 07):
 * un comprobante emitido no se edita ni se borra.
 */
@Injectable()
export class EInvoiceService {
  private readonly logger = new Logger('EInvoice');

  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(EINVOICE_PROVIDERS) private readonly providers: EInvoiceProvider[],
    @Inject(ENV) private readonly env: Env,
    @Inject(EventBus) private readonly events: EventBus,
  ) {}

  // ---------------------------------------------------------------- configuración

  getSettings(user: AuthUser) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [s] = await tx.select().from(einvoiceSettings);
      const series = await tx.select().from(einvoiceSeries);
      const byBranch = new Map<string, Record<string, string>>();
      for (const r of series) byBranch.set(r.branchId, { ...(byBranch.get(r.branchId) ?? {}), [r.kind]: r.serie });
      return {
        enabled: s?.enabled ?? false,
        provider: s?.provider ?? 'nubefact',
        legalName: s?.legalName ?? null,
        fiscalAddress: s?.fiscalAddress ?? null,
        apiUrl: s?.apiUrl ?? null,
        hasToken: Boolean(s?.tokenEnc),
        series: [...byBranch.entries()].map(([branchId, k]) => ({ branchId, boleta: k.boleta, factura: k.factura, ncBoleta: k.nc_boleta, ncFactura: k.nc_factura, guia: k.guia ?? null })),
        providers: this.providers.map((p) => p.name),
      };
    });
  }

  /** Lo mínimo que necesita el POS (cualquier vendedor): si emitir y el tope de boleta anónima. */
  status(user: AuthUser) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [s] = await tx.select({ enabled: einvoiceSettings.enabled }).from(einvoiceSettings);
      return { enabled: s?.enabled ?? false, boletaAnonLimitCents: BOLETA_ANON_LIMIT_CENTS };
    });
  }

  saveSettings(user: AuthUser, input: z.infer<typeof SettingsSchema>) {
    if (!this.providers.some((p) => p.name === input.provider)) throw new BadRequestException(`OSE "${input.provider}" no disponible`);
    if (input.token && !this.env.EINVOICE_ENC_KEY) throw new BadRequestException('El servidor no tiene EINVOICE_ENC_KEY configurada');
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [current] = await tx.select().from(einvoiceSettings);
      const tokenEnc = input.token ? seal(input.token, this.env.EINVOICE_ENC_KEY!) : current?.tokenEnc ?? null;
      if (input.enabled && !tokenEnc) throw new BadRequestException('Falta el token del OSE');
      const values = {
        enabled: input.enabled,
        provider: input.provider,
        legalName: input.legalName,
        fiscalAddress: input.fiscalAddress,
        apiUrl: input.apiUrl,
        tokenEnc,
        updatedAt: new Date(),
      };
      await tx.insert(einvoiceSettings).values({ tenantId: user.tenantId, ...values }).onConflictDoUpdate({ target: einvoiceSettings.tenantId, set: values });

      for (const s of input.series) {
        for (const [kind, value] of [
          ['boleta', s.boleta],
          ['factura', s.factura],
          ['nc_boleta', s.ncBoleta],
          ['nc_factura', s.ncFactura],
          ...(s.guia ? ([['guia', s.guia]] as const) : []),
        ] as const) {
          await tx
            .insert(einvoiceSeries)
            .values({ tenantId: user.tenantId, branchId: s.branchId, kind, serie: value })
            .onConflictDoUpdate({ target: [einvoiceSeries.tenantId, einvoiceSeries.branchId, einvoiceSeries.kind], set: { serie: value } });
        }
      }
      return this.getSettingsTx(tx);
    });
  }

  private async getSettingsTx(tx: Tx) {
    const [s] = await tx.select({ enabled: einvoiceSettings.enabled }).from(einvoiceSettings);
    return { enabled: s?.enabled ?? false };
  }

  // ---------------------------------------------------------------- emisión (dentro de la transacción de negocio)

  /** Comprobante de una venta. Devuelve null si la tienda no tiene facturación electrónica. */
  async issueForSale(
    tx: Tx,
    user: AuthUser,
    p: { saleId: string; branchId: string; lines: SaleLineRef[]; request?: z.infer<typeof DocumentRequestSchema>; issuedAt?: Date },
  ): Promise<DocRow | null> {
    const ctx = await this.context(tx);
    if (!ctx) {
      if (p.request) throw new BadRequestException('La tienda no tiene facturación electrónica activada');
      return null;
    }
    const kind = p.request?.type ?? 'boleta';
    const items = buildItems(await this.lineInputs(tx, p.lines), ctx.taxRateBp, ctx.pricesIncludeTax);
    const totals = totalsOf(items);
    const customer = normalizeCustomer(kind, totals.totalCents, p.request?.customer);
    return this.insert(tx, user, ctx, { kind, seriesKind: kind, branchId: p.branchId, saleId: p.saleId, customer, items, issuedAt: p.issuedAt });
  }

  /**
   * Nota de crédito sobre un comprobante. Si el original fue rechazado no existe para SUNAT,
   * así que no hace falta nota. Para anulación total se copian los ítems del original.
   */
  async issueCreditNote(
    tx: Tx,
    user: AuthUser,
    p: { source: DocRow; branchId: string; returnId?: string; reasonCode: '01' | '07'; reasonText: string; lines?: SaleLineRef[] },
  ): Promise<DocRow | null> {
    if (p.source.status === 'rejected' || p.source.kind === 'nota_credito') return null;
    const ctx = await this.context(tx);
    if (!ctx) return null;
    const original = p.source.payload as EDoc;
    // Los montos de devolución ya vienen con IGV (al precio cobrado).
    const items = p.lines ? buildItems(await this.lineInputs(tx, p.lines), original.taxRateBp, true) : original.items;
    return this.insert(tx, user, ctx, {
      kind: 'nota_credito',
      seriesKind: p.source.kind === 'factura' ? 'nc_factura' : 'nc_boleta',
      branchId: p.branchId,
      saleId: p.source.saleId,
      returnId: p.returnId,
      referenceId: p.source.id,
      customer: original.customer,
      items,
      reference: { kind: p.source.kind as 'boleta' | 'factura', serie: p.source.serie, numero: p.source.numero, reasonCode: p.reasonCode, reasonText: p.reasonText },
    });
  }

  /** Prendas entregadas en un cambio: nuevo comprobante del mismo tipo y cliente que el original. */
  async issueReplacement(tx: Tx, user: AuthUser, p: { source: DocRow; branchId: string; returnId: string; lines: SaleLineRef[] }) {
    const ctx = await this.context(tx);
    if (!ctx || p.source.kind === 'nota_credito') return null;
    const original = p.source.payload as EDoc;
    const items = buildItems(await this.lineInputs(tx, p.lines), ctx.taxRateBp, ctx.pricesIncludeTax);
    const kind = p.source.kind as 'boleta' | 'factura';
    const customer = normalizeCustomer(kind, totalsOf(items).totalCents, original.customer);
    return this.insert(tx, user, ctx, { kind, seriesKind: kind, branchId: p.branchId, saleId: p.source.saleId, returnId: p.returnId, customer, items });
  }

  /**
   * Guía de remisión de una transferencia (motivo 04: traslado entre establecimientos de la
   * misma empresa). Se numera dentro de la transacción del envío: si el envío falla, no se
   * consume número. Devuelve null si la tienda no emite comprobantes electrónicos.
   */
  async issueGuideForTransfer(
    tx: Tx,
    user: AuthUser,
    p: { transferId: string; fromBranchId: string; toBranchId: string; items: { variantId: string; quantity: number }[]; shipment?: Shipment; note?: string },
  ): Promise<DocRow | null> {
    const ctx = await this.context(tx);
    if (!ctx) return null;
    if (!p.shipment) throw new BadRequestException({ message: 'Completa los datos del traslado para la guía de remisión', code: 'SHIPMENT_REQUIRED' });
    validateShipment(p.shipment);

    const [t] = await tx.select({ ruc: tenants.ruc }).from(tenants);
    const [settings] = await tx.select({ legalName: einvoiceSettings.legalName }).from(einvoiceSettings);
    const bs = await tx.select().from(branches).where(inArray(branches.id, [p.fromBranchId, p.toBranchId]));
    const from = bs.find((b) => b.id === p.fromBranchId)!;
    const to = bs.find((b) => b.id === p.toBranchId)!;
    if (!t?.ruc) throw new ConflictException({ message: 'Registra el RUC de la tienda para emitir guías', code: 'TENANT_RUC_MISSING' });
    for (const b of [from, to]) {
      if (!b.ubigeo || !b.address) throw new ConflictException({ message: `Completa la dirección y el ubigeo de "${b.name}"`, code: 'BRANCH_ADDRESS_MISSING', branchId: b.id });
    }
    const [s] = await tx.select({ serie: einvoiceSeries.serie }).from(einvoiceSeries).where(and(eq(einvoiceSeries.branchId, p.fromBranchId), eq(einvoiceSeries.kind, 'guia')));
    if (!s) throw new ConflictException({ message: 'Configura la serie de guías (T…) de la sucursal de origen', code: 'EINVOICE_SERIES_MISSING' });

    const numero = await nextNumber(tx, user.tenantId, `einv:${s.serie}`);
    const today = localDate(ctx.tz, new Date());
    const lines = await this.lineInputs(tx, p.items.map((i) => ({ ...i, amountCents: 0 })));
    const guide: EGuide = {
      kind: 'guia_remitente',
      serie: s.serie,
      numero,
      issueDate: today,
      startDate: p.shipment.startDate ?? today,
      reasonCode: '04',
      reasonText: 'Traslado entre establecimientos de la misma empresa',
      recipient: { ruc: t.ruc, name: settings?.legalName ?? '' },
      origin: { ubigeo: from.ubigeo!, address: from.address! },
      destination: { ubigeo: to.ubigeo!, address: to.address! },
      transport: {
        mode: p.shipment.mode,
        lightVehicle: p.shipment.lightVehicle,
        vehiclePlate: p.shipment.vehiclePlate,
        driver: p.shipment.driver,
        carrier: p.shipment.carrier,
      },
      weightKg: p.shipment.weightKg,
      packages: p.shipment.packages,
      items: lines.map((l) => ({ code: l.code, description: l.description, quantity: l.quantity })),
      note: p.note,
    };
    const [row] = await tx
      .insert(einvoiceDocuments)
      .values({
        tenantId: user.tenantId,
        branchId: p.fromBranchId,
        transferId: p.transferId,
        kind: 'guia_remitente',
        serie: s.serie,
        numero,
        customerDocType: 'ruc',
        customerDocNumber: t.ruc,
        customerName: guide.recipient.name,
        totalCents: 0,
        provider: ctx.provider,
        payload: guide,
      })
      .returning();
    return row;
  }

  forTransfer(tx: Tx, transferId: string) {
    return tx.select().from(einvoiceDocuments).where(eq(einvoiceDocuments.transferId, transferId)).orderBy(asc(einvoiceDocuments.createdAt));
  }

  /** Comprobante vigente (boleta o factura) de una venta, para notas de crédito. */
  async saleDocument(tx: Tx, saleId: string) {
    const [doc] = await tx
      .select()
      .from(einvoiceDocuments)
      .where(and(eq(einvoiceDocuments.saleId, saleId), inArray(einvoiceDocuments.kind, ['boleta', 'factura'])))
      .orderBy(asc(einvoiceDocuments.createdAt))
      .limit(1);
    return doc ?? null;
  }

  // ---------------------------------------------------------------- envío al OSE (fuera de la transacción)

  /** Tras el commit: en modo async no bloquea la venta; en sync espera (pruebas). */
  async afterCommit(tenantId: string, ids: string[]) {
    if (!ids.length) return;
    const work = this.sendMany(tenantId, ids);
    if (this.env.EINVOICE_DISPATCH === 'sync') await work;
    else void work.catch((e) => this.logger.error(`Envío diferido falló: ${e}`));
  }

  private async sendMany(tenantId: string, ids: string[]) {
    // En orden de creación: una nota de crédito sale después de su comprobante.
    for (const id of ids) await this.send(tenantId, id);
  }

  async send(tenantId: string, id: string) {
    return this.db.withTenant(tenantId, async (tx) => {
      const [doc] = await tx.select().from(einvoiceDocuments).where(eq(einvoiceDocuments.id, id)).for('update', { skipLocked: true });
      if (!doc || doc.status === 'accepted' || doc.status === 'rejected') return doc ?? null;

      if (doc.referenceId) {
        const [ref] = await tx.select({ status: einvoiceDocuments.status }).from(einvoiceDocuments).where(eq(einvoiceDocuments.id, doc.referenceId));
        if (ref && ref.status !== 'accepted') return doc; // se envía cuando el original esté aceptado
      }

      const [settings] = await tx.select().from(einvoiceSettings);
      const provider = this.providers.find((p) => p.name === doc.provider);
      if (!settings?.tokenEnc || !settings.apiUrl || !provider) {
        return this.update(tx, doc, { status: 'error', lastError: 'OSE no configurado' });
      }
      const cfg = { apiUrl: settings.apiUrl, token: open(settings.tokenEnc, this.env.EINVOICE_ENC_KEY!) };
      const isGuide = doc.kind === 'guia_remitente';
      if (isGuide && !provider.sendGuide) return this.update(tx, doc, { status: 'error', lastError: 'El OSE configurado no emite guías de remisión' });
      try {
        // Si ya se envió antes (posible corte a mitad de camino), primero se consulta: nunca duplicar.
        const result = isGuide
          ? ((doc.sentAt ? await provider.queryGuide!(doc.payload as EGuide, cfg) : null) ?? (await provider.sendGuide!(doc.payload as EGuide, cfg)))
          : ((doc.sentAt ? await provider.query(doc.payload as EDoc, cfg) : null) ?? (await provider.send(doc.payload as EDoc, cfg)));
        return this.update(tx, doc, {
          status: result.state === 'accepted' ? 'accepted' : result.state === 'rejected' ? 'rejected' : 'pending',
          sentAt: doc.sentAt ?? new Date(),
          sunatDescription: result.description ?? null,
          pdfUrl: result.pdfUrl ?? doc.pdfUrl,
          hash: result.hash ?? doc.hash,
          qr: result.qr ?? doc.qr,
          lastError: null,
        });
      } catch (e) {
        if (!(e instanceof OseUnavailableError)) this.logger.error(`Comprobante ${doc.serie}-${doc.numero}: ${e}`);
        return this.update(tx, doc, { status: 'error', lastError: e instanceof Error ? e.message : String(e) });
      }
    });
  }

  /** Job: reenvía pendientes/errores (máx. 20 intentos) de todas las tiendas. */
  async run() {
    const due = await this.db.withSystem((tx) =>
      tx
        .select({ id: einvoiceDocuments.id, tenantId: einvoiceDocuments.tenantId })
        .from(einvoiceDocuments)
        .where(and(or(eq(einvoiceDocuments.status, 'pending'), eq(einvoiceDocuments.status, 'error')), lt(einvoiceDocuments.attempts, 20)))
        .orderBy(asc(einvoiceDocuments.createdAt))
        .limit(500),
    );
    let accepted = 0;
    for (const d of due) if ((await this.send(d.tenantId, d.id))?.status === 'accepted') accepted++;
    return { processed: due.length, accepted };
  }

  // ---------------------------------------------------------------- consultas

  list(user: AuthUser, q: z.infer<typeof ListSchema>) {
    return this.db.withTenant(user.tenantId, (tx) =>
      tx
        .select({
          id: einvoiceDocuments.id,
          kind: einvoiceDocuments.kind,
          serie: einvoiceDocuments.serie,
          numero: einvoiceDocuments.numero,
          status: einvoiceDocuments.status,
          totalCents: einvoiceDocuments.totalCents,
          customerName: einvoiceDocuments.customerName,
          saleId: einvoiceDocuments.saleId,
          sunatDescription: einvoiceDocuments.sunatDescription,
          lastError: einvoiceDocuments.lastError,
          pdfUrl: einvoiceDocuments.pdfUrl,
          createdAt: einvoiceDocuments.createdAt,
        })
        .from(einvoiceDocuments)
        .where(q.status ? eq(einvoiceDocuments.status, q.status) : undefined)
        .orderBy(desc(einvoiceDocuments.createdAt))
        .limit(q.limit),
    );
  }

  forSale(tx: Tx, saleId: string) {
    return tx.select().from(einvoiceDocuments).where(eq(einvoiceDocuments.saleId, saleId)).orderBy(asc(einvoiceDocuments.createdAt));
  }

  async retry(user: AuthUser, id: string) {
    const doc = await this.send(user.tenantId, id);
    if (!doc) throw new NotFoundException('Comprobante no encontrado');
    return doc;
  }

  // ---------------------------------------------------------------- helpers

  private async context(tx: Tx) {
    const [s] = await tx.select().from(einvoiceSettings);
    if (!s?.enabled) return null;
    const [t] = await tx.select({ tz: tenants.timezone, currency: tenants.currency, taxRateBp: tenants.taxRateBp, pricesIncludeTax: tenants.pricesIncludeTax }).from(tenants);
    return { provider: s.provider, ...t };
  }

  private async lineInputs(tx: Tx, lines: SaleLineRef[]): Promise<LineInput[]> {
    const rows = await tx
      .select({ id: variants.id, sku: variants.sku, options: variants.options, name: products.name })
      .from(variants)
      .innerJoin(products, eq(products.id, variants.productId))
      .where(inArray(variants.id, lines.map((l) => l.variantId)));
    return lines.map((l) => {
      const v = rows.find((r) => r.id === l.variantId)!;
      const opts = Object.values(v.options).join(' ');
      return { code: v.sku, description: `${v.name}${opts ? ` ${opts}` : ''}`.slice(0, 250), quantity: l.quantity, amountCents: l.amountCents };
    });
  }

  private async insert(
    tx: Tx,
    user: AuthUser,
    ctx: NonNullable<Awaited<ReturnType<EInvoiceService['context']>>>,
    p: {
      kind: EDoc['kind'];
      seriesKind: 'boleta' | 'factura' | 'nc_boleta' | 'nc_factura';
      branchId: string;
      saleId?: string | null;
      returnId?: string;
      referenceId?: string;
      customer: EDocCustomer;
      items: EDoc['items'];
      reference?: EDoc['reference'];
      /** Fecha de emisión = fecha real de la venta (ventas sin conexión). */
      issuedAt?: Date;
    },
  ) {
    const [s] = await tx
      .select({ serie: einvoiceSeries.serie })
      .from(einvoiceSeries)
      .where(and(eq(einvoiceSeries.branchId, p.branchId), eq(einvoiceSeries.kind, p.seriesKind)));
    if (!s) throw new ConflictException({ message: 'Configura las series de comprobantes de esta sucursal', code: 'EINVOICE_SERIES_MISSING' });

    // Correlativo dentro de la transacción: sin huecos ni duplicados aunque haya ventas simultáneas.
    const numero = await nextNumber(tx, user.tenantId, `einv:${s.serie}`);
    const edoc: EDoc = {
      kind: p.kind,
      serie: s.serie,
      numero,
      issueDate: localDate(ctx.tz, p.issuedAt ?? new Date()),
      currency: ctx.currency === 'USD' ? 'USD' : 'PEN',
      taxRateBp: ctx.taxRateBp,
      customer: p.customer,
      items: p.items,
      totals: totalsOf(p.items),
      reference: p.reference,
    };
    const [row] = await tx
      .insert(einvoiceDocuments)
      .values({
        tenantId: user.tenantId,
        branchId: p.branchId,
        saleId: p.saleId ?? null,
        returnId: p.returnId ?? null,
        referenceId: p.referenceId ?? null,
        kind: p.kind,
        serie: s.serie,
        numero,
        customerDocType: p.customer.docType,
        customerDocNumber: p.customer.docNumber,
        customerName: p.customer.name,
        totalCents: edoc.totals.totalCents,
        provider: ctx.provider,
        payload: edoc,
      })
      .returning();
    return row;
  }

  private async update(tx: Tx, doc: DocRow, changes: Partial<typeof einvoiceDocuments.$inferInsert>) {
    if (changes.status === 'rejected' && doc.status !== 'rejected') {
      await this.events.publish(tx, {
        type: 'einvoice.rejected',
        tenantId: doc.tenantId,
        kind: doc.kind,
        serie: doc.serie,
        numero: doc.numero,
        description: changes.sunatDescription ?? null,
        saleId: doc.saleId,
        transferId: doc.transferId,
      });
    }
    const [row] = await tx
      .update(einvoiceDocuments)
      .set({ ...changes, attempts: sql`${einvoiceDocuments.attempts} + 1` })
      .where(eq(einvoiceDocuments.id, doc.id))
      .returning();
    return row;
  }
}
