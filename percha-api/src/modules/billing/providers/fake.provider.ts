import { createHmac, timingSafeEqual } from 'node:crypto';
import type { CheckoutRequest, CheckoutResult, NormalizedEvent, PaymentProvider } from './provider';

/**
 * Pasarela simulada para desarrollo y pruebas (se activa con BILLING_FAKE_SECRET; prohibida en
 * producción). Permite probar el ciclo completo —prueba, factura, gracia, bloqueo, pago— sin
 * llaves reales ni red.
 * Webhook: cuerpo {"id","type":"paid","ref"} firmado con cabecera x-fake-signature = HMAC-SHA256.
 */
export class FakeProvider implements PaymentProvider {
  readonly name = 'fake' as const;
  readonly methods = ['card', 'yape', 'wallet_qr'] as PaymentProvider['methods'];

  constructor(private readonly secret: string) {}

  async createCheckout(req: CheckoutRequest): Promise<CheckoutResult> {
    return { providerRef: `fake_${req.invoiceId}`, kind: 'redirect', url: `https://pagos.example/fake/${req.invoiceId}` };
  }

  async saveCard(req: { token: string }) {
    return { customerId: 'fake_cus', cardId: req.token };
  }

  /** La tarjeta "card_fail" siempre es rechazada. */
  async chargeSavedCard(req: { invoiceId: string; cardId: string }) {
    return req.cardId === 'card_fail'
      ? { paid: false, providerRef: '', message: 'Tarjeta rechazada' }
      : { paid: true, providerRef: `fake_chg_${req.invoiceId}` };
  }

  async parseWebhook(rawBody: Buffer, headers: Record<string, string | string[] | undefined>): Promise<NormalizedEvent | null> {
    const sig = Buffer.from(String(headers['x-fake-signature'] ?? ''));
    const expected = Buffer.from(createHmac('sha256', this.secret).update(rawBody).digest('hex'));
    if (sig.length !== expected.length || !timingSafeEqual(sig, expected)) return null;
    const body = JSON.parse(rawBody.toString('utf8')) as { id: string; type: string; ref: string; method?: string };
    return { eventId: body.id, type: body.type === 'paid' ? 'payment.succeeded' : 'ignored', providerRef: body.ref, method: body.method ?? 'yape', raw: body };
  }
}
