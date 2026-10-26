import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { createApp, resetDatabase } from './helpers';

/** La app muestra `message` tal cual: nunca debe llegar en inglés ni con detalles técnicos. */
describe('Mensajes de error claros', () => {
  let app: INestApplication;
  beforeAll(async () => {
    await resetDatabase();
    app = await createApp();
  });
  afterAll(async () => app?.close());

  it('ruta inexistente, sin sesión y JSON mal formado: en español y con código', async () => {
    const s = app.getHttpServer();
    expect((await request(s).get('/v1/nada')).body).toEqual({ message: 'No encontramos lo que buscas', code: 'NOT_FOUND' });
    expect((await request(s).get('/v1/sales')).body).toEqual({ message: 'Tu sesión venció. Vuelve a iniciar sesión.', code: 'UNAUTHENTICATED' });
    const bad = await request(s).post('/v1/auth/login').set('Content-Type', 'application/json').send('{malo');
    expect(bad.body).toEqual({ message: 'Los datos enviados no son válidos', code: 'BAD_REQUEST' });
  });

  it('demasiados intentos: mensaje claro (no "ThrottlerException")', async () => {
    const s = app.getHttpServer();
    let last: request.Response | undefined;
    for (let i = 0; i < 12; i++) last = await request(s).post('/v1/auth/login').send({ email: 'x@y.pe', password: 'zzzzzzzzzz' });
    expect(last!.status).toBe(429);
    expect(last!.body.code).toBe('TOO_MANY_REQUESTS');
    expect(last!.body.message).toMatch(/^Demasiados intentos/);
  });

  it('los mensajes propios y de validación no se tocan', async () => {
    const r = await request(app.getHttpServer()).post('/v1/auth/register').send({ storeName: 'A' });
    expect(r.status).toBe(400);
    expect(r.body.message).not.toBe('Los datos enviados no son válidos');
  });
});
