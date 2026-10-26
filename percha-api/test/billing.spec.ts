import { INestApplication } from '@nestjs/common';
import { createHmac } from 'node:crypto';
import { Client } from 'pg';
import request from 'supertest';
import { addMonths } from '../src/modules/billing/billing.service';
import { verifyStripeSignature } from '../src/modules/billing/providers/stripe.provider';
import { api, createApp, resetDatabase } from './helpers';

const FAKE_SECRET = 'fake-webhook-secret';
const hours = (h: number) => h * 3_600_000;
const days = (d: number) => hours(24 * d);

/** Ciclo completo: prueba → factura → gracia → bloqueo suave → pago → renovación automática. */
describe('Facturación SaaS (fase 8)', () => {
  let app: INestApplication;
  const s: Record<string, any> = {};

  const webhook = (body: object, secret = FAKE_SECRET) => {
    const raw = JSON.stringify(body);
    return request(app.getHttpServer())
      .post('/v1/billing/webhooks/fake')
      .set('Content-Type', 'application/json')
      .set('x-fake-signature', createHmac('sha256', secret).update(raw).digest('hex'))
      .send(raw);
  };
  const run = (at: number) => api(app, s.admin).post('/admin/billing/run', { now: new Date(at).toISOString() });

  beforeAll(async () => {
    await resetDatabase();
    app = await createApp();
    const a = await api(app).post('/auth/register', { storeName: 'Boutique Alma', ownerName: 'Joao', email: 'joao@alma.pe', password: 'clave-segura-1' });
    s.owner = a.body.accessToken;
    const p = await api(app).post('/auth/register', { storeName: 'Plataforma', ownerName: 'Admin', email: 'admin@percha.pe', password: 'clave-segura-2' });
    s.admin = p.body.accessToken;

    // Se promueve al superadmin directo en la BD (en producción: scripts/make-admin.mjs).
    const db = new Client({ connectionString: (process.env.TEST_ADMIN_URL ?? 'postgres://postgres:postgres@localhost:5432/postgres').replace(/\/postgres$/, '/percha_test') });
    await db.connect();
    await db.query(`INSERT INTO platform_admins (user_id) SELECT id FROM users WHERE email = 'admin@percha.pe'`);
    await db.end();
  });
  afterAll(async () => app?.close());

  it('una tienda nueva arranca en prueba con el plan Crece', async () => {
    const res = await api(app, s.owner).get('/billing');
    expect(res.body).toMatchObject({ status: 'trialing', readOnly: false, plan: { code: 'crece', priceCents: 14900 }, usage: { branches: 1, members: 1, products: 0 } });
    s.trialEnd = new Date(res.body.trialEndsAt).getTime();
    expect(s.trialEnd - Date.now()).toBeGreaterThan(days(13.9));
    expect((await api(app, s.owner).get('/billing/plans')).body.map((p: any) => p.code)).toEqual(['emprende', 'crece', 'pro']);
  });

  it('aplica los límites del plan y no deja bajar si el uso no cabe', async () => {
    expect((await api(app, s.owner).post('/billing/plan', { planCode: 'emprende' })).status).toBe(200);
    const blocked = await api(app, s.owner).post('/branches', { name: 'Sucursal 2' });
    expect(blocked.status).toBe(402);
    expect(blocked.body).toMatchObject({ code: 'PLAN_LIMIT', resource: 'branches', limit: 1, current: 1 });

    await api(app, s.owner).post('/billing/plan', { planCode: 'crece' });
    expect((await api(app, s.owner).post('/branches', { name: 'Sucursal 2' })).status).toBe(201);
    const down = await api(app, s.owner).post('/billing/plan', { planCode: 'emprende' });
    expect(down.status).toBe(409);
    expect(down.body.exceeded).toEqual(['branches']);
  });

  it('el backoffice es solo para superadmins', async () => {
    expect((await api(app, s.owner).get('/admin/metrics')).status).toBe(403);
    const m = await api(app, s.admin).get('/admin/metrics');
    expect(m.body).toMatchObject({ tenants: 2, trialing: 2, mrr_cents: 0 });
    const list = await api(app, s.admin).get('/admin/tenants');
    expect(list.body.find((t: any) => t.name === 'Boutique Alma')).toMatchObject({ plan_code: 'crece', subscription_status: 'trialing' });
  });

  it('al terminar la prueba: factura abierta y periodo de gracia (todo sigue funcionando)', async () => {
    const r = await run(s.trialEnd + hours(1));
    expect(r.body).toMatchObject({ invoiced: 2, pastDue: 2 });
    // Correrlo otra vez no duplica facturas.
    expect((await run(s.trialEnd + hours(2))).body.invoiced).toBe(0);

    const b = await api(app, s.owner).get('/billing');
    expect(b.body).toMatchObject({ status: 'past_due', readOnly: false });
    expect(b.body.openInvoices).toHaveLength(1);
    expect(b.body.openInvoices[0]).toMatchObject({ amountCents: 14900, currency: 'PEN' });
    s.invoice = b.body.openInvoices[0];
    expect((await api(app, s.owner).post('/categories', { name: 'En gracia' })).status).toBe(201);
  });

  it('pasada la gracia: bloqueo suave (se puede ver y pagar, no operar)', async () => {
    expect((await run(s.trialEnd + days(8))).body.suspended).toBe(2);
    const write = await api(app, s.owner).post('/categories', { name: 'Bloqueada' });
    expect(write.status).toBe(402);
    expect(write.body.code).toBe('SUBSCRIPTION_SUSPENDED');
    expect((await api(app, s.owner).get('/products')).status).toBe(200);
    expect((await api(app, s.owner).get('/billing')).body.readOnly).toBe(true);

    const checkout = await api(app, s.owner).post(`/billing/invoices/${s.invoice.id}/pay`, { provider: 'fake', method: 'yape' });
    expect(checkout.status).toBe(200);
    s.ref = checkout.body.providerRef;
  });

  it('webhook firmado: acredita el pago una sola vez y reactiva la tienda', async () => {
    expect((await webhook({ id: 'evt_1', type: 'paid', ref: s.ref }, 'otra-clave')).status).toBe(401);
    expect((await webhook({ id: 'evt_1', type: 'paid', ref: s.ref })).body).toEqual({ paid: s.invoice.id });
    expect((await webhook({ id: 'evt_1', type: 'paid', ref: s.ref })).body).toEqual({ duplicate: true });

    const b = await api(app, s.owner).get('/billing');
    expect(b.body).toMatchObject({ status: 'active', openInvoices: [] });
    expect(new Date(b.body.currentPeriodEnd).getTime()).toBe(addMonths(new Date(s.trialEnd), 1).getTime());
    s.periodEnd = new Date(b.body.currentPeriodEnd).getTime();
    expect((await api(app, s.owner).post('/categories', { name: 'Reactivada' })).status).toBe(201);
    expect((await api(app, s.admin).get('/admin/metrics')).body.mrr_cents).toBe(14900);
  });

  it('con tarjeta guardada se renueva solo; si la rechazan, entra en gracia', async () => {
    expect((await api(app, s.owner).post('/billing/card', { token: 'card_ok', phone: '987654321' })).body).toEqual({ autopay: true });
    const ok = await run(s.periodEnd + hours(1));
    expect(ok.body).toMatchObject({ charged: 1 });
    const b1 = await api(app, s.owner).get('/billing');
    expect(b1.body.status).toBe('active');
    const next = new Date(b1.body.currentPeriodEnd).getTime();
    expect(next).toBe(addMonths(new Date(s.periodEnd), 1).getTime());

    await api(app, s.owner).post('/billing/card', { token: 'card_fail', phone: '987654321' });
    const fail = await run(next + hours(1));
    expect(fail.body).toMatchObject({ chargeFailed: 1 });
    expect((await api(app, s.owner).get('/billing')).body.status).toBe('past_due');
  });

  it('pago manual verificado por el superadmin (Plin / transferencia)', async () => {
    const inv = (await api(app, s.owner).get('/billing')).body.openInvoices[0];
    expect((await api(app, s.owner).post(`/admin/invoices/${inv.id}/mark-paid`, { method: 'plin', reference: 'OP 123456' })).status).toBe(403);
    expect((await api(app, s.admin).post(`/admin/invoices/${inv.id}/mark-paid`, { method: 'plin', reference: 'OP 123456' })).status).toBe(200);
    const b = await api(app, s.owner).get('/billing');
    expect(b.body.status).toBe('active');
    expect(b.body.history[0]).toMatchObject({ status: 'paid', provider: 'manual', method: 'plin' });
  });

  it('registrar tarjeta desde el navegador con enlace firmado (sin sesión)', async () => {
    const link = await api(app, s.owner).post('/billing/card/setup-link');
    expect(link.status).toBe(200);
    const t = new URL(link.body.url).searchParams.get('t')!;

    const page = await request(app.getHttpServer()).get(`/v1/billing/card-setup?t=${t}`);
    expect(page.status).toBe(200);
    expect(page.headers['content-security-policy']).toContain('js.culqi.com');
    expect(page.text).toContain('Cobro automático');

    const tampered = t.slice(0, -2) + (t.endsWith('A') ? 'BB' : 'AA');
    expect((await request(app.getHttpServer()).post('/v1/billing/card-setup').send({ t: tampered, token: 'card_ok', phone: '987654321' })).status).toBe(401);
    const ok = await request(app.getHttpServer()).post('/v1/billing/card-setup').send({ t, token: 'card_ok', phone: '987654321' });
    expect(ok.body).toEqual({ autopay: true });
    expect((await api(app, s.owner).get('/billing')).body.autopay).toBe(true);
  });

  it('el superadmin ve facturas por tienda y /auth/me lo identifica', async () => {
    expect((await api(app, s.admin).get('/auth/me')).body.isPlatformAdmin).toBe(true);
    expect((await api(app, s.owner).get('/auth/me')).body.isPlatformAdmin).toBe(false);
    const tenantId = (await api(app, s.owner).get('/auth/me')).body.tenantId;
    const inv = await api(app, s.admin).get(`/admin/tenants/${tenantId}/invoices`);
    expect(inv.body.length).toBeGreaterThanOrEqual(3);
  });

  it('cancelar al final del periodo deja la tienda en solo lectura', async () => {
    await api(app, s.owner).post('/billing/cancel');
    const b = await api(app, s.owner).get('/billing');
    expect(b.body.cancelAtPeriodEnd).toBe(true);
    await run(new Date(b.body.currentPeriodEnd).getTime() + hours(1));
    expect((await api(app, s.owner).get('/billing')).body.status).toBe('canceled');
    expect((await api(app, s.owner).post('/categories', { name: 'X' })).status).toBe(402);
  });
});

describe('Enlace firmado de la página de pago', () => {
  it('rechaza enlaces vencidos o alterados', async () => {
    const { BillingService } = await import('../src/modules/billing/billing.service');
    const svc = Object.create(BillingService.prototype) as InstanceType<typeof BillingService>;
    (svc as any).env = { JWT_ACCESS_SECRET: 'x'.repeat(40) };
    const t = svc.signPayLink('inv-1');
    expect(svc.verifyPayLink('inv-1', t)).toBe(true);
    expect(svc.verifyPayLink('inv-2', t)).toBe(false);
    expect(svc.verifyPayLink('inv-1', t, Date.now() + 2 * 3_600_000)).toBe(false);
    expect(svc.verifyPayLink('inv-1', 'basura')).toBe(false);
  });
});

describe('Utilidades de facturación', () => {
  it('addMonths respeta el fin de mes', () => {
    expect(addMonths(new Date('2027-01-31T10:00:00Z'), 1).toISOString()).toBe('2027-02-28T10:00:00.000Z');
    expect(addMonths(new Date('2028-01-31T10:00:00Z'), 1).toISOString()).toBe('2028-02-29T10:00:00.000Z');
    expect(addMonths(new Date('2026-10-25T10:00:00Z'), 1).toISOString()).toBe('2026-11-25T10:00:00.000Z');
  });

  it('verifica la firma de Stripe (cuerpo, secreto y antigüedad)', () => {
    const body = Buffer.from('{"id":"evt_1"}');
    const t = Math.floor(Date.now() / 1000);
    const sig = createHmac('sha256', 'whsec_x').update(`${t}.${body}`).digest('hex');
    expect(verifyStripeSignature(body, `t=${t},v1=${sig}`, 'whsec_x')).toBe(true);
    expect(verifyStripeSignature(Buffer.from('{"id":"evt_2"}'), `t=${t},v1=${sig}`, 'whsec_x')).toBe(false);
    expect(verifyStripeSignature(body, `t=${t},v1=${sig}`, 'otra')).toBe(false);
    expect(verifyStripeSignature(body, `t=${t},v1=${sig}`, 'whsec_x', Date.now() + 600_000)).toBe(false);
  });
});
