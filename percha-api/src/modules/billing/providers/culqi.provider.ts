import type { CheckoutRequest, CheckoutResult, NormalizedEvent, PaymentProvider } from './provider';
import { ProviderError } from './provider';

const BASE = 'https://api.culqi.com/v2';

/**
 * Culqi: tarjetas (con cobro automático usando tarjeta guardada), Yape y billeteras por QR
 * (según los medios habilitados en tu cuenta Culqi).
 *
 * IMPORTANTE: los nombres de campos siguen la API v2 de Culqi (apidocs.culqi.com). Antes de
 * pasar a producción, valida cada llamada con tus llaves de integración ("test"): esta clase
 * es el único lugar a ajustar si algo difiere.
 *
 * Yape y Plin no permiten débito automático: cada mes se genera una ORDEN que el dueño paga
 * desde Culqi Checkout. Por eso el motor emite una factura y la deja abierta.
 */
export class CulqiProvider implements PaymentProvider {
  readonly name = 'culqi' as const;
  readonly methods = ['card', 'yape', 'wallet_qr'] as PaymentProvider['methods'];

  constructor(
    private readonly secretKey: string,
    private readonly publicKey: string,
  ) {}

  async createCheckout(req: CheckoutRequest): Promise<CheckoutResult> {
    const [firstName, ...rest] = req.customer.name.split(' ');
    const order = await this.call<{ id: string }>('POST', '/orders', {
      amount: req.amountCents,
      currency_code: req.currency,
      description: req.description.slice(0, 80),
      order_number: `PERCHA-${req.invoiceNumber}`,
      client_details: { first_name: firstName, last_name: rest.join(' ') || firstName, email: req.customer.email },
      // La orden vence en 72 h; si no se paga, la factura sigue abierta y se genera otra.
      expiration_date: Math.floor(Date.now() / 1000) + 72 * 3600,
      confirm: false,
      metadata: { invoice_id: req.invoiceId },
    });
    return {
      providerRef: order.id,
      kind: 'culqi_checkout',
      data: { publicKey: this.publicKey, orderId: order.id, amount: req.amountCents, currency: req.currency, method: req.method },
    };
  }

  /** Culqi exige datos del cliente para guardar tarjetas: se envían los reales del dueño. */
  async saveCard(req: { email: string; name: string; token: string; phone: string; address: string; city: string }) {
    const [firstName, ...rest] = req.name.split(' ');
    const customer = await this.call<{ id: string }>('POST', '/customers', {
      first_name: firstName,
      last_name: rest.join(' ') || firstName,
      email: req.email,
      address: req.address,
      address_city: req.city,
      country_code: 'PE',
      phone_number: req.phone,
    });
    const card = await this.call<{ id: string }>('POST', '/cards', { customer_id: customer.id, token_id: req.token });
    return { customerId: customer.id, cardId: card.id };
  }

  async chargeSavedCard(req: { invoiceId: string; amountCents: number; currency: string; email: string; cardId: string; description: string }) {
    try {
      const charge = await this.call<{ id: string }>(
        'POST',
        '/charges',
        {
          amount: req.amountCents,
          currency_code: req.currency,
          email: req.email,
          source_id: req.cardId,
          description: req.description.slice(0, 80),
          metadata: { invoice_id: req.invoiceId },
        },
        // Marca el cargo como recurrente (cargo posterior sin que el cliente reingrese la tarjeta).
        { 'X-Charge-Channel': 'recurrent' },
      );
      return { paid: true, providerRef: charge.id };
    } catch (e) {
      // Tarjeta rechazada: la factura queda abierta y la tienda entra en periodo de gracia.
      if (e instanceof ProviderError && e.status && e.status < 500) return { paid: false, providerRef: '', message: e.message };
      throw e;
    }
  }

  /**
   * Verificación por "fetch-back": no se confía en el cuerpo del webhook. Se toma el id de la
   * orden y se consulta a Culqi con la llave secreta; solo si Culqi dice "paid" se acredita.
   */
  async parseWebhook(rawBody: Buffer): Promise<NormalizedEvent | null> {
    let body: Record<string, unknown>;
    try {
      body = JSON.parse(rawBody.toString('utf8'));
    } catch {
      return null;
    }
    const data = typeof body.data === 'string' ? safeJson(body.data) : (body.data as Record<string, unknown> | undefined);
    const orderId = (data?.id ?? data?.order_id) as string | undefined;
    if (!orderId || !orderId.startsWith('ord_')) return { eventId: String(body.id ?? rawBody.length), type: 'ignored', raw: body };

    const order = await this.call<{ id: string; state?: string; metadata?: { invoice_id?: string }; payment_method?: string }>('GET', `/orders/${orderId}`);
    const state = order.state ?? '';
    return {
      eventId: `${order.id}:${state}`,
      type: state === 'paid' ? 'payment.succeeded' : state === 'expired' ? 'payment.failed' : 'ignored',
      providerRef: order.id,
      invoiceId: order.metadata?.invoice_id,
      method: order.payment_method ?? 'culqi',
      raw: body,
    };
  }

  private async call<T>(method: 'GET' | 'POST', path: string, body?: unknown, headers: Record<string, string> = {}): Promise<T> {
    const res = await fetch(`${BASE}${path}`, {
      method,
      headers: { Authorization: `Bearer ${this.secretKey}`, 'Content-Type': 'application/json', ...headers },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(15_000),
    });
    const json = (await res.json().catch(() => ({}))) as Record<string, unknown>;
    if (!res.ok) {
      throw new ProviderError(String(json.user_message ?? json.merchant_message ?? `Culqi respondió ${res.status}`), res.status);
    }
    return json as T;
  }
}

function safeJson(s: string): Record<string, unknown> | undefined {
  try {
    return JSON.parse(s);
  } catch {
    return undefined;
  }
}
