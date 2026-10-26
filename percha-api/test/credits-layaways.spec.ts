import { INestApplication } from '@nestjs/common';
import { Client } from 'pg';
import { normalizeCreditCode } from '../src/modules/credits/credits.service';
import { LayawaysService } from '../src/modules/sales/layaways.service';
import { api, createApp, resetDatabase, urls } from './helpers';

describe('Vales, gift cards y apartados', () => {
  let app: INestApplication;
  const s: Record<string, any> = {};
  const o = () => api(app, s.owner);
  const stock = async (variantId: string) => (await o().get(`/inventory/stock?branchId=${s.branch}&variantId=${variantId}`)).body[0]?.quantity ?? 0;
  const expectedCash = async () => (await o().get(`/cash-sessions/current?branchId=${s.branch}`)).body.summary.expectedCashCents;
  const sell = (token: string, body: object) => api(app, token).post('/sales', { branchId: s.branch, ...body });

  beforeAll(async () => {
    await resetDatabase();
    app = await createApp();
    const reg = await api(app).post('/auth/register', { storeName: 'Alma', ownerName: 'Joao', email: 'j@alma.pe', password: 'clave-segura-1' });
    s.owner = reg.body.accessToken;
    s.branch = (await o().get('/branches')).body[0].id;
    await o().post('/attributes', { name: 'Talla', values: ['S', 'M'] });
    const p = await o().post('/products', {
      name: 'Vestido midi',
      priceCents: 18990,
      matrix: { Talla: ['S', 'M'] },
      initialStock: { branchId: s.branch, items: [{ options: { Talla: 'S' }, quantity: 5 }, { options: { Talla: 'M' }, quantity: 10 }] },
    });
    s.product = p.body.id;
    s.S = p.body.variants.find((v: any) => v.options.Talla === 'S').id;
    s.M = p.body.variants.find((v: any) => v.options.Talla === 'M').id;
    const inv = await o().post('/team/invitations', { email: 'v@alma.pe', role: 'seller', branchId: s.branch });
    s.seller = (await api(app).post('/auth/invitations/accept', { token: inv.body.token, name: 'Diego', password: 'vendedor-123' })).body.accessToken;
    s.customer = (await o().post('/customers', { docType: 'dni', docNumber: '45678912', name: 'Lucía Ramos' })).body.id;
    await o().post('/cash-sessions', { branchId: s.branch, openingCents: 0 });
  });
  afterAll(async () => app?.close());

  describe('Saldo a favor y vales', () => {
    it('devolución sin reembolso en dinero: emite un vale a nombre del cliente', async () => {
      const sale = await sell(s.seller, { customerId: s.customer, items: [{ variantId: s.M, quantity: 1 }], payments: [{ method: 'cash', amountCents: 18990 }] });
      const cashBefore = await expectedCash();
      const ret = await api(app, s.seller).post(`/sales/${sale.body.id}/returns`, {
        branchId: s.branch,
        items: [{ saleItemId: sale.body.items[0].id, quantity: 1 }],
        payments: [{ method: 'store_credit', amountCents: 18990 }],
        reason: 'No le quedó',
      });
      expect(ret.status).toBe(201);
      expect(ret.body.credit.code).toMatch(/^VALE-[2-9A-HJKMNP-Z]{4}-[2-9A-HJKMNP-Z]{4}-[2-9A-HJKMNP-Z]{4}$/);
      expect(ret.body.credit.balanceCents).toBe(18990);
      expect(await expectedCash()).toBe(cashBefore); // no salió dinero de la caja
      s.code = ret.body.credit.code;
    });

    it('consulta tolerante al formato; códigos inválidos o inexistentes', async () => {
      const loose = s.code.toLowerCase().replace(/-/g, '').replace('vale', '');
      const r = await api(app, s.seller).get(`/store-credits/lookup?code=${loose}`);
      expect(r.body).toMatchObject({ kind: 'refund', balanceCents: 18990, status: 'active', customerName: 'Lucía Ramos' });
      expect(r.body.code).toBeUndefined(); // el código nunca se vuelve a mostrar
      expect((await api(app, s.seller).get('/store-credits/lookup?code=VALE-0000-0000-0000')).status).toBe(400);
      expect((await api(app, s.seller).get('/store-credits/lookup?code=VALE-2222-2222-2222')).status).toBe(404);
      expect(normalizeCreditCode('vale 2345 6789 abcd')).toBe('VALE-2345-6789-ABCD');
    });

    it('pagar con vale + efectivo descuenta el saldo; sin saldo no hay venta', async () => {
      const ok = await sell(s.seller, { items: [{ variantId: s.M, quantity: 1 }], payments: [{ method: 'store_credit', amountCents: 10000, creditCode: s.code }, { method: 'cash', amountCents: 8990 }] });
      expect(ok.status).toBe(201);
      expect(ok.body.payments.find((p: any) => p.method === 'store_credit').reference).toBe(`Vale …${s.code.slice(-4)}`);
      expect((await api(app, s.seller).get(`/store-credits/lookup?code=${s.code}`)).body.balanceCents).toBe(8990);

      const before = await stock(s.M);
      const short = await sell(s.seller, { items: [{ variantId: s.M, quantity: 1 }], payments: [{ method: 'store_credit', amountCents: 18990, creditCode: s.code }] });
      expect(short.status).toBe(422);
      expect(short.body).toMatchObject({ code: 'CREDIT_INSUFFICIENT', balanceCents: 8990 });
      expect(await stock(s.M)).toBe(before);
      expect((await sell(s.seller, { items: [{ variantId: s.M, quantity: 1 }], payments: [{ method: 'store_credit', amountCents: 18990 }] })).body.code).toBe('CREDIT_CODE_REQUIRED');
      s.creditSale = ok.body.id;
    });

    it('dos cajas no pueden gastar el mismo saldo', async () => {
      const body = { items: [{ variantId: s.M, quantity: 1 }], payments: [{ method: 'store_credit', amountCents: 8990, creditCode: s.code }, { method: 'cash', amountCents: 10000 }] };
      const [a, b] = await Promise.all([sell(s.seller, body), sell(s.owner, body)]);
      expect([a.status, b.status].sort()).toEqual([201, 422]);
      expect((await o().get(`/store-credits/lookup?code=${s.code}`)).body).toMatchObject({ balanceCents: 0, status: 'used' });
      s.spentSale = a.status === 201 ? a.body.id : b.body.id;
    });

    it('anular una venta pagada con vale devuelve el saldo', async () => {
      await o().post(`/sales/${s.spentSale}/void`, { reason: 'Error de cobro' });
      expect((await o().get(`/store-credits/lookup?code=${s.code}`)).body.balanceCents).toBe(8990);
    });

    it('cortesía solo con permiso; gift card pagada entra a caja', async () => {
      expect((await api(app, s.seller).post('/store-credits/courtesy', { kind: 'courtesy', amountCents: 5000 })).status).toBe(403);
      expect((await o().post('/store-credits/courtesy', { kind: 'courtesy', amountCents: 5000, customerId: s.customer, note: 'Disculpas por la demora' })).body.kind).toBe('courtesy');

      const cashBefore = await expectedCash();
      const gift = await api(app, s.seller).post('/gift-cards', { branchId: s.branch, amountCents: 10000, payments: [{ method: 'cash', amountCents: 10000 }] });
      expect(gift.status).toBe(201);
      expect(gift.body).toMatchObject({ kind: 'gift', balanceCents: 10000 });
      expect(gift.body.code).toBeDefined();
      expect(await expectedCash()).toBe(cashBefore + 10000);
    });

    it('la ficha del cliente muestra su saldo a favor', async () => {
      const c = await o().get(`/customers/${s.customer}`);
      expect(c.body.stats.creditBalanceCents).toBe(8990 + 5000);
    });
  });

  describe('Apartados', () => {
    it('adelanto mínimo 10 %; al apartar, las prendas salen del disponible', async () => {
      const body = { branchId: s.branch, customerId: s.customer, items: [{ variantId: s.S, quantity: 2 }], days: 15 };
      expect((await api(app, s.seller).post('/layaways', { ...body, payments: [{ method: 'cash', amountCents: 1000 }] })).body.code).toBe('DEPOSIT_TOO_LOW');
      const cashBefore = await expectedCash();
      const l = await api(app, s.seller).post('/layaways', { ...body, payments: [{ method: 'cash', amountCents: 10000 }] });
      expect(l.status).toBe(201);
      expect(l.body).toMatchObject({ number: 1, status: 'open', totalCents: 37980, paidCents: 10000, pendingCents: 27980, customerName: 'Lucía Ramos' });
      expect(await stock(s.S)).toBe(3);
      expect(await expectedCash()).toBe(cashBefore + 10000);
      s.layaway = l.body.id;
    });

    it('abonos: no más que el saldo; no se entrega sin pagar todo', async () => {
      expect((await api(app, s.seller).post(`/layaways/${s.layaway}/payments`, { payments: [{ method: 'cash', amountCents: 30000 }] })).body.code).toBe('OVERPAYMENT');
      const p = await api(app, s.seller).post(`/layaways/${s.layaway}/payments`, { payments: [{ method: 'wallet', amountCents: 7980 }] });
      expect(p.body.pendingCents).toBe(20000);
      expect((await api(app, s.seller).post(`/layaways/${s.layaway}/complete`, {})).body.code).toBe('LAYAWAY_UNPAID');
    });

    it('entregar: venta normal al precio congelado, sin descontar el stock dos veces ni duplicar caja', async () => {
      await o().patch(`/products/${s.product}`, { priceCents: 24990 }); // subió el precio después de apartar
      const cashBefore = await expectedCash();
      const done = await api(app, s.seller).post(`/layaways/${s.layaway}/complete`, { payments: [{ method: 'cash', amountCents: 20000 }] });
      expect(done.status).toBe(200);
      expect(done.body.layaway).toMatchObject({ status: 'completed', paidCents: 37980 });
      expect(done.body.sale).toMatchObject({ totalCents: 37980, customerId: s.customer });
      expect(done.body.sale.items[0].unitPriceCents).toBe(18990);
      expect(done.body.sale.payments).toEqual([expect.objectContaining({ method: 'layaway', amountCents: 37980 })]);
      expect(await stock(s.S)).toBe(3);
      expect(await expectedCash()).toBe(cashBefore + 20000); // solo el último abono
      const kardex = await o().get(`/inventory/movements?variantId=${s.S}&branchId=${s.branch}`);
      expect(kardex.body.slice(0, 3).map((m: any) => m.type)).toEqual(['sale', 'layaway_release', 'layaway_reserve']);
      expect((await o().post(`/sales/${done.body.sale.id}/void`, { reason: 'x error' })).body.code).toBe('LAYAWAY_SALE');
    });

    it('cancelar: vuelve el stock y lo abonado queda como vale o se devuelve en efectivo', async () => {
      const mk = () => api(app, s.seller).post('/layaways', { branchId: s.branch, customerId: s.customer, items: [{ variantId: s.S, quantity: 1 }], payments: [{ method: 'cash', amountCents: 5000 }] });
      const a = await mk();
      expect(await stock(s.S)).toBe(2);
      const asCredit = await api(app, s.seller).post(`/layaways/${a.body.id}/cancel`, { reason: 'Ya no la quiere', refund: 'store_credit' });
      expect(asCredit.body.layaway.status).toBe('cancelled');
      expect(asCredit.body.credit.balanceCents).toBe(5000);
      expect(await stock(s.S)).toBe(3);

      const b = await mk();
      const cashBefore = await expectedCash();
      await api(app, s.seller).post(`/layaways/${b.body.id}/cancel`, { reason: 'Se mudó', refund: 'cash' });
      expect(await expectedCash()).toBe(cashBefore - 5000);
      expect((await api(app, s.seller).post(`/layaways/${b.body.id}/payments`, { payments: [{ method: 'cash', amountCents: 100 }] })).status).toBe(409);
    });

    it('vencidos: avisa a la sucursal', async () => {
      const l = await api(app, s.seller).post('/layaways', { branchId: s.branch, customerId: s.customer, items: [{ variantId: s.S, quantity: 1 }], payments: [{ method: 'cash', amountCents: 5000 }], days: 1 });
      const db = new Client({ connectionString: urls.owner });
      await db.connect();
      await db.query(`update layaways set expires_at = now() - interval '1 day' where id = $1`, [l.body.id]);
      await db.end();
      expect((await api(app, s.seller).get(`/layaways/${l.body.id}`)).body.expired).toBe(true);
      expect((await app.get(LayawaysService).notifyExpired()).expired).toBe(1);
      const inbox = await api(app, s.seller).get('/notifications');
      expect(inbox.body[0]).toMatchObject({ type: 'layaway.expired', link: `/layaways/${l.body.id}` });
      const list = await api(app, s.seller).get('/layaways?status=open');
      expect(list.body[0].id).toBe(l.body.id); // lo vencido primero
    });
  });
});
