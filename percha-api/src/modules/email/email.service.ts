import { Inject, Injectable, Logger } from '@nestjs/common';
import { ENV, Env } from '../../config/env';

export interface Email {
  to: string;
  subject: string;
  text: string;
  html: string;
}

/**
 * Envío de correos transaccionales (hoy: recuperar contraseña) con Resend (API HTTP).
 * En pruebas (`EMAIL_FAKE`) los correos quedan en memoria para inspeccionarlos.
 * Si no hay proveedor configurado, se registra un aviso y no se envía: la API responde igual
 * (no revela si el correo existe).
 */
@Injectable()
export class EmailService {
  static outbox: Email[] = [];
  private readonly logger = new Logger('Email');

  constructor(@Inject(ENV) private readonly env: Env) {}

  async send(email: Email) {
    if (this.env.EMAIL_FAKE) {
      EmailService.outbox.push(email);
      return;
    }
    if (!this.env.RESEND_API_KEY) {
      this.logger.warn('RESEND_API_KEY no configurada: correo no enviado');
      return;
    }
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${this.env.RESEND_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: this.env.EMAIL_FROM, to: [email.to], subject: email.subject, text: email.text, html: email.html }),
      signal: AbortSignal.timeout(10_000),
    });
    if (!res.ok) this.logger.error(`Resend respondió ${res.status}`);
  }
}
