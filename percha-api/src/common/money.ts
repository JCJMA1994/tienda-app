/**
 * Utilidades de dinero en céntimos (enteros). Nunca usar floats para montos.
 */

/** Porcentaje en puntos básicos: applyBp(10000, 1800) = 1800 (18%). */
export function applyBp(amount: number, bp: number): number {
  return Math.round((amount * bp) / 10_000);
}

/**
 * Impuesto de un total.
 * - Precios con IGV incluido: igv = total * t / (1 + t)
 * - Precios sin IGV: igv = base * t (y el total se incrementa)
 */
export function computeTax(amount: number, rateBp: number, pricesIncludeTax: boolean) {
  if (pricesIncludeTax) {
    const tax = Math.round((amount * rateBp) / (10_000 + rateBp));
    return { total: amount, tax };
  }
  const tax = applyBp(amount, rateBp);
  return { total: amount + tax, tax };
}

/**
 * Reparte un monto entero entre partes proporcionales a `weights` sin perder céntimos
 * (método del mayor residuo). Se usa para prorratear el descuento del ticket en las líneas,
 * lo que permite devolver una prenda al precio que realmente se pagó.
 */
export function allocate(amount: number, weights: number[]): number[] {
  const totalWeight = weights.reduce((a, b) => a + b, 0);
  if (totalWeight === 0) return weights.map(() => 0);
  const raw = weights.map((w) => (amount * w) / totalWeight);
  const floored = raw.map(Math.floor);
  let remainder = amount - floored.reduce((a, b) => a + b, 0);
  const order = raw
    .map((r, i) => ({ i, frac: r - Math.floor(r) }))
    .sort((a, b) => b.frac - a.frac);
  for (const { i } of order) {
    if (remainder <= 0) break;
    floored[i] += 1;
    remainder -= 1;
  }
  return floored;
}

/** "S/ 1,240.00" para textos (mensajes, correos). */
export function formatSoles(cents: number) {
  return `S/ ${(cents / 100).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}
