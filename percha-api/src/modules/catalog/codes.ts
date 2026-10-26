/**
 * Generación de códigos legibles para SKU y de códigos de barras internos.
 */

/** "Negro" -> "NEG", "Azul marino" -> "AZU", "XL" -> "XL", "28" -> "28". */
export function valueCode(value: string): string {
  const clean = value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, '');
  if (!clean) return 'X';
  return clean.length <= 4 ? clean : clean.slice(0, 3);
}

/** Código único dentro de un atributo: si "NEG" ya existe, usa "NEG2", "NEG3"... */
export function uniqueCode(value: string, taken: Set<string>): string {
  const base = valueCode(value);
  let code = base;
  for (let n = 2; taken.has(code); n++) code = `${base}${n}`;
  taken.add(code);
  return code;
}

/** Prefijo de SKU a partir del nombre: "Vestido midi" -> "VES". */
export function skuPrefix(name: string): string {
  return valueCode(name.split(/\s+/)[0] ?? name).slice(0, 3).padEnd(3, 'X');
}

/**
 * EAN-13 de uso interno. El rango GS1 20–29 está reservado para uso dentro de la tienda,
 * así que no choca con códigos de fábrica y cualquier lector lo reconoce.
 * Formato: "20" + correlativo de 10 dígitos + dígito verificador.
 */
export function internalEan13(sequence: number): string {
  const body = `20${String(sequence).padStart(10, '0')}`;
  if (body.length !== 12) throw new Error('Se agotó el rango de códigos internos');
  return body + ean13CheckDigit(body);
}

export function ean13CheckDigit(first12: string): string {
  const sum = [...first12].reduce((acc, d, i) => acc + Number(d) * (i % 2 === 0 ? 1 : 3), 0);
  return String((10 - (sum % 10)) % 10);
}

/** Producto cartesiano: { Talla:[S,M], Color:[Negro] } -> [{Talla:S,Color:Negro},{Talla:M,Color:Negro}] */
export function cartesian(matrix: [string, string[]][]): Record<string, string>[] {
  return matrix.reduce<Record<string, string>[]>(
    (acc, [name, values]) => acc.flatMap((combo) => values.map((v) => ({ ...combo, [name]: v }))),
    [{}],
  );
}

/** Clave estable para comparar combinaciones sin importar el orden de las propiedades. */
export function optionsKey(options: Record<string, string>): string {
  return Object.keys(options)
    .sort()
    .map((k) => `${k}=${options[k]}`)
    .join('|');
}
