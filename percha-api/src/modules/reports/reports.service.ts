import { localDate, shiftDate } from '../../common/dates';
import { BadRequestException, Inject, Injectable } from '@nestjs/common';
import { SQL, sql } from 'drizzle-orm';
import { z } from 'zod';
import { assertBranchAccess, AuthUser } from '../../common/auth-user';
import { DatabaseService, Tx } from '../../database/database.service';
import { attributes, tenants } from '../../database/schema';
import { hasPermission } from '../../common/authz/permissions';

export const RangeSchema = z.object({
  /** Fechas locales de la tienda (YYYY-MM-DD), ambas inclusive. Por defecto: últimos 30 días. */
  from: z.string().date().optional(),
  to: z.string().date().optional(),
  branchId: z.string().uuid().optional(),
});

export const TopSchema = RangeSchema.extend({ limit: z.coerce.number().int().min(1).max(100).default(10) });
export const AttributesSchema = RangeSchema.extend({ productId: z.string().uuid().optional() });
export const DeadStockSchema = z.object({
  branchId: z.string().uuid().optional(),
  /** Sin ventas en los últimos N días. */
  days: z.coerce.number().int().min(7).max(365).default(60),
});
export const ValuationSchema = z.object({ branchId: z.string().uuid().optional() });

type Range = z.infer<typeof RangeSchema>;

/** node-postgres devuelve bigint como string: se normaliza a number (céntimos caben de sobra). */
const n = (v: unknown) => Number(v ?? 0);

/**
 * Movimientos que representan VENTA NETA de unidades: venta, cambio entregado, devolución
 * (resta) y anulación (resta). Las ventas anuladas se excluyen por completo, junto con su
 * reverso: para los reportes, una venta anulada nunca existió.
 */
const SOLD_TYPES = sql`('sale', 'sale_void', 'return_in', 'exchange_out')`;
const NOT_VOIDED = sql`not (m.type in ('sale', 'sale_void') and m.reference_id in (select id from sales where status = 'voided'))`;

/**
 * Reportes de la fase 7. Todo es SQL de agregación dentro de `withTenant`: RLS también aplica
 * a estas consultas crudas, así que un reporte nunca mezcla tiendas.
 *
 * Convenciones:
 * - Montos en céntimos y CON IGV (lo que pagó el cliente). Se agrega la versión sin IGV donde
 *   se calcula margen, porque el IGV no es ingreso de la tienda.
 * - Ventas netas = ventas completadas + diferencia de devoluciones/cambios del período
 *   (una devolución resta el día que ocurre, no el día de la venta original).
 * - Costo de lo vendido = costo registrado en cada movimiento del kardex (costo promedio al
 *   momento de la salida), así el margen histórico no cambia cuando sube el costo.
 */
@Injectable()
export class ReportsService {
  constructor(@Inject(DatabaseService) private readonly db: DatabaseService) {}

  summary(user: AuthUser, q: Range) {
    return this.run(user, q, async (tx, ctx) => {
      const [row] = (
        await tx.execute(sql`
          with s as (
            select count(*) filter (where status = 'completed') as tickets,
                   coalesce(sum(total_cents) filter (where status = 'completed'), 0) as sales_total,
                   coalesce(sum(discount_cents) filter (where status = 'completed'), 0) as discounts,
                   count(*) filter (where status = 'voided') as voided
              from sales
             where ${ctx.inRange(sql`created_at`)} ${ctx.branch(sql`branch_id`)}
          ), r as (
            select count(*) as returns,
                   coalesce(sum(returned_cents), 0) as returned,
                   coalesce(sum(difference_cents), 0) as difference
              from returns
             where ${ctx.inRange(sql`created_at`)} ${ctx.branch(sql`branch_id`)}
          ), m as (
            select coalesce(-sum(m.quantity), 0) as units,
                   coalesce(-sum(m.quantity * coalesce(m.unit_cost_cents, 0)), 0) as cogs
              from stock_movements m
             where m.type in ${SOLD_TYPES} and ${NOT_VOIDED}
               and ${ctx.inRange(sql`m.created_at`)} ${ctx.branch(sql`m.branch_id`)}
          )
          select * from s, r, m`)
      ).rows as Record<string, unknown>[];

      const tickets = n(row.tickets);
      const netSales = n(row.sales_total) + n(row.difference);
      const cogs = n(row.cogs);
      const netExTax = ctx.exTax(netSales);
      return {
        range: ctx.range,
        tickets,
        units: n(row.units),
        netSalesCents: netSales,
        netSalesExTaxCents: netExTax,
        averageTicketCents: tickets ? Math.round(n(row.sales_total) / tickets) : 0,
        discountsCents: n(row.discounts),
        voidedSales: n(row.voided),
        returns: n(row.returns),
        returnedCents: n(row.returned),
        ...ctx.costs({
          costOfSalesCents: cogs,
          grossMarginCents: netExTax - cogs,
          grossMarginPct: netExTax > 0 ? round1(((netExTax - cogs) / netExTax) * 100) : null,
        }),
      };
    });
  }

  /** Serie diaria con todos los días del rango (los días sin ventas vienen en 0, listos para graficar). */
  daily(user: AuthUser, q: Range) {
    return this.run(user, q, async (tx, ctx) => {
      const rows = (
        await tx.execute(sql`
          with days as (
            select generate_series(${ctx.range.from}::date, ${ctx.range.to}::date, interval '1 day')::date as d
          ), s as (
            select (created_at at time zone ${ctx.tz})::date as d, count(*) as tickets, sum(total_cents) as total
              from sales
             where status = 'completed' and ${ctx.inRange(sql`created_at`)} ${ctx.branch(sql`branch_id`)}
             group by 1
          ), r as (
            select (created_at at time zone ${ctx.tz})::date as d, sum(difference_cents) as diff
              from returns
             where ${ctx.inRange(sql`created_at`)} ${ctx.branch(sql`branch_id`)}
             group by 1
          )
          select to_char(days.d, 'YYYY-MM-DD') as date,
                 coalesce(s.tickets, 0) as tickets,
                 coalesce(s.total, 0) + coalesce(r.diff, 0) as net
            from days left join s using (d) left join r using (d)
           order by days.d`)
      ).rows as Record<string, unknown>[];
      return { range: ctx.range, days: rows.map((r) => ({ date: String(r.date), tickets: n(r.tickets), netSalesCents: n(r.net) })) };
    });
  }

  /** Más vendidos por unidades netas (ventas − devoluciones + cambios entregados). */
  topProducts(user: AuthUser, q: z.infer<typeof TopSchema>) {
    return this.run(user, q, async (tx, ctx) => {
      const rows = (
        await tx.execute(sql`
          with sold as (
            select si.variant_id,
                   si.quantity as qty,
                   -- cada línea al precio realmente cobrado (descuento prorrateado + IGV del ticket)
                   round(si.line_total_cents * s.total_cents::numeric / nullif(s.subtotal_cents - s.discount_cents, 0)) as revenue
              from sale_items si join sales s on s.id = si.sale_id
             where s.status = 'completed' and ${ctx.inRange(sql`s.created_at`)} ${ctx.branch(sql`s.branch_id`)}
            union all
            select ri.variant_id,
                   case when ri.direction = 'in' then -ri.quantity else ri.quantity end,
                   case when ri.direction = 'in' then -ri.quantity else ri.quantity end * ri.unit_price_cents
              from return_items ri join returns r on r.id = ri.return_id
             where ${ctx.inRange(sql`r.created_at`)} ${ctx.branch(sql`r.branch_id`)}
          ), cogs as (
            select m.variant_id, -sum(m.quantity * coalesce(m.unit_cost_cents, 0)) as cogs
              from stock_movements m
             where m.type in ${SOLD_TYPES} and ${NOT_VOIDED}
               and ${ctx.inRange(sql`m.created_at`)} ${ctx.branch(sql`m.branch_id`)}
             group by 1
          ), per_variant as (
            select variant_id, sum(qty) as qty, sum(revenue) as revenue from sold group by 1
          )
          select p.id, p.name, p.sku_base,
                 sum(pv.qty) as units,
                 sum(pv.revenue) as revenue,
                 sum(coalesce(c.cogs, 0)) as cogs
            from per_variant pv
            join variants v on v.id = pv.variant_id
            join products p on p.id = v.product_id
            left join cogs c on c.variant_id = pv.variant_id
           group by p.id, p.name, p.sku_base
          having sum(pv.qty) > 0
           order by units desc, revenue desc
           limit ${q.limit}`)
      ).rows as Record<string, unknown>[];

      return {
        range: ctx.range,
        items: rows.map((r) => {
          const revenue = n(r.revenue);
          const exTax = ctx.exTax(revenue);
          return {
            productId: String(r.id),
            name: String(r.name),
            skuBase: String(r.sku_base),
            units: n(r.units),
            netSalesCents: revenue,
            ...ctx.costs({ grossMarginCents: exTax - n(r.cogs) }),
          };
        }),
      };
    });
  }

  /**
   * Rotación por valor de atributo (talla, color...): unidades vendidas en el período vs. stock
   * actual. sellThrough = vendidas / (vendidas + stock). Responde "¿qué tallas se me agotan y
   * cuáles se quedan?", la pregunta de compra más común en una boutique.
   */
  attributes(user: AuthUser, q: z.infer<typeof AttributesSchema>) {
    return this.run(user, q, async (tx, ctx) => {
      const rows = (
        await tx.execute(sql`
          with mv as (
            select m.variant_id, -sum(m.quantity) as sold
              from stock_movements m
             where m.type in ${SOLD_TYPES} and ${NOT_VOIDED}
               and ${ctx.inRange(sql`m.created_at`)} ${ctx.branch(sql`m.branch_id`)}
             group by 1
          ), st as (
            select variant_id, sum(quantity) as stock
              from stock_levels sl
             where true ${ctx.branch(sql`sl.branch_id`)}
             group by 1
          )
          select o.key as attribute, o.value,
                 coalesce(sum(mv.sold), 0) as sold,
                 coalesce(sum(st.stock), 0) as stock
            from variants v
            cross join lateral jsonb_each_text(v.options) o
            left join mv on mv.variant_id = v.id
            left join st on st.variant_id = v.id
           where true ${q.productId ? sql`and v.product_id = ${q.productId}` : sql``}
           group by 1, 2`)
      ).rows as Record<string, unknown>[];

      // Se ordena como el dueño definió sus atributos (XS, S, M... y no alfabético).
      const defs = await tx.select().from(attributes);
      const order = (a: string, v: string) => {
        const def = defs.find((d) => d.name === a);
        return [def?.position ?? 99, def?.values.findIndex((x) => x.value === v) ?? 99];
      };
      const grouped = new Map<string, { value: string; sold: number; stock: number; sellThroughPct: number | null }[]>();
      for (const r of rows) {
        const sold = n(r.sold);
        const stock = n(r.stock);
        const list = grouped.get(String(r.attribute)) ?? [];
        list.push({ value: String(r.value), sold, stock, sellThroughPct: sold + stock > 0 ? round1((Math.max(sold, 0) / (Math.max(sold, 0) + stock)) * 100) : null });
        grouped.set(String(r.attribute), list);
      }
      return {
        range: ctx.range,
        attributes: [...grouped.entries()]
          .sort(([a], [b]) => order(a, '')[0] - order(b, '')[0])
          .map(([name, values]) => ({ name, values: values.sort((x, y) => order(name, x.value)[1] - order(name, y.value)[1]) })),
      };
    });
  }

  /**
   * Stock muerto: variantes con unidades en tienda y sin ventas en N días (o nunca vendidas y
   * con más de N días desde que entraron). Ordenado por plata inmovilizada (a costo).
   */
  deadStock(user: AuthUser, q: z.infer<typeof DeadStockSchema>) {
    return this.run(user, q, async (tx, ctx) => {
      const rows = (
        await tx.execute(sql`
          select v.id, v.sku, v.options, p.name as product_name, sl.branch_id, sl.quantity,
                 v.avg_cost_cents, coalesce(v.price_cents, p.price_cents) as price_cents,
                 last.at as last_sale_at, first.at as first_in_at
            from stock_levels sl
            join variants v on v.id = sl.variant_id
            join products p on p.id = v.product_id
            left join lateral (
              select max(m.created_at) as at from stock_movements m
               where m.variant_id = v.id and m.branch_id = sl.branch_id and m.type in ('sale', 'exchange_out')
            ) last on true
            left join lateral (
              select min(m.created_at) as at from stock_movements m
               where m.variant_id = v.id and m.branch_id = sl.branch_id and m.quantity > 0
            ) first on true
           where sl.quantity > 0 ${ctx.branch(sql`sl.branch_id`)}
             and coalesce(last.at, first.at) < now() - make_interval(days => ${q.days})
           order by sl.quantity * v.avg_cost_cents desc, sl.quantity desc
           limit 100`)
      ).rows as Record<string, unknown>[];

      const now = Date.now();
      const items = rows.map((r) => {
        const since = new Date(String(r.last_sale_at ?? r.first_in_at)).getTime();
        return {
          variantId: String(r.id),
          sku: String(r.sku),
          productName: String(r.product_name),
          options: r.options as Record<string, string>,
          branchId: String(r.branch_id),
          quantity: n(r.quantity),
          neverSold: r.last_sale_at == null,
          daysWithoutSale: Math.floor((now - since) / 86_400_000),
          retailValueCents: n(r.quantity) * n(r.price_cents),
          ...ctx.costs({ costValueCents: n(r.quantity) * n(r.avg_cost_cents) }),
        };
      });
      return {
        days: q.days,
        items,
        totalUnits: items.reduce((a, i) => a + i.quantity, 0),
        ...ctx.costs({ totalCostValueCents: items.reduce((a, i) => a + ((i as { costValueCents?: number }).costValueCents ?? 0), 0) }),
      };
    });
  }

  /** Valorización del inventario actual por categoría: a costo y a precio de venta. */
  valuation(user: AuthUser, q: z.infer<typeof ValuationSchema>) {
    return this.run(user, q, async (tx, ctx) => {
      const rows = (
        await tx.execute(sql`
          select coalesce(c.name, 'Sin categoría') as category,
                 sum(sl.quantity) as units,
                 sum(sl.quantity * v.avg_cost_cents) as cost_value,
                 sum(sl.quantity * coalesce(v.price_cents, p.price_cents)) as retail_value
            from stock_levels sl
            join variants v on v.id = sl.variant_id
            join products p on p.id = v.product_id
            left join categories c on c.id = p.category_id
           where sl.quantity > 0 ${ctx.branch(sql`sl.branch_id`)}
           group by 1
           order by cost_value desc, units desc`)
      ).rows as Record<string, unknown>[];

      const categories = rows.map((r) => {
        const retail = n(r.retail_value);
        const cost = n(r.cost_value);
        return {
          category: String(r.category),
          units: n(r.units),
          retailValueCents: retail,
          ...ctx.costs({ costValueCents: cost, potentialMarginCents: ctx.exTax(retail) - cost }),
        };
      });
      const totalRetail = categories.reduce((a, c) => a + c.retailValueCents, 0);
      const totalCost = rows.reduce((a, r) => a + n(r.cost_value), 0);
      return {
        categories,
        totalUnits: categories.reduce((a, c) => a + c.units, 0),
        totalRetailValueCents: totalRetail,
        ...ctx.costs({ totalCostValueCents: totalCost, potentialMarginCents: ctx.exTax(totalRetail) - totalCost }),
      };
    });
  }

  // ---------------------------------------------------------------- contexto común

  /**
   * Comisiones por vendedora en el período. Misma convención que las ventas netas:
   *   ventas completadas de la vendedora (por fecha de venta)
   * + diferencia de devoluciones y cambios de SUS ventas (por fecha de la devolución: una
   *   devolución de este mes resta este mes, aunque la venta haya sido el anterior).
   * La comisión se calcula sobre el neto SIN IGV (el IGV no es ingreso de la tienda) con el
   * porcentaje de cada integrante; las anuladas no cuentan.
   */
  commissions(user: AuthUser, q: Range) {
    return this.run(user, q, async (tx, ctx) => {
      const rows = (
        await tx.execute(sql`
          with s as (
            select seller_id, count(*) as tickets, sum(total_cents) as sold
              from sales
             where status = 'completed' and ${ctx.inRange(sql`created_at`)} ${ctx.branch(sql`branch_id`)}
             group by seller_id
          ), r as (
            select sa.seller_id, count(*) as returns, sum(r.difference_cents) as diff
              from returns r join sales sa on sa.id = r.sale_id
             where ${ctx.inRange(sql`r.created_at`)} ${ctx.branch(sql`r.branch_id`)}
             group by sa.seller_id
          )
          select m.id as membership_id, u.name, m.role, m.commission_bp,
                 coalesce(s.tickets, 0) as tickets, coalesce(s.sold, 0) as sold,
                 coalesce(r.returns, 0) as returns, coalesce(r.diff, 0) as diff
            from memberships m
            join users u on u.id = m.user_id
            left join s on s.seller_id = m.id
            left join r on r.seller_id = m.id
           where s.seller_id is not null or r.seller_id is not null
           order by coalesce(s.sold, 0) + coalesce(r.diff, 0) desc`)
      ).rows as Record<string, unknown>[];
      const sellers = rows.map((r) => {
        const net = n(r.sold) + n(r.diff);
        const netExTax = ctx.exTax(net);
        const bp = r.commission_bp === null ? null : n(r.commission_bp);
        return {
          membershipId: r.membership_id as string,
          name: r.name as string,
          role: r.role as string,
          tickets: n(r.tickets),
          soldCents: n(r.sold),
          returns: n(r.returns),
          returnsCents: n(r.diff),
          netCents: net,
          netExTaxCents: netExTax,
          commissionBp: bp,
          commissionCents: bp === null ? 0 : Math.round((netExTax * bp) / 10_000),
        };
      });
      return { range: ctx.range, sellers, totals: { netCents: sellers.reduce((a, x) => a + x.netCents, 0), commissionCents: sellers.reduce((a, x) => a + x.commissionCents, 0) } };
    });
  }

  private run<T>(user: AuthUser, q: Partial<Range>, fn: (tx: Tx, ctx: ReportContext) => Promise<T>) {
    const branchId = q.branchId ?? user.branchId ?? undefined;
    if (branchId) assertBranchAccess(user, branchId);

    return this.db.withTenant(user.tenantId, async (tx) => {
      const [store] = await tx.select({ tz: tenants.timezone, taxRateBp: tenants.taxRateBp }).from(tenants);
      const today = localDate(store.tz, new Date());
      const to = q.to ?? today;
      const from = q.from ?? shiftDate(to, -29);
      if (from > to) throw new BadRequestException('"from" debe ser anterior o igual a "to"');
      if (shiftDate(from, 366) < to) throw new BadRequestException('El rango máximo es de un año');

      const showCosts = hasPermission(user.role, 'costs.read');
      const ctx: ReportContext = {
        tz: store.tz,
        range: { from, to, timezone: store.tz },
        // Límites del día en la zona de la tienda: [from 00:00, to+1 00:00)
        inRange: (col) =>
          sql`${col} >= (${from}::date)::timestamp at time zone ${store.tz} and ${col} < ((${to}::date + 1))::timestamp at time zone ${store.tz}`,
        branch: (col) => (branchId ? sql`and ${col} = ${branchId}` : sql``),
        exTax: (cents) => Math.round((cents * 10_000) / (10_000 + store.taxRateBp)),
        costs: <C extends object>(fields: C) => (showCosts ? fields : ({} as Partial<C>)),
      };
      return fn(tx, ctx);
    });
  }
}

interface ReportContext {
  tz: string;
  range: { from: string; to: string; timezone: string };
  inRange: (col: SQL) => SQL;
  branch: (col: SQL) => SQL;
  /** Monto sin IGV (los precios de la tienda incluyen IGV; ver docs/07-reportes.md). */
  exTax: (cents: number) => number;
  /** Devuelve los campos de costo solo si el rol tiene costs.read. */
  costs: <C extends object>(fields: C) => C | Partial<C>;
}

const round1 = (x: number) => Math.round(x * 10) / 10;

/** Fecha local (YYYY-MM-DD) en una zona horaria IANA. */
