import { createHmac, timingSafeEqual } from 'node:crypto';
import type { CheckoutRequest, CheckoutResult, NormalizedEvent, PaymentProvider } from './provider';
import { ProviderError } from './provider';

/**
 * Stripe Checkout para tarjetas (útil para clientes con tarjetas internacionales).
 *
 * Limitaciones a tener presentes:
 * - Stripe NO ofrece Yape ni Plin; esos van por Culqi.
 * - Stripe no lista Perú como país para abrir cuenta: se necesita una entidad en un país
 *   soportado (p. ej. una LLC en EE. UU. vía Stripe Atlas). Verifícalo en stripe.com/global.
 *
 * Firma de webhooks: cabecera Stripe-Signature "t=...,v1=..." = HMAC-SHA256(secreto, `${t}.${body}`).
 * Se exige el cuerpo crudo (sin parsear) y una antigüedad máxima de 5 minutos.
 */
export class StripeProvider implements PaymentProvider {
  readonly name = 'stripe' as const;
  readonly methods = ['card'] as PaymentProvider['methods'];

  constructor(
    private readonly secretKey: string,
    private readonly webhookSecret: string,
    private readonly appUrl: string,
  ) {}

  async createCheckout(req: CheckoutRequest): Promise<CheckoutResult> {
    const form = new URLSearchParams({
      mode: 'payment',
      success_url: `${this.appUrl}/billing?paid=${req.invoiceId}`,
      cancel_url: `${this.appUrl}/billing`,
      client_reference_id: req.invoiceId,
      customer_email: req.customer.email,
      'metadata[invoice_id]': req.invoiceId,
      'payment_intent_data[metadata][invoice_id]': req.invoiceId,
      'line_items[0][quantity]': '1',
      'line_items[0][price_data][currency]': req.currency.toLowerCase(),
      'line_items[0][price_data][unit_amount]': String(req.amountCents),
      'line_items[0][price_data][product_data][name]': req.description,
    });
    const res = await fetch('https://api.stripe.com/v1/checkout/sessions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${this.secretKey}`, 'Content-Type': 'application/x-www-form-urlencoded' },
      body: form,
      signal: AbortSignal.timeout(15_000),
    });
    const json = (await res.json().catch(() => ({}))) as { id?: string; url?: string; error?: { message?: string } };
    if (!res.ok || !json.id) throw new ProviderError(json.error?.message ?? `Stripe respondió ${res.status}`, res.status);
    return { providerRef: json.id, kind: 'redirect', url: json.url };
  }

  async parseWebhook(rawBody: Buffer, headers: Record<string, string | string[] | undefined>): Promise<NormalizedEvent | null> {
    if (!verifyStripeSignature(rawBody, String(headers['stripe-signature'] ?? ''), this.webhookSecret)) return null;
    const event = JSON.parse(rawBody.toString('utf8')) as {
      id: string;
      type: string;
      data: { object: { id: string; payment_status?: string; metadata?: { invoice_id?: string } } };
    };
    const obj = event.data.object;
    const paid = event.type === 'checkout.session.completed' && obj.payment_status === 'paid';
    return {
      eventId: event.id,
      type: paid ? 'payment.succeeded' : event.type === 'checkout.session.expired' ? 'payment.failed' : 'ignored',
      providerRef: obj.id,
      invoiceId: obj.metadata?.invoice_id,
      method: 'card',
      raw: event,
    };
  }
}

export function verifyStripeSignature(rawBody: Buffer, header: string, secret: string, now = Date.now(), toleranceSec = 300): boolean {
  const parts = Object.fromEntries(header.split(',').map((p) => p.split('=') as [string, string]));
  const t = Number(parts.t);
  const v1 = parts.v1;
  if (!t || !v1 || Math.abs(now / 1000 - t) > toleranceSec) return false;
  const expected = createHmac('sha256', secret).update(`${t}.${rawBody.toString('utf8')}`).digest('hex');
  const a = Buffer.from(expected);
  const b = Buffer.from(v1);
  return a.length === b.length && timingSafeEqual(a, b);
}
