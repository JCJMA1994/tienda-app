// Envía por push las notificaciones nuevas (cron cada minuto). Requiere `npm run build`.
import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';

const { AppModule } = await import('../dist/app.module.js');
const { NotificationsService } = await import('../dist/modules/notifications/notifications.service.js');
const app = await NestFactory.createApplicationContext(AppModule, { logger: ['error', 'warn'] });
try {
  console.log('Push:', JSON.stringify(await app.get(NotificationsService).dispatchPush()));
} finally {
  await app.close();
}
