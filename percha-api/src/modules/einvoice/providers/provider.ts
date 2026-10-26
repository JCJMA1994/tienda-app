import type { EDoc } from '../document';
import type { EGuide } from '../guide';

export interface OseConfig {
  apiUrl: string;
  token: string;
}

/**
 * Resultado de enviar o consultar un comprobante:
 * - accepted: SUNAT lo aceptó.
 * - rejected: SUNAT/OSE lo rechazó (no se reintenta; se corrige con otro comprobante).
 * - sent: el OSE lo recibió pero SUNAT aún no responde (boletas van en resumen diario):
 *   se consulta después.
 */
export interface OseResult {
  state: 'accepted' | 'rejected' | 'sent';
  description?: string;
  pdfUrl?: string;
  hash?: string;
  qr?: string;
  raw?: unknown;
}

export interface EInvoiceProvider {
  readonly name: string;
  send(doc: EDoc, cfg: OseConfig): Promise<OseResult>;
  /** null si el OSE no conoce el comprobante. */
  query(doc: EDoc, cfg: OseConfig): Promise<OseResult | null>;
  /** Guía de remisión remitente (opcional: no todos los OSE la ofrecen). */
  sendGuide?(guide: EGuide, cfg: OseConfig): Promise<OseResult>;
  queryGuide?(guide: EGuide, cfg: OseConfig): Promise<OseResult | null>;
}

/** Error de red o del OSE caído: el comprobante queda en "error" y se reintenta. */
export class OseUnavailableError extends Error {}

export const EINVOICE_PROVIDERS = Symbol('EINVOICE_PROVIDERS');
