/**
 * Contrato común de las pasarelas. El motor de facturación (BillingService) no sabe nada de
 * Culqi ni de Stripe: cada adaptador traduce entre este contrato y su API.
 */
export type ProviderName = 'culqi' | 'stripe' | 'fake';

/** Cómo quiere pagar el dueño esta factura. */
export type PayMethod = 'card' | 'yape' | 'wallet_qr';

export interface CheckoutRequest {
  invoiceId: string;
  invoiceNumber: number;
  amountCents: number;
  currency: string;
  description: string;
  method: PayMethod;
  customer: { email: string; name: string };
}

export interface CheckoutResult {
  providerRef: string;
  /**
   * - `culqi_checkout`: la app abre Culqi Checkout con `publicKey` + `orderId`
   *   (Yape, billeteras por QR, tarjeta).
   * - `redirect`: la app abre `url` (Stripe Checkout).
   */
  kind: 'culqi_checkout' | 'redirect';
  url?: string;
  data?: Record<string, unknown>;
}

export interface NormalizedEvent {
  /** Id único del evento en la pasarela (idempotencia). */
  eventId: string;
  type: 'payment.succeeded' | 'payment.failed' | 'ignored';
  providerRef?: string;
  invoiceId?: string;
  method?: string;
  raw: unknown;
}

export interface PaymentProvider {
  readonly name: ProviderName;
  readonly methods: PayMethod[];
  createCheckout(req: CheckoutRequest): Promise<CheckoutResult>;
  /** Verifica autenticidad y traduce el webhook. Devuelve null si no es válido. */
  parseWebhook(rawBody: Buffer, headers: Record<string, string | string[] | undefined>): Promise<NormalizedEvent | null>;
  /** Solo pasarelas con tarjeta guardada (cobro automático mensual). */
  saveCard?(req: { email: string; name: string; token: string; phone: string; address: string; city: string }): Promise<{ customerId: string; cardId: string }>;
  chargeSavedCard?(req: {
    invoiceId: string;
    amountCents: number;
    currency: string;
    email: string;
    cardId: string;
    description: string;
  }): Promise<{ paid: boolean; providerRef: string; message?: string }>;
}

export const PAYMENT_PROVIDERS = Symbol('PAYMENT_PROVIDERS');

export class ProviderError extends Error {
  constructor(
    message: string,
    readonly status?: number,
  ) {
    super(message);
  }
}
