import { INestApplication } from '@nestjs/common';
import { api, createApp, resetDatabase } from './helpers';

describe('Comisiones, cierre de caja y conteo de inventario', () => {
  let app: INestApplication;
  const s: Record<string, any> = {};
  const o = () => api(app, s.owner);
  const d = () => api(app, s.seller);
  const stock = async (v: string) => (await o().get(`/inventory/stock?branchId=${s.branch}&variantId=${v}`)).body[0]?.quantity ?? 0;

  beforeAll(async () => {
    await resetDatabase();
    app = await createApp();
    s.owner = (await api(app).post('/auth/register', { storeName: 'Alma', ownerName: 'Joao', email: 'j@alma.pe', password: 'clave-segura-1' })).body.accessToken;
    s.branch = (await o().get('/branches')).body[0].id;
    await o().post('/attributes', { name: 'Talla', values: ['S', 'M'] });
    const p = await o().post('/products', {
      name: 'Vestido midi',
      priceCents: 11800, // con IGV 18 %: 10000 sin IGV
      matrix: { Talla: ['S', 'M'] },
      initialStock: { branchId: s.branch, items: [{ options: { Talla: 'S' }, quantity: 10 }, { options: { Talla: 'M' }, quantity: 5 }] },
    });
    s.S = p.body.variants.find((v: any) => v.options.Talla === 'S').id;
    s.M = p.body.variants.find((v: any) => v.options.Talla === 'M').id;
    const inv = await o().post('/team/invitations', { email: 'v@alma.pe', role: 'seller', branchId: s.branch });
    const acc = await api(app).post('/auth/invitations/accept', { token: inv.body.token, name: 'Diego', password: 'vendedor-123' });
    s.seller = acc.body.accessToken;
    s.sellerId = (await d().get('/auth/me')).body.membershipId;
    s.cash = (await o().post('/cash-sessions', { branchId: s.branch, openingCents: 5000 })).body.id;
  });
  afterAll(async () => app?.close());

  describe('Comisiones', () => {
    it('sobre ventas netas sin IGV; la devolución resta a quien vendió', async () => {
      expect((await o().patch(`/team/members/${s.sellerId}`, { commissionBp: 300 })).status).toBe(200);
      const sell = (who: () => any, qty: number, method = 'card') => who().post('/sales', { branchId: s.branch, items: [{ variantId: s.S, quantity: qty }], payments: [{ method, amountCents: 11800 * qty }] });
      const a = await sell(d, 3, 'cash'); // Diego: 3 × 118.00 (en efectivo)
      await sell(o, 1); // Joao: 1 (sin comisión)
      // Joao procesa la devolución de una prenda de la venta de Diego: igual le resta a Diego.
      await o().post(`/sales/${a.body.id}/returns`, { branchId: s.branch, items: [{ saleItemId: a.body.items[0].id, quantity: 1 }], payments: [{ method: 'cash', amountCents: 11800 }], reason: 'Talla' });

      const r = await o().get(`/reports/commissions?branchId=${s.branch}`);
      const diego = r.body.sellers.find((x: any) => x.name === 'Diego');
      expect(diego).toMatchObject({ tickets: 1, soldCents: 35400, returns: 1, returnsCents: -11800, netCents: 23600, netExTaxCents: 20000, commissionBp: 300, commissionCents: 600 });
      expect(r.body.sellers.find((x: any) => x.name === 'Joao')).toMatchObject({ netCents: 11800, commissionBp: null, commissionCents: 0 });
      expect(r.body.totals.commissionCents).toBe(600);
      expect((await d().get('/reports/commissions')).status).toBe(403);
    });
  });

  describe('Cierre de caja imprimible', () => {
    it('reporte con medios de pago, ventas, devoluciones y arqueo; queda en la lista', async () => {
      const partial = await o().get(`/cash-sessions/${s.cash}/report`);
      expect(partial.body).toMatchObject({ status: 'open', openingCents: 5000, branchName: expect.any(String), openedBy: 'Joao', countedCashCents: null });
      await o().post(`/cash-sessions/${s.cash}/close`, { countedCashCents: 28500 });
      const r = await o().get(`/cash-sessions/${s.cash}/report`);
      expect(r.body).toMatchObject({
        status: 'closed',
        closedBy: 'Joao',
        sales: { count: 2, totalCents: 47200, voidedCount: 0 },
        returns: { count: 1, differenceCents: -11800 },
        // 5000 de apertura + 35400 en efectivo − 11800 devueltos
        expectedCashCents: 28600,
        countedCashCents: 28500,
        differenceCents: -100,
      });
      expect(r.body.byMethod).toEqual(expect.arrayContaining([{ method: 'cash', totalCents: 23600 }, { method: 'card', totalCents: 11800 }]));
      expect((await o().get(`/cash-sessions?branchId=${s.branch}`)).body[0].id).toBe(s.cash);
    });
  });

  describe('Conteo de inventario guiado', () => {
    it('cuenta con la tienda abierta: lo vendido después de contar no es faltante; aplica una sola vez', async () => {
      await o().post('/cash-sessions', { branchId: s.branch, openingCents: 0 });
      const c = (await o().post('/stock-counts', { branchId: s.branch, note: 'Fin de mes' })).body;
      expect((await o().post('/stock-counts', { branchId: s.branch })).body.code).toBe('COUNT_OPEN');

      const sBefore = await stock(s.S); // 7 (10 − 3 − 1 + 1)
      for (let i = 0; i < 6; i++) await o().post(`/stock-counts/${c.id}/items`, { variantId: s.S }); // 6 escaneos: falta 1
      // Después de contar la S se vende una: NO debe contarse como faltante.
      await o().post('/sales', { branchId: s.branch, items: [{ variantId: s.S, quantity: 1 }], payments: [{ method: 'card', amountCents: 11800 }] });
      const view = await o().post(`/stock-counts/${c.id}/items`, { variantId: s.M, mode: 'set', quantity: 6 }); // sobra 1
      expect(view.body.items.find((i: any) => i.variantId === s.S)).toMatchObject({ counted: 6, stockAtFirstScan: sBefore, difference: -1 });
      expect(view.body.totals).toMatchObject({ missing: 1, extra: 1 });

      const applied = await o().post(`/stock-counts/${c.id}/apply`, {});
      expect(applied.body).toMatchObject({ status: 'applied', adjusted: 2, missingUnits: 1, extraUnits: 1 });
      expect(await stock(s.S)).toBe(sBefore - 1 - 1); // −1 vendida (real) −1 faltante del conteo
      expect(await stock(s.M)).toBe(6);
      expect((await o().post(`/stock-counts/${c.id}/apply`, {})).body.code).toBe('COUNT_CLOSED');
      const kardex = (await o().get(`/inventory/movements?variantId=${s.M}&branchId=${s.branch}`)).body;
      expect(kardex[0]).toMatchObject({ type: 'adjustment', quantity: 1, reason: expect.stringContaining('Conteo de inventario #') });
      expect((await o().get('/inventory/integrity')).body.ok).toBe(true);
    });

    it('conteo completo: lo no contado con stock se ajusta a 0 solo si se pide', async () => {
      const c = (await o().post('/stock-counts', { branchId: s.branch })).body;
      await o().post(`/stock-counts/${c.id}/items`, { variantId: s.S, mode: 'set', quantity: await stock(s.S) });
      await o().post(`/stock-counts/${c.id}/apply`, { zeroUncounted: true });
      expect(await stock(s.M)).toBe(0);
    });
  });
});
