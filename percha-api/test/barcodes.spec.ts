import { barcodeCandidates } from '../src/modules/catalog/barcodes';
import { api, createApp, resetDatabase } from './helpers';
import { INestApplication } from '@nestjs/common';

describe('Códigos leídos por cámara o lector', () => {
  it('limpia y equipara UPC-A con EAN-13', () => {
    expect(barcodeCandidates(' 7751234567893\r\n')).toEqual(['7751234567893']);
    expect(barcodeCandidates('012345678905')).toEqual(['012345678905', '0012345678905']);
    expect(barcodeCandidates('0012345678905')).toEqual(['0012345678905', '012345678905']);
    expect(barcodeCandidates('VST-001-S')).toEqual(['VST-001-S']);
    expect(barcodeCandidates('  ')).toEqual([]);
  });

  describe('búsqueda del POS', () => {
    let app: INestApplication;
    const s: Record<string, any> = {};
    beforeAll(async () => {
      await resetDatabase();
      app = await createApp();
      s.t = (await api(app).post('/auth/register', { storeName: 'Alma', ownerName: 'Joao', email: 'j@alma.pe', password: 'clave-segura-1' })).body.accessToken;
      s.b = (await api(app, s.t).get('/branches')).body[0].id;
      const p = await api(app, s.t).post('/products', { name: 'Jean importado', priceCents: 19990, initialStock: { branchId: s.b, items: [{ options: {}, quantity: 2 }] } });
      s.v = p.body.variants[0];
      // Código del fabricante (UPC-A guardado como EAN-13 con 0 adelante).
      await api(app, s.t).patch(`/variants/${s.v.id}`, { barcode: '0012345678905' });
    });
    afterAll(async () => app?.close());

    it('encuentra la prenda con EAN-13, UPC-A, SKU en minúsculas o con basura del lector', async () => {
      const find = (code: string) => api(app, s.t).get(`/variants/lookup?code=${encodeURIComponent(code)}&branchId=${s.b}`);
      for (const code of ['0012345678905', '012345678905', ` ${s.v.sku.toLowerCase()} `]) {
        const r = await find(code);
        expect([code, r.status, r.body.id]).toEqual([code, 200, s.v.id]);
      }
      const miss = await find('9999999999999');
      expect(miss.body).toMatchObject({ code: 'CODE_NOT_FOUND', message: 'Código no encontrado' });
    });
  });
});
