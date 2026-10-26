import { INestApplication } from '@nestjs/common';
import { suggest } from '../src/modules/purchasing/replenishment';
import { api, createApp, resetDatabase } from './helpers';

const P = { windowDays: 28, coverDays: 30, leadDays: 7 };

describe('Reposición sugerida: reglas', () => {
  it('pide lo que falta para cubrir el periodo + la espera del proveedor, restando stock y lo que viene', () => {
    // 6 vendidas en 28 días → 37 días necesitan ~7.9 → 8; hay 2 y vienen 3 → pedir 3.
    expect(suggest({ stock: 2, minQuantity: 0, demand: 6, incoming: 3 }, P)).toMatchObject({ quantity: 3, ratePerWeek: 1.5, coverageDays: 23, urgency: 'planned' });
  });
  it('agotada: urgencia máxima; sin ventas pero bajo el mínimo: completa el mínimo', () => {
    expect(suggest({ stock: 0, minQuantity: 0, demand: 3, incoming: 0 }, P)).toMatchObject({ quantity: 4, urgency: 'out' });
    expect(suggest({ stock: 9, minQuantity: 12, demand: 0, incoming: 0 }, P)).toMatchObject({ quantity: 3, coverageDays: null });
  });
  it('si alcanza, no sugiere nada; devoluciones de más no generan demanda negativa', () => {
    expect(suggest({ stock: 50, minQuantity: 0, demand: 4, incoming: 0 }, P).quantity).toBe(0);
    expect(suggest({ stock: 5, minQuantity: 0, demand: -2, incoming: 0 }, P)).toMatchObject({ quantity: 0, coverageDays: null });
  });
  it('se agota antes de que llegue un pedido nuevo: crítica', () => {
    expect(suggest({ stock: 1, minQuantity: 0, demand: 28, incoming: 0 }, P).urgency).toBe('critical');
  });
});

describe('Reposición sugerida: con datos reales', () => {
  let app: INestApplication;
  const s: Record<string, any> = {};
  const o = () => api(app, s.owner);
  const sell = (variantId: string, quantity: number) =>
    o().post('/sales', { branchId: s.branch, items: [{ variantId, quantity }], payments: [{ method: 'card', amountCents: 18990 * quantity }] });

  beforeAll(async () => {
    await resetDatabase();
    app = await createApp();
    s.owner = (await api(app).post('/auth/register', { storeName: 'Alma', ownerName: 'Joao', email: 'j@alma.pe', password: 'clave-segura-1' })).body.accessToken;
    s.branch = (await o().get('/branches')).body[0].id;
    await o().post('/attributes', { name: 'Talla', values: ['S', 'M', 'L'] });
    const p = await o().post('/products', {
      name: 'Vestido midi',
      priceCents: 18990,
      costCents: 8000,
      matrix: { Talla: ['S', 'M', 'L'] },
      initialStock: { branchId: s.branch, items: [{ options: { Talla: 'S' }, quantity: 8 }, { options: { Talla: 'M' }, quantity: 10 }, { options: { Talla: 'L' }, quantity: 3 }] },
    });
    const v = (t: string) => p.body.variants.find((x: any) => x.options.Talla === t).id;
    Object.assign(s, { S: v('S'), M: v('M'), L: v('L') });
    await o().post('/cash-sessions', { branchId: s.branch, openingCents: 0 });

    await sell(s.S, 6); // S: rota
    await sell(s.L, 3); // L: agotada
    const m = await sell(s.M, 1); // M: se vende y se devuelve → demanda neta 0
    await o().post(`/sales/${m.body.id}/returns`, { branchId: s.branch, items: [{ saleItemId: m.body.items[0].id, quantity: 1 }], payments: [{ method: 'card', amountCents: 18990 }], reason: 'Talla' });
    await o().post('/inventory/adjustments', { branchId: s.branch, reason: 'Merma', items: [{ variantId: s.M, delta: -1 }] }); // no es demanda
    await o().put('/inventory/min-stock', { branchId: s.branch, variantId: s.M, minQuantity: 12 });

    s.supplier = (await o().post('/suppliers', { name: 'Textiles Gamarra' })).body.id;
    const po = await o().post('/purchase-orders', { supplierId: s.supplier, branchId: s.branch, items: [{ variantId: s.S, quantity: 3, unitCostCents: 7500 }] });
    await o().post(`/purchase-orders/${po.body.id}/confirm`); // 3 en camino
  });
  afterAll(async () => app?.close());

  it('sugiere por talla, resta lo que viene, agrupa por proveedor y ordena por urgencia', async () => {
    const r = await o().get(`/purchasing/suggestions?branchId=${s.branch}`);
    expect(r.status).toBe(200);
    const all = r.body.suppliers.flatMap((g: any) => g.items);
    const byVariant = Object.fromEntries(all.map((i: any) => [i.variantId, i]));

    expect(byVariant[s.S]).toMatchObject({ stock: 2, incoming: 3, soldInWindow: 6, quantity: 3, unitCostCents: 7500, supplierId: s.supplier });
    expect(byVariant[s.L]).toMatchObject({ stock: 0, soldInWindow: 3, quantity: 4, urgency: 'out' });
    expect(byVariant[s.M]).toMatchObject({ stock: 9, minQuantity: 12, soldInWindow: 0, quantity: 3 });

    const [first, last] = [r.body.suppliers[0], r.body.suppliers.at(-1)];
    expect(first).toMatchObject({ supplierId: s.supplier, supplierName: 'Textiles Gamarra', units: 3, totalCents: 22500 });
    expect(last.supplierId).toBeNull();
    expect(last.items[0].variantId).toBe(s.L); // agotada primero
    expect(r.body.totals).toMatchObject({ variants: 3, units: 10 });
  });

  it('parámetros: más días a cubrir → más unidades; valida rangos', async () => {
    const r = await o().get(`/purchasing/suggestions?branchId=${s.branch}&coverDays=60`);
    const L = r.body.suppliers.flatMap((g: any) => g.items).find((i: any) => i.variantId === s.L);
    expect(L.quantity).toBe(Math.ceil((3 / 28) * 67));
    expect((await o().get(`/purchasing/suggestions?branchId=${s.branch}&windowDays=2`)).status).toBe(400);
  });
});
