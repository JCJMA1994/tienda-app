// Ciclo de facturación para el cron (cada hora o diario). Requiere `npm run build`.
//   node scripts/billing-run.mjs
import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';

const { AppModule } = await import('../dist/app.module.js');
const { BillingService } = await import('../dist/modules/billing/billing.service.js');

const app = await NestFactory.createApplicationContext(AppModule, { logger: ['error', 'warn', 'log'] });
try {
  const result = await app.get(BillingService).run(new Date());
  console.log('Facturación:', JSON.stringify(result));
} finally {
  await app.close();
}
