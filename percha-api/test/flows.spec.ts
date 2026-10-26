import { INestApplication } from '@nestjs/common';
import { Client } from 'pg';
import { ean13CheckDigit } from '../src/modules/catalog/codes';
import { api, createApp, resetDatabase, urls } from './helpers';

/**
 * Historias de punta a punta contra Postgres real (RLS incluido).
 * Los tests comparten estado y van en orden, como un día en la boutique.
 */
describe('Percha API — fases 1 a 6', () => {
  let app: INestApplication;
  const s: Record<string, any> = {};

  beforeAll(async () => {
    await resetDatabase();
    app = await createApp();
  });
  afterAll(async () => app?.close());

  // ---------------------------------------------------------------- Fase 1-2
  describe('Identidad y multi-tenant', () => {
    it('registra dos tiendas independientes', async () => {
      const a = await api(app).post('/auth/register', { storeName: 'Boutique Alma', ownerName: 'Joao', email: 'joao@alma.pe', password: 'clave-segura-1' });
      expect(a.status).toBe(201);
      s.ownerA = a.body.accessToken;
      s.refreshA = a.body.refreshToken;
      s.tenantA = a.body.tenantId;

      const b = await api(app).post('/auth/register', { storeName: 'Otra Tienda', ownerName: 'Rival', email: 'rival@otra.pe', password: 'clave-segura-2' });
      s.ownerB = b.body.accessToken;

      const branches = await api(app, s.ownerA).get('/branches');
      expect(branches.body).toHaveLength(1);
      s.branchA = branches.body[0].id;
    });

    it('rechaza peticiones sin token y login con clave errada', async () => {
      expect((await api(app).get('/products')).status).toBe(401);
      expect((await api(app).post('/auth/login', { email: 'joao@alma.pe', password: 'mala' })).status).toBe(401);
    });

    it('rota el refresh token y detecta su reutilización', async () => {
      const first = await api(app).post('/auth/refresh', { refreshToken: s.refreshA });
      expect(first.status).toBe(200);
      const reuse = await api(app).post('/auth/refresh', { refreshToken: s.refreshA });
      expect(reuse.status).toBe(401);
      // La reutilización revoca también el token nuevo.
      expect((await api(app).post('/auth/refresh', { refreshToken: first.body.refreshToken })).status).toBe(401);
      const login = await api(app).post('/auth/login', { email: 'JOAO@alma.pe', password: 'clave-segura-1' });
      s.ownerA = login.body.accessToken;
    });

    it('calcula el onboarding a partir de los datos', async () => {
      await api(app, s.ownerA).patch('/store', { ruc: '20123456789' });
      const ob = await api(app, s.ownerA).get('/store/onboarding');
      expect(ob.body.completed).toBe(1);
      expect(ob.body.nextStep).toBe('attributes');
    });
  });

  // ---------------------------------------------------------------- Fase 3
  describe('Catálogo', () => {
    it('crea atributos con códigos automáticos', async () => {
      const talla = await api(app, s.ownerA).post('/attributes', { name: 'Talla', position: 0, values: ['S', 'M', 'L'] });
      expect(talla.status).toBe(201);
      const color = await api(app, s.ownerA).post('/attributes', { name: 'Color', position: 1, values: ['Negro', 'Beige'] });
      expect(color.body.values).toEqual([{ value: 'Negro', code: 'NEG' }, { value: 'Beige', code: 'BEI' }]);
    });

    it('crea un producto con matriz talla × color y stock inicial', async () => {
      const cat = await api(app, s.ownerA).post('/categories', { name: 'Vestidos' });
      s.categoryA = cat.body.id;
      const res = await api(app, s.ownerA).post('/products', {
        name: 'Vestido midi',
        skuBase: 'VST-014',
        categoryId: s.categoryA,
        priceCents: 18990,
        costCents: 8000,
        matrix: { Talla: ['S', 'M', 'L'], Color: ['Negro', 'Beige'] },
        initialStock: { branchId: s.branchA, items: [{ options: { Talla: 'M', Color: 'Negro' }, quantity: 2 }, { options: { Talla: 'L', Color: 'Negro' }, quantity: 1 }] },
      });
      expect(res.status).toBe(201);
      expect(res.body.variants).toHaveLength(6);
      const mNeg = res.body.variants.find((v: any) => v.sku === 'VST-014-M-NEG');
      expect(mNeg.stock[0].quantity).toBe(2);
      expect(mNeg.barcode).toMatch(/^20\d{11}$/);
      expect(mNeg.barcode.slice(-1)).toBe(ean13CheckDigit(mNeg.barcode.slice(0, 12)));
      s.productA = res.body.id;
      s.vMNeg = mNeg.id;
      s.vLNeg = res.body.variants.find((v: any) => v.sku === 'VST-014-L-NEG').id;
      s.vSBei = res.body.variants.find((v: any) => v.sku === 'VST-014-S-BEI').id;
      s.barcodeMNeg = mNeg.barcode;
    });

    it('busca por código de barras para el POS', async () => {
      const res = await api(app, s.ownerA).get(`/variants/lookup?code=${s.barcodeMNeg}&branchId=${s.branchA}`);
      expect(res.body).toMatchObject({ sku: 'VST-014-M-NEG', effectivePriceCents: 18990, stock: 2 });
    });

    it('importa un catálogo y rechaza archivos con errores sin escribir nada', async () => {
      const bad = await api(app, s.ownerA).post('/catalog/import', {
        branchId: s.branchA,
        rows: [
          { name: 'Polo básico', priceCents: 4990, options: { Talla: 'M' } },
          { name: 'Polo básico', priceCents: 4990, options: { Talla: 'M' } },
        ],
      });
      expect(bad.status).toBe(422);
      expect(bad.body.errors[0].row).toBe(1);

      const ok = await api(app, s.ownerA).post('/catalog/import', {
        branchId: s.branchA,
        rows: [
          { name: 'Polo básico', category: 'Polos', priceCents: 4990, costCents: 2000, options: { Talla: 'M', Color: 'Blanco' }, quantity: 10 },
          { name: 'Polo básico', category: 'Polos', priceCents: 4990, costCents: 2000, options: { Talla: 'L', Color: 'Blanco' }, quantity: 5 },
          { name: 'Correa de cuero', category: 'Accesorios', priceCents: 7900, quantity: 3 },
        ],
      });
      expect(ok.status).toBe(201);
      expect(ok.body).toEqual({ products: 2, variants: 3, unitsLoaded: 18 });
      const attrs = await api(app, s.ownerA).get('/attributes');
      expect(attrs.body.find((a: any) => a.name === 'Color').values.map((v: any) => v.value)).toContain('Blanco');
    });

    it('impide quitar un valor de atributo en uso', async () => {
      const attrs = await api(app, s.ownerA).get('/attributes');
      const talla = attrs.body.find((a: any) => a.name === 'Talla');
      const res = await api(app, s.ownerA).put(`/attributes/${talla.id}`, { values: ['S', 'L'] });
      expect(res.status).toBe(409);
    });

    it('aísla tiendas: B no ve ni referencia datos de A (RLS + FK compuesta)', async () => {
      expect((await api(app, s.ownerB).get(`/products/${s.productA}`)).status).toBe(404);
      expect((await api(app, s.ownerB).get('/products')).body.total).toBe(0);
      const sneaky = await api(app, s.ownerB).post('/products', { name: 'Intruso', priceCents: 100, categoryId: s.categoryA });
      expect(sneaky.status).toBe(422);
    });
  });

  // ---------------------------------------------------------------- Fase 6 (antes de vender, llega mercadería)
  describe('Compras', () => {
    it('crea, confirma y recibe parcialmente una OC; recalcula el costo promedio', async () => {
      const sup = await api(app, s.ownerA).post('/suppliers', { name: 'Textiles Gamarra', ruc: '20555555555' });
      const po = await api(app, s.ownerA).post('/purchase-orders', {
        supplierId: sup.body.id,
        branchId: s.branchA,
        items: [{ variantId: s.vMNeg, quantity: 4, unitCostCents: 9500 }],
      });
      expect(po.body).toMatchObject({ status: 'draft', number: 1, totalCents: 38000 });
      s.poA = po.body.id;
      const itemId = po.body.items[0].id;

      expect((await api(app, s.ownerA).post(`/purchase-orders/${s.poA}/receipts`, { items: [{ purchaseOrderItemId: itemId, quantity: 1 }] })).status).toBe(409);
      await api(app, s.ownerA).post(`/purchase-orders/${s.poA}/confirm`);

      const over = await api(app, s.ownerA).post(`/purchase-orders/${s.poA}/receipts`, { items: [{ purchaseOrderItemId: itemId, quantity: 5 }] });
      expect(over.status).toBe(422);

      const r1 = await api(app, s.ownerA).post(`/purchase-orders/${s.poA}/receipts`, { items: [{ purchaseOrderItemId: itemId, quantity: 2 }] });
      expect(r1.body.status).toBe('partial');

      const product = await api(app, s.ownerA).get(`/products/${s.productA}`);
      const v = product.body.variants.find((x: any) => x.id === s.vMNeg);
      // (2 × 8000 + 2 × 9500) / 4 = 8750
      expect(v.avgCostCents).toBe(8750);
      expect(v.stock[0].quantity).toBe(4);

      const r2 = await api(app, s.ownerA).post(`/purchase-orders/${s.poA}/receipts`, { items: [{ purchaseOrderItemId: itemId, quantity: 2 }] });
      expect(r2.body.status).toBe('received');
      expect((await api(app, s.ownerA).post(`/purchase-orders/${s.poA}/cancel`)).status).toBe(409);
    });
  });

  // ---------------------------------------------------------------- Equipo y roles
  describe('Equipo, invitaciones y PIN', () => {
    it('invita a un vendedor, acepta y queda con permisos limitados', async () => {
      const inv = await api(app, s.ownerA).post('/team/invitations', { email: 'diego@alma.pe', role: 'seller', branchId: s.branchA });
      expect(inv.status).toBe(201);
      const acc = await api(app).post('/auth/invitations/accept', { token: inv.body.token, name: 'Diego', password: 'vendedor-123' });
      expect(acc.status).toBe(201);
      s.seller = acc.body.accessToken;

      const me = await api(app, s.seller).get('/auth/me');
      expect(me.body.role).toBe('seller');
      expect(me.body.branchId).toBe(s.branchA);

      // Sin costos, sin ajustes, sin gestión de equipo.
      const product = await api(app, s.seller).get(`/products/${s.productA}`);
      expect(product.body.costCents).toBeUndefined();
      expect(product.body.variants[0].avgCostCents).toBeUndefined();
      expect((await api(app, s.seller).post('/inventory/adjustments', { branchId: s.branchA, reason: 'test', items: [{ variantId: s.vMNeg, delta: 1 }] })).status).toBe(403);
      expect((await api(app, s.seller).get('/team/members')).status).toBe(403);
      // La invitación no se puede reutilizar.
      expect((await api(app).post('/auth/invitations/accept', { token: inv.body.token, name: 'Xavier', password: 'otra-clave-1' })).status).toBe(401);
    });

    it('PIN único por sucursal y cambio rápido de vendedor', async () => {
      const members = await api(app, s.ownerA).get('/team/members');
      s.ownerMember = members.body.find((m: any) => m.role === 'owner').id;
      s.sellerMember = members.body.find((m: any) => m.role === 'seller').id;

      expect((await api(app, s.ownerA).put(`/team/members/${s.ownerMember}/pin`, { pin: '4321' })).status).toBe(204);
      expect((await api(app, s.seller).put(`/team/members/${s.sellerMember}/pin`, { pin: '4321' })).status).toBe(409);
      expect((await api(app, s.seller).put(`/team/members/${s.sellerMember}/pin`, { pin: '1111' })).status).toBe(204);

      const sw = await api(app, s.ownerA).post('/auth/pin', { branchId: s.branchA, pin: '1111' });
      expect(sw.status).toBe(200);
      const me = await api(app, sw.body.accessToken).get('/auth/me');
      expect(me.body.role).toBe('seller');
    });

    it('no deja a la tienda sin dueño ni permite auto-promoverse', async () => {
      expect((await api(app, s.ownerA).patch(`/team/members/${s.ownerMember}`, { role: 'manager' })).status).toBe(403);
      expect((await api(app, s.seller).patch(`/team/members/${s.sellerMember}`, { role: 'owner' })).status).toBe(403);
    });
  });

  // ---------------------------------------------------------------- Fase 4-5
  describe('Caja, ventas, anulaciones y cambios', () => {
    it('no vende sin caja abierta', async () => {
      const res = await api(app, s.seller).post('/sales', { branchId: s.branchA, items: [{ variantId: s.vMNeg, quantity: 1 }], payments: [{ method: 'cash', amountCents: 18990 }] });
      expect(res.status).toBe(409);
      expect(res.body.code).toBe('CASH_CLOSED');
    });

    it('vende, descuenta stock, calcula IGV incluido y vuelto', async () => {
      const cash = await api(app, s.seller).post('/cash-sessions', { branchId: s.branchA, openingCents: 10000 });
      s.cashA = cash.body.id;
      const res = await api(app, s.seller).post('/sales', {
        branchId: s.branchA,
        items: [{ variantId: s.vMNeg, quantity: 1 }, { variantId: s.vMNeg, quantity: 1 }],
        payments: [{ method: 'cash', amountCents: 37980 }],
        cashReceivedCents: 40000,
      });
      expect(res.status).toBe(201);
      expect(res.body).toMatchObject({ number: 1, subtotalCents: 37980, totalCents: 37980, taxCents: 5794, changeCents: 2020 });
      expect(res.body.items).toHaveLength(1); // ítems repetidos se fusionan
      s.sale1 = res.body;
      const byNumber = await api(app, s.seller).get(`/sales?branchId=${s.branchA}&number=1`);
      expect(byNumber.body.map((x: any) => x.id)).toEqual([res.body.id]);
      const stock = await api(app, s.ownerA).get(`/inventory/stock?branchId=${s.branchA}&variantId=${s.vMNeg}`);
      expect(stock.body[0].quantity).toBe(4);
    });

    it('stock insuficiente: la venta completa se revierte', async () => {
      const res = await api(app, s.seller).post('/sales', {
        branchId: s.branchA,
        items: [{ variantId: s.vMNeg, quantity: 1 }, { variantId: s.vLNeg, quantity: 2 }],
        payments: [{ method: 'card', amountCents: 56970 }],
      });
      expect(res.status).toBe(422);
      expect(res.body).toMatchObject({ code: 'INSUFFICIENT_STOCK', available: 1 });
      const stock = await api(app, s.ownerA).get(`/inventory/stock?branchId=${s.branchA}&variantId=${s.vMNeg}`);
      expect(stock.body[0].quantity).toBe(4);
    });

    it('rechaza pagos que no cuadran', async () => {
      const res = await api(app, s.seller).post('/sales', { branchId: s.branchA, items: [{ variantId: s.vMNeg, quantity: 1 }], payments: [{ method: 'cash', amountCents: 100 }] });
      expect(res.body.code).toBe('PAYMENT_MISMATCH');
    });

    it('descuento sobre el límite requiere PIN de supervisor', async () => {
      const body = { branchId: s.branchA, items: [{ variantId: s.vMNeg, quantity: 1 }], discountCents: 5000, payments: [{ method: 'card', amountCents: 13990 }] };
      const denied = await api(app, s.seller).post('/sales', body);
      expect(denied.body.code).toBe('APPROVAL_REQUIRED');
      expect((await api(app, s.seller).post('/sales', { ...body, approverPin: '9999' })).body.code).toBe('APPROVAL_INVALID');
      const ok = await api(app, s.seller).post('/sales', { ...body, approverPin: '4321' });
      expect(ok.status).toBe(201);
      expect(ok.body.discountApprovedBy).toBe(s.ownerMember);
      s.sale2 = ok.body;
    });

    it('dos ventas simultáneas de la última unidad: solo una gana', async () => {
      const body = { branchId: s.branchA, items: [{ variantId: s.vLNeg, quantity: 1 }], payments: [{ method: 'card', amountCents: 18990 }] };
      const [r1, r2] = await Promise.all([api(app, s.seller).post('/sales', body), api(app, s.ownerA).post('/sales', body)]);
      expect([r1.status, r2.status].sort()).toEqual([201, 422]);
    });

    it('cambio de talla: devuelve M Negro con descuento, se lleva S Beige y paga la diferencia', async () => {
      // La venta 2 tuvo S/ 50 de descuento: la prenda se valora a S/ 139.90, la nueva cuesta S/ 189.90.
      const res = await api(app, s.seller).post(`/sales/${s.sale2.id}/returns`, {
        branchId: s.branchA,
        items: [{ saleItemId: s.sale2.items[0].id, quantity: 1 }],
        replacements: [{ variantId: s.vSBei, quantity: 1 }],
        payments: [{ method: 'cash', amountCents: 5000 }],
        reason: 'Le quedó grande',
      });
      expect(res.status).toBe(422); // S Beige no tiene stock

      await api(app, s.ownerA).post('/inventory/adjustments', { branchId: s.branchA, reason: 'Conteo físico', items: [{ variantId: s.vSBei, counted: 2 }] });
      const ok = await api(app, s.seller).post(`/sales/${s.sale2.id}/returns`, {
        branchId: s.branchA,
        items: [{ saleItemId: s.sale2.items[0].id, quantity: 1 }],
        replacements: [{ variantId: s.vSBei, quantity: 1 }],
        payments: [{ method: 'cash', amountCents: 5000 }],
        reason: 'Le quedó grande',
      });
      expect(ok.status).toBe(201);
      expect(ok.body).toMatchObject({ kind: 'exchange', returnedCents: 13990, replacementCents: 18990, differenceCents: 5000 });

      const again = await api(app, s.seller).post(`/sales/${s.sale2.id}/returns`, { branchId: s.branchA, items: [{ saleItemId: s.sale2.items[0].id, quantity: 1 }], payments: [{ method: 'cash', amountCents: 13990 }], reason: 'otra vez' });
      expect(again.status).toBe(422);
    });

    it('anular: vendedor necesita PIN; se repone stock y se revierte el pago', async () => {
      expect((await api(app, s.seller).post(`/sales/${s.sale1.id}/void`, { reason: 'Cobro duplicado' })).body.code).toBe('APPROVAL_REQUIRED');
      const res = await api(app, s.seller).post(`/sales/${s.sale1.id}/void`, { reason: 'Cobro duplicado', approverPin: '4321' });
      expect(res.status).toBe(200);
      expect(res.body.status).toBe('voided');
      expect(res.body.payments.map((p: any) => p.amountCents).sort()).toEqual([-37980, 37980]);
      expect((await api(app, s.ownerA).post(`/sales/${s.sale2.id}/void`, { reason: 'x tiene devolución' })).body.code).toBe('USE_RETURN');
    });

    it('cierra caja: esperado = apertura + efectivo neto', async () => {
      // 100.00 apertura + 379.80 venta − 379.80 anulación + 50.00 diferencia del cambio = 150.00
      const res = await api(app, s.seller).post(`/cash-sessions/${s.cashA}/close`, { countedCashCents: 14900 });
      expect(res.body).toMatchObject({ status: 'closed', expectedCashCents: 15000, differenceCents: -100 });
    });
  });

  // ---------------------------------------------------------------- Garantías de la BD
  describe('Garantías a nivel de base de datos', () => {
    it('el kardex es inmutable y cuadra con el stock', async () => {
      const kardex = await api(app, s.ownerA).get(`/inventory/movements?variantId=${s.vMNeg}`);
      const types = kardex.body.map((m: any) => m.type);
      expect(types).toEqual(expect.arrayContaining(['initial', 'purchase_receipt', 'sale', 'sale_void', 'return_in']));
      expect(kardex.body[0].balanceAfter).toBe(kardex.body.reduce((a: number, m: any) => a + m.quantity, 0));

      const db = new Client({ connectionString: urls.app });
      await db.connect();
      await expect(db.query('UPDATE stock_movements SET quantity = 999')).rejects.toThrow(/permission denied/);
      const noTenant = await db.query('SELECT count(*)::int AS c FROM products');
      expect(noTenant.rows[0].c).toBe(0); // sin app.tenant_id no se ve nada
      await db.end();
    });

    it('el onboarding avanza solo con el uso real', async () => {
      const ob = await api(app, s.ownerA).get('/store/onboarding');
      expect(ob.body.completed).toBe(5);
    });
  });
});
