import { INestApplication } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Client } from 'pg';
import request from 'supertest';
import { api, createApp, resetDatabase, urls } from './helpers';

/**
 * Auditoría del stock como prueba: cada operación que sube o baja stock se aplica UNA vez,
 * los correlativos no tienen huecos ni repetidos, y al final el stock de cada variante es
 * exactamente la suma de su kardex.
 */
describe('Stock: idempotencia, correlativos e integridad', () => {
  let app: INestApplication;
  const s: Record<string, any> = {};
  const o = () => api(app, s.owner);
  const post = (url: string, body: object, key?: string) => {
    const r = request(app.getHttpServer()).post(`/v1${url}`).set('Authorization', `Bearer ${s.owner}`);
    return (key ? r.set('Idempotency-Key', key) : r).send(body);
  };
  const stock = async (variantId: string, branchId = s.main) => (await o().get(`/inventory/stock?branchId=${branchId}&variantId=${variantId}`)).body[0]?.quantity ?? 0;
  const sale = (variantId: string, quantity = 1, extra: object = {}) => ({ branchId: s.main, items: [{ variantId, quantity }], payments: [{ method: 'card', amountCents: 18990 * quantity }], ...extra });

  beforeAll(async () => {
    await resetDatabase();
    app = await createApp();
    const reg = await api(app).post('/auth/register', { storeName: 'Alma', ownerName: 'Joao', email: 'j@alma.pe', password: 'clave-segura-1' });
    s.owner = reg.body.accessToken;
    s.main = (await o().get('/branches')).body[0].id;
    s.mall = (await o().post('/branches', { name: 'Mall' })).body.id;
    await o().post('/attributes', { name: 'Talla', values: ['S', 'M'] });
    const p = await o().post('/products', {
      name: 'Vestido midi',
      priceCents: 18990,
      costCents: 8000,
      matrix: { Talla: ['S', 'M'] },
      initialStock: { branchId: s.main, items: [{ options: { Talla: 'S' }, quantity: 10 }, { options: { Talla: 'M' }, quantity: 3 }] },
    });
    s.S = p.body.variants.find((v: any) => v.options.Talla === 'S').id;
    s.M = p.body.variants.find((v: any) => v.options.Talla === 'M').id;
    s.customer = (await o().post('/customers', { name: 'Lucía Ramos', phone: '987111222' })).body.id;
    await o().post('/cash-sessions', { branchId: s.main, openingCents: 0 });
  });
  afterAll(async () => app?.close());

  describe('Ventas', () => {
    it('reintento con la misma clave: misma venta, stock descontado una vez', async () => {
      const key = randomUUID();
      const a = await post('/sales', sale(s.S), key);
      const b = await post('/sales', sale(s.S), key);
      expect(a.status).toBe(201);
      expect(b.body).toMatchObject({ id: a.body.id, number: a.body.number, replayed: true });
      expect(await stock(s.S)).toBe(9);
      s.firstSale = a.body;
    });

    it('la misma clave con otro contenido se rechaza (no es un reintento)', async () => {
      const key = randomUUID();
      await post('/sales', sale(s.S), key);
      const r = await post('/sales', sale(s.S, 2), key);
      expect(r.status).toBe(409);
      expect(r.body.code).toBe('IDEMPOTENCY_KEY_REUSED');
      expect(await stock(s.S)).toBe(8);
    });

    it('reintentos simultáneos con la misma clave: una sola venta', async () => {
      const key = randomUUID();
      const results = await Promise.all([post('/sales', sale(s.S), key), post('/sales', sale(s.S), key), post('/sales', sale(s.S), key)]);
      expect(new Set(results.map((r) => r.body.id)).size).toBe(1);
      expect(await stock(s.S)).toBe(7);
    });

    it('correlativos: sin huecos aunque falle una venta, sin repetidos con ventas simultáneas', async () => {
      expect((await post('/sales', sale(s.M, 50))).body.code).toBe('INSUFFICIENT_STOCK'); // no consume número
      await Promise.all([post('/sales', sale(s.S)), post('/sales', sale(s.S)), post('/sales', sale(s.S))]);
      const numbers = (await o().get(`/sales?branchId=${s.main}&limit=100`)).body.map((x: any) => x.number).sort((a: number, b: number) => a - b);
      expect(numbers).toEqual(Array.from({ length: numbers.length }, (_, i) => i + 1));
      expect(await stock(s.S)).toBe(4);
    });

    it('anular devuelve el stock una vez; anular de nuevo no hace nada', async () => {
      await o().post(`/sales/${s.firstSale.id}/void`, { reason: 'Error de cobro' });
      expect((await o().post(`/sales/${s.firstSale.id}/void`, { reason: 'Error de cobro' })).status).toBe(409);
      expect(await stock(s.S)).toBe(5);
    });
  });

  describe('Devoluciones y cambios', () => {
    it('reintento: una devolución; no se devuelve más de lo vendido', async () => {
      const sold = await post('/sales', sale(s.S, 2), randomUUID());
      const itemId = sold.body.items[0].id;
      expect(await stock(s.S)).toBe(3);
      const body = { branchId: s.main, items: [{ saleItemId: itemId, quantity: 1 }], payments: [{ method: 'cash', amountCents: 18990 }], reason: 'No le quedó' };
      const key = randomUUID();
      const a = await post(`/sales/${sold.body.id}/returns`, body, key);
      const b = await post(`/sales/${sold.body.id}/returns`, body, key);
      expect(a.status).toBe(201);
      expect(b.body).toMatchObject({ id: a.body.id, replayed: true });
      expect(await stock(s.S)).toBe(4);
      // Otra devolución (otra clave) de la unidad restante: válida. Una tercera: no hay qué devolver.
      expect((await post(`/sales/${sold.body.id}/returns`, body, randomUUID())).status).toBe(201);
      expect((await post(`/sales/${sold.body.id}/returns`, body, randomUUID())).status).toBe(422);
      expect(await stock(s.S)).toBe(5);
    });
  });

  describe('Compras, ajustes, transferencias y apartados', () => {
    it('recepción de mercadería: reintento no suma dos veces', async () => {
      const sup = await o().post('/suppliers', { name: 'Textiles' });
      const po = await o().post('/purchase-orders', { supplierId: sup.body.id, branchId: s.main, items: [{ variantId: s.M, quantity: 4, unitCostCents: 8000 }] });
      await o().post(`/purchase-orders/${po.body.id}/confirm`);
      const key = randomUUID();
      const body = { items: [{ purchaseOrderItemId: po.body.items[0].id, quantity: 4 }] };
      await post(`/purchase-orders/${po.body.id}/receipts`, body, key);
      const again = await post(`/purchase-orders/${po.body.id}/receipts`, body, key);
      expect(again.body.replayed).toBe(true);
      expect(await stock(s.M)).toBe(7);
    });

    it('ajuste por variación: reintento no ajusta dos veces', async () => {
      const key = randomUUID();
      const body = { branchId: s.main, reason: 'Merma', items: [{ variantId: s.M, delta: -1 }] };
      await post('/inventory/adjustments', body, key);
      await post('/inventory/adjustments', body, key);
      expect(await stock(s.M)).toBe(6);
    });

    it('transferencia: reintento envía una vez; recibir dos veces no suma dos veces', async () => {
      const key = randomUUID();
      const body = { fromBranchId: s.main, toBranchId: s.mall, items: [{ variantId: s.M, quantity: 2 }] };
      const a = await post('/transfers', body, key);
      const b = await post('/transfers', body, key);
      expect(b.body.id).toBe(a.body.id);
      expect(await stock(s.M)).toBe(4);
      await o().post(`/transfers/${a.body.id}/receive`, {});
      expect((await o().post(`/transfers/${a.body.id}/receive`, {})).status).toBe(409);
      expect(await stock(s.M, s.mall)).toBe(2);
    });

    it('apartado: crear y abonar con reintentos se aplican una vez', async () => {
      const key = randomUUID();
      const body = { branchId: s.main, customerId: s.customer, items: [{ variantId: s.M, quantity: 1 }], payments: [{ method: 'cash', amountCents: 5000 }] };
      const a = await post('/layaways', body, key);
      const b = await post('/layaways', body, key);
      expect(b.body.id).toBe(a.body.id);
      expect(await stock(s.M)).toBe(3);
      const payKey = randomUUID();
      await post(`/layaways/${a.body.id}/payments`, { payments: [{ method: 'cash', amountCents: 3000 }] }, payKey);
      const paid = await post(`/layaways/${a.body.id}/payments`, { payments: [{ method: 'cash', amountCents: 3000 }] }, payKey);
      expect(paid.body.paidCents).toBe(8000);
    });
  });

  describe('Ventas sin conexión', () => {
    it('si al sincronizar falta stock: ajuste explícito + venta, nunca stock negativo oculto', async () => {
      const before = await stock(s.M); // 3
      const occurredAt = new Date(Date.now() - 2 * 3_600_000).toISOString();
      const r = await post('/sales', { ...sale(s.M, before + 2), offline: { occurredAt } }, randomUUID());
      expect(r.status).toBe(201);
      expect(new Date(r.body.createdAt).toISOString()).toBe(occurredAt); // fecha real de la venta
      expect(await stock(s.M)).toBe(0);
      const kardex = (await o().get(`/inventory/movements?variantId=${s.M}&branchId=${s.main}`)).body;
      const auto = kardex.find((m: any) => m.type === 'adjustment' && m.quantity === 2);
      expect(auto.reason).toContain('venta sin conexión');
      expect((await o().get('/notifications')).body.some((n: any) => n.title === 'Revisa el stock: venta sin conexión')).toBe(true);
    });

    it('una venta que llegó pero cuya respuesta se perdió, reenviada desde la cola, no se duplica', async () => {
      const key = randomUUID();
      const first = await post('/sales', sale(s.S), key); // el POS no recibió esta respuesta…
      const fromQueue = await post('/sales', { ...sale(s.S), offline: { occurredAt: new Date().toISOString() } }, key);
      expect(fromQueue.body).toMatchObject({ id: first.body.id, replayed: true });
    });

    it('la venta queda a nombre de quien la hizo en el equipo, aunque sincronice otra persona', async () => {
      const inv = await o().post('/team/invitations', { email: 'v@alma.pe', role: 'seller', branchId: s.main });
      const seller = await api(app).post('/auth/invitations/accept', { token: inv.body.token, name: 'Diego', password: 'vendedor-123' });
      const sellerId = seller.body.user?.membershipId ?? (await api(app, seller.body.accessToken).get('/auth/me')).body.membershipId;
      const r = await post('/sales', { ...sale(s.S), offline: { occurredAt: new Date().toISOString(), sellerMembershipId: sellerId } }, randomUUID());
      expect(r.body.sellerId).toBe(sellerId);
      // Un id ajeno a la tienda no se acepta: queda quien sincroniza.
      const r2 = await post('/sales', { ...sale(s.S), offline: { occurredAt: new Date().toISOString(), sellerMembershipId: randomUUID() } }, randomUUID());
      expect(r2.body.sellerId).not.toBe(sellerId);
    });

    it('rechaza ventas sin conexión de hace más de 72 h o con fecha futura', async () => {
      const old = new Date(Date.now() - 80 * 3_600_000).toISOString();
      const future = new Date(Date.now() + 3_600_000).toISOString();
      expect((await post('/sales', { ...sale(s.S), offline: { occurredAt: old } })).body.code).toBe('OFFLINE_TOO_OLD');
      expect((await post('/sales', { ...sale(s.S), offline: { occurredAt: future } })).body.code).toBe('OFFLINE_CLOCK');
    });
  });

  describe('Defensas en la base e integridad', () => {
    it('la base impide un segundo movimiento igual para la misma operación', async () => {
      const db = new Client({ connectionString: urls.owner });
      await db.connect();
      const [m] = (await db.query(`select * from stock_movements where reference_type = 'sale' limit 1`)).rows;
      await expect(
        db.query(
          `insert into stock_movements (tenant_id, branch_id, variant_id, type, quantity, balance_after, reference_type, reference_id, actor_membership_id)
           values ($1, $2, $3, $4, $5, 0, $6, $7, $8)`,
          [m.tenant_id, m.branch_id, m.variant_id, m.type, m.quantity, m.reference_type, m.reference_id, m.actor_membership_id],
        ),
      ).rejects.toThrow(/stock_movements_once_per_operation_uq/);
      await db.end();
    });

    it('al final: el stock de cada variante es exactamente la suma de su kardex', async () => {
      const r = await o().get('/inventory/integrity');
      expect(r.body).toMatchObject({ ok: true, discrepancies: [] });
      expect(r.body.checked).toBeGreaterThanOrEqual(3);
    });

    it('las claves de idempotencia se limpian a los 7 días', async () => {
      const db = new Client({ connectionString: urls.owner });
      await db.connect();
      await db.query(`update idempotency_keys set created_at = now() - interval '8 days' where key = (select key from idempotency_keys limit 1)`);
      const { IdempotencyService } = await import('../src/common/idempotency');
      expect((await app.get(IdempotencyService).purge()).purged).toBe(1);
      await db.end();
    });

    it('la verificación detecta un stock alterado por fuera del kardex', async () => {
      const db = new Client({ connectionString: urls.owner });
      await db.connect();
      await db.query(`update stock_levels set quantity = quantity + 5 where variant_id = $1 and branch_id = $2`, [s.S, s.main]);
      const r = await o().get('/inventory/integrity');
      expect(r.body.ok).toBe(false);
      expect(r.body.discrepancies).toEqual([expect.objectContaining({ variantId: s.S, branchId: s.main })]);
      await db.query(`update stock_levels set quantity = quantity - 5 where variant_id = $1 and branch_id = $2`, [s.S, s.main]);
      await db.end();
    });
  });
});
