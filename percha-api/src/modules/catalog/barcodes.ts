/**
 * Normalización de códigos leídos (misma regla que la app, `lib/core/barcodes.dart`):
 * quita espacios/caracteres de control y trata UPC-A (12) y EAN-13 con 0 inicial como el
 * mismo código.
 */
export function barcodeCandidates(raw: string): string[] {
  // eslint-disable-next-line no-control-regex
  const code = raw.replace(/[\x00-\x1F\x7F\s]/g, '');
  if (!code) return [];
  const out = new Set([code]);
  if (/^\d{12}$/.test(code)) out.add(`0${code}`);
  if (/^0\d{12}$/.test(code)) out.add(code.slice(1));
  return [...out];
}
