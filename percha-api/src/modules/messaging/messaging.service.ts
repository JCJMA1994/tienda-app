import { BadRequestException, ConflictException, HttpException, HttpStatus, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { and, desc, eq, gt, inArray } from 'drizzle-orm';
import { z } from 'zod';
import { assertBranchAccess, AuthUser } from '../../common/auth-user';
import { formatSoles } from '../../common/money';
import { ENV, Env } from '../../config/env';
import { DatabaseService } from '../../database/database.service';
import { einvoiceDocuments, messagingSettings, outboundMessages, sales, tenants } from '../../database/schema';
import { sha256 } from '../../common/crypto';
import { open, seal } from '../../common/crypto';
import { ApachiyClient } from '../integrations/apachiy.client';
import { ApachiyWhatsApp, FakeWhatsApp, WhatsAppError, WhatsAppSender } from './whatsapp';

export const MessagingSettingsSchema = z.object({
  enabled: z.boolean(),
  provider: z.enum(['apachiy', 'fake']).default('apachiy'),
  /** Número de WhatsApp vinculado, con código de país y solo dígitos (p. ej. 51987654321). */
  instance: z.string().regex(/^\d{8,15}$/, 'Número con código de país, solo dígitos'),
  token: z.string().min(10).optional(),
});

export const SendReceiptSchema = z.object({
  /** Celular del cliente: 9 dígitos peruanos o con código de país. */
  phone: z.string().trim().regex(/^\+?\d{6,15}$/),
  /** Reenviar aunque ya se haya enviado hace poco al mismo número. */
  force: z.boolean().default(false),
});

/** Celular peruano de 9 dígitos → 51XXXXXXXXX; con código de país se respeta. */
export function normalizePhone(raw: string) {
  const digits = raw.replace(/\D/g, '');
  return /^9\d{8}$/.test(digits) ? `51${digits}` : digits;
}

export const maskPhone = (p: string) => `${p.slice(0, 2)}•••••${p.slice(-3)}`;

/** Solo se descargan PDFs desde el OSE (https y dominios permitidos): evita SSRF. */
const PDF_HOSTS = [/(^|\.)nubefact\.com$/i];

/**
 * Mensajes de WhatsApp desde el número de CADA tienda (no el de Percha): el cliente reconoce
 * a su boutique. El token de la tienda se guarda cifrado.
 *
 * Primer uso: enviar el comprobante (PDF) o el resumen de la compra al celular que el cliente
 * da en caja. Solo se envía a pedido (no hay mensajes masivos ni de marketing).
 */
@Injectable()
export class MessagingService {
  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  private get key() {
    const k = this.env.SECRETS_ENC_KEY ?? this.env.EINVOICE_ENC_KEY;
    if (!k) throw new BadRequestException('El servidor no tiene SECRETS_ENC_KEY configurada');
    return k;
  }

  getSettings(user: AuthUser) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [s] = await tx.select().from(messagingSettings);
      return { enabled: s?.enabled ?? false, provider: s?.provider ?? 'apachiy', instance: s?.instance ?? null, hasToken: Boolean(s?.tokenEnc) };
    });
  }

  saveSettings(user: AuthUser, input: z.infer<typeof MessagingSettingsSchema>) {
    if (input.provider === 'fake' && !this.env.EINVOICE_FAKE) throw new BadRequestException('Proveedor no disponible');
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [current] = await tx.select().from(messagingSettings);
      const tokenEnc = input.token ? seal(input.token, this.key) : current?.tokenEnc ?? null;
      if (input.enabled && !tokenEnc && input.provider !== 'fake') throw new BadRequestException('Falta el token de Apachiy');
      const values = { enabled: input.enabled, provider: input.provider, instance: input.instance, tokenEnc, updatedAt: new Date() };
      await tx.insert(messagingSettings).values({ tenantId: user.tenantId, ...values }).onConflictDoUpdate({ target: messagingSettings.tenantId, set: values });
      return { enabled: input.enabled, instance: input.instance, hasToken: Boolean(tokenEnc) };
    });
  }

  /** Estado mínimo para el POS (cualquier vendedor): ¿mostrar "Enviar por WhatsApp"? */
  status(user: AuthUser) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [s] = await tx.select({ enabled: messagingSettings.enabled }).from(messagingSettings);
      return { whatsapp: s?.enabled ?? false };
    });
  }

  async sendSaleReceipt(user: AuthUser, saleId: string, input: z.infer<typeof SendReceiptSchema>) {
    const to = normalizePhone(input.phone);
    if (to.length < 8) throw new BadRequestException({ message: 'Número de celular inválido', code: 'INVALID_PHONE' });

    // 1) Leer lo necesario y aplicar el antiduplicado (fuera de la llamada externa).
    const ctx = await this.db.withTenant(user.tenantId, async (tx) => {
      const [settings] = await tx.select().from(messagingSettings);
      if (!settings?.enabled || !settings.instance) {
        throw new HttpException({ message: 'WhatsApp no está configurado en esta tienda', code: 'WHATSAPP_DISABLED' }, HttpStatus.CONFLICT);
      }
      const [sale] = await tx.select().from(sales).where(eq(sales.id, saleId));
      if (!sale) throw new NotFoundException('Venta no encontrada');
      assertBranchAccess(user, sale.branchId);
      const [store] = await tx.select({ name: tenants.name }).from(tenants);
      const [doc] = await tx
        .select()
        .from(einvoiceDocuments)
        .where(and(eq(einvoiceDocuments.saleId, saleId), inArray(einvoiceDocuments.kind, ['boleta', 'factura'])))
        .orderBy(desc(einvoiceDocuments.createdAt))
        .limit(1);
      const [recent] = await tx
        .select()
        .from(outboundMessages)
        .where(and(eq(outboundMessages.saleId, saleId), eq(outboundMessages.toHash, sha256(to)), inArray(outboundMessages.status, ['sent', 'uncertain']), gt(outboundMessages.createdAt, new Date(Date.now() - 10 * 60_000))))
        .limit(1);
      if (recent && !input.force) {
        throw new ConflictException({
          message: recent.status === 'uncertain' ? 'Hace poco se intentó enviar y no hubo confirmación: revisa el chat antes de reenviar' : 'Ya se envió a este número hace menos de 10 minutos',
          code: 'ALREADY_SENT',
        });
      }
      return { settings, sale, store, doc };
    });

    const sender = this.sender(ctx.settings);
    const code = ctx.doc ? `${ctx.doc.kind === 'factura' ? 'Factura' : 'Boleta'} ${ctx.doc.serie}-${ctx.doc.numero}` : `Ticket #${ctx.sale.number}`;
    const text = [
      `Gracias por tu compra en ${ctx.store.name}.`,
      `${code} · Total ${formatSoles(ctx.sale.totalCents)}`,
      ctx.doc?.pdfUrl ? `Descárgalo aquí: ${ctx.doc.pdfUrl}` : null,
    ]
      .filter(Boolean)
      .join('\n');

    // 2) Enviar: PDF adjunto si se puede descargar del OSE; si no, texto con enlace.
    let result;
    try {
      const pdf = ctx.doc?.status === 'accepted' && ctx.doc.pdfUrl ? await this.downloadPdf(ctx.doc.pdfUrl) : null;
      result = pdf
        ? await sender.sendDocument(to, { base64: pdf, filename: `${ctx.doc!.serie}-${ctx.doc!.numero}.pdf`, caption: text })
        : await sender.sendText(to, text);
    } catch (e) {
      await this.log(user, saleId, to, { status: 'failed', error: e instanceof Error ? e.message : String(e) });
      if (e instanceof WhatsAppError) throw new HttpException({ message: e.message, code: e.code }, HttpStatus.BAD_GATEWAY);
      throw e;
    }
    await this.log(user, saleId, to, result);
    return {
      status: result.status,
      to: maskPhone(to),
      message: result.status === 'sent' ? 'Enviado por WhatsApp' : 'No hubo confirmación: revisa el chat antes de reenviar',
    };
  }

  private sender(s: typeof messagingSettings.$inferSelect): WhatsAppSender {
    if (s.provider === 'fake' && this.env.EINVOICE_FAKE) return new FakeWhatsApp();
    return new ApachiyWhatsApp(new ApachiyClient(this.env.APACHIY_BASE_URL, open(s.tokenEnc!, this.key)), s.instance!);
  }

  private async downloadPdf(url: string): Promise<string | null> {
    try {
      const u = new URL(url);
      if (u.protocol !== 'https:' || !PDF_HOSTS.some((h) => h.test(u.hostname))) return null;
      const res = await fetch(u, { signal: AbortSignal.timeout(15_000), redirect: 'error' });
      if (!res.ok || !(res.headers.get('content-type') ?? '').includes('pdf')) return null;
      const buf = Buffer.from(await res.arrayBuffer());
      return buf.length > 0 && buf.length <= 8 * 1024 * 1024 ? buf.toString('base64') : null;
    } catch {
      return null;
    }
  }

  private log(user: AuthUser, saleId: string, to: string, r: { status: string; providerMessageId?: string; requestId?: string; error?: string }) {
    return this.db.withTenant(user.tenantId, (tx) =>
      tx.insert(outboundMessages).values({
        tenantId: user.tenantId,
        saleId,
        channel: 'whatsapp',
        toMasked: maskPhone(to),
        toHash: sha256(to),
        status: r.status,
        providerMessageId: r.providerMessageId,
        requestId: r.requestId,
        error: r.error?.slice(0, 300),
        createdBy: user.membershipId,
      }),
    );
  }
}
