import { RequestMethod } from '@nestjs/common';
import 'reflect-metadata';
import { Logger } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import type { NestExpressApplication } from '@nestjs/platform-express';
import helmet from 'helmet';
import { AppModule } from './app.module';
import { configureHttp } from './common/http';
import { ENV, Env } from './config/env';

async function bootstrap() {
  // rawBody: los webhooks verifican la firma sobre el cuerpo exacto que envió la pasarela.
  const app = await NestFactory.create<NestExpressApplication>(AppModule, { rawBody: true });
  const env = app.get<Env>(ENV);

  // Detrás de proxies inversos (Cloudflare, Render, Traefik), asegura que la IP real del cliente se lea en el Throttler.
  app.set('trust proxy', env.TRUST_PROXY === 'true' ? true : env.TRUST_PROXY === 'false' ? false : Number.isInteger(Number(env.TRUST_PROXY)) ? Number(env.TRUST_PROXY) : env.TRUST_PROXY);

  app.use(helmet());
  // Topes de tamaño (JSON 2 MB, imágenes 10 MB) y archivos locales: ver configureHttp.
  configureHttp(app, env);
  // El catálogo público vive en una URL corta y compartible: /c/<slug>.
  app.setGlobalPrefix('v1', { exclude: [{ path: 'c/:slug', method: RequestMethod.GET }] });
  app.enableShutdownHooks();
  // La app móvil no necesita CORS; solo la web admin, con orígenes explícitos.
  // credentials: el panel web envía la cookie de sesión (solo a orígenes permitidos).
  app.enableCors({ origin: env.NODE_ENV === 'production' ? env.CORS_ORIGINS : true, credentials: true });

  await app.listen(env.PORT);
  new Logger('Bootstrap').log(`Percha API escuchando en :${env.PORT}/v1`);
}

void bootstrap();
