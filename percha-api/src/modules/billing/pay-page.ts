/**
 * Página mínima con Culqi Checkout para pagar una ORDEN (Yape, billeteras, agentes).
 *
 * VERIFICAR antes de producción contra la guía de "Culqi Checkout" de docs.culqi.com:
 * la URL del script y los nombres de `settings`/`options` siguen la versión vigente al
 * escribir esto. Es el único lugar a ajustar si Culqi cambia su librería.
 *
 * Al completarse el pago, Culqi notifica por webhook y el backend acredita la factura
 * (verificando la orden contra la API de Culqi). Esta página no acredita nada por sí sola.
 */
const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);

export function culqiPayPage(d: {
  publicKey: string;
  orderId: string;
  amountCents: number;
  currency: string;
  title: string;
  store: string;
  returnUrl: string;
}): string {
  // Los datos van como JSON en un <script type="application/json"> (nunca interpolados en JS).
  const config = JSON.stringify(d).replace(/</g, '\\u003c');
  const amount = `${d.currency === 'PEN' ? 'S/' : d.currency} ${(d.amountCents / 100).toFixed(2)}`;
  return `<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Pagar ${esc(d.title)}</title>
<style>
  body{margin:0;font-family:system-ui,-apple-system,"Segoe UI",sans-serif;background:#F4F4F2;color:#18181B;display:grid;place-items:center;min-height:100vh}
  main{max-width:360px;padding:32px 24px;text-align:center}
  h1{font-size:22px;margin:0 0 4px} p{color:#52525B;margin:4px 0 24px}
  .amount{font-size:32px;font-weight:700;margin:8px 0 24px}
  button{width:100%;height:52px;border:0;border-radius:12px;background:#3F37C9;color:#fff;font-size:16px;font-weight:600}
  a{display:block;margin-top:16px;color:#3F37C9}
</style>
</head>
<body>
<main>
  <h1>${esc(d.title)}</h1>
  <p>${esc(d.store)}</p>
  <div class="amount">${esc(amount)}</div>
  <button id="pay" type="button">Pagar con Yape u otro medio</button>
  <a href="${esc(d.returnUrl)}">Volver a la app</a>
  <p id="msg" role="status"></p>
</main>
<script type="application/json" id="cfg">${config}</script>
<script src="https://js.culqi.com/checkout-js"></script>
<script>
  const cfg = JSON.parse(document.getElementById('cfg').textContent);
  const msg = document.getElementById('msg');
  const checkout = new CulqiCheckout(cfg.publicKey, {
    settings: { title: cfg.title, currency: cfg.currency, amount: cfg.amountCents, order: cfg.orderId },
    options: {
      lang: 'auto',
      modal: true,
      paymentMethods: { yape: true, billetera: true, bancaMovil: true, agente: true, tarjeta: false, cuotealo: false },
    },
  });
  checkout.culqi = function () {
    if (checkout.order) {
      msg.textContent = 'Listo. Confirmaremos tu pago en unos segundos; ya puedes volver a la app.';
    } else if (checkout.error) {
      msg.textContent = checkout.error.user_message || 'No se pudo completar el pago.';
    }
  };
  document.getElementById('pay').addEventListener('click', () => checkout.open());
</script>
</body>
</html>`;
}

/**
 * Registrar tarjeta para el cobro automático. Culqi Checkout solo con "tarjeta": devuelve un
 * token que esta página envía a POST /v1/billing/card-setup junto al enlace firmado.
 * Misma advertencia: verificar el uso de CulqiCheckout contra la guía vigente.
 */
export function culqiCardSetupPage(d: { publicKey: string; token: string; returnUrl: string }): string {
  const config = JSON.stringify(d).replace(/</g, '\\u003c');
  return `<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Registrar tarjeta · Percha</title>
<style>
  body{margin:0;font-family:system-ui,-apple-system,"Segoe UI",sans-serif;background:#F4F4F2;color:#18181B;display:grid;place-items:center;min-height:100vh}
  main{max-width:360px;padding:32px 24px}
  h1{font-size:22px;margin:0 0 8px} p{color:#52525B;margin:0 0 20px;line-height:1.5}
  label{display:block;font-size:13px;font-weight:600;margin-bottom:6px}
  input{width:100%;box-sizing:border-box;height:48px;border:1px solid #D4D4D8;border-radius:12px;padding:0 14px;font-size:16px;margin-bottom:16px}
  button{width:100%;height:52px;border:0;border-radius:12px;background:#3F37C9;color:#fff;font-size:16px;font-weight:600}
  a{display:block;margin-top:16px;color:#3F37C9;text-align:center}
</style>
</head>
<body>
<main>
  <h1>Cobro automático</h1>
  <p>Registra tu tarjeta y cada mes pagaremos tu plan sin que tengas que hacer nada. La tarjeta la guarda Culqi; Percha no la ve.</p>
  <label for="phone">Celular (9 dígitos)</label>
  <input id="phone" inputmode="numeric" maxlength="9" autocomplete="tel">
  <button id="go" type="button">Registrar tarjeta</button>
  <a href="${esc(d.returnUrl)}">Volver a la app</a>
  <p id="msg" role="status"></p>
</main>
<script type="application/json" id="cfg">${config}</script>
<script src="https://js.culqi.com/checkout-js"></script>
<script>
  const cfg = JSON.parse(document.getElementById('cfg').textContent);
  const msg = document.getElementById('msg');
  const phone = document.getElementById('phone');
  const checkout = new CulqiCheckout(cfg.publicKey, {
    settings: { title: 'Percha', currency: 'PEN', amount: 0 },
    options: { lang: 'auto', modal: true, paymentMethods: { tarjeta: true, yape: false, billetera: false, bancaMovil: false, agente: false, cuotealo: false } },
  });
  checkout.culqi = async function () {
    if (!checkout.token) {
      msg.textContent = (checkout.error && checkout.error.user_message) || 'No se pudo registrar la tarjeta.';
      return;
    }
    checkout.close();
    msg.textContent = 'Guardando…';
    const res = await fetch('/v1/billing/card-setup', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ t: cfg.token, token: checkout.token.id, phone: phone.value }),
    });
    msg.textContent = res.ok ? 'Listo. El cobro automático quedó activo; ya puedes volver a la app.' : 'No se pudo guardar la tarjeta. Intenta de nuevo.';
  };
  document.getElementById('go').addEventListener('click', () => {
    if (!/^\\d{9}$/.test(phone.value)) { msg.textContent = 'Ingresa un celular de 9 dígitos.'; return; }
    checkout.open();
  });
</script>
</body>
</html>`;
}
