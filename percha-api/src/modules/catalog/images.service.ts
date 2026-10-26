import { BadRequestException, Inject, Injectable, NotFoundException, PayloadTooLargeException } from '@nestjs/common';
import { and, asc, eq, sql } from 'drizzle-orm';
import { randomUUID } from 'node:crypto';
import sharp from 'sharp';
import type { AuthUser } from '../../common/auth-user';
import { DatabaseService, Tx } from '../../database/database.service';
import { productImages, products } from '../../database/schema';
import { AuditService } from '../audit/audit.service';
import { StorageService } from '../storage/storage.service';

export const MAX_IMAGES_PER_PRODUCT = 8;
export const MAX_UPLOAD_BYTES = 10 * 1024 * 1024;

/** Firmas de archivo aceptadas (se revisan los bytes, no lo que diga el cliente). */
function sniff(buf: Buffer): 'jpeg' | 'png' | 'webp' | 'heic' | null {
  if (buf.length < 12) return null;
  if (buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'jpeg';
  if (buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'png';
  if (buf.subarray(0, 4).toString('ascii') === 'RIFF' && buf.subarray(8, 12).toString('ascii') === 'WEBP') return 'webp';
  if (buf.subarray(4, 8).toString('ascii') === 'ftyp' && /hei|mif|avi/.test(buf.subarray(8, 12).toString('ascii'))) return 'heic';
  return null;
}

/**
 * Fotos de producto. Cada imagen se REPROCESA en el servidor:
 * - Se valida por su firma real (no por la extensión) y con tope de píxeles (bombas de descompresión).
 * - Se endereza según la orientación de la cámara y se **eliminan los metadatos** (incluida la
 *   ubicación GPS que suelen traer las fotos del celular).
 * - Se guardan dos tamaños en WebP: 1200 px (detalle) y 400 px (listas, POS, etiquetas).
 * El archivo original nunca se guarda ni se sirve.
 */
@Injectable()
export class ImagesService {
  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(StorageService) private readonly storage: StorageService,
    @Inject(AuditService) private readonly audit: AuditService,
  ) {}

  async add(user: AuthUser, productId: string, body: Buffer | undefined, optionValue?: string) {
    if (!body?.length) throw new BadRequestException('Envía la imagen en el cuerpo (image/jpeg, image/png, image/webp)');
    if (body.length > MAX_UPLOAD_BYTES) throw new PayloadTooLargeException('La imagen supera 10 MB');
    if (!sniff(body)) throw new BadRequestException({ message: 'El archivo no es una imagen JPG, PNG, WebP o HEIC', code: 'INVALID_IMAGE' });

    let full: { data: Buffer; info: sharp.OutputInfo };
    let thumb: Buffer;
    try {
      const base = sharp(body, { limitInputPixels: 50_000_000, failOn: 'error' }).rotate();
      full = await base.clone().resize({ width: 1200, height: 1200, fit: 'inside', withoutEnlargement: true }).webp({ quality: 82 }).toBuffer({ resolveWithObject: true });
      thumb = await base.clone().resize({ width: 400, height: 400, fit: 'cover', position: 'attention' }).webp({ quality: 78 }).toBuffer();
    } catch {
      throw new BadRequestException({ message: 'No se pudo leer la imagen. Prueba con otra foto.', code: 'INVALID_IMAGE' });
    }

    return this.db.withTenant(user.tenantId, async (tx) => {
      const [product] = await tx.select({ id: products.id }).from(products).where(eq(products.id, productId)).for('update');
      if (!product) throw new NotFoundException('Producto no encontrado');
      const [{ count, maxPos }] = await tx
        .select({ count: sql<number>`count(*)::int`, maxPos: sql<number>`coalesce(max(${productImages.position}), -1)::int` })
        .from(productImages)
        .where(eq(productImages.productId, productId));
      if (count >= MAX_IMAGES_PER_PRODUCT) throw new BadRequestException({ message: `Máximo ${MAX_IMAGES_PER_PRODUCT} fotos por producto`, code: 'TOO_MANY_IMAGES' });

      const name = randomUUID();
      const key = `t/${user.tenantId}/p/${productId}/${name}.webp`;
      const thumbKey = `t/${user.tenantId}/p/${productId}/${name}_thumb.webp`;
      await this.storage.put(key, full.data, 'image/webp');
      await this.storage.put(thumbKey, thumb, 'image/webp');

      const [row] = await tx
        .insert(productImages)
        .values({ tenantId: user.tenantId, productId, key, thumbKey, width: full.info.width, height: full.info.height, position: maxPos + 1, optionValue: optionValue?.trim() || null })
        .returning();
      await this.syncCover(tx, productId);
      await this.audit.log(tx, user, 'product.image_added', 'product', productId, { imageId: row.id });
      return this.present(row);
    });
  }

  remove(user: AuthUser, productId: string, imageId: string) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [row] = await tx.delete(productImages).where(and(eq(productImages.id, imageId), eq(productImages.productId, productId))).returning();
      if (!row) throw new NotFoundException('Foto no encontrada');
      await this.syncCover(tx, productId);
      await this.audit.log(tx, user, 'product.image_removed', 'product', productId, { imageId });
      // Se borran los archivos después del cambio en BD (si falla, queda un archivo huérfano, no un enlace roto).
      await this.storage.delete(row.key).catch(() => undefined);
      await this.storage.delete(row.thumbKey).catch(() => undefined);
      return { ok: true };
    });
  }

  reorder(user: AuthUser, productId: string, ids: string[]) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const rows = await tx.select({ id: productImages.id }).from(productImages).where(eq(productImages.productId, productId));
      if (rows.length !== ids.length || !rows.every((r) => ids.includes(r.id))) throw new BadRequestException('La lista debe incluir todas las fotos del producto');
      for (const [i, id] of ids.entries()) await tx.update(productImages).set({ position: i }).where(eq(productImages.id, id));
      await this.syncCover(tx, productId);
      return this.list(tx, productId);
    });
  }

  async list(tx: Tx, productId: string) {
    const rows = await tx.select().from(productImages).where(eq(productImages.productId, productId)).orderBy(asc(productImages.position));
    return rows.map((r) => this.present(r));
  }

  /** La primera foto es la portada (la que se ve en listas y en el POS). */
  private async syncCover(tx: Tx, productId: string) {
    const [first] = await tx.select({ thumbKey: productImages.thumbKey }).from(productImages).where(eq(productImages.productId, productId)).orderBy(asc(productImages.position)).limit(1);
    await tx.update(products).set({ imageUrl: first ? this.storage.url(first.thumbKey) : null }).where(eq(products.id, productId));
  }

  private present(r: typeof productImages.$inferSelect) {
    return { id: r.id, url: this.storage.url(r.key), thumbUrl: this.storage.url(r.thumbKey), width: r.width, height: r.height, position: r.position, optionValue: r.optionValue };
  }
}
