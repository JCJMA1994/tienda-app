import { RequestMethod } from '@nestjs/common';
import { INestApplication } from '@nestjs/common';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { Test } from '@nestjs/testing';
import { configureHttp } from '../src/common/http';
import { execSync } from 'node:child_process';
import { Client } from 'pg';
import request from 'supertest';

const DB = 'percha_test';
const HOST = process.env.TEST_PG_HOST ?? 'localhost:5432';
const ADMIN_URL = process.env.TEST_ADMIN_URL ?? `postgres://postgres:postgres@${HOST}/postgres`;

export const urls = {
  owner: `postgres://percha_owner:owner_dev_pass@${HOST}/${DB}`,
  app: `postgres://percha_app:app_dev_pass@${HOST}/${DB}`,
  system: `postgres://percha_system:system_dev_pass@${HOST}/${DB}`,
};

/** BD limpia por ejecución: se recrea y se migra con el mismo script que producción. */
export async function resetDatabase() {
  const admin = new Client({ connectionString: ADMIN_URL });
  await admin.connect();
  await admin.query(`DROP DATABASE IF EXISTS ${DB} WITH (FORCE)`);
  await admin.query(`CREATE DATABASE ${DB} OWNER percha_owner`);
  await admin.end();
  execSync('node scripts/migrate.mjs', { env: { ...process.env, DATABASE_OWNER_URL: urls.owner }, stdio: 'pipe' });
}

export async function createApp(): Promise<INestApplication> {
  Object.assign(process.env, {
    NODE_ENV: 'test',
    DATABASE_APP_URL: urls.app,
    DATABASE_SYSTEM_URL: urls.system,
    JWT_ACCESS_SECRET: 'test-secret-test-secret-test-secret-123',
    BILLING_FAKE_SECRET: 'fake-webhook-secret',
    EINVOICE_ENC_KEY: Buffer.alloc(32, 7).toString('base64'),
    EINVOICE_DISPATCH: 'sync',
    EINVOICE_FAKE: 'true',
    LOOKUP_FAKE: 'true',
    EMAIL_FAKE: 'true',
    STORAGE_DIR: '/tmp/percha-test-storage',
  });
  // Import diferido: el módulo lee el entorno al construirse.
  const { AppModule } = await import('../src/app.module');
  const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
  const app = moduleRef.createNestApplication<NestExpressApplication>({ rawBody: true });
  configureHttp(app, { STORAGE_DRIVER: 'local', STORAGE_DIR: '/tmp/percha-test-storage' });
  // El catálogo público vive en una URL corta y compartible: /c/<slug>.
  app.setGlobalPrefix('v1', { exclude: [{ path: 'c/:slug', method: RequestMethod.GET }] });
  await app.init();
  return app;
}

/** Cliente HTTP con token, para escribir los tests como "historias". */
export function api(app: INestApplication, token?: string) {
  const server = app.getHttpServer();
  const auth = (r: request.Test) => (token ? r.set('Authorization', `Bearer ${token}`) : r);
  return {
    get: (url: string) => auth(request(server).get(`/v1${url}`)),
    post: (url: string, body?: object) => auth(request(server).post(`/v1${url}`)).send(body ?? {}),
    patch: (url: string, body: object) => auth(request(server).patch(`/v1${url}`)).send(body),
    put: (url: string, body: object) => auth(request(server).put(`/v1${url}`)).send(body),
    delete: (url: string) => auth(request(server).delete(`/v1${url}`)),
  };
}
