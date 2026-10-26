import type { NestExpressApplication } from '@nestjs/platform-express';
import { resolve } from 'node:path';

/** Configuración HTTP común (servidor y pruebas). */
export function configureHttp(app: NestExpressApplication, env: { STORAGE_DRIVER: string; STORAGE_DIR: string }) {
  // Tope de tamaño: evita cuerpos gigantes (la importación de 2 000 filas pesa < 1 MB).
  app.useBodyParser('json', { limit: '2mb' });
  // Fotos: el cuerpo es la imagen. Tope de 10 MB (el servidor la reduce a ~200 KB).
  app.useBodyParser('raw', { type: ['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'], limit: '10mb' });
  if (env.STORAGE_DRIVER === 'local') {
    // Solo desarrollo: archivos públicos ya procesados, con cabeceras que impiden ejecutarlos.
    app.useStaticAssets(resolve(env.STORAGE_DIR), {
      prefix: '/media/',
      index: false,
      dotfiles: 'deny',
      setHeaders: (res) => {
        res.setHeader('X-Content-Type-Options', 'nosniff');
        res.setHeader('Content-Security-Policy', "default-src 'none'");
        res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
      },
    });
  }
}
