import { DeleteObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { Inject, Injectable } from '@nestjs/common';
import { mkdir, rm, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { ENV, Env } from '../../config/env';

/**
 * Almacén de objetos para archivos públicos (fotos de producto).
 * - local: disco del servidor, servido en /media (desarrollo y pruebas).
 * - s3: Cloudflare R2 / S3 compatible; los archivos se sirven desde MEDIA_PUBLIC_URL (CDN).
 *
 * Las claves incluyen la tienda y un UUID (`t/<tienda>/p/<producto>/<uuid>.webp`): no se
 * pueden adivinar ni listar. Solo se guardan imágenes ya procesadas por el servidor.
 */
@Injectable()
export class StorageService {
  private readonly s3?: S3Client;

  constructor(@Inject(ENV) private readonly env: Env) {
    if (env.STORAGE_DRIVER === 's3') {
      this.s3 = new S3Client({
        region: env.S3_REGION,
        endpoint: env.S3_ENDPOINT,
        credentials: { accessKeyId: env.S3_ACCESS_KEY_ID!, secretAccessKey: env.S3_SECRET_ACCESS_KEY! },
      });
    }
  }

  get localDir() {
    return resolve(this.env.STORAGE_DIR);
  }

  async put(key: string, body: Buffer, contentType: string) {
    this.assertKey(key);
    if (this.s3) {
      await this.s3.send(
        new PutObjectCommand({ Bucket: this.env.S3_BUCKET, Key: key, Body: body, ContentType: contentType, CacheControl: 'public, max-age=31536000, immutable' }),
      );
      return;
    }
    const path = join(this.localDir, key);
    await mkdir(dirname(path), { recursive: true });
    await writeFile(path, body);
  }

  async delete(key: string) {
    this.assertKey(key);
    if (this.s3) {
      await this.s3.send(new DeleteObjectCommand({ Bucket: this.env.S3_BUCKET, Key: key }));
      return;
    }
    await rm(join(this.localDir, key), { force: true });
  }

  url(key: string) {
    const base = this.env.STORAGE_DRIVER === 's3' ? this.env.MEDIA_PUBLIC_URL! : `${this.env.PUBLIC_API_URL}/media`;
    return `${base.replace(/\/$/, '')}/${key}`;
  }

  /** Solo claves generadas por nosotros: nada de "../" ni rutas absolutas. */
  private assertKey(key: string) {
    if (!/^t\/[0-9a-f-]{36}\/p\/[0-9a-f-]{36}\/[0-9a-f-]{36}(_thumb)?\.webp$/.test(key)) throw new Error('Clave de archivo inválida');
  }
}
