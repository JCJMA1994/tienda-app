// Avisa los apartados vencidos (cron diario). Requiere `npm run build`.
import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';

const { AppModule } = await import('../dist/app.module.js');
const { LayawaysService } = await import('../dist/modules/sales/layaways.service.js');
const app = await NestFactory.createApplicationContext(AppModule, { logger: ['error', 'warn'] });
try {
  console.log('Apartados:', JSON.stringify(await app.get(LayawaysService).notifyExpired()));
} finally {
  await app.close();
}
