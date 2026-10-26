/**
 * Reglas de la reposición sugerida (puras, probadas sin base de datos).
 *
 * Para cada variante (talla × color) de una sucursal:
 *   ritmo     = unidades vendidas netas en la ventana / días de la ventana
 *   objetivo  = ritmo × (días a cubrir + días que tarda el proveedor)
 *   pedir     = máx(objetivo, stock mínimo) − stock actual − lo que ya viene en camino
 * Se redondea hacia arriba (no se piden medias prendas) y no se sugiere nada si no hace falta.
 */
export interface ReplenishmentInput {
  stock: number;
  minQuantity: number;
  demand: number; // unidades netas vendidas en la ventana (ventas − devoluciones)
  incoming: number; // pedidas y aún no recibidas
}

export interface ReplenishmentParams {
  windowDays: number;
  coverDays: number;
  leadDays: number;
}

export type Urgency = 'out' | 'critical' | 'soon' | 'planned';

export function suggest(i: ReplenishmentInput, p: ReplenishmentParams) {
  const rate = Math.max(i.demand, 0) / p.windowDays;
  const target = Math.ceil(rate * (p.coverDays + p.leadDays));
  const available = Math.max(i.stock, 0) + Math.max(i.incoming, 0);
  const quantity = Math.max(Math.max(target, i.minQuantity) - available, 0);
  const coverageDays = rate > 0 ? Math.floor(available / rate) : null;
  // Urgencia: agotada; se agota antes de que llegue un pedido nuevo; dentro del periodo; planificada.
  const urgency: Urgency =
    i.stock <= 0 ? 'out' : coverageDays !== null && coverageDays < p.leadDays ? 'critical' : coverageDays !== null && coverageDays < p.leadDays + p.coverDays / 2 ? 'soon' : 'planned';
  return { quantity, ratePerWeek: Math.round(rate * 7 * 10) / 10, coverageDays, urgency };
}

const ORDER: Record<Urgency, number> = { out: 0, critical: 1, soon: 2, planned: 3 };
export const byUrgency = (a: { urgency: Urgency; coverageDays: number | null }, b: { urgency: Urgency; coverageDays: number | null }) =>
  ORDER[a.urgency] - ORDER[b.urgency] || (a.coverageDays ?? 0) - (b.coverageDays ?? 0);
