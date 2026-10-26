import { INestApplication } from '@nestjs/common';
import sharp from 'sharp';
import request from 'supertest';
import { api, createApp, resetDatabase } from './helpers';

/** Foto "de celular": 3000×2000 con metadatos EXIF que no deben llegar al público. */
const phonePhoto = () =>
  sharp({ create: { width: 3000, height: 2000, channels: 3, background: '#7a5cff' } })
    .jpeg()
    .withMetadata({ exif: { IFD0: { Artist: 'ubicacion-secreta', Copyright: 'privado' } } })
    .toBuffer();

describe('Fotos de producto, clientes y ticket', () => {
  let app: INestApplication;
  const s: Record<string, any> = {};
  const upload = (token: string, productId: string, body: Buffer, type = 'image/jpeg', option?: string) =>
    request(app.getHttpServer())
      .post(`/v1/products/${productId}/images${option ? `?option=${encodeURIComponent(option)}` : ''}`)
      .set('Authorization', `Bearer ${token}`)
      .set('Content-Type', type)
      .send(body);
  const mediaPath = (url: string) => new URL(url).pathname;

  beforeAll(async () => {
    await resetDatabase();
    app = await createApp();
    const reg = await api(app).post('/auth/register', { storeName: 'Boutique Alma', ownerName: 'Joao', email: 'j@alma.pe', password: 'clave-segura-1' });
    s.owner = reg.body.accessToken;
    const o = api(app, s.owner);
    s.branch = (await o.get('/branches')).body[0].id;
    await o.patch('/branches/' + s.branch, { address: 'Av. Larco 345, Miraflores' });
    await o.post('/attributes', { name: 'Talla', values: ['S', 'M'] });
    const p = await o.post('/products', {
      name: 'Vestido midi',
      priceCents: 18990,
      matrix: { Talla: ['S', 'M'] },
      initialStock: { branchId: s.branch, items: [{ options: { Talla: 'S' }, quantity: 10 }, { options: { Talla: 'M' }, quantity: 10 }] },
    });
    s.product = p.body;
    s.M = p.body.variants.find((v: any) => v.options.Talla === 'M').id;
    const inv = await o.post('/team/invitations', { email: 'v@alma.pe', role: 'seller', branchId: s.branch });
    s.seller = (await api(app).post('/auth/invitations/accept', { token: inv.body.token, name: 'Diego', password: 'vendedor-123' })).body.accessToken;
    await o.post('/cash-sessions', { branchId: s.branch, openingCents: 0 });
  });
  afterAll(async () => app?.close());

  describe('Fotos', () => {
    it('reprocesa la foto: WebP, máx. 1200 px, miniatura y SIN metadatos', async () => {
      const res = await upload(s.owner, s.product.id, await phonePhoto());
      expect(res.status).toBe(201);
      expect(res.body).toMatchObject({ width: 1200, height: 800, position: 0 });
      const full = await request(app.getHttpServer()).get(mediaPath(res.body.url)).buffer(true).parse((r, cb) => {
        const chunks: Buffer[] = [];
        r.on('data', (c: Buffer) => chunks.push(c));
        r.on('end', () => cb(null, Buffer.concat(chunks)));
      });
      expect(full.headers['content-type']).toContain('image/webp');
      expect(full.headers['x-content-type-options']).toBe('nosniff');
      const meta = await sharp(full.body as Buffer).metadata();
      expect(meta.format).toBe('webp');
      expect(meta.exif).toBeUndefined();
      s.first = res.body;
    });

    it('rechaza lo que no es imagen aunque diga image/jpeg, y respeta permisos', async () => {
      const fake = await upload(s.owner, s.product.id, Buffer.from('<script>alert(1)</script> no soy una foto'));
      expect(fake.status).toBe(400);
      expect(fake.body.code).toBe('INVALID_IMAGE');
      expect((await upload(s.seller, s.product.id, await phonePhoto())).status).toBe(403);
    });

    it('portada = primera foto; reordenar la cambia; detalle incluye las fotos', async () => {
      const second = await upload(s.owner, s.product.id, await sharp({ create: { width: 800, height: 1000, channels: 3, background: '#000' } }).png().toBuffer(), 'image/png', 'Negro');
      expect(second.body).toMatchObject({ position: 1, optionValue: 'Negro' });
      let detail = await api(app, s.owner).get(`/products/${s.product.id}`);
      expect(detail.body.images.map((i: any) => i.id)).toEqual([s.first.id, second.body.id]);
      expect(detail.body.imageUrl).toBe(s.first.thumbUrl);

      await api(app, s.owner).put(`/products/${s.product.id}/images/order`, { ids: [second.body.id, s.first.id] });
      detail = await api(app, s.owner).get(`/products/${s.product.id}`);
      expect(detail.body.imageUrl).toBe(second.body.thumbUrl);

      // Borrar: deja de servirse el archivo.
      await api(app, s.owner).delete(`/products/${s.product.id}/images/${second.body.id}`);
      expect((await request(app.getHttpServer()).get(mediaPath(second.body.url))).status).toBe(404);
      expect((await api(app, s.owner).get(`/products/${s.product.id}`)).body.imageUrl).toBe(s.first.thumbUrl);
    });

    it('máximo 8 fotos por producto', async () => {
      const img = await sharp({ create: { width: 50, height: 50, channels: 3, background: '#fff' } }).webp().toBuffer();
      for (let i = 0; i < 7; i++) expect((await upload(s.owner, s.product.id, img, 'image/webp')).status).toBe(201);
      const ninth = await upload(s.owner, s.product.id, img, 'image/webp');
      expect(ninth.body.code).toBe('TOO_MANY_IMAGES');
    });
  });

  describe('Clientes', () => {
    it('ficha con validación y sin duplicar documento', async () => {
      const c = await api(app, s.seller).post('/customers', { docType: 'dni', docNumber: '45678912', name: 'Lucía Ramos', phone: '987654321', birthday: '03-15', whatsappOptIn: true });
      expect(c.status).toBe(201);
      expect(c.body.whatsappOptInAt).not.toBeNull();
      s.customer = c.body.id;
      expect((await api(app, s.seller).post('/customers', { docType: 'dni', docNumber: '45678912', name: 'Otra' })).body.code).toBe('CUSTOMER_EXISTS');
      expect((await api(app, s.seller).post('/customers', { docType: 'dni', docNumber: '123', name: 'X' })).status).toBe(400);
      expect((await api(app, s.seller).get('/customers?search=lucía')).body[0].id).toBe(s.customer);
    });

    it('ventas asociadas: gasto, compras y talla habitual', async () => {
      for (let i = 0; i < 2; i++) {
        await api(app, s.seller).post('/sales', { branchId: s.branch, customerId: s.customer, items: [{ variantId: s.M, quantity: 1 }], payments: [{ method: 'cash', amountCents: 18990 }] });
      }
      const c = await api(app, s.seller).get(`/customers/${s.customer}`);
      expect(c.body.stats).toMatchObject({ purchases: 2, spentCents: 37980, topSizes: ['M'] });
      expect(c.body.recentSales).toHaveLength(2);
      s.saleId = c.body.recentSales[0].id;
    });

    it('el detalle de venta trae cliente y datos de la tienda para el ticket', async () => {
      const sale = await api(app, s.seller).get(`/sales/${s.saleId}`);
      expect(sale.body.customer).toEqual({ id: s.customer, name: 'Lucía Ramos' });
      expect(sale.body.store).toMatchObject({ name: 'Boutique Alma', branchAddress: 'Av. Larco 345, Miraflores' });
    });

    it('anonimizar (derecho de cancelación): borra datos personales, conserva ventas', async () => {
      expect((await api(app, s.seller).delete(`/customers/${s.customer}`)).status).toBe(403);
      expect((await api(app, s.owner).delete(`/customers/${s.customer}`)).status).toBe(200);
      expect((await api(app, s.owner).get(`/customers/${s.customer}`)).status).toBe(404);
      const sale = await api(app, s.owner).get(`/sales/${s.saleId}`);
      expect(sale.status).toBe(200);
      expect(sale.body.customer.name).toBe('Cliente anonimizado');
      // El documento queda libre para registrarse de nuevo si vuelve.
      expect((await api(app, s.owner).post('/customers', { docType: 'dni', docNumber: '45678912', name: 'Lucía Ramos' })).status).toBe(201);
    });
  });
});
