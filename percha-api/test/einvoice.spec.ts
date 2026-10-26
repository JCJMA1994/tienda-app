import { INestApplication } from '@nestjs/common';
import { Client } from 'pg';
import { buildItems, isValidRuc, normalizeCustomer, totalsOf } from '../src/modules/einvoice/document';
import { FakeOse } from '../src/modules/einvoice/providers/fake.provider';
import { open, seal } from '../src/common/crypto';
import { api, createApp, resetDatabase } from './helpers';

const RUC_OK = '20131312955';

describe('Facturación electrónica SUNAT', () => {
  let app: INestApplication;
  const s: Record<string, any> = {};
  const sell = (body: object) => api(app, s.owner).post('/sales', { branchId: s.branch, ...body });
  const pay = (cents: number) => [{ method: 'cash', amountCents: cents }];

  beforeAll(async () => {
    await resetDatabase();
    app = await createApp();
    const reg = await api(app).post('/auth/register', { storeName: 'Alma', ownerName: 'Joao', email: 'j@alma.pe', password: 'clave-segura-1' });
    s.owner = reg.body.accessToken;
    const o = api(app, s.owner);
    s.branch = (await o.get('/branches')).body[0].id;
    const vestido = await o.post('/products', { name: 'Vestido midi', priceCents: 18990, initialStock: { branchId: s.branch, items: [{ options: {}, quantity: 50 }] } });
    s.vestido = vestido.body.variants[0].id;
    const abrigo = await o.post('/products', { name: 'Abrigo de lana', priceCents: 80000, initialStock: { branchId: s.branch, items: [{ options: {}, quantity: 5 }] } });
    s.abrigo = abrigo.body.variants[0].id;
    await o.put(`/team/members/${(await o.get('/auth/me')).body.membershipId}/pin`, { pin: '4321' });
    await o.post('/cash-sessions', { branchId: s.branch, openingCents: 0 });
  });
  afterAll(async () => app?.close());

  it('sin activar: las ventas no emiten comprobante y pedir uno da error', async () => {
    const plain = await sell({ items: [{ variantId: s.vestido, quantity: 1 }], payments: pay(18990) });
    expect(plain.body.documents).toEqual([]);
    const withDoc = await sell({ items: [{ variantId: s.vestido, quantity: 1 }], payments: pay(18990), document: { type: 'boleta' } });
    expect(withDoc.status).toBe(400);
  });

  it('configura el OSE: el token se guarda cifrado y nunca se devuelve', async () => {
    const base = {
      enabled: true,
      provider: 'fake',
      legalName: 'ALMA BOUTIQUE S.A.C.',
      fiscalAddress: 'Av. Larco 123, Miraflores, Lima',
      apiUrl: 'https://ose.example/api',
      series: [{ branchId: s.branch, boleta: 'B001', factura: 'F001', ncBoleta: 'BC01', ncFactura: 'FC01' }],
    };
    expect((await api(app, s.owner).put('/einvoice/settings', base)).status).toBe(400); // falta token
    expect((await api(app, s.owner).put('/einvoice/settings', { ...base, token: 'tok_secreto_123456' })).status).toBe(200);

    expect((await api(app, s.owner).get('/einvoice/status')).body).toEqual({ enabled: true, boletaAnonLimitCents: 70000 });
    const got = await api(app, s.owner).get('/einvoice/settings');
    expect(got.body).toMatchObject({ enabled: true, hasToken: true, series: [{ boleta: 'B001', ncFactura: 'FC01' }] });
    expect(JSON.stringify(got.body)).not.toContain('tok_secreto');

    const db = new Client({ connectionString: (process.env.TEST_ADMIN_URL ?? 'postgres://postgres:postgres@localhost:5432/postgres').replace(/\/postgres$/, '/percha_test') });
    await db.connect();
    const { rows } = await db.query('select token_enc from einvoice_settings');
    await db.end();
    expect(rows[0].token_enc).not.toContain('tok_secreto');
  });

  it('boleta por defecto: numerada, enviada y aceptada, con IGV por línea', async () => {
    const res = await sell({ items: [{ variantId: s.vestido, quantity: 1 }], payments: pay(18990) });
    expect(res.status).toBe(201);
    expect(res.body.documents[0]).toMatchObject({ kind: 'boleta', serie: 'B001', numero: 1, status: 'accepted', customerName: 'CLIENTES VARIOS' });
    expect(res.body.documents[0].pdfUrl).toContain('B001-1');
    const sent = FakeOse.received.at(-1)!;
    expect(sent.totals).toEqual({ gravadaCents: 16093, exoneradaCents: 0, igvCents: 2897, totalCents: 18990 });
    expect(sent.items[0].description).toBe('Vestido midi');
    s.boletaSale = res.body;
  });

  it('boleta mayor a S/ 700: exige identificar al cliente y no consume números si falla', async () => {
    const anon = await sell({ items: [{ variantId: s.abrigo, quantity: 1 }], payments: pay(80000) });
    expect(anon.status).toBe(400);
    expect(anon.body.code).toBe('DOCUMENT_CUSTOMER_REQUIRED');
    const ok = await sell({
      items: [{ variantId: s.abrigo, quantity: 1 }],
      payments: pay(80000),
      document: { type: 'boleta', customer: { docType: 'dni', docNumber: '45678912', name: 'Lucía Ramos' } },
    });
    expect(ok.body.documents[0]).toMatchObject({ serie: 'B001', numero: 2, customerDocNumber: '45678912' });
  });

  it('factura: exige RUC válido (dígito verificador) y razón social', async () => {
    const bad = await sell({ items: [{ variantId: s.vestido, quantity: 1 }], payments: pay(18990), document: { type: 'factura', customer: { docType: 'ruc', docNumber: '20131312956', name: 'X SAC' } } });
    expect(bad.body.code).toBe('INVALID_RUC');
    const ok = await sell({
      items: [{ variantId: s.vestido, quantity: 2 }],
      payments: pay(37980),
      document: { type: 'factura', customer: { docType: 'ruc', docNumber: RUC_OK, name: 'Empresa Cliente S.A.C.', address: 'Lima' } },
    });
    expect(ok.body.documents[0]).toMatchObject({ kind: 'factura', serie: 'F001', numero: 1, status: 'accepted' });
    s.facturaSale = ok.body;
  });

  it('anular una venta emite nota de crédito motivo 01 que referencia la boleta', async () => {
    const res = await api(app, s.owner).post(`/sales/${s.boletaSale.id}/void`, { reason: 'Cobro duplicado' });
    expect(res.status).toBe(200);
    const nc = res.body.documents.find((d: any) => d.kind === 'nota_credito');
    expect(nc).toMatchObject({ serie: 'BC01', numero: 1, status: 'accepted', totalCents: 18990 });
    expect(FakeOse.received.at(-1)!.reference).toEqual({ kind: 'boleta', serie: 'B001', numero: 1, reasonCode: '01', reasonText: 'Cobro duplicado' });
  });

  it('devolución sobre factura: nota de crédito motivo 07 por lo devuelto', async () => {
    const res = await api(app, s.owner).post(`/sales/${s.facturaSale.id}/returns`, {
      branchId: s.branch,
      items: [{ saleItemId: s.facturaSale.items[0].id, quantity: 1 }],
      payments: [{ method: 'cash', amountCents: 18990 }],
      reason: 'Fallado',
    });
    expect(res.status).toBe(201);
    const sent = FakeOse.received.at(-1)!;
    expect(sent).toMatchObject({ kind: 'nota_credito', serie: 'FC01', numero: 1, reference: { serie: 'F001', numero: 1, reasonCode: '07' } });
    expect(sent.totals.totalCents).toBe(18990);
    expect(sent.customer.docNumber).toBe(RUC_OK);
  });

  it('OSE caído: la venta se completa igual y el comprobante se reenvía después', async () => {
    FakeOse.down = true;
    const res = await sell({ items: [{ variantId: s.vestido, quantity: 1 }], payments: pay(18990) });
    FakeOse.down = false;
    expect(res.status).toBe(201);
    const doc = res.body.documents[0];
    expect(doc).toMatchObject({ status: 'error', numero: 3 });
    expect(doc.lastError).toContain('caído');

    const retry = await api(app, s.owner).post(`/einvoices/${doc.id}/retry`);
    expect(retry.body).toMatchObject({ status: 'accepted', lastError: null });
  });

  it('comprobante rechazado: no se le emite nota de crédito al anular', async () => {
    const res = await sell({
      items: [{ variantId: s.vestido, quantity: 1 }],
      payments: pay(18990),
      document: { type: 'factura', customer: { docType: 'ruc', docNumber: RUC_OK, name: 'RECHAZO SAC' } },
    });
    expect(res.body.documents[0].status).toBe('rejected');
    const v = await api(app, s.owner).post(`/sales/${res.body.id}/void`, { reason: 'Datos errados' });
    expect(v.body.documents).toHaveLength(1);
  });

  it('ventas simultáneas reciben correlativos distintos y seguidos', async () => {
    const body = { items: [{ variantId: s.vestido, quantity: 1 }], payments: pay(18990) };
    const [a, b] = await Promise.all([sell(body), sell(body)]);
    expect([a.body.documents[0].numero, b.body.documents[0].numero].sort()).toEqual([4, 5]);
    const list = await api(app, s.owner).get('/einvoices?status=accepted');
    expect(list.body.length).toBeGreaterThanOrEqual(7);
  });
});

describe('Documento y utilidades', () => {
  it('IGV por línea: precios con IGV, sin IGV y exonerados', () => {
    expect(buildItems([{ code: 'A', description: 'A', quantity: 2, amountCents: 37980 }], 1800, true)[0]).toMatchObject({ subtotalCents: 32186, igvCents: 5794, totalCents: 37980 });
    expect(buildItems([{ code: 'A', description: 'A', quantity: 1, amountCents: 10000 }], 1800, false)[0]).toMatchObject({ subtotalCents: 10000, igvCents: 1800, totalCents: 11800 });
    const ex = buildItems([{ code: 'A', description: 'A', quantity: 1, amountCents: 5000 }], 0, true);
    expect(totalsOf(ex)).toEqual({ gravadaCents: 0, exoneradaCents: 5000, igvCents: 0, totalCents: 5000 });
  });

  it('valida RUC con dígito verificador y documentos de boleta', () => {
    expect(isValidRuc('20131312955')).toBe(true);
    expect(isValidRuc('20131312956')).toBe(false);
    expect(isValidRuc('30131312955')).toBe(false);
    expect(() => normalizeCustomer('boleta', 10000, { docType: 'dni', docNumber: '1234', name: 'Ana' })).toThrow();
    expect(normalizeCustomer('boleta', 10000).name).toBe('CLIENTES VARIOS');
  });

  it('cifra y descifra; un cifrado alterado se rechaza', () => {
    const key = Buffer.alloc(32, 3).toString('base64');
    const sealed = seal('token-ose', key);
    expect(open(sealed, key)).toBe('token-ose');
    const [iv, tag, data] = sealed.split('.');
    expect(() => open([iv, tag, Buffer.from('x' + data).toString('base64')].join('.'), key)).toThrow();
  });
});
