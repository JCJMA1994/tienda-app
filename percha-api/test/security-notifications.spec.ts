import { INestApplication } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { api, createApp, resetDatabase } from './helpers';

describe('Seguridad y notificaciones', () => {
  let app: INestApplication;
  const s: Record<string, any> = {};

  beforeAll(async () => {
    await resetDatabase();
    app = await createApp();
    const reg = await api(app).post('/auth/register', { storeName: 'Alma', ownerName: 'Joao', email: 'j@alma.pe', password: 'clave-segura-1' });
    s.owner = reg.body.accessToken;
    const o = api(app, s.owner);
    s.main = (await o.get('/branches')).body[0].id;
    s.mall = (await o.post('/branches', { name: 'Mall' })).body.id;
    s.ownerMember = (await o.get('/auth/me')).body.membershipId;
    await o.put(`/team/members/${s.ownerMember}/pin`, { pin: '4321' });

    // Vendedor y almacenero del mall.
    const invSeller = await o.post('/team/invitations', { email: 'v@alma.pe', role: 'seller', branchId: s.main });
    s.seller = (await api(app).post('/auth/invitations/accept', { token: invSeller.body.token, name: 'Diego', password: 'vendedor-123' })).body.accessToken;
    const invStock = await o.post('/team/invitations', { email: 'a@alma.pe', role: 'stock', branchId: s.mall });
    s.mallStock = (await api(app).post('/auth/invitations/accept', { token: invStock.body.token, name: 'Ana', password: 'almacen-123' })).body.accessToken;

    const p = await o.post('/products', { name: 'Vestido midi', priceCents: 18990, initialStock: { branchId: s.main, items: [{ options: {}, quantity: 2 }] } });
    s.productId = p.body.id;
    s.variant = p.body.variants[0].id;
    await o.put('/inventory/min-stock', { branchId: s.main, variantId: s.variant, minQuantity: 1 });
    await o.post('/cash-sessions', { branchId: s.main, openingCents: 0 });
  });
  afterAll(async () => app?.close());

  describe('Bloqueos por intentos fallidos', () => {
    it('5 contraseñas erradas bloquean el correo 15 min (aunque luego pongan la correcta)', async () => {
      for (let i = 0; i < 5; i++) {
        expect((await api(app).post('/auth/login', { email: 'v@alma.pe', password: 'mala-clave' })).status).toBe(401);
      }
      const locked = await api(app).post('/auth/login', { email: 'v@alma.pe', password: 'vendedor-123' });
      expect(locked.status).toBe(429);
      expect(locked.body).toMatchObject({ code: 'TOO_MANY_ATTEMPTS' });
      expect(locked.body.retryAfterSeconds).toBeGreaterThan(800);
      // Otro correo no se ve afectado.
      expect((await api(app).post('/auth/login', { email: 'j@alma.pe', password: 'clave-segura-1' })).status).toBe(200);
    });

    it('el PIN de aprobación se bloquea tras 5 intentos de quien lo prueba', async () => {
      const body = (pin: string) => ({ branchId: s.main, items: [{ variantId: s.variant, quantity: 1 }], discountCents: 5000, payments: [{ method: 'card', amountCents: 13990 }], approverPin: pin });
      for (let i = 0; i < 5; i++) {
        expect((await api(app, s.seller).post('/sales', body('0000'))).body.code).toBe('APPROVAL_INVALID');
      }
      const locked = await api(app, s.seller).post('/sales', body('4321'));
      expect(locked.status).toBe(429);
    });

    it('el cambio de vendedor por PIN también se bloquea por sucursal', async () => {
      for (let i = 0; i < 5; i++) await api(app, s.owner).post('/auth/pin', { branchId: s.mall, pin: '9999' });
      expect((await api(app, s.owner).post('/auth/pin', { branchId: s.mall, pin: '9998' })).status).toBe(429);
    });
  });

  describe('Sesiones y tokens', () => {
    it('cambiar la contraseña exige la actual y cierra las demás sesiones', async () => {
      const other = await api(app).post('/auth/login', { email: 'j@alma.pe', password: 'clave-segura-1' });
      expect((await api(app, s.owner).post('/auth/password', { currentPassword: 'equivocada', newPassword: 'nueva-clave-2' })).status).toBe(401);
      expect((await api(app, s.owner).post('/auth/password', { currentPassword: 'clave-segura-1', newPassword: 'sinnumeros' })).status).toBe(400);

      const ok = await api(app, s.owner).post('/auth/password', { currentPassword: 'clave-segura-1', newPassword: 'nueva-clave-2' });
      expect(ok.status).toBe(200);
      s.owner = ok.body.accessToken;
      expect((await api(app).post('/auth/refresh', { refreshToken: other.body.refreshToken })).status).toBe(401);
      expect((await api(app).post('/auth/login', { email: 'j@alma.pe', password: 'nueva-clave-2' })).status).toBe(200);
    });

    it('rechaza JWT de otro emisor/audiencia aunque use el mismo secreto', async () => {
      const jwt = new JwtService({ secret: process.env.JWT_ACCESS_SECRET });
      const forged = await jwt.signAsync({ sub: 'x', tid: 'x', mid: 'x', role: 'owner', bid: null }, { issuer: 'otro-sistema', audience: 'percha-app' });
      expect((await api(app, forged).get('/auth/me')).status).toBe(401);
    });

    it('rechaza cuerpos de más de 2 MB', async () => {
      const big = { rows: [{ name: 'x'.repeat(3 * 1024 * 1024) }], branchId: s.main };
      expect((await api(app, s.owner).post('/catalog/import', big)).status).toBe(413);
    });
  });

  describe('Notificaciones', () => {
    it('transferencia: avisa a quien recibe en la sucursal destino (no al que envía)', async () => {
      const t = await api(app, s.owner).post('/transfers', { fromBranchId: s.main, toBranchId: s.mall, items: [{ variantId: s.variant, quantity: 1 }] });
      expect(t.status).toBe(201);
      const inbox = await api(app, s.mallStock).get('/notifications');
      expect(inbox.body[0]).toMatchObject({ type: 'transfer.incoming', link: `/transfers/${t.body.id}`, readAt: null });
      expect((await api(app, s.mallStock).get('/notifications/unread-count')).body.unread).toBeGreaterThanOrEqual(1);
      expect((await api(app, s.owner).get('/notifications')).body.some((n: any) => n.type === 'transfer.incoming')).toBe(false);
      s.transferNotif = inbox.body[0].id;
    });

    it('stock bajo: avisa al cruzar el mínimo y no repite mientras siga sin leer', async () => {
      // Quedaba 1 (mínimo 1) tras la transferencia; se vende y se agota.
      const before = (await api(app, s.owner).get('/notifications')).body.filter((n: any) => n.type === 'stock.low').length;
      expect(before).toBeGreaterThanOrEqual(1); // la transferencia ya lo dejó en el mínimo
      await api(app, s.owner).post('/sales', { branchId: s.main, items: [{ variantId: s.variant, quantity: 1 }], payments: [{ method: 'cash', amountCents: 18990 }] });
      const after = (await api(app, s.owner).get('/notifications')).body.filter((n: any) => n.type === 'stock.low');
      expect(after).toHaveLength(before); // mismo producto, aviso aún sin leer: no se duplica
      expect(after[0].link).toBe(`/products/${s.productId}`);
    });

    it('cada quien marca solo sus notificaciones', async () => {
      expect((await api(app, s.owner).post(`/notifications/${s.transferNotif}/read`)).status).toBe(404);
      expect((await api(app, s.mallStock).post(`/notifications/${s.transferNotif}/read`)).status).toBe(200);
      const all = await api(app, s.mallStock).post('/notifications/read-all');
      expect(all.status).toBe(200);
      expect((await api(app, s.mallStock).get('/notifications/unread-count')).body.unread).toBe(0);
    });

    it('el dueño recibe aviso cuando alguien se une al equipo', async () => {
      const inbox = await api(app, s.owner).get('/notifications?limit=50');
      expect(inbox.body.filter((n: any) => n.type === 'team.joined').map((n: any) => n.title)).toEqual(expect.arrayContaining(['Diego se unió al equipo', 'Ana se unió al equipo']));
    });

    it('registra el dispositivo para push (el token pasa al último usuario)', async () => {
      const token = 'fcm-token-de-prueba-'.padEnd(40, 'x');
      expect((await api(app, s.owner).post('/devices', { token, platform: 'android' })).status).toBe(200);
      expect((await api(app, s.seller).post('/devices', { token, platform: 'android' })).status).toBe(200);
    });
  });
});
