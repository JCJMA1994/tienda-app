import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { createApp, resetDatabase } from './helpers';

/** Panel web: el refresh token viaja solo en una cookie HttpOnly, nunca en el JSON. */
describe('Sesión del panel web (cookie HttpOnly)', () => {
  let app: INestApplication;
  const web = (r: request.Test) => r.set('X-Client', 'web');
  const cookieOf = (res: request.Response) => ([] as string[]).concat(res.headers['set-cookie'] ?? []).find((c) => c.startsWith('percha_rt='));

  beforeAll(async () => {
    await resetDatabase();
    app = await createApp();
  });
  afterAll(async () => app?.close());

  it('registro y login web: cookie HttpOnly, SameSite=Strict, solo para /v1/auth; sin refreshToken en el cuerpo', async () => {
    const r = await web(request(app.getHttpServer()).post('/v1/auth/register')).send({ storeName: 'Alma', ownerName: 'Joao', email: 'j@alma.pe', password: 'clave-segura-1' });
    expect(r.status).toBe(201);
    expect(r.body.accessToken).toEqual(expect.any(String));
    expect(r.body.refreshToken).toBeUndefined();
    const c = cookieOf(r)!;
    expect(c).toMatch(/HttpOnly/);
    expect(c).toMatch(/SameSite=Strict/);
    expect(c).toMatch(/Path=\/v1\/auth/);

    const login = await web(request(app.getHttpServer()).post('/v1/auth/login')).send({ email: 'j@alma.pe', password: 'clave-segura-1' });
    expect(login.body.refreshToken).toBeUndefined();
    expect(cookieOf(login)).toBeDefined();
  });

  it('al recargar la página, la sesión se recupera con la cookie (y rota)', async () => {
    const login = await web(request(app.getHttpServer()).post('/v1/auth/login')).send({ email: 'j@alma.pe', password: 'clave-segura-1' });
    const first = cookieOf(login)!.split(';')[0];
    const r = await web(request(app.getHttpServer()).post('/v1/auth/refresh')).set('Cookie', first).send({});
    expect(r.status).toBe(200);
    expect(r.body.accessToken).toEqual(expect.any(String));
    const second = cookieOf(r)!.split(';')[0];
    expect(second).not.toBe(first);
    // La cookie anterior ya no sirve (rotación con detección de reuso).
    expect((await web(request(app.getHttpServer()).post('/v1/auth/refresh')).set('Cookie', first).send({})).status).toBe(401);
  });

  it('sin la cabecera X-Client la cookie se ignora (no basta una petición desde otro sitio)', async () => {
    const login = await web(request(app.getHttpServer()).post('/v1/auth/login')).send({ email: 'j@alma.pe', password: 'clave-segura-1' });
    const cookie = cookieOf(login)!.split(';')[0];
    const r = await request(app.getHttpServer()).post('/v1/auth/refresh').set('Cookie', cookie).send({});
    expect(r.status).toBe(400);
  });

  it('cerrar sesión borra la cookie y la revoca', async () => {
    const login = await web(request(app.getHttpServer()).post('/v1/auth/login')).send({ email: 'j@alma.pe', password: 'clave-segura-1' });
    const cookie = cookieOf(login)!.split(';')[0];
    const out = await web(request(app.getHttpServer()).post('/v1/auth/logout')).set('Authorization', `Bearer ${login.body.accessToken}`).set('Cookie', cookie).send({});
    expect(out.status).toBeLessThan(300);
    expect(cookieOf(out)).toMatch(/percha_rt=;|Expires=Thu, 01 Jan 1970/);
    expect((await web(request(app.getHttpServer()).post('/v1/auth/refresh')).set('Cookie', cookie).send({})).status).toBe(401);
  });

  it('la app móvil (sin X-Client) sigue recibiendo el refresh token en el cuerpo', async () => {
    const r = await request(app.getHttpServer()).post('/v1/auth/login').send({ email: 'j@alma.pe', password: 'clave-segura-1' });
    expect(r.body.refreshToken).toEqual(expect.any(String));
    expect(cookieOf(r)).toBeUndefined();
  });
});
