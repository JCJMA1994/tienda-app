import { createSign } from 'node:crypto';

export interface PushMessage {
  token: string;
  title: string;
  body: string;
  link?: string | null;
}

export interface PushSender {
  /** Devuelve los tokens inválidos (desinstalaron la app) para borrarlos. */
  send(messages: PushMessage[]): Promise<{ invalidTokens: string[] }>;
}

export const PUSH_SENDER = Symbol('PUSH_SENDER');

/** Sin credenciales de Firebase: las notificaciones quedan solo en la bandeja de la app. */
export class NoopPushSender implements PushSender {
  async send() {
    return { invalidTokens: [] };
  }
}

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

/**
 * Firebase Cloud Messaging (API HTTP v1) sin SDK: se firma un JWT con la cuenta de servicio
 * (RS256), se canjea por un token OAuth y se envía cada mensaje. El token OAuth se reutiliza
 * hasta que vence. El contenido del push es mínimo (sin montos ni datos de clientes): el
 * detalle se ve dentro de la app, con sesión.
 */
export class FcmPushSender implements PushSender {
  private accessToken: { value: string; expires: number } | null = null;
  constructor(private readonly account: ServiceAccount) {}

  async send(messages: PushMessage[]) {
    if (!messages.length) return { invalidTokens: [] };
    const token = await this.oauthToken();
    const invalidTokens: string[] = [];
    for (const m of messages) {
      const res = await fetch(`https://fcm.googleapis.com/v1/projects/${this.account.project_id}/messages:send`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: { token: m.token, notification: { title: m.title, body: m.body }, data: m.link ? { link: m.link } : undefined } }),
        signal: AbortSignal.timeout(10_000),
      });
      if (res.status === 404 || res.status === 400) invalidTokens.push(m.token);
    }
    return { invalidTokens };
  }

  private async oauthToken() {
    if (this.accessToken && this.accessToken.expires > Date.now() + 60_000) return this.accessToken.value;
    const now = Math.floor(Date.now() / 1000);
    const b64 = (o: object) => Buffer.from(JSON.stringify(o)).toString('base64url');
    const unsigned = `${b64({ alg: 'RS256', typ: 'JWT' })}.${b64({
      iss: this.account.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    })}`;
    const signature = createSign('RSA-SHA256').update(unsigned).sign(this.account.private_key, 'base64url');
    const res = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${signature}` }),
      signal: AbortSignal.timeout(10_000),
    });
    const json = (await res.json()) as { access_token: string; expires_in: number };
    this.accessToken = { value: json.access_token, expires: Date.now() + json.expires_in * 1000 };
    return json.access_token;
  }
}
