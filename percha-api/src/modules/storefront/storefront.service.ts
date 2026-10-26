import { Inject, Injectable } from '@nestjs/common';
import { and, asc, desc, eq, inArray, sql } from 'drizzle-orm';
import { z } from 'zod';
import type { AuthUser } from '../../common/auth-user';
import { DomainError } from '../../common/domain-error';
import { EventBus } from '../../common/events';
import { IdempotencyService } from '../../common/idempotency';
import { appliesTo, applyPromotions, Promo } from '../promotions/engine';
import { PromotionsService } from '../promotions/promotions.service';
import { ENV, Env } from '../../config/env';
import { DatabaseService, Tx } from '../../database/database.service';
import { nextNumber } from '../../database/sequences';
import {
  catalogOrderItems,
  catalogOrders,
  catalogSettings,
  categories,
  customers,
  productImages,
  products,
  stockLevels,
  tenants,
  variants,
} from '../../database/schema';
import { StorageService } from '../storage/storage.service';

const RESERVED = new Set(['admin', 'api', 'app', 'www', 'percha', 'login', 'soporte', 'ayuda']);

export const CatalogSettingsSchema = z.object({
  enabled: z.boolean(),
  slug: z
    .string()
    .trim()
    .toLowerCase()
    .regex(/^[a-z0-9](?:[a-z0-9-]{1,38})[a-z0-9]$/, 'De 3 a 40 letras minúsculas, números o guiones')
    .refine((s) => !RESERVED.has(s), 'Ese nombre está reservado'),
  whatsapp: z.string().regex(/^\d{8,15}$/, 'Número con código de país, solo dígitos').nullable().optional(),
  branchId: z.string().uuid().nullable().optional(),
  description: z.string().trim().max(300).nullable().optional(),
});

export const PublicOrderSchema = z.object({
  name: z.string().trim().min(2).max(80),
  phone: z
    .string()
    .transform((v) => v.replace(/[\s-]/g, ''))
    .pipe(z.string().regex(/^\+?\d{9,15}$/, 'Celular inválido')),
  note: z.string().trim().max(300).optional(),
  items: z.array(z.object({ variantId: z.string().uuid(), quantity: z.number().int().min(1).max(5) })).min(1).max(20),
  /** Trampa para bots: un humano nunca la ve ni la llena. */
  website: z.string().max(0).optional(),
});

export const OrderStatusSchema = z.object({ status: z.enum(['contacted', 'completed', 'cancelled']) });

/** Disponibilidad pública: nunca se muestra el stock exacto (dato de la tienda). */
export type Availability = 'available' | 'few' | 'out';
export const availabilityOf = (qty: number): Availability => (qty <= 0 ? 'out' : qty <= 3 ? 'few' : 'available');

/**
 * Promoción que se muestra en la vitrina: el mejor porcentaje (con su precio rebajado) o, si
 * no hay, la etiqueta del "lleva X, paga Y". El precio final siempre lo calcula el POS.
 */
export function promoBadge(promos: Promo[], target: { productId: string; categoryId: string | null }, priceCents: number): { promoLabel?: string; promoPriceCents?: number } {
  const own = promos.filter((p) => appliesTo(p, target));
  const percent = own.filter((p) => p.kind === 'percent').sort((a, b) => (b.percentBp ?? 0) - (a.percentBp ?? 0))[0];
  if (percent?.percentBp) return { promoLabel: `−${percent.percentBp / 100} %`, promoPriceCents: priceCents - Math.round((priceCents * percent.percentBp) / 10_000) };
  const bundle = own.find((p) => p.kind === 'buy_x_pay_y');
  return bundle ? { promoLabel: `${bundle.buyQty}x${bundle.payQty}` } : {};
}

const normalizePhone = (raw: string) => {
  const d = raw.replace(/\D/g, '');
  return /^9\d{8}$/.test(d) ? `51${d}` : d;
};

/**
 * Catálogo público (vitrina) de cada tienda: fotos, precios y tallas disponibles en tiempo
 * real, para compartir por WhatsApp o Instagram. El cliente arma un pedido; la tienda lo
 * contacta y lo convierte en apartado o venta.
 *
 * Seguridad: el slug se resuelve con el pool de sistema y TODO lo demás se lee con RLS de esa
 * tienda (`withTenant`). Solo productos publicados y activos; sin costos, sin stock exacto,
 * sin ids de tienda. Los pedidos se limitan por IP y llevan una trampa para bots.
 */
@Injectable()
export class StorefrontService {
  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(StorageService) private readonly storage: StorageService,
    @Inject(EventBus) private readonly events: EventBus,
    @Inject(ENV) private readonly env: Env,
    @Inject(IdempotencyService) private readonly idem: IdempotencyService,
    @Inject(PromotionsService) private readonly promotions: PromotionsService,
  ) {}

  // ---------------------------------------------------------------- configuración (tienda)

  getSettings(user: AuthUser) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [s] = await tx.select().from(catalogSettings);
      const [{ published }] = await tx.select({ published: sql<number>`count(*)::int` }).from(products).where(and(eq(products.published, true), eq(products.active, true)));
      return { enabled: s?.enabled ?? false, slug: s?.slug ?? null, whatsapp: s?.whatsapp ?? null, branchId: s?.branchId ?? null, description: s?.description ?? null, url: s ? this.url(s.slug) : null, published };
    });
  }

  async saveSettings(user: AuthUser, input: z.infer<typeof CatalogSettingsSchema>) {
    const taken = await this.db.withSystem((tx) => tx.select({ tenantId: catalogSettings.tenantId }).from(catalogSettings).where(eq(catalogSettings.slug, input.slug)));
    if (taken.some((t) => t.tenantId !== user.tenantId)) throw DomainError.conflict('SLUG_TAKEN', 'Ese enlace ya lo usa otra tienda: prueba otro');
    return this.db.withTenant(user.tenantId, async (tx) => {
      const values = { enabled: input.enabled, slug: input.slug, whatsapp: input.whatsapp ?? null, branchId: input.branchId ?? null, description: input.description ?? null, updatedAt: new Date() };
      await tx.insert(catalogSettings).values({ tenantId: user.tenantId, ...values }).onConflictDoUpdate({ target: catalogSettings.tenantId, set: values });
      return { ...values, url: this.url(input.slug) };
    });
  }

  setPublished(user: AuthUser, productId: string, published: boolean) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [p] = await tx.update(products).set({ published, updatedAt: new Date() }).where(eq(products.id, productId)).returning({ id: products.id, published: products.published });
      if (!p) throw DomainError.notFound('PRODUCT_NOT_FOUND', 'Producto no encontrado');
      return p;
    });
  }

  url(slug: string) {
    return `${this.env.PUBLIC_API_URL.replace(/\/$/, '')}/c/${slug}`;
  }

  // ---------------------------------------------------------------- vitrina pública

  /** Resuelve el slug (pool de sistema) y ejecuta el resto con RLS de esa tienda. */
  private async withStore<T>(slug: string, fn: (tx: Tx, s: typeof catalogSettings.$inferSelect) => Promise<T>) {
    const [s] = await this.db.withSystem((tx) => tx.select().from(catalogSettings).where(eq(catalogSettings.slug, slug.toLowerCase())));
    if (!s?.enabled) throw DomainError.notFound('CATALOG_NOT_FOUND', 'Catálogo no encontrado');
    return this.db.withTenant(s.tenantId, (tx) => fn(tx, s));
  }

  /** Stock por variante (de la sucursal elegida o la suma de todas). */
  private async stockFor(tx: Tx, variantIds: string[], branchId: string | null) {
    if (!variantIds.length) return new Map<string, number>();
    const rows = await tx
      .select({ variantId: stockLevels.variantId, qty: sql<number>`sum(${stockLevels.quantity})::int` })
      .from(stockLevels)
      .where(and(inArray(stockLevels.variantId, variantIds), branchId ? eq(stockLevels.branchId, branchId) : undefined))
      .groupBy(stockLevels.variantId);
    return new Map(rows.map((r) => [r.variantId, r.qty]));
  }

  publicCatalog(slug: string) {
    return this.withStore(slug, async (tx, s) => {
      const [store] = await tx.select({ name: tenants.name }).from(tenants);
      const list = await tx
        .select({ id: products.id, name: products.name, priceCents: products.priceCents, imageUrl: products.imageUrl, category: categories.name, categoryId: products.categoryId })
        .from(products)
        .leftJoin(categories, eq(categories.id, products.categoryId))
        .where(and(eq(products.published, true), eq(products.active, true)))
        .orderBy(desc(products.updatedAt))
        .limit(500);
      const vs = list.length
        ? await tx.select({ id: variants.id, productId: variants.productId, priceCents: variants.priceCents }).from(variants).where(and(inArray(variants.productId, list.map((p) => p.id)), eq(variants.active, true)))
        : [];
      const stock = await this.stockFor(tx, vs.map((v) => v.id), s.branchId);
      const promos = await this.promotions.activeAt(tx, new Date());
      return {
        store: { name: store.name, description: s.description, whatsapp: s.whatsapp },
        products: list.map((p) => {
          const own = vs.filter((v) => v.productId === p.id);
          const prices = own.map((v) => v.priceCents ?? p.priceCents);
          const total = own.reduce((a, v) => a + Math.max(stock.get(v.id) ?? 0, 0), 0);
          const from = prices.length ? Math.min(...prices) : p.priceCents;
          return {
            id: p.id,
            name: p.name,
            category: p.category,
            imageUrl: p.imageUrl,
            fromPriceCents: from,
            ...promoBadge(promos, { productId: p.id, categoryId: p.categoryId }, from),
            availability: availabilityOf(total),
          };
        }),
      };
    });
  }

  publicProduct(slug: string, productId: string) {
    return this.withStore(slug, async (tx, s) => {
      const [p] = await tx.select().from(products).where(and(eq(products.id, productId), eq(products.published, true), eq(products.active, true)));
      if (!p) throw DomainError.notFound('PRODUCT_NOT_FOUND', 'Producto no disponible');
      const vs = await tx.select().from(variants).where(and(eq(variants.productId, p.id), eq(variants.active, true))).orderBy(asc(variants.sku));
      const stock = await this.stockFor(tx, vs.map((v) => v.id), s.branchId);
      const promos = await this.promotions.activeAt(tx, new Date());
      const imgs = await tx.select().from(productImages).where(eq(productImages.productId, p.id)).orderBy(asc(productImages.position));
      return {
        id: p.id,
        name: p.name,
        description: p.description,
        images: imgs.map((i) => ({ url: this.storage.url(i.key), thumbUrl: this.storage.url(i.thumbKey), optionValue: i.optionValue })),
        ...promoBadge(promos, { productId: p.id, categoryId: p.categoryId }, p.priceCents),
        variants: vs.map((v) => {
          const price = v.priceCents ?? p.priceCents;
          return { id: v.id, options: v.options, priceCents: price, promoPriceCents: promoBadge(promos, { productId: p.id, categoryId: p.categoryId }, price).promoPriceCents ?? null, availability: availabilityOf(stock.get(v.id) ?? 0) };
        }),
      };
    });
  }

  /** Pedido del cliente. No reserva stock: la tienda lo confirma por WhatsApp. */
  async createOrder(slug: string, input: z.infer<typeof PublicOrderSchema>, idempotencyKey?: string) {
    if (input.website) throw DomainError.invalid('INVALID_ORDER', 'Pedido inválido'); // bot
    const result = await this.withStore(slug, async (tx, s) => {
      // Doble toque o red lenta en el celular del cliente: el mismo pedido no se crea dos veces.
      const prev = await this.idem.begin(tx, s.tenantId, idempotencyKey, 'catalog.order', { slug, ...input });
      if (prev) {
        const [o] = await tx.select().from(catalogOrders).where(eq(catalogOrders.id, prev));
        return { number: o.number, total: o.totalCents, lines: [] as { label: string }[], whatsapp: null as string | null };
      }
      const rows = await tx
        .select({ id: variants.id, options: variants.options, priceCents: variants.priceCents, productPrice: products.priceCents, name: products.name, productId: products.id, categoryId: products.categoryId })
        .from(variants)
        .innerJoin(products, eq(products.id, variants.productId))
        .where(and(inArray(variants.id, input.items.map((i) => i.variantId)), eq(variants.active, true), eq(products.published, true), eq(products.active, true)));
      if (rows.length !== new Set(input.items.map((i) => i.variantId)).size) throw DomainError.invalid('ITEM_UNAVAILABLE', 'Alguna prenda ya no está disponible: actualiza la página');
      const stock = await this.stockFor(tx, rows.map((r) => r.id), s.branchId);
      const lines = input.items.map((i) => {
        const r = rows.find((x) => x.id === i.variantId)!;
        if ((stock.get(r.id) ?? 0) < i.quantity) throw DomainError.rule('OUT_OF_STOCK', `${r.name} ${Object.values(r.options).join(' ')} no tiene stock suficiente`);
        return { ...i, unitPriceCents: r.priceCents ?? r.productPrice, label: `${i.quantity} × ${r.name}${Object.keys(r.options).length ? ` (${Object.values(r.options).join(' · ')})` : ''}` };
      });
      const promo = applyPromotions(
        lines.map((l) => ({ productId: rows.find((r) => r.id === l.variantId)!.productId, categoryId: rows.find((r) => r.id === l.variantId)!.categoryId, quantity: l.quantity, unitPriceCents: l.unitPriceCents })),
        await this.promotions.activeAt(tx, new Date()),
      );
      const total = lines.reduce((a, l) => a + l.unitPriceCents * l.quantity, 0) - promo.totalCents;
      const number = await nextNumber(tx, s.tenantId, 'catalog_order');
      const [order] = await tx
        .insert(catalogOrders)
        .values({ tenantId: s.tenantId, number, customerName: input.name, customerPhone: normalizePhone(input.phone), note: input.note, totalCents: total })
        .returning();
      await tx.insert(catalogOrderItems).values(lines.map((l) => ({ tenantId: s.tenantId, orderId: order.id, variantId: l.variantId, quantity: l.quantity, unitPriceCents: l.unitPriceCents })));
      await this.events.publish(tx, { type: 'catalog.order_received', tenantId: s.tenantId, orderId: order.id, number, customerName: input.name, totalCents: total, branchId: s.branchId });
      await this.idem.complete(tx, s.tenantId, idempotencyKey, order.id);
      return { number, total, lines, whatsapp: s.whatsapp };
    });
    // Mensaje listo para que el cliente también escriba por WhatsApp (la tienda ya tiene el pedido).
    const text = [`Hola, acabo de hacer el pedido #${result.number}:`, ...result.lines.map((l) => `• ${l.label}`), `Total referencial: S/ ${(result.total / 100).toFixed(2)}`].join('\n');
    return {
      number: result.number,
      totalCents: result.total,
      whatsappUrl: result.whatsapp ? `https://wa.me/${result.whatsapp}?text=${encodeURIComponent(text)}` : null,
    };
  }

  // ---------------------------------------------------------------- pedidos (tienda)

  listOrders(user: AuthUser, status?: string) {
    return this.db.withTenant(user.tenantId, (tx) =>
      tx
        .select()
        .from(catalogOrders)
        .where(status ? eq(catalogOrders.status, status as 'new') : undefined)
        .orderBy(asc(sql`case when ${catalogOrders.status} = 'new' then 0 else 1 end`), desc(catalogOrders.createdAt))
        .limit(100),
    );
  }

  getOrder(user: AuthUser, id: string) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [o] = await tx.select().from(catalogOrders).where(eq(catalogOrders.id, id));
      if (!o) throw DomainError.notFound('ORDER_NOT_FOUND', 'Pedido no encontrado');
      const items = await tx
        .select({ variantId: catalogOrderItems.variantId, quantity: catalogOrderItems.quantity, unitPriceCents: catalogOrderItems.unitPriceCents, productName: products.name, options: variants.options })
        .from(catalogOrderItems)
        .innerJoin(variants, eq(variants.id, catalogOrderItems.variantId))
        .innerJoin(products, eq(products.id, variants.productId))
        .where(eq(catalogOrderItems.orderId, id));
      return { ...o, items };
    });
  }

  setStatus(user: AuthUser, id: string, status: 'contacted' | 'completed' | 'cancelled') {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [o] = await tx.update(catalogOrders).set({ status, updatedAt: new Date() }).where(eq(catalogOrders.id, id)).returning();
      if (!o) throw DomainError.notFound('ORDER_NOT_FOUND', 'Pedido no encontrado');
      return o;
    });
  }

  /** Crea (o reutiliza por celular) la ficha del cliente para apartar o vender. */
  linkCustomer(user: AuthUser, id: string) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [o] = await tx.select().from(catalogOrders).where(eq(catalogOrders.id, id)).for('update');
      if (!o) throw DomainError.notFound('ORDER_NOT_FOUND', 'Pedido no encontrado');
      if (o.customerId) return { customerId: o.customerId };
      const [existing] = await tx.select({ id: customers.id }).from(customers).where(eq(customers.phone, o.customerPhone)).limit(1);
      const customerId = existing?.id ?? (await tx.insert(customers).values({ tenantId: user.tenantId, name: o.customerName, phone: o.customerPhone }).returning({ id: customers.id }))[0].id;
      await tx.update(catalogOrders).set({ customerId, status: o.status === 'new' ? 'contacted' : o.status, updatedAt: new Date() }).where(eq(catalogOrders.id, id));
      return { customerId };
    });
  }
}
