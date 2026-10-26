// Reenvía al OSE los comprobantes pendientes o con error (cron cada 5–15 min). Requiere `npm run build`.
import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';

const { AppModule } = await import('../dist/app.module.js');
const { EInvoiceService } = await import('../dist/modules/einvoice/einvoice.service.js');

const app = await NestFactory.createApplicationContext(AppModule, { logger: ['error', 'warn', 'log'] });
try {
  console.log('Comprobantes:', JSON.stringify(await app.get(EInvoiceService).run()));
} finally {
  await app.close();
}
