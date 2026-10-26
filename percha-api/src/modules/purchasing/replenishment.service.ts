import { Inject, Injectable } from '@nestjs/common';
import { sql } from 'drizzle-orm';
import { z } from 'zod';
import { assertBranchAccess, AuthUser } from '../../common/auth-user';
import { DatabaseService } from '../../database/database.service';
import { byUrgency, suggest } from './replenishment';

export const SuggestionsQuerySchema = z.object({
  branchId: z.string().uuid(),
  /** Ventana de ventas que se mira (días). */
  windowDays: z.coerce.number().int().min(7).max(180).default(28),
  /** Cuántos días de venta debe cubrir el pedido. */
  coverDays: z.coerce.number().int().min(7).max(120).default(30),
  /** Cuánto tarda el proveedor en entregar. */
  leadDays: z.coerce.number().int().min(0).max(60).default(7),
});

type Row = {
  variant_id: string;
  sku: string;
  options: Record<string, string>;
  product_id: string;
  product_name: string;
  stock: number;
  min_quantity: number;
  demand: number;
  incoming: number;
  supplier_id: string | null;
  supplier_name: string | null;
  unit_cost_cents: number;
};

/**
 * Reposición sugerida: qué pedir, por talla y color, según lo que realmente se vende.
 * Lee el kardex (ventas netas de devoluciones y anulaciones), el stock, el mínimo y lo que
 * ya viene en órdenes abiertas. Agrupa por el último proveedor de cada variante, listo para
 * crear las órdenes de compra.
 */
@Injectable()
export class ReplenishmentService {
  constructor(@Inject(DatabaseService) private readonly db: DatabaseService) {}

  suggestions(user: AuthUser, q: z.infer<typeof SuggestionsQuerySchema>) {
    assertBranchAccess(user, q.branchId);
    return this.db.withTenant(user.tenantId, async (tx) => {
      const { rows } = await tx.execute<Row>(sql`
        with demand as (
          select variant_id, -sum(quantity)::int as units
          from stock_movements
          where branch_id = ${q.branchId}
            and created_at >= now() - make_interval(days => ${q.windowDays})
            and type in ('sale', 'exchange_out', 'sale_void', 'return_in')
          group by variant_id
        ),
        incoming as (
          select i.variant_id, sum(i.quantity_ordered - i.quantity_received)::int as units
          from purchase_order_items i
          join purchase_orders o on o.id = i.purchase_order_id
          where o.branch_id = ${q.branchId} and o.status in ('ordered', 'partial')
          group by i.variant_id
        ),
        last_buy as (
          select distinct on (i.variant_id) i.variant_id, o.supplier_id, i.unit_cost_cents
          from purchase_order_items i
          join purchase_orders o on o.id = i.purchase_order_id
          where o.status <> 'cancelled'
          order by i.variant_id, o.created_at desc
        )
        select v.id as variant_id, v.sku, v.options, p.id as product_id, p.name as product_name,
               coalesce(s.quantity, 0)::int as stock, coalesce(s.min_quantity, 0)::int as min_quantity,
               coalesce(d.units, 0)::int as demand, coalesce(inc.units, 0)::int as incoming,
               lb.supplier_id, sup.name as supplier_name,
               coalesce(lb.unit_cost_cents, nullif(v.avg_cost_cents, 0), p.cost_cents)::int as unit_cost_cents
        from variants v
        join products p on p.id = v.product_id
        left join stock_levels s on s.variant_id = v.id and s.branch_id = ${q.branchId}
        left join demand d on d.variant_id = v.id
        left join incoming inc on inc.variant_id = v.id
        left join last_buy lb on lb.variant_id = v.id
        left join suppliers sup on sup.id = lb.supplier_id
        where v.active and p.active
          and (coalesce(d.units, 0) > 0 or coalesce(s.quantity, 0) < coalesce(s.min_quantity, 0))`);

      const items = rows
        .map((r) => {
          const s = suggest({ stock: r.stock, minQuantity: r.min_quantity, demand: r.demand, incoming: r.incoming }, q);
          return {
            variantId: r.variant_id,
            sku: r.sku,
            productId: r.product_id,
            productName: r.product_name,
            options: r.options,
            stock: r.stock,
            minQuantity: r.min_quantity,
            soldInWindow: r.demand,
            incoming: r.incoming,
            supplierId: r.supplier_id,
            unitCostCents: r.unit_cost_cents,
            ...s,
          };
        })
        .filter((i) => i.quantity > 0)
        .sort(byUrgency);

      // Agrupado por proveedor (el último al que se le compró cada variante).
      const groups = new Map<string, { supplierId: string | null; supplierName: string | null; items: typeof items; totalCents: number; units: number }>();
      for (const i of items) {
        const k = i.supplierId ?? 'none';
        const g = groups.get(k) ?? { supplierId: i.supplierId, supplierName: rows.find((r) => r.supplier_id === i.supplierId)?.supplier_name ?? null, items: [], totalCents: 0, units: 0 };
        g.items.push(i);
        g.totalCents += i.quantity * i.unitCostCents;
        g.units += i.quantity;
        groups.set(k, g);
      }
      return {
        params: q,
        totals: { variants: items.length, units: items.reduce((a, i) => a + i.quantity, 0), costCents: items.reduce((a, i) => a + i.quantity * i.unitCostCents, 0) },
        // Primero los proveedores conocidos con más urgencia; "sin proveedor" al final.
        suppliers: [...groups.values()].sort((a, b) => (a.supplierId ? 0 : 1) - (b.supplierId ? 0 : 1) || byUrgency(a.items[0], b.items[0])),
      };
    });
  }
}
