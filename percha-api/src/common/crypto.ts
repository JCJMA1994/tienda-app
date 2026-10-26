import { hash, verify } from '@node-rs/argon2';
import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';

/** Argon2id: estándar actual (OWASP) para contraseñas y PIN. */
export const hashSecret = (plain: string) => hash(plain);
export const verifySecret = (hashed: string, plain: string) => verify(hashed, plain).catch(() => false);

/** Token opaco para refresh/invitaciones. En BD se guarda solo su SHA-256. */
export function newOpaqueToken() {
  const token = randomBytes(32).toString('base64url');
  return { token, hash: sha256(token) };
}

export const sha256 = (value: string) => createHash('sha256').update(value).digest('hex');

export const normalizeEmail = (email: string) => email.trim().toLowerCase();

/**
 * Cifrado de secretos en reposo (tokens de OSE y WhatsApp, secretos TOTP) con AES-256-GCM.
 * Formato: base64(iv) . base64(tag) . base64(cifrado). La clave vive solo en el entorno.
 */
export function seal(plain: string, keyB64: string): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', Buffer.from(keyB64, 'base64'), iv);
  const data = Buffer.concat([cipher.update(plain, 'utf8'), cipher.final()]);
  return [iv, cipher.getAuthTag(), data].map((b) => b.toString('base64')).join('.');
}

export function open(sealed: string, keyB64: string): string {
  const [iv, tag, data] = sealed.split('.').map((p) => Buffer.from(p, 'base64'));
  const decipher = createDecipheriv('aes-256-gcm', Buffer.from(keyB64, 'base64'), iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(data), decipher.final()]).toString('utf8');
}
