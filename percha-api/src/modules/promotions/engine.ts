/**
 * Motor de promociones (puro). La MISMA lógica existe en la app (Dart) y ambas se prueban con
 * los mismos casos (`test/fixtures/promotions-vectors.json`): el total que ve la cajera es el
 * que cobra el servidor, incluso en ventas sin conexión.
 *
 * Reglas:
 *  1. Una prenda recibe a lo sumo UNA promoción.
 *  2. "Lleva X, paga Y": se juntan las prendas elegibles de todo el ticket, de la más cara a
 *     la más barata; en cada grupo completo de X, las (X − Y) más baratas salen gratis.
 *  3. Porcentaje: a cada prenda que quede sin promoción se le aplica el mejor porcentaje
 *     vigente que le corresponda (redondeo por prenda).
 *  4. Se calculan dos formas (con y sin "lleva X, paga Y") y se aplica la que más le ahorra
 *     al cliente.
 * Orden estable: a igualdad, por id de promoción y por posición de la línea.
 */
export interface PromoLine {
  productId: string;
  categoryId: string | null;
  quantity: number;
  unitPriceCents: number;
}

export interface Promo {
  id: string;
  name: string;
  kind: 'percent' | 'buy_x_pay_y';
  percentBp?: number | null;
  buyQty?: number | null;
  payQty?: number | null;
  scope: 'all' | 'categories' | 'products';
  categoryIds: string[];
  productIds: string[];
}

export interface PromoResult {
  lines: { discountCents: number; promotionId: string | null }[];
  totalCents: number;
}

export function appliesTo(p: Promo, l: Pick<PromoLine, 'productId' | 'categoryId'>) {
  if (p.scope === 'all') return true;
  if (p.scope === 'products') return p.productIds.includes(l.productId);
  return l.categoryId !== null && p.categoryIds.includes(l.categoryId);
}

type Unit = { line: number; price: number; discount: number; promo: string | null };

function run(lines: PromoLine[], promos: Promo[], withBundles: boolean): Unit[] {
  const units: Unit[] = lines.flatMap((l, line) => Array.from({ length: l.quantity }, () => ({ line, price: l.unitPriceCents, discount: 0, promo: null as string | null })));
  const sorted = [...promos].sort((a, b) => a.id.localeCompare(b.id));

  if (withBundles) {
    for (const p of sorted.filter((x) => x.kind === 'buy_x_pay_y' && x.buyQty && x.payQty)) {
      const eligible = units
        .map((u, i) => ({ u, i }))
        .filter(({ u }) => u.promo === null && appliesTo(p, lines[u.line]))
        .sort((a, b) => b.u.price - a.u.price || a.i - b.i);
      const groups = Math.floor(eligible.length / p.buyQty!);
      for (let g = 0; g < groups; g++) {
        const group = eligible.slice(g * p.buyQty!, (g + 1) * p.buyQty!);
        group.forEach(({ u }) => (u.promo = p.id));
        // Las más baratas del grupo (al final, por el orden) salen gratis.
        group.slice(p.payQty!).forEach(({ u }) => (u.discount = u.price));
      }
    }
  }

  for (const u of units) {
    if (u.promo !== null) continue;
    let best: { id: string; off: number } | null = null;
    for (const p of sorted) {
      if (p.kind !== 'percent' || !p.percentBp || !appliesTo(p, lines[u.line])) continue;
      const off = Math.round((u.price * p.percentBp) / 10_000);
      if (!best || off > best.off) best = { id: p.id, off };
    }
    if (best && best.off > 0) {
      u.discount = best.off;
      u.promo = best.id;
    }
  }
  return units;
}

export function applyPromotions(lines: PromoLine[], promos: Promo[]): PromoResult {
  if (!promos.length || !lines.length) return { lines: lines.map(() => ({ discountCents: 0, promotionId: null })), totalCents: 0 };
  const a = run(lines, promos, true);
  const b = run(lines, promos, false);
  const sum = (u: Unit[]) => u.reduce((s, x) => s + x.discount, 0);
  const best = sum(a) >= sum(b) ? a : b;
  const out = lines.map(() => ({ discountCents: 0, promotionId: null as string | null }));
  for (const u of best) {
    out[u.line].discountCents += u.discount;
    // La línea muestra la promoción que más le descontó.
    if (u.promo && u.discount > 0) out[u.line].promotionId ??= u.promo;
  }
  return { lines: out, totalCents: sum(best) };
}
