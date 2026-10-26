/**
 * Página pública del catálogo: HTML liviano, sin frameworks, pensado para abrirse desde un
 * enlace de WhatsApp en un celular con datos móviles.
 *
 * Seguridad: los datos de la tienda van como JSON escapado en un <script type="application/json">
 * y TODO se pinta con textContent / createElement (nunca innerHTML con datos). CSP con nonce:
 * solo corre el script de esta página.
 */
export function storefrontPage(p: { slug: string; nonce: string; data: unknown; title: string; description: string; image: string | null; url: string }) {
  const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);
  const json = JSON.stringify({ slug: p.slug, catalog: p.data }).replace(/</g, '\\u003c');
  return `<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>${esc(p.title)}</title>
<meta name="description" content="${esc(p.description)}">
<meta property="og:type" content="website">
<meta property="og:title" content="${esc(p.title)}">
<meta property="og:description" content="${esc(p.description)}">
<meta property="og:url" content="${esc(p.url)}">
${p.image ? `<meta property="og:image" content="${esc(p.image)}">` : ''}
<meta name="theme-color" content="#171514">
<style nonce="${p.nonce}">
:root{--ground:#F7F6F4;--surface:#fff;--ink:#171514;--muted:#6B6560;--border:#E7E4E0;--accent:#171514;--onAccent:#fff;--accentSoft:#EFEEFB;--accentInk:#4B3FD1;--warn:#B93815;--warnSoft:#FDF1EC}
@media (prefers-color-scheme:dark){:root{--ground:#0D0C0B;--surface:#161514;--ink:#F5F4F2;--muted:#A39D96;--border:#2B2826;--accent:#F5F4F2;--onAccent:#0D0C0B;--accentSoft:#25223A;--accentInk:#B3ABFF;--warn:#FF9B6B;--warnSoft:#2C1810}}
*{box-sizing:border-box}body{margin:0;font-family:"Inter",system-ui,-apple-system,"Segoe UI",sans-serif;-webkit-font-smoothing:antialiased;background:var(--ground);color:var(--ink);padding-bottom:calc(88px + env(safe-area-inset-bottom))}
header{padding:20px 16px 8px}h1{font-size:26px;font-weight:650;letter-spacing:-.02em;margin:0 0 4px}header p{margin:0;color:var(--muted)}
.chips{display:flex;gap:8px;overflow-x:auto;padding:8px 16px}.chip{border:1px solid var(--border);background:var(--surface);color:var(--ink);border-radius:999px;padding:8px 14px;font-size:14px;white-space:nowrap}.chip[aria-pressed=true]{background:var(--accent);color:var(--onAccent);border-color:var(--accent)}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(160px,1fr));gap:12px;padding:8px 16px}
.card{background:var(--surface);border:1px solid var(--border);border-radius:14px;overflow:hidden;text-align:left;padding:0;color:inherit;font:inherit}
.card img,.ph{width:100%;aspect-ratio:4/5;object-fit:cover;display:block;background:var(--border)}.card div{padding:10px}.card b{display:block;font-size:14px}.price{font-weight:700;margin-top:4px}
.pill{display:inline-block;font-size:12px;font-weight:600;padding:2px 8px;border-radius:999px;margin-top:6px;background:var(--accentSoft);color:var(--accentInk)}.pill.few,.pill.out{background:var(--warnSoft);color:var(--warn)}
.bar{position:fixed;left:16px;right:16px;bottom:calc(16px + env(safe-area-inset-bottom));display:none}.bar button{width:100%}
.btn{border:0;border-radius:12px;background:var(--accent);color:var(--onAccent);font-weight:600;font-size:15px;min-height:50px;padding:0 18px}.btn[disabled]{opacity:.5}.btn.ghost{background:var(--surface);color:var(--ink);border:1px solid var(--border)}
dialog{border:0;border-radius:24px 24px 0 0;margin:auto 0 0;width:100%;max-width:560px;max-height:92vh;padding:0;background:var(--surface);color:var(--ink)}dialog::backdrop{background:rgba(0,0,0,.45)}
.sheet{padding:16px 16px calc(16px + env(safe-area-inset-bottom));overflow:auto;max-height:92vh}.gallery{display:flex;overflow-x:auto;scroll-snap-type:x mandatory;gap:8px;border-radius:16px}.gallery img{flex:0 0 100%;scroll-snap-align:start;aspect-ratio:4/5;object-fit:cover;border-radius:16px}
.opts{display:flex;flex-wrap:wrap;gap:8px;margin:8px 0 16px}.opt{border:1px solid var(--border);background:var(--surface);color:var(--ink);border-radius:12px;min-width:48px;min-height:44px;padding:0 12px;font-size:15px}.opt[aria-pressed=true]{background:var(--accent);color:var(--onAccent);border-color:var(--accent)}.opt[disabled]{text-decoration:line-through;opacity:.45}
label{display:block;font-size:13px;font-weight:600;margin:12px 0 6px}input,textarea{width:100%;border:1px solid var(--border);border-radius:12px;padding:12px;font:inherit;background:var(--ground);color:var(--ink)}input:focus,textarea:focus{outline:none;border-color:var(--ink)}
.row{display:flex;justify-content:space-between;gap:12px;padding:8px 0;border-bottom:1px solid var(--border)}.muted{color:var(--muted);font-size:13px}.hp{position:absolute;left:-10000px}
.err{color:var(--warn);font-weight:600;margin-top:10px}
.promo{display:inline-block;font-size:12px;font-weight:700;padding:2px 8px;border-radius:999px;background:var(--accentInk);color:var(--onAccent);margin-left:6px}s{color:var(--muted);font-weight:400;margin-left:6px}
</style>
</head>
<body>
<header><h1 id="store"></h1><p id="desc"></p></header>
<nav class="chips" id="chips" aria-label="Categorías"></nav>
<main class="grid" id="grid" aria-live="polite"></main>
<div class="bar" id="bar"><button class="btn" id="cartBtn" type="button"></button></div>
<dialog id="product"><div class="sheet" id="productBody"></div></dialog>
<dialog id="cart"><div class="sheet" id="cartBody"></div></dialog>
<script type="application/json" id="data">${json}</script>
<script nonce="${p.nonce}">
(() => {
  const { slug, catalog } = JSON.parse(document.getElementById('data').textContent);
  const S = (c) => 'S/ ' + (c / 100).toFixed(2);
  const AV = { available: 'Disponible', few: 'Últimas unidades', out: 'Agotado' };
  const el = (tag, props = {}, ...kids) => { const n = Object.assign(document.createElement(tag), props); kids.flat().forEach((k) => n.append(k)); return n; };
  const key = 'percha-cart-' + slug;
  let cart = [];
  try { cart = JSON.parse(localStorage.getItem(key) || '[]'); } catch {}
  const save = () => { try { localStorage.setItem(key, JSON.stringify(cart)); } catch {} renderBar(); };

  document.getElementById('store').textContent = catalog.store.name;
  document.getElementById('desc').textContent = catalog.store.description || 'Elige tus prendas y te escribimos por WhatsApp para confirmar.';

  let filter = null;
  const cats = [...new Set(catalog.products.map((p) => p.category).filter(Boolean))];
  const chips = document.getElementById('chips');
  const chip = (label, value) => { const b = el('button', { className: 'chip', type: 'button', textContent: label }); b.setAttribute('aria-pressed', String(filter === value)); b.onclick = () => { filter = value; renderChips(); renderGrid(); }; return b; };
  const renderChips = () => { chips.replaceChildren(...(cats.length ? [chip('Todo', null), ...cats.map((c) => chip(c, c))] : [])); };

  const renderGrid = () => {
    const grid = document.getElementById('grid');
    const items = catalog.products.filter((p) => !filter || p.category === filter);
    if (!items.length) return grid.replaceChildren(el('p', { className: 'muted', textContent: 'Pronto subiremos nuestras prendas.' }));
    grid.replaceChildren(...items.map((p) => {
      const img = p.imageUrl ? el('img', { src: p.imageUrl, alt: p.name, loading: 'lazy' }) : el('div', { className: 'ph' });
      const card = el('button', { className: 'card', type: 'button' }, img, el('div', {}, el('b', { textContent: p.name }), el('div', { className: 'price' }, 'Desde ' + S(p.promoPriceCents ?? p.fromPriceCents), p.promoPriceCents ? el('s', { textContent: S(p.fromPriceCents) }) : '', p.promoLabel ? el('span', { className: 'promo', textContent: p.promoLabel }) : ''), el('span', { className: 'pill ' + p.availability, textContent: AV[p.availability] })));
      card.onclick = () => openProduct(p.id);
      return card;
    }));
  };

  async function openProduct(id) {
    const body = document.getElementById('productBody');
    body.replaceChildren(el('p', { className: 'muted', textContent: 'Cargando…' }));
    document.getElementById('product').showModal();
    const res = await fetch('/v1/public/catalog/' + encodeURIComponent(slug) + '/products/' + encodeURIComponent(id));
    if (!res.ok) return body.replaceChildren(el('p', { className: 'err', textContent: 'Esta prenda ya no está disponible.' }));
    const p = await res.json();
    const attrs = [...new Set(p.variants.flatMap((v) => Object.keys(v.options)))];
    const pick = {};
    const status = el('p', { className: 'muted' });
    const add = el('button', { className: 'btn', type: 'button', textContent: 'Agregar al pedido', disabled: true });
    const match = () => p.variants.find((v) => attrs.every((a) => v.options[a] === pick[a]));
    const refresh = () => {
      const v = attrs.length ? match() : p.variants[0];
      add.disabled = !v || v.availability === 'out';
      status.textContent = !v ? 'Elige ' + attrs.filter((a) => !pick[a]).join(' y ').toLowerCase() : S(v.promoPriceCents ?? v.priceCents) + (v.promoPriceCents ? ' (antes ' + S(v.priceCents) + ')' : '') + ' · ' + AV[v.availability] + (p.promoLabel && !v.promoPriceCents ? ' · Promo ' + p.promoLabel : '');
    };
    const groups = attrs.map((a) => {
      const values = [...new Set(p.variants.map((v) => v.options[a]))];
      const box = el('div', { className: 'opts' });
      const draw = () => box.replaceChildren(...values.map((val) => {
        const anyStock = p.variants.some((v) => v.options[a] === val && v.availability !== 'out');
        const b = el('button', { className: 'opt', type: 'button', textContent: val, disabled: !anyStock });
        b.setAttribute('aria-pressed', String(pick[a] === val));
        b.onclick = () => { pick[a] = val; draw(); refresh(); };
        return b;
      }));
      draw();
      return [el('label', { textContent: a }), box];
    });
    add.onclick = () => {
      const v = attrs.length ? match() : p.variants[0];
      const found = cart.find((c) => c.variantId === v.id);
      if (found) found.quantity = Math.min(found.quantity + 1, 5);
      else cart.push({ variantId: v.id, quantity: 1, label: p.name + (attrs.length ? ' (' + attrs.map((a) => v.options[a]).join(' · ') + ')' : ''), priceCents: v.promoPriceCents ?? v.priceCents });
      save();
      document.getElementById('product').close();
    };
    const gallery = el('div', { className: 'gallery' }, ...p.images.map((i) => el('img', { src: i.url, alt: p.name, loading: 'lazy' })));
    body.replaceChildren(gallery, el('h2', { textContent: p.name }), p.description ? el('p', { className: 'muted', textContent: p.description }) : '', ...groups.flat(), status, add, el('button', { className: 'btn ghost', type: 'button', textContent: 'Cerrar', onclick: () => document.getElementById('product').close() }));
    refresh();
  }

  const renderBar = () => {
    const n = cart.reduce((a, c) => a + c.quantity, 0);
    document.getElementById('bar').style.display = n ? 'block' : 'none';
    document.getElementById('cartBtn').textContent = 'Ver pedido · ' + n + (n === 1 ? ' prenda' : ' prendas') + ' · ' + S(cart.reduce((a, c) => a + c.priceCents * c.quantity, 0));
  };

  document.getElementById('cartBtn').onclick = () => {
    const body = document.getElementById('cartBody');
    const name = el('input', { id: 'n', autocomplete: 'name', required: true, maxLength: 80 });
    const phone = el('input', { id: 'p', type: 'tel', inputMode: 'tel', autocomplete: 'tel', required: true, maxLength: 15, placeholder: '987654321' });
    const note = el('textarea', { id: 'o', rows: 2, maxLength: 300, placeholder: 'Ej. ¿la tienen en otro color?' });
    const trap = el('input', { className: 'hp', tabIndex: -1, autocomplete: 'off', 'aria-hidden': 'true' });
    const err = el('p', { className: 'err', role: 'alert' });
    const send = el('button', { className: 'btn', type: 'button', textContent: 'Enviar pedido' });
    // Una clave por pedido: si la red falla y el cliente vuelve a tocar "Enviar", no se duplica.
    const orderKey = crypto.randomUUID ? crypto.randomUUID() : '10000000-1000-4000-8000-100000000000'.replace(/[018]/g, (c) => (c ^ (crypto.getRandomValues(new Uint8Array(1))[0] & (15 >> (c / 4)))).toString(16));
    const lines = () => cart.map((c, i) => el('div', { className: 'row' }, el('span', { textContent: c.quantity + ' × ' + c.label }), el('span', {}, S(c.priceCents * c.quantity) + ' ', el('button', { className: 'opt', type: 'button', textContent: 'Quitar', onclick: () => { cart.splice(i, 1); save(); cart.length ? document.getElementById('cartBtn').onclick() : document.getElementById('cart').close(); } }))));
    send.onclick = async () => {
      err.textContent = '';
      if (name.value.trim().length < 2) return (err.textContent = 'Escribe tu nombre');
      if (!/^\\+?\\d{9,15}$/.test(phone.value.replace(/\\s/g, ''))) return (err.textContent = 'Escribe un celular válido');
      send.disabled = true;
      const res = await fetch('/v1/public/catalog/' + encodeURIComponent(slug) + '/orders', {
        method: 'POST', headers: { 'Content-Type': 'application/json', 'Idempotency-Key': orderKey },
        body: JSON.stringify({ name: name.value.trim(), phone: phone.value.replace(/\\s/g, ''), note: note.value.trim() || undefined, website: trap.value || undefined, items: cart.map((c) => ({ variantId: c.variantId, quantity: c.quantity })) }),
      }).catch(() => null);
      send.disabled = false;
      const json = res ? await res.json().catch(() => ({})) : {};
      if (!res || !res.ok) return (err.textContent = json.message || 'No se pudo enviar. Revisa tu conexión.');
      cart = []; save();
      body.replaceChildren(el('h2', { textContent: '¡Pedido #' + json.number + ' enviado!' }), el('p', { textContent: 'La tienda te escribirá para confirmar disponibilidad, pago y entrega.' }),
        json.whatsappUrl ? el('a', { className: 'btn', href: json.whatsappUrl, target: '_blank', rel: 'noopener', textContent: 'Escribir por WhatsApp', style: 'display:flex;align-items:center;justify-content:center;text-decoration:none' }) : '',
        el('button', { className: 'btn ghost', type: 'button', textContent: 'Seguir viendo', style: 'width:100%;margin-top:8px', onclick: () => document.getElementById('cart').close() }));
    };
    body.replaceChildren(el('h2', { textContent: 'Tu pedido' }), ...lines(), el('p', { className: 'muted', textContent: 'Precios referenciales. La tienda confirma disponibilidad y pago por WhatsApp.' }),
      el('label', { htmlFor: 'n', textContent: 'Tu nombre' }), name, el('label', { htmlFor: 'p', textContent: 'Celular (WhatsApp)' }), phone, el('label', { htmlFor: 'o', textContent: 'Comentario (opcional)' }), note, trap, err, send);
    document.getElementById('cart').showModal();
  };

  renderChips(); renderGrid(); renderBar();
})();
</script>
</body>
</html>`;
}

/** El enlace no existe o la tienda desactivó su catálogo. */
export function notFoundPage() {
  return `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Catálogo no disponible</title>
<style>body{margin:0;min-height:100vh;display:grid;place-items:center;font-family:system-ui,sans-serif;background:#F7F6F4;color:#171514;text-align:center;padding:24px}@media (prefers-color-scheme:dark){body{background:#0D0C0B;color:#F5F4F2}}p{color:#6B6560}</style></head>
<body><main><h1>Este catálogo no está disponible</h1><p>Revisa el enlace o escríbele a la tienda.</p></main></body></html>`;
}
