// Mantenimiento diario: borra claves de idempotencia de más de 7 días. Requiere `npm run build`.
import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';

const { AppModule } = await import('../dist/app.module.js');
const { IdempotencyService } = await import('../dist/common/idempotency.js');
const app = await NestFactory.createApplicationContext(AppModule, { logger: ['error', 'warn'] });
try {
  console.log('Idempotencia:', JSON.stringify(await app.get(IdempotencyService).purge()));
} finally {
  await app.close();
}
