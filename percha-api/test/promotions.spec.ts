import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { api, createApp, resetDatabase } from './helpers';

describe('Promociones automáticas', () => {
  let app: INestApplication;
  const s: Record<string, any> = {};
  const o = () => api(app, s.owner);
  const now = () => new Date().toISOString();
  const hoursAgo = (h: number) => new Date(Date.now() - h * 3_600_000).toISOString();
  const sale = (items: { variantId: string; quantity: number }[], amountCents: number, extra: object = {}) =>
    o().post('/sales', { branchId: s.branch, items, payments: [{ method: 'card', amountCents }], ...extra });

  beforeAll(async () => {
    await resetDatabase();
    app = await createApp();
    s.owner = (await api(app).post('/auth/register', { storeName: 'Alma', ownerName: 'Joao', email: 'j@alma.pe', password: 'clave-segura-1' })).body.accessToken;
    s.branch = (await o().get('/branches')).body[0].id;
    s.verano = (await o().post('/categories', { name: 'Verano' })).body.id;
    const mk = async (name: string, priceCents: number, categoryId?: string) => {
      const p = await o().post('/products', { name, priceCents, categoryId, initialStock: { branchId: s.branch, items: [{ options: {}, quantity: 20 }] } });
      return { product: p.body.id, variant: p.body.variants[0].id };
    };
    s.blusa = await mk('Blusa lino', 7990);
    s.polo = await mk('Polo básico', 4990);
    s.vestido = await mk('Vestido playa', 15990, s.verano);
    await o().post('/cash-sessions', { branchId: s.branch, openingCents: 0 });
    const inv = await o().post('/team/invitations', { email: 'v@alma.pe', role: 'seller', branchId: s.branch });
    s.seller = (await api(app).post('/auth/invitations/accept', { token: inv.body.token, name: 'Diego', password: 'vendedor-123' })).body.accessToken;
  });
  afterAll(async () => app?.close());

  it('valida las reglas y solo quien edita el catálogo puede crearlas', async () => {
    const bad = await o().post('/promotions', { name: '2x2', kind: 'buy_x_pay_y', buyQty: 2, payQty: 2, startsAt: now() });
    expect(bad.status).toBe(400);
    expect((await o().post('/promotions', { name: 'Sin %', kind: 'percent', startsAt: now() })).status).toBe(400);
    expect((await o().post('/promotions', { name: 'Cat', kind: 'percent', percentBp: 2000, scope: 'categories', startsAt: now() })).status).toBe(400);
    expect((await api(app, s.seller).post('/promotions', { name: '10 %', kind: 'percent', percentBp: 1000, startsAt: now() })).status).toBe(403);
    expect((await api(app, s.seller).get('/promotions')).status).toBe(200); // el POS las lee
  });

  it('2x1 entre blusa y polo: la cotización y el cobro coinciden; pagar sin promo no cuadra', async () => {
    s.b21 = (await o().post('/promotions', { name: '2x1 tops', kind: 'buy_x_pay_y', buyQty: 2, payQty: 1, scope: 'products', productIds: [s.blusa.product, s.polo.product], startsAt: hoursAgo(1) })).body;
    const items = [{ variantId: s.blusa.variant, quantity: 1 }, { variantId: s.polo.variant, quantity: 1 }];
    const q = await o().post('/sales/quote', { branchId: s.branch, items, discountCents: 0 });
    expect(q.body).toMatchObject({ subtotalCents: 12980, promoDiscountCents: 4990, totalCents: 7990 });
    expect(q.body.lines.find((l: any) => l.variantId === s.polo.variant)).toMatchObject({ promoDiscountCents: 4990, promotionName: '2x1 tops' });

    const wrong = await sale(items, 12980);
    expect(wrong.body).toMatchObject({ code: 'PAYMENT_MISMATCH', expectedCents: 7990 });
    const ok = await sale(items, 7990);
    expect(ok.status).toBe(201);
    expect(ok.body).toMatchObject({ subtotalCents: 12980, discountCents: 4990, totalCents: 7990 });
  });

  it('porcentaje por categoría + descuento manual encima; el límite manual se mide después de la promo', async () => {
    s.p30 = (await o().post('/promotions', { name: 'Verano −30 %', kind: 'percent', percentBp: 3000, scope: 'categories', categoryIds: [s.verano], startsAt: hoursAgo(1) })).body;
    const items = [{ variantId: s.vestido.variant, quantity: 1 }];
    const q = await o().post('/sales/quote', { branchId: s.branch, items, discountCents: 500 });
    // 15990 − 4797 (30 %) − 500 manual
    expect(q.body).toMatchObject({ promoDiscountCents: 4797, totalCents: 10693 });
    expect((await sale(items, 10693, { discountCents: 500 })).status).toBe(201);
  });

  it('inactiva, vencida o futura no se aplica; una venta sin conexión usa las vigentes a su hora real', async () => {
    await o().put(`/promotions/${s.p30.id}`, { name: 'Verano −30 %', kind: 'percent', percentBp: 3000, scope: 'categories', categoryIds: [s.verano], startsAt: hoursAgo(1), active: false });
    const items = [{ variantId: s.vestido.variant, quantity: 1 }];
    expect((await o().post('/sales/quote', { branchId: s.branch, items, discountCents: 0 })).body.promoDiscountCents).toBe(0);

    await o().put(`/promotions/${s.p30.id}`, { name: 'Verano −30 %', kind: 'percent', percentBp: 3000, scope: 'categories', categoryIds: [s.verano], startsAt: hoursAgo(1), active: true });
    // Venta hecha hace 3 h (antes de que empezara la promo): precio normal.
    expect((await sale(items, 15990, { offline: { occurredAt: hoursAgo(3) } })).status).toBe(201);
    // Hecha hace 30 min: con promo.
    expect((await sale(items, 11193, { offline: { occurredAt: hoursAgo(0.5) } })).status).toBe(201);
  });

  it('la foto del POS trae las promociones (para calcular igual sin conexión) y la vitrina las muestra', async () => {
    const snap = await o().get(`/inventory/snapshot?branchId=${s.branch}`);
    expect(snap.body.promotions.map((p: any) => p.name).sort()).toEqual(['2x1 tops', 'Verano −30 %']);
    expect(snap.body.variants.find((v: any) => v.id === s.vestido.variant).categoryId).toBe(s.verano);

    await o().put('/catalog/settings', { enabled: true, slug: 'alma-promos' });
    for (const p of [s.vestido, s.blusa]) await o().put(`/catalog/products/${p.product}/published`, { published: true });
    const c = await request(app.getHttpServer()).get('/v1/public/catalog/alma-promos');
    const byName = Object.fromEntries(c.body.products.map((p: any) => [p.name, p]));
    expect(byName['Vestido playa']).toMatchObject({ promoLabel: '−30 %', promoPriceCents: 11193 });
    expect(byName['Blusa lino']).toMatchObject({ promoLabel: '2x1' });
  });
});
