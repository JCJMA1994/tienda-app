import { ApachiyClient, ApachiyError } from '../integrations/apachiy.client';

export interface SendResult {
  /** sent · uncertain (el proveedor no confirmó; puede haber llegado) */
  status: 'sent' | 'uncertain';
  providerMessageId?: string;
  requestId?: string;
}

export interface WhatsAppSender {
  sendText(to: string, text: string): Promise<SendResult>;
  sendDocument(to: string, file: { base64: string; filename: string; caption?: string }): Promise<SendResult>;
}

export class WhatsAppError extends Error {
  constructor(
    message: string,
    readonly code: string,
  ) {
    super(message);
  }
}

/**
 * WhatsApp vía Apachiy: envía desde la instancia (número de la tienda) vinculada en su panel.
 *   POST /api/v1/message/sendtext/{instancia}   { number, text }
 *   POST /api/v1/message/sendmedia/{instancia}  { number, mediatype, media(base64), filename, caption }
 * Un 502 significa que no hubo confirmación: NO se reintenta (podría duplicarse el mensaje).
 */
export class ApachiyWhatsApp implements WhatsAppSender {
  constructor(
    private readonly client: ApachiyClient,
    private readonly instance: string,
  ) {}

  sendText(to: string, text: string) {
    return this.send(`/api/v1/message/sendtext/${this.instance}`, { number: to, text: text.slice(0, 4096) });
  }

  sendDocument(to: string, f: { base64: string; filename: string; caption?: string }) {
    return this.send(`/api/v1/message/sendmedia/${this.instance}`, {
      number: to,
      mediatype: 'document',
      media: f.base64,
      filename: f.filename.slice(0, 180),
      caption: f.caption,
    });
  }

  private async send(path: string, body: unknown): Promise<SendResult> {
    try {
      const { data, requestId } = await this.client.post<{ provider_id?: string }>(path, body, 30_000);
      return { status: 'sent', providerMessageId: data?.provider_id, requestId };
    } catch (e) {
      if (e instanceof ApachiyError) {
        if (e.uncertain) return { status: 'uncertain', requestId: e.requestId };
        if (e.status === 401 || e.status === 403) throw new WhatsAppError('WhatsApp no está conectado: revisa el token y la instancia en Apachiy', 'WHATSAPP_NOT_CONNECTED');
        if (e.status === 429) throw new WhatsAppError('Se alcanzó el límite de mensajes del plan de WhatsApp', 'WHATSAPP_QUOTA');
        if (e.status === 422) throw new WhatsAppError(`WhatsApp rechazó el mensaje: ${e.message}`, 'WHATSAPP_INVALID');
      }
      throw new WhatsAppError('No se pudo enviar por WhatsApp. Intenta de nuevo en un momento.', 'WHATSAPP_UNAVAILABLE');
    }
  }
}

/** Pruebas: guarda los envíos; el número 51900000502 simula un 502 (sin confirmación). */
export class FakeWhatsApp implements WhatsAppSender {
  static sent: { to: string; kind: 'text' | 'document'; text?: string; filename?: string }[] = [];

  async sendText(to: string, text: string): Promise<SendResult> {
    if (to === '51900000502') return { status: 'uncertain' };
    FakeWhatsApp.sent.push({ to, kind: 'text', text });
    return { status: 'sent', providerMessageId: `wa_${FakeWhatsApp.sent.length}` };
  }

  async sendDocument(to: string, f: { filename: string; caption?: string }): Promise<SendResult> {
    FakeWhatsApp.sent.push({ to, kind: 'document', filename: f.filename, text: f.caption });
    return { status: 'sent' };
  }
}
