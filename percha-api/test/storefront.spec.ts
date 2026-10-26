import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { api, createApp, resetDatabase } from './helpers';

describe('Catálogo público y pedidos', () => {
  let app: INestApplication;
  const s: Record<string, any> = {};
  const o = () => api(app, s.owner);
  const pub = () => request(app.getHttpServer());

  beforeAll(async () => {
    await resetDatabase();
    app = await createApp();
    // Nombre con HTML a propósito: la página debe escaparlo.
    const reg = await api(app).post('/auth/register', { storeName: 'Alma <script>x</script>', ownerName: 'Joao', email: 'j@alma.pe', password: 'clave-segura-1' });
    s.owner = reg.body.accessToken;
    s.branch = (await o().get('/branches')).body[0].id;
    await o().post('/attributes', { name: 'Talla', values: ['S', 'M'] });
    const p = await o().post('/products', {
      name: 'Vestido midi',
      priceCents: 18990,
      costCents: 8000,
      matrix: { Talla: ['S', 'M'] },
      initialStock: { branchId: s.branch, items: [{ options: { Talla: 'S' }, quantity: 10 }] },
    });
    s.product = p.body.id;
    s.S = p.body.variants.find((v: any) => v.options.Talla === 'S').id;
    s.M = p.body.variants.find((v: any) => v.options.Talla === 'M').id;
    s.hidden = (await o().post('/products', { name: 'Blusa privada', priceCents: 7990, initialStock: { branchId: s.branch, items: [{ options: {}, quantity: 5 }] } })).body;
    const inv = await o().post('/team/invitations', { email: 'v@alma.pe', role: 'seller', branchId: s.branch });
    s.seller = (await api(app).post('/auth/invitations/accept', { token: inv.body.token, name: 'Diego', password: 'vendedor-123' })).body.accessToken;
  });
  afterAll(async () => app?.close());

  it('configuración: enlace válido, no reservado y único entre tiendas', async () => {
    expect((await o().put('/catalog/settings', { enabled: true, slug: 'A' })).status).toBe(400);
    expect((await o().put('/catalog/settings', { enabled: true, slug: 'admin' })).status).toBe(400);
    const ok = await o().put('/catalog/settings', { enabled: false, slug: 'Boutique-Alma', whatsapp: '51987654321', description: 'Ropa para el día a día' });
    expect(ok.body.url).toMatch(/\/c\/boutique-alma$/);

    const other = await api(app).post('/auth/register', { storeName: 'Otra', ownerName: 'Xavier', email: 'x@otra.pe', password: 'clave-segura-1' });
    const r = await api(app, other.body.accessToken).put('/catalog/settings', { enabled: true, slug: 'boutique-alma' });
    expect([r.status, r.body.code, other.status]).toEqual([409, 'SLUG_TAKEN', 201]);
  });

  it('desactivado no existe; activado muestra SOLO lo publicado, sin costos ni stock exacto', async () => {
    expect((await pub().get('/v1/public/catalog/boutique-alma')).status).toBe(404);
    const page = await pub().get('/c/boutique-alma');
    expect([page.status, page.headers['content-type']]).toEqual([404, 'text/html; charset=utf-8']);
    expect(page.text).toContain('Este catálogo no está disponible');
    await o().put('/catalog/settings', { enabled: true, slug: 'boutique-alma', whatsapp: '51987654321', description: 'Ropa para el día a día' });
    expect((await pub().get('/v1/public/catalog/boutique-alma')).body.products).toEqual([]);

    expect((await api(app, s.seller).put(`/catalog/products/${s.product}/published`, { published: true })).status).toBe(403);
    await o().put(`/catalog/products/${s.product}/published`, { published: true });
    const c = await pub().get('/v1/public/catalog/boutique-alma');
    expect(c.body.products).toEqual([{ id: s.product, name: 'Vestido midi', category: null, imageUrl: null, fromPriceCents: 18990, availability: 'available' }]);
    expect(c.body.store).toMatchObject({ whatsapp: '51987654321' });

    const d = await pub().get(`/v1/public/catalog/boutique-alma/products/${s.product}`);
    expect(d.body.variants.map((v: any) => [v.options.Talla, v.availability])).toEqual([['M', 'out'], ['S', 'available']]);
    const raw = JSON.stringify([c.body, d.body]);
    expect(raw).not.toMatch(/costCents|avgCost|quantity|tenantId/);
    expect((await pub().get(`/v1/public/catalog/boutique-alma/products/${s.hidden.id}`)).status).toBe(404);
  });

  it('página pública: HTML escapado, CSP con nonce y vista previa para WhatsApp', async () => {
    const r = await pub().get('/c/boutique-alma');
    expect(r.status).toBe(200);
    expect(r.headers['content-security-policy']).toMatch(/script-src 'nonce-[A-Za-z0-9+/=]+'/);
    expect(r.text).toContain('<meta property="og:title" content="Alma &lt;script&gt;x&lt;/script&gt;">');
    expect(r.text).not.toContain('<script>x</script>');
    expect(r.text).toContain('\\u003cscript>x\\u003c/script>'); // dentro del JSON embebido
    // El script de la página es JavaScript válido (se compila sin ejecutarse).
    const code = /<script nonce="[^"]+">([\s\S]*?)<\/script>/.exec(r.text)![1];
    expect(() => new Function(code)).not.toThrow();
  });

  it('pedido: valida, no acepta agotados ni ocultos, avisa a la tienda y arma el WhatsApp', async () => {
    const send = (body: object) => pub().post('/v1/public/catalog/boutique-alma/orders').send({ name: 'Lucía', phone: '987 111 222', ...body });
    expect((await send({ items: [{ variantId: s.S, quantity: 1 }], website: 'spam.com' })).status).toBe(400);
    expect((await send({ items: [{ variantId: s.hidden.variants[0].id, quantity: 1 }] })).body.code).toBe('ITEM_UNAVAILABLE');
    expect((await send({ items: [{ variantId: s.M, quantity: 1 }] })).body.code).toBe('OUT_OF_STOCK');

    const ok = await send({ phone: '987111222', note: '¿Tienen en negro?', items: [{ variantId: s.S, quantity: 2 }] });
    expect(ok.status).toBe(201);
    expect(ok.body).toMatchObject({ number: 1, totalCents: 37980 });
    expect(decodeURIComponent(ok.body.whatsappUrl)).toContain('https://wa.me/51987654321?text=Hola, acabo de hacer el pedido #1');
    expect(decodeURIComponent(ok.body.whatsappUrl)).toContain('2 × Vestido midi (S)');

    const inbox = await api(app, s.seller).get('/notifications');
    expect(inbox.body[0]).toMatchObject({ type: 'catalog.order', title: 'Nuevo pedido del catálogo · #1' });
    s.order = (await api(app, s.seller).get('/catalog/orders')).body[0];
    expect(s.order).toMatchObject({ status: 'new', customerPhone: '51987111222' });
    // El pedido NO reserva stock: la tienda lo confirma y recién ahí aparta o vende.
    expect((await o().get(`/inventory/stock?branchId=${s.branch}&variantId=${s.S}`)).body[0].quantity).toBe(10);
  });

  it('la tienda crea la ficha del cliente desde el pedido (por celular, sin duplicar)', async () => {
    const a = await api(app, s.seller).post(`/catalog/orders/${s.order.id}/customer`);
    const b = await api(app, s.seller).post(`/catalog/orders/${s.order.id}/customer`);
    expect(a.body.customerId).toBe(b.body.customerId);
    const detail = await api(app, s.seller).get(`/catalog/orders/${s.order.id}`);
    expect(detail.body).toMatchObject({ status: 'contacted', customerId: a.body.customerId });
    expect(detail.body.items).toEqual([expect.objectContaining({ variantId: s.S, quantity: 2, productName: 'Vestido midi' })]);
    expect((await api(app, s.seller).post(`/catalog/orders/${s.order.id}/status`, { status: 'completed' })).body.status).toBe('completed');
  });

  it('límite de pedidos por IP contra spam', async () => {
    const send = () => pub().post('/v1/public/catalog/boutique-alma/orders').send({ name: 'Bot', phone: '987111222', items: [{ variantId: s.S, quantity: 1 }] });
    const statuses = [];
    for (let i = 0; i < 6; i++) statuses.push((await send()).status);
    expect(statuses).toContain(429);
  });
});
