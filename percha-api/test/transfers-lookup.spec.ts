import { INestApplication } from '@nestjs/common';
import { execSync } from 'node:child_process';
import { FakeIdentityProvider } from '../src/modules/lookup/providers';
import { api, createApp, resetDatabase, urls } from './helpers';

describe('Transferencias entre sucursales y consulta RUC/DNI', () => {
  let app: INestApplication;
  const s: Record<string, any> = {};
  const stock = async (branchId: string, variantId: string) =>
    (await api(app, s.owner).get(`/inventory/stock?branchId=${branchId}&variantId=${variantId}`)).body[0]?.quantity ?? 0;

  beforeAll(async () => {
    await resetDatabase();
    app = await createApp();
    const reg = await api(app).post('/auth/register', { storeName: 'Alma', ownerName: 'Joao', email: 'j@alma.pe', password: 'clave-segura-1' });
    s.owner = reg.body.accessToken;
    const o = api(app, s.owner);
    s.main = (await o.get('/branches')).body[0].id;
    s.mall = (await o.post('/branches', { name: 'Jockey Plaza' })).body.id;
    await o.post('/attributes', { name: 'Talla', values: ['S', 'M'] });
    const p = await o.post('/products', {
      name: 'Vestido midi',
      priceCents: 18990,
      costCents: 8000,
      matrix: { Talla: ['S', 'M'] },
      initialStock: { branchId: s.main, items: [{ options: { Talla: 'S' }, quantity: 5 }, { options: { Talla: 'M' }, quantity: 3 }] },
    });
    s.S = p.body.variants.find((v: any) => v.options.Talla === 'S').id;
    s.M = p.body.variants.find((v: any) => v.options.Talla === 'M').id;

    // Almacenero fijo en la sucursal del mall.
    const inv = await o.post('/team/invitations', { email: 'ana@alma.pe', role: 'stock', branchId: s.mall });
    s.mallStock = (await api(app).post('/auth/invitations/accept', { token: inv.body.token, name: 'Ana', password: 'almacen-123' })).body.accessToken;
  });
  afterAll(async () => app?.close());

  describe('Transferencias', () => {
    it('enviar: sale del origen y queda en tránsito (no está en ninguna sucursal)', async () => {
      const res = await api(app, s.owner).post('/transfers', {
        fromBranchId: s.main,
        toBranchId: s.mall,
        items: [{ variantId: s.S, quantity: 3 }, { variantId: s.M, quantity: 2 }],
        notes: 'Reposición fin de semana',
      });
      expect(res.status).toBe(201);
      expect(res.body).toMatchObject({ number: 1, status: 'in_transit' });
      s.t1 = res.body;
      expect(await stock(s.main, s.S)).toBe(2);
      expect(await stock(s.mall, s.S)).toBe(0);
    });

    it('sin stock suficiente no se envía nada', async () => {
      const res = await api(app, s.owner).post('/transfers', {
        fromBranchId: s.main,
        toBranchId: s.mall,
        items: [{ variantId: s.S, quantity: 1 }, { variantId: s.M, quantity: 9 }],
      });
      expect(res.status).toBe(422);
      expect(await stock(s.main, s.S)).toBe(2);
    });

    it('el destino recibe lo que llegó; el faltante queda registrado', async () => {
      const itemM = s.t1.items.find((i: any) => i.variantId === s.M);
      // El almacenero del mall recibe; no podría recibir algo destinado a otra sucursal.
      const res = await api(app, s.mallStock).post(`/transfers/${s.t1.id}/receive`, {
        items: [{ itemId: itemM.id, quantity: 1 }],
        notes: 'Llegó una M menos',
      });
      expect(res.status).toBe(200);
      expect(res.body.status).toBe('received');
      expect(res.body.items.find((i: any) => i.variantId === s.M)).toMatchObject({ quantitySent: 2, quantityReceived: 1, missing: 1 });
      expect(await stock(s.mall, s.S)).toBe(3);
      expect(await stock(s.mall, s.M)).toBe(1);
      expect((await api(app, s.owner).post(`/transfers/${s.t1.id}/receive`, {})).status).toBe(409);
    });

    it('permisos por sucursal: el almacenero del mall no envía desde la principal', async () => {
      const res = await api(app, s.mallStock).post('/transfers', { fromBranchId: s.main, toBranchId: s.mall, items: [{ variantId: s.S, quantity: 1 }] });
      expect(res.status).toBe(403);
      const list = await api(app, s.mallStock).get('/transfers');
      expect(list.body.map((t: any) => t.id)).toContain(s.t1.id); // ve lo que le llegó
    });

    it('cancelar en tránsito devuelve el stock al origen', async () => {
      const t = await api(app, s.owner).post('/transfers', { fromBranchId: s.main, toBranchId: s.mall, items: [{ variantId: s.S, quantity: 2 }] });
      expect(await stock(s.main, s.S)).toBe(0);
      const c = await api(app, s.owner).post(`/transfers/${t.body.id}/cancel`);
      expect(c.body.status).toBe('cancelled');
      expect(await stock(s.main, s.S)).toBe(2);
      const kardex = await api(app, s.owner).get(`/inventory/movements?variantId=${s.S}&branchId=${s.main}`);
      expect(kardex.body.slice(0, 2).map((m: any) => m.type)).toEqual(['transfer_in', 'transfer_out']);
    });
  });

  describe('Consulta RUC y DNI', () => {
    it('valida el formato antes de consultar (no gasta consultas)', async () => {
      const before = FakeIdentityProvider.calls;
      expect((await api(app, s.owner).get('/lookup/ruc/20131312956')).body.code).toBe('INVALID_RUC');
      expect((await api(app, s.owner).get('/lookup/dni/1234')).body.code).toBe('INVALID_DNI');
      expect(FakeIdentityProvider.calls).toBe(before);
    });

    it('RUC: razón social y dirección; la segunda consulta sale de la caché', async () => {
      const before = FakeIdentityProvider.calls;
      const a = await api(app, s.owner).get('/lookup/ruc/20131312955');
      expect(a.body).toMatchObject({ ruc: '20131312955', status: 'ACTIVO', condition: 'HABIDO', warnings: [] });
      expect(a.body.name).toContain('SUNAT');
      await api(app, s.mallStock).get('/lookup/ruc/20131312955');
      expect(FakeIdentityProvider.calls).toBe(before + 1);
    });

    it('advierte si el contribuyente no está habido', async () => {
      const res = await api(app, s.owner).get('/lookup/ruc/20100070970');
      expect(res.body.warnings).toEqual(['Contribuyente NO HABIDO']);
    });

    it('padrón SUNAT (gratuito): se importa del archivo oficial y se consulta sin servicios externos', async () => {
      const out = execSync('node scripts/import-padron.mjs test/fixtures/padron_sample.txt', {
        env: { ...process.env, DATABASE_OWNER_URL: urls.owner },
      }).toString();
      expect(out).toContain('Padrón cargado: 2 RUC');

      const before = FakeIdentityProvider.calls;
      const a = await api(app, s.owner).get('/lookup/ruc/20601234565');
      // Latin-1 bien decodificado y dirección armada desde las columnas del padrón.
      expect(a.body).toMatchObject({ name: 'BOUTIQUE ESPAÑA S.A.C.', status: 'ACTIVO', condition: 'HABIDO', address: 'AV. LARCO NRO. 345 URB.', warnings: [] });
      const b = await api(app, s.owner).get('/lookup/ruc/20555555556');
      expect(b.body.warnings).toEqual(['RUC en estado BAJA DE OFICIO', 'Contribuyente NO HABIDO']);
      expect(FakeIdentityProvider.calls).toBe(before); // no se llamó a ningún servicio externo

      // Volver a importar reemplaza el padrón (no duplica).
      execSync('node scripts/import-padron.mjs test/fixtures/padron_sample.txt --only-active', { env: { ...process.env, DATABASE_OWNER_URL: urls.owner } });
      expect((await api(app, s.owner).get('/lookup/ruc/20555555556')).status).toBe(404);
    });

    it('DNI: nombre completo; inexistente responde 404', async () => {
      expect((await api(app, s.owner).get('/lookup/dni/45678912')).body).toEqual({ dni: '45678912', name: 'LUCIA RAMOS TORRES' });
      expect((await api(app, s.owner).get('/lookup/dni/11111111')).status).toBe(404);
    });
  });
});
