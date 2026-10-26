import { INestApplication } from '@nestjs/common';
import { validateShipment } from '../src/modules/einvoice/guide';
import { FakeOse } from '../src/modules/einvoice/providers/fake.provider';
import { NubefactProvider } from '../src/modules/einvoice/providers/nubefact.provider';
import { api, createApp, resetDatabase } from './helpers';

const shipment = {
  mode: 'private',
  lightVehicle: true,
  vehiclePlate: 'abc-123',
  driver: { dni: '45678912', firstName: 'Diego', lastName: 'Rojas' },
  weightKg: 1.5,
  packages: 1,
};

describe('Guía de remisión en transferencias', () => {
  let app: INestApplication;
  const s: Record<string, any> = {};
  const o = () => api(app, s.owner);
  const send = (extra: object = {}) => o().post('/transfers', { fromBranchId: s.main, toBranchId: s.mall, items: [{ variantId: s.v, quantity: 2 }], notes: 'Reposición', ...extra });

  beforeAll(async () => {
    await resetDatabase();
    app = await createApp();
    const reg = await api(app).post('/auth/register', { storeName: 'Alma', ownerName: 'Joao', email: 'j@alma.pe', password: 'clave-segura-1' });
    s.owner = reg.body.accessToken;
    s.main = (await o().get('/branches')).body[0].id;
    s.mall = (await o().post('/branches', { name: 'Jockey Plaza' })).body.id;
    await o().patch('/store', { ruc: '20601234565' });
    const p = await o().post('/products', { name: 'Vestido midi', priceCents: 18990, initialStock: { branchId: s.main, items: [{ options: {}, quantity: 10 }] } });
    s.v = p.body.variants[0].id;
    await o().put('/einvoice/settings', {
      enabled: true,
      provider: 'fake',
      legalName: 'ALMA BOUTIQUE S.A.C.',
      fiscalAddress: 'Av. Larco 345, Miraflores',
      apiUrl: 'https://ose.example/api',
      token: 'tok_secreto_123456',
      series: [
        { branchId: s.main, boleta: 'B001', factura: 'F001', ncBoleta: 'BC01', ncFactura: 'FC01', guia: 'T001' },
        { branchId: s.mall, boleta: 'B002', factura: 'F002', ncBoleta: 'BC02', ncFactura: 'FC02', guia: 'T002' },
      ],
    });
  });
  afterAll(async () => app?.close());

  it('con comprobantes activos, no se envía mercadería sin datos del traslado', async () => {
    expect((await send()).body.code).toBe('SHIPMENT_REQUIRED');
    const stock = await o().get(`/inventory/stock?branchId=${s.main}&variantId=${s.v}`);
    expect(stock.body[0].quantity).toBe(10); // nada se movió
  });

  it('exige dirección y ubigeo de ambas sucursales', async () => {
    const r = await send({ shipment });
    expect(r.status).toBe(409);
    expect(r.body.code).toBe('BRANCH_ADDRESS_MISSING');
    await o().patch(`/branches/${s.main}`, { address: 'Av. Larco 345, Miraflores', ubigeo: '150122' });
    await o().patch(`/branches/${s.mall}`, { address: 'Av. Javier Prado Este 4200, Surco', ubigeo: '150140' });
    expect((await o().patch(`/branches/${s.mall}`, { ubigeo: '15014' })).status).toBe(400);
  });

  it('reglas del traslado: placa y conductor en transporte privado; RUC de la empresa en público', async () => {
    expect((await send({ shipment: { ...shipment, vehiclePlate: undefined } })).body.code).toBe('SHIPMENT_PLATE_REQUIRED');
    expect((await send({ shipment: { ...shipment, lightVehicle: false } })).body.code).toBe('SHIPMENT_LICENSE_REQUIRED');
    expect((await send({ shipment: { mode: 'public', weightKg: 2 } })).body.code).toBe('SHIPMENT_CARRIER_REQUIRED');
    expect(() => validateShipment({ mode: 'public', lightVehicle: true, weightKg: 1, packages: 1, carrier: { ruc: '20131312955', name: 'Olva' } })).not.toThrow();
  });

  it('emite la guía remitente (motivo 04) desde la serie de la sucursal de origen', async () => {
    const r = await send({ shipment });
    expect(r.status).toBe(201);
    expect(r.body.documents).toEqual([expect.objectContaining({ kind: 'guia_remitente', serie: 'T001', numero: 1, status: 'accepted' })]);
    expect(r.body.documents[0].pdfUrl).toContain('T001-1');

    const g = FakeOse.guides.at(-1)!;
    expect(g).toMatchObject({
      reasonCode: '04',
      recipient: { ruc: '20601234565', name: 'ALMA BOUTIQUE S.A.C.' },
      origin: { ubigeo: '150122' },
      destination: { ubigeo: '150140', address: 'Av. Javier Prado Este 4200, Surco' },
      transport: { mode: 'private', vehiclePlate: 'ABC123' },
      weightKg: 1.5,
      note: 'Reposición',
    });
    expect(g.items).toEqual([{ code: expect.any(String), description: 'Vestido midi', quantity: 2 }]);
    s.transfer = r.body.id;
  });

  it('cancelar una transferencia con guía aceptada pide darla de baja', async () => {
    await o().post(`/transfers/${s.transfer}/cancel`);
    const inbox = await o().get('/notifications?limit=50');
    expect(inbox.body.some((n: any) => n.title === 'Da de baja la guía T001-1')).toBe(true);
  });

  it('formato Nubefact de la guía', () => {
    const json = new NubefactProvider().toGuideJson({ ...FakeOse.guides.at(-1)!, issueDate: '2026-10-26', startDate: '2026-10-27' });
    expect(json).toMatchObject({
      operacion: 'generar_guia',
      tipo_de_comprobante: 7,
      serie: 'T001',
      cliente_tipo_de_documento: 6,
      motivo_de_traslado: '04',
      tipo_de_transporte: '02',
      fecha_de_emision: '26-10-2026',
      fecha_de_inicio_de_traslado: '27-10-2026',
      peso_bruto_unidad_de_medida: 'KGM',
      transportista_placa_numero: 'ABC123',
      conductor_documento_numero: '45678912',
      punto_de_partida_ubigeo: '150122',
      punto_de_llegada_ubigeo: '150140',
    });
    expect(json.items[0]).toMatchObject({ unidad_de_medida: 'NIU', cantidad: 2 });
  });
});
