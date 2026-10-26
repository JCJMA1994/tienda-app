import { INestApplication } from '@nestjs/common';
import { Client } from 'pg';
import { localDate, shiftDate } from '../src/common/dates';
import { api, createApp, resetDatabase } from './helpers';

/**
 * Un día de tienda con ventas, descuento, anulación y un cambio de talla, y luego se
 * verifican los números de cada reporte a mano.
 */
describe('Reportes (fase 7)', () => {
  let app: INestApplication;
  const s: Record<string, any> = {};

  beforeAll(async () => {
    await resetDatabase();
    app = await createApp();
    const reg = await api(app).post('/auth/register', { storeName: 'Rep', ownerName: 'Ana', email: 'ana@rep.pe', password: 'clave-segura-1' });
    s.owner = reg.body.accessToken;
    const o = api(app, s.owner);
    s.branch = (await o.get('/branches')).body[0].id;

    await o.post('/attributes', { name: 'Talla', values: ['S', 'M'] });
    const vestido = await o.post('/products', {
      name: 'Vestido midi',
      priceCents: 18990,
      costCents: 8000,
      matrix: { Talla: ['S', 'M'] },
      initialStock: { branchId: s.branch, items: [{ options: { Talla: 'S' }, quantity: 3 }, { options: { Talla: 'M' }, quantity: 5 }] },
    });
    s.S = vestido.body.variants.find((v: any) => v.options.Talla === 'S').id;
    s.M = vestido.body.variants.find((v: any) => v.options.Talla === 'M').id;
    const correa = await o.post('/products', {
      name: 'Correa',
      priceCents: 7900,
      costCents: 2000,
      initialStock: { branchId: s.branch, items: [{ options: {}, quantity: 2 }] },
    });
    s.correa = correa.body.variants[0].id;

    await o.put(`/team/members/${(await o.get('/auth/me')).body.membershipId}/pin`, { pin: '4321' });
    await o.post('/cash-sessions', { branchId: s.branch, openingCents: 0 });

    const sale1 = await o.post('/sales', {
      branchId: s.branch,
      items: [{ variantId: s.S, quantity: 1 }, { variantId: s.M, quantity: 2 }],
      payments: [{ method: 'cash', amountCents: 56970 }],
    });
    // 10% de descuento: dentro del límite, sin aprobación.
    await o.post('/sales', { branchId: s.branch, items: [{ variantId: s.M, quantity: 1 }], discountCents: 1899, payments: [{ method: 'card', amountCents: 17091 }] });
    const sale3 = await o.post('/sales', { branchId: s.branch, items: [{ variantId: s.S, quantity: 1 }], payments: [{ method: 'cash', amountCents: 18990 }] });
    await o.post(`/sales/${sale3.body.id}/void`, { reason: 'Cobro duplicado' });

    // Cambio de talla parejo: devuelve S, se lleva M.
    const lineS = sale1.body.items.find((i: any) => i.variantId === s.S);
    const ex = await o.post(`/sales/${sale1.body.id}/returns`, {
      branchId: s.branch,
      items: [{ saleItemId: lineS.id, quantity: 1 }],
      replacements: [{ variantId: s.M, quantity: 1 }],
      reason: 'Cambio de talla',
    });
    expect(ex.status).toBe(201);

    // La correa "entró" hace 45 días: se mueve la fecha en la BD de prueba (el kardex es
    // inmutable por trigger, así que se desactiva solo para preparar el escenario).
    const admin = new Client({ connectionString: (process.env.TEST_ADMIN_URL ?? 'postgres://postgres:postgres@localhost:5432/postgres').replace(/\/postgres$/, '/percha_test') });
    await admin.connect();
    await admin.query('ALTER TABLE stock_movements DISABLE TRIGGER stock_movements_append_only');
    await admin.query(`UPDATE stock_movements SET created_at = now() - interval '45 days' WHERE variant_id = $1`, [s.correa]);
    await admin.query('ALTER TABLE stock_movements ENABLE TRIGGER stock_movements_append_only');
    await admin.end();
  });
  afterAll(async () => app?.close());

  it('resumen: ventas netas, unidades, costo y margen (sin la venta anulada)', async () => {
    const res = await api(app, s.owner).get('/reports/summary');
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({
      tickets: 2,
      voidedSales: 1,
      returns: 1,
      netSalesCents: 74061, // 56970 + 17091; el cambio parejo no mueve dinero
      netSalesExTaxCents: 62764, // 74061 / 1.18
      units: 4, // 3 + 1 − 1 devuelta + 1 entregada en el cambio
      costOfSalesCents: 32000, // 4 × S/ 80
      grossMarginCents: 30764,
      grossMarginPct: 49,
      discountsCents: 1899,
      averageTicketCents: 37031,
    });
    expect(res.body.range.timezone).toBe('America/Lima');
  });

  it('serie diaria: todos los días del rango, hoy con las ventas', async () => {
    const res = await api(app, s.owner).get('/reports/daily');
    expect(res.body.days).toHaveLength(30);
    const today = res.body.days.at(-1);
    expect(today).toEqual({ date: localDate('America/Lima', new Date()), tickets: 2, netSalesCents: 74061 });
    expect(res.body.days[0].netSalesCents).toBe(0);
  });

  it('más vendidos: unidades netas e ingreso al precio cobrado', async () => {
    const res = await api(app, s.owner).get('/reports/top-products');
    expect(res.body.items).toHaveLength(1); // la correa no se vendió
    expect(res.body.items[0]).toMatchObject({ name: 'Vestido midi', units: 4, netSalesCents: 74061, grossMarginCents: 30764 });
  });

  it('rotación por talla: la M se agota, la S se queda', async () => {
    const res = await api(app, s.owner).get('/reports/attributes');
    const talla = res.body.attributes.find((a: any) => a.name === 'Talla');
    expect(talla.values).toEqual([
      { value: 'S', sold: 0, stock: 3, sellThroughPct: 0 },
      { value: 'M', sold: 4, stock: 1, sellThroughPct: 80 },
    ]);
  });

  it('stock muerto: la correa lleva 45 días sin venderse', async () => {
    const res = await api(app, s.owner).get('/reports/dead-stock?days=30');
    expect(res.body.items).toHaveLength(1);
    expect(res.body.items[0]).toMatchObject({ productName: 'Correa', quantity: 2, neverSold: true, costValueCents: 4000, retailValueCents: 15800 });
    expect(res.body.items[0].daysWithoutSale).toBeGreaterThanOrEqual(44);
  });

  it('valorización a costo y a precio de venta', async () => {
    const res = await api(app, s.owner).get('/reports/valuation');
    expect(res.body).toMatchObject({
      totalUnits: 6,
      totalCostValueCents: 36000, // 4 vestidos × 80 + 2 correas × 20
      totalRetailValueCents: 91760,
      potentialMarginCents: 41763, // 91760 / 1.18 − 36000
    });
    expect(res.body.categories[0].category).toBe('Sin categoría');
  });

  it('valida el rango y exige permiso', async () => {
    const today = localDate('America/Lima', new Date());
    expect((await api(app, s.owner).get(`/reports/summary?from=${today}&to=${shiftDate(today, -1)}`)).status).toBe(400);
    expect((await api(app, s.owner).get(`/reports/summary?from=${shiftDate(today, -400)}&to=${today}`)).status).toBe(400);

    const inv = await api(app, s.owner).post('/team/invitations', { email: 'v@rep.pe', role: 'seller', branchId: s.branch });
    const seller = await api(app).post('/auth/invitations/accept', { token: inv.body.token, name: 'Vale', password: 'vendedor-123' });
    expect((await api(app, seller.body.accessToken).get('/reports/summary')).status).toBe(403);
  });
});
