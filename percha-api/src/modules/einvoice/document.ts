import { DomainError } from '../../common/domain-error';
import { isValidRuc } from '../../common/peru';

/**
 * Comprobante en formato NEUTRO (independiente del OSE). Montos en céntimos.
 * Los adaptadores (Nubefact, etc.) lo traducen a su JSON.
 */
export type EDocKind = 'boleta' | 'factura' | 'nota_credito';
export type CustomerDocType = 'none' | 'dni' | 'ruc' | 'ce';

export interface EDocCustomer {
  docType: CustomerDocType;
  docNumber: string | null;
  name: string;
  address?: string | null;
}

export interface EDocItem {
  code: string;
  description: string;
  quantity: number;
  /** Valor de venta (sin IGV) de la línea. */
  subtotalCents: number;
  igvCents: number;
  /** Precio de venta (con IGV) de la línea. */
  totalCents: number;
  igvType: 'gravado' | 'exonerado';
}

export interface EDoc {
  kind: EDocKind;
  serie: string;
  numero: number;
  issueDate: string; // YYYY-MM-DD, fecha local de la tienda
  currency: 'PEN' | 'USD';
  taxRateBp: number;
  customer: EDocCustomer;
  items: EDocItem[];
  totals: { gravadaCents: number; exoneradaCents: number; igvCents: number; totalCents: number };
  reference?: {
    kind: 'boleta' | 'factura';
    serie: string;
    numero: number;
    /** Catálogo 09 SUNAT: 01 anulación de la operación, 07 devolución por ítem. */
    reasonCode: '01' | '07';
    reasonText: string;
  };
}

export interface LineInput {
  code: string;
  description: string;
  quantity: number;
  /** Monto de la línea; si `inclusive`, ya incluye IGV. */
  amountCents: number;
}

/**
 * Ítems con IGV calculado POR LÍNEA y totales como SUMA de líneas: el OSE valida que los
 * totales cuadren con los ítems, así que se arma de abajo hacia arriba.
 */
export function buildItems(lines: LineInput[], taxRateBp: number, inclusive: boolean): EDocItem[] {
  return lines.map((l) => {
    if (taxRateBp === 0) {
      return { code: l.code, description: l.description, quantity: l.quantity, subtotalCents: l.amountCents, igvCents: 0, totalCents: l.amountCents, igvType: 'exonerado' as const };
    }
    if (inclusive) {
      const igv = Math.round((l.amountCents * taxRateBp) / (10_000 + taxRateBp));
      return { code: l.code, description: l.description, quantity: l.quantity, subtotalCents: l.amountCents - igv, igvCents: igv, totalCents: l.amountCents, igvType: 'gravado' as const };
    }
    const igv = Math.round((l.amountCents * taxRateBp) / 10_000);
    return { code: l.code, description: l.description, quantity: l.quantity, subtotalCents: l.amountCents, igvCents: igv, totalCents: l.amountCents + igv, igvType: 'gravado' as const };
  });
}

export function totalsOf(items: EDocItem[]): EDoc['totals'] {
  const sum = (f: (i: EDocItem) => number) => items.reduce((a, i) => a + f(i), 0);
  return {
    gravadaCents: sum((i) => (i.igvType === 'gravado' ? i.subtotalCents : 0)),
    exoneradaCents: sum((i) => (i.igvType === 'exonerado' ? i.subtotalCents : 0)),
    igvCents: sum((i) => i.igvCents),
    totalCents: sum((i) => i.totalCents),
  };
}


/** Tope SUNAT: boletas por más de S/ 700 deben identificar al comprador. */
export const BOLETA_ANON_LIMIT_CENTS = 70_000;

export function normalizeCustomer(kind: 'boleta' | 'factura', totalCents: number, c?: Partial<EDocCustomer>): EDocCustomer {
  const docType = c?.docType ?? 'none';
  const number = c?.docNumber?.trim() || null;
  const name = c?.name?.trim() || '';

  if (kind === 'factura') {
    if (docType !== 'ruc' || !number || !isValidRuc(number)) {
      throw DomainError.invalid('INVALID_RUC', 'La factura requiere un RUC válido del cliente');
    }
    if (name.length < 2) throw DomainError.invalid('CUSTOMER_NAME_REQUIRED', 'La factura requiere la razón social del cliente');
    return { docType, docNumber: number, name, address: c?.address ?? null };
  }

  if (docType === 'none') {
    if (totalCents > BOLETA_ANON_LIMIT_CENTS) {
      throw DomainError.invalid('DOCUMENT_CUSTOMER_REQUIRED', 'Las boletas mayores a S/ 700 deben identificar al cliente (DNI, RUC o CE)');
    }
    return { docType: 'none', docNumber: null, name: name || 'CLIENTES VARIOS' };
  }
  const valid =
    (docType === 'dni' && /^\d{8}$/.test(number ?? '')) ||
    (docType === 'ruc' && isValidRuc(number ?? '')) ||
    (docType === 'ce' && /^[A-Z0-9]{8,12}$/i.test(number ?? ''));
  if (!valid) throw DomainError.invalid('INVALID_CUSTOMER_DOC', `Número de ${docType.toUpperCase()} inválido`);
  if (name.length < 2) throw DomainError.invalid('CUSTOMER_NAME_REQUIRED', 'Indica el nombre del cliente');
  return { docType, docNumber: number, name, address: c?.address ?? null };
}

export { isValidRuc };
