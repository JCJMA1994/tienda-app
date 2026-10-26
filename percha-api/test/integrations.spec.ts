import { INestApplication } from '@nestjs/common';
import { base32Encode, totpAt, verifyTotp } from '../src/modules/auth/totp';
import { EmailService } from '../src/modules/email/email.service';
import { ApachiyCpeValidator } from '../src/modules/lookup/cpe';
import { ApachiyIdentityProvider } from '../src/modules/lookup/providers';
import { FakeWhatsApp } from '../src/modules/messaging/whatsapp';
import { api, createApp, resetDatabase } from './helpers';

describe('TOTP (RFC 6238)', () => {
  it('coincide con el vector oficial y tolera ±30 s', () => {
    const secret = base32Encode(Buffer.from('12345678901234567890'));
    expect(secret).toBe('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
    expect(totpAt(secret, 59_000)).toBe('287082'); // RFC 6238: 94287082 (8 dígitos)
    expect(totpAt(secret, 1_111_111_109_000)).toBe('081804'); // RFC: 07081804
    expect(verifyTotp(secret, totpAt(secret, 1_000_000_000_000 - 30_000), 1_000_000_000_000)).toBe(true);
    expect(verifyTotp(secret, totpAt(secret, 1_000_000_000_000 - 90_000), 1_000_000_000_000)).toBe(false);
  });
});

describe('Apachiy: mapeo de respuestas documentadas', () => {
  const client = (data: unknown) => ({ get: async () => ({ data, status: 200 }), post: async () => ({ data, status: 200, requestId: 'req-1' }) }) as never;

  it('DNI y RUC', async () => {
    const dni = await new ApachiyIdentityProvider(client({ documento: '45678912', nombres: 'LUCIA', apellido_paterno: 'RAMOS', apellido_materno: 'TORRES', nombre_o_razon_social: 'RAMOS TORRES LUCIA' })).dni('45678912');
    expect(dni).toEqual({ dni: '45678912', name: 'RAMOS TORRES LUCIA' });
    const ruc = await new ApachiyIdentityProvider(
      client({ nombre_o_razon_social: 'EMPRESA SAC', direccion: 'AV. LARCO 123', ubigeo: { distrito: 'MIRAFLORES', provincia: 'LIMA', departamento: 'LIMA' }, estado_contribuyente: '00', condicion_domicilio: 'HABIDO' }),
    ).ruc('20131312955');
    // El estado viene como código: no se usa para no mostrar advertencias falsas.
    expect(ruc).toEqual({ ruc: '20131312955', name: 'EMPRESA SAC', address: 'AV. LARCO 123, MIRAFLORES, LIMA, LIMA', status: null, condition: 'HABIDO' });
  });

  it('validez de comprobante', async () => {
    const ok = await new ApachiyCpeValidator(client({ comprobante: { estado: 'ACEPTADO' }, contribuyente: { estado_ruc: 'ACTIVO', condicion_domicilio: 'HABIDO' }, observaciones: [] })).validate({ ruc: '20131312955', type: '01', serie: 'F001', numero: 1, date: '2026-10-20' });
    expect(ok).toMatchObject({ verdict: 'valid', status: 'ACEPTADO', requestId: 'req-1' });
    const bad = await new ApachiyCpeValidator(client({ comprobante: { estado: 'NO AUTORIZADO' } })).validate({ ruc: '20131312955', type: '01', serie: 'F001', numero: 1, date: '2026-10-20' });
    expect(bad.verdict).toBe('invalid');
  });
});

describe('Integraciones y pendientes de seguridad', () => {
  let app: INestApplication;
  const s: Record<string, any> = {};

  beforeAll(async () => {
    await resetDatabase();
    app = await createApp();
    const reg = await api(app).post('/auth/register', { storeName: 'Boutique Alma', ownerName: 'Joao', email: 'j@alma.pe', password: 'clave-segura-1' });
    s.owner = reg.body.accessToken;
    s.refresh = reg.body.refreshToken;
    const o = api(app, s.owner);
    s.branch = (await o.get('/branches')).body[0].id;
    const p = await o.post('/products', { name: 'Vestido midi', priceCents: 18990, costCents: 8000, initialStock: { branchId: s.branch, items: [{ options: {}, quantity: 10 }] } });
    s.variant = p.body.variants[0].id;
    await o.post('/cash-sessions', { branchId: s.branch, openingCents: 0 });
  });
  afterAll(async () => app?.close());

  describe('Recuperar contraseña por correo', () => {
    it('no revela si el correo existe', async () => {
      const before = EmailService.outbox.length;
      expect((await api(app).post('/auth/password/forgot', { email: 'nadie@x.pe' })).status).toBe(202);
      expect(EmailService.outbox.length).toBe(before);
    });

    it('enlace de un solo uso que cierra todas las sesiones', async () => {
      await api(app).post('/auth/password/forgot', { email: 'J@alma.pe' });
      const mail = EmailService.outbox.at(-1)!;
      expect(mail.to).toBe('j@alma.pe');
      const token = /reset\?token=([\w-]+)/.exec(mail.text)![1];

      expect((await api(app).post('/auth/password/reset', { token, newPassword: 'sinnumeros' })).status).toBe(400);
      expect((await api(app).post('/auth/password/reset', { token, newPassword: 'nueva-clave-9' })).status).toBe(200);
      expect((await api(app).post('/auth/password/reset', { token, newPassword: 'otra-clave-9' })).status).toBe(401);
      expect((await api(app).post('/auth/refresh', { refreshToken: s.refresh })).status).toBe(401);

      const login = await api(app).post('/auth/login', { email: 'j@alma.pe', password: 'nueva-clave-9' });
      expect(login.status).toBe(200);
      s.owner = login.body.accessToken;
    });
  });

  describe('Verificación en dos pasos', () => {
    it('activar: secreto + código correcto → 10 códigos de recuperación', async () => {
      const setup = await api(app, s.owner).post('/auth/2fa/setup');
      expect(setup.body.otpauthUri).toContain('otpauth://totp/Percha');
      s.secret = setup.body.secret;
      expect((await api(app, s.owner).post('/auth/2fa/enable', { code: '000000' })).status).toBe(401);
      const on = await api(app, s.owner).post('/auth/2fa/enable', { code: totpAt(s.secret, Date.now()) });
      expect(on.body.recoveryCodes).toHaveLength(10);
      s.recovery = on.body.recoveryCodes;
      expect((await api(app, s.owner).get('/auth/me')).body.twoFactorEnabled).toBe(true);
    });

    it('con 2FA, la contraseña sola no da sesión; el desafío no sirve como token', async () => {
      const login = await api(app).post('/auth/login', { email: 'j@alma.pe', password: 'nueva-clave-9' });
      expect(login.body.requiresTwoFactor).toBe(true);
      expect(login.body.accessToken).toBeUndefined();
      expect((await api(app, login.body.challenge).get('/auth/me')).status).toBe(401);

      expect((await api(app).post('/auth/2fa/verify', { challenge: login.body.challenge, code: '123456' })).status).toBe(401);
      const ok = await api(app).post('/auth/2fa/verify', { challenge: login.body.challenge, code: totpAt(s.secret, Date.now()) });
      expect(ok.body.accessToken).toBeDefined();
      s.owner = ok.body.accessToken;
    });

    it('código de recuperación: funciona una sola vez', async () => {
      const c1 = (await api(app).post('/auth/login', { email: 'j@alma.pe', password: 'nueva-clave-9' })).body.challenge;
      expect((await api(app).post('/auth/2fa/verify', { challenge: c1, recoveryCode: s.recovery[0] })).body.accessToken).toBeDefined();
      const c2 = (await api(app).post('/auth/login', { email: 'j@alma.pe', password: 'nueva-clave-9' })).body.challenge;
      expect((await api(app).post('/auth/2fa/verify', { challenge: c2, recoveryCode: s.recovery[0] })).status).toBe(401);
    });

    it('desactivar exige contraseña y código', async () => {
      expect((await api(app, s.owner).post('/auth/2fa/disable', { password: 'nueva-clave-9' })).status).toBe(401);
      expect((await api(app, s.owner).post('/auth/2fa/disable', { password: 'nueva-clave-9', code: totpAt(s.secret, Date.now()) })).body).toEqual({ enabled: false });
    });
  });

  describe('Factura del proveedor validada en SUNAT al recibir', () => {
    it('rechaza una factura anulada y registra la válida', async () => {
      const o = api(app, s.owner);
      const noRuc = await o.post('/suppliers', { name: 'Sin RUC' });
      const sup = await o.post('/suppliers', { name: 'Textiles SUNAT', ruc: '20131312955' });
      const mk = async (supplierId: string) => {
        const po = await o.post('/purchase-orders', { supplierId, branchId: s.branch, items: [{ variantId: s.variant, quantity: 2, unitCostCents: 9000 }] });
        await o.post(`/purchase-orders/${po.body.id}/confirm`);
        return po.body;
      };
      const po1 = await mk(noRuc.body.id);
      const invoice = { serie: 'F001', numero: 1, date: '2026-10-20', totalCents: 18000 };
      expect((await o.post(`/purchase-orders/${po1.id}/receipts`, { items: [{ purchaseOrderItemId: po1.items[0].id, quantity: 2 }], supplierInvoice: invoice })).body.code).toBe('SUPPLIER_RUC_MISSING');

      const po2 = await mk(sup.body.id);
      const anulada = await o.post(`/purchase-orders/${po2.id}/receipts`, { items: [{ purchaseOrderItemId: po2.items[0].id, quantity: 2 }], supplierInvoice: { ...invoice, numero: 999 } });
      expect(anulada.status).toBe(422);
      expect(anulada.body).toMatchObject({ code: 'SUPPLIER_INVOICE_INVALID', status: 'ANULADO' });

      const ok = await o.post(`/purchase-orders/${po2.id}/receipts`, { items: [{ purchaseOrderItemId: po2.items[0].id, quantity: 2 }], supplierInvoice: invoice });
      expect(ok.status).toBe(201);
      expect(ok.body.receipt).toMatchObject({ supplierInvoiceSerie: 'F001', supplierInvoiceNumber: 1, supplierInvoiceStatus: 'valid' });

      const direct = await o.post('/lookup/cpe', { ruc: '20131312955', type: '01', serie: 'f001', numero: 1, date: '2026-10-20' });
      expect(direct.body).toMatchObject({ verdict: 'valid', status: 'ACEPTADO' });
    });
  });

  describe('Comprobante por WhatsApp', () => {
    it('configuración: token cifrado y nunca devuelto', async () => {
      const r = await api(app, s.owner).put('/messaging/settings', { enabled: true, provider: 'fake', instance: '51987654321', token: 'myt_live_secreto_123' });
      expect(r.body).toEqual({ enabled: true, instance: '51987654321', hasToken: true });
      expect(JSON.stringify((await api(app, s.owner).get('/messaging/settings')).body)).not.toContain('secreto');
      expect((await api(app, s.owner).get('/messaging/status')).body).toEqual({ whatsapp: true });
    });

    it('envía el resumen, evita duplicados y respeta el "sin confirmación"', async () => {
      const sale = await api(app, s.owner).post('/sales', { branchId: s.branch, items: [{ variantId: s.variant, quantity: 1 }], payments: [{ method: 'cash', amountCents: 18990 }] });
      const send = (phone: string, force = false) => api(app, s.owner).post(`/sales/${sale.body.id}/whatsapp`, { phone, force });

      const ok = await send('987654321');
      expect(ok.body).toMatchObject({ status: 'sent', to: '51•••••321' });
      expect(FakeWhatsApp.sent.at(-1)).toMatchObject({ to: '51987654321', kind: 'text' });
      expect(FakeWhatsApp.sent.at(-1)!.text).toContain('Boutique Alma');
      expect(FakeWhatsApp.sent.at(-1)!.text).toContain('S/ 189.90');

      expect((await send('987654321')).body.code).toBe('ALREADY_SENT');
      expect((await send('987654321', true)).body.status).toBe('sent');

      const uncertain = await send('+51900000502');
      expect(uncertain.body.status).toBe('uncertain');
      expect((await send('+51900000502')).body.message).toContain('revisa el chat');
    });
  });
});
