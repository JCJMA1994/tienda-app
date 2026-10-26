import { z } from 'zod';

/**
 * Variables de entorno validadas al arrancar. Si falta algo, la app no inicia
 * (mejor fallar en el deploy que en la primera venta).
 */
const EnvSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(3000),
  /** Confianza en proxies inversos (Cloudflare, Nginx, Render): número de saltos o boolean. Por defecto 1 en producción. */
  TRUST_PROXY: z.string().default('1'),
  DATABASE_APP_URL: z.string().url(),
  DATABASE_SYSTEM_URL: z.string().url(),
  JWT_ACCESS_SECRET: z.string().min(32, 'JWT_ACCESS_SECRET debe tener al menos 32 caracteres'),
  JWT_ACCESS_TTL_SECONDS: z.coerce.number().int().positive().default(900),
  REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().positive().default(30),
  /** Panel web: cookie de sesión. `strict` si la app y la API comparten dominio (app.x.com / api.x.com). */
  WEB_COOKIE_SAMESITE: z.enum(['strict', 'lax', 'none']).default('strict'),
  /** Opcional: dominio de la cookie (p. ej. .system-failed-tech.com). Por defecto, solo el de la API. */
  WEB_COOKIE_DOMAIN: z.string().optional(),
  INVITATION_TTL_HOURS: z.coerce.number().int().positive().default(72),
  // ---- Facturación SaaS (fase 8) ----
  TRIAL_DAYS: z.coerce.number().int().min(0).max(90).default(14),
  TRIAL_PLAN: z.string().default('crece'),
  /** Días que la tienda sigue operando normal después de vencer sin pagar. */
  BILLING_GRACE_DAYS: z.coerce.number().int().min(0).max(30).default(7),
  /** URL pública de la web/app, para volver desde el checkout de Stripe. */
  APP_URL: z.string().url().default('https://app.system-failed-tech.com'),
  /** URL pública de esta API (para la página de pago de Culqi que se abre desde la app). */
  PUBLIC_API_URL: z.string().url().default('http://localhost:3000'),
  CULQI_PUBLIC_KEY: z.string().optional(),
  CULQI_SECRET_KEY: z.string().optional(),
  STRIPE_SECRET_KEY: z.string().optional(),
  STRIPE_WEBHOOK_SECRET: z.string().optional(),
  /** Solo desarrollo y pruebas: habilita una pasarela simulada. Nunca en producción. */
  BILLING_FAKE_SECRET: z.string().optional(),
  // ---- Facturación electrónica SUNAT ----
  /** 32 bytes en base64 para cifrar los tokens de OSE de cada tienda (AES-256-GCM). */
  EINVOICE_ENC_KEY: z
    .string()
    .refine((k) => Buffer.from(k, 'base64').length === 32, 'EINVOICE_ENC_KEY debe ser 32 bytes en base64')
    .optional(),
  /** async: la venta no espera al OSE (recomendado). sync: espera (útil en pruebas). */
  EINVOICE_DISPATCH: z.enum(['async', 'sync']).default('async'),
  /** Solo desarrollo y pruebas: permite el OSE simulado "fake". */
  EINVOICE_FAKE: z.enum(['true', 'false']).default('false').transform((v) => v === 'true'),
  // ---- Consulta RUC / DNI ----
  /** Token de la plataforma en decolecta.com (lo paga Percha, no cada tienda). */
  DECOLECTA_TOKEN: z.string().optional(),
  /** Apachiy (apachiy.mytems.cloud): DNI, RUC y validez de comprobantes, con token de la plataforma. */
  APACHIY_TOKEN: z.string().optional(),
  APACHIY_BASE_URL: z.string().url().default('https://apachiy.mytems.cloud'),
  /** Respaldo opcional: peru-consult-api autoalojado (github.com/giansalex/peru-consult-api). */
  PERU_CONSULT_URL: z.string().url().optional(),
  PERU_CONSULT_TOKEN: z.string().optional(),
  /** Solo desarrollo y pruebas: proveedor simulado de RUC/DNI. */
  LOOKUP_FAKE: z.enum(['true', 'false']).default('false').transform((v) => v === 'true'),
  // ---- Secretos de usuarios (2FA) y de tiendas (WhatsApp). Si falta, se usa EINVOICE_ENC_KEY ----
  SECRETS_ENC_KEY: z
    .string()
    .refine((k) => Buffer.from(k, 'base64').length === 32, 'SECRETS_ENC_KEY debe ser 32 bytes en base64')
    .optional(),
  /** El backoffice exige 2FA (por defecto, solo en producción). */
  ADMIN_REQUIRE_2FA: z.enum(['true', 'false']).optional().transform((v) => v === 'true'),
  // ---- Correo (recuperar contraseña). Resend: resend.com ----
  RESEND_API_KEY: z.string().optional(),
  EMAIL_FROM: z.string().default('Percha <no-responder@system-failed-tech.com>'),
  /** Solo pruebas: guarda los correos en memoria en lugar de enviarlos. */
  EMAIL_FAKE: z.enum(['true', 'false']).default('false').transform((v) => v === 'true'),
  // ---- Archivos (fotos de producto) ----
  /** local: disco del servidor (desarrollo). s3: Cloudflare R2, AWS S3 o compatible. */
  STORAGE_DRIVER: z.enum(['local', 's3']).default('local'),
  STORAGE_DIR: z.string().default('./storage'),
  S3_ENDPOINT: z.string().url().optional(),
  S3_REGION: z.string().default('auto'),
  S3_BUCKET: z.string().optional(),
  S3_ACCESS_KEY_ID: z.string().optional(),
  S3_SECRET_ACCESS_KEY: z.string().optional(),
  /** URL pública del bucket o CDN (p. ej. https://media.system-failed-tech.com). */
  MEDIA_PUBLIC_URL: z.string().url().optional(),
  // ---- Notificaciones push (opcional) ----
  /** JSON de la cuenta de servicio de Firebase en base64. Sin esto, solo bandeja en la app. */
  FCM_SERVICE_ACCOUNT_B64: z.string().optional(),
  /** Orígenes permitidos para la web admin, separados por coma. Vacío = ninguno. */
  CORS_ORIGINS: z
    .string()
    .default('')
    .transform((s) => s.split(',').map((o) => o.trim()).filter(Boolean)),
});

export type Env = z.infer<typeof EnvSchema>;

/** La pasarela simulada nunca puede quedar activa en producción. */
const assertSafe = (env: Env) => {
  if (env.NODE_ENV === 'production' && env.BILLING_FAKE_SECRET) {
    throw new Error('BILLING_FAKE_SECRET no se permite en producción');
  }
  if (env.NODE_ENV === 'production' && env.STORAGE_DRIVER === 'local') {
    console.warn('STORAGE_DRIVER=local en producción: las fotos se pierden si el servidor se recrea. Usa s3 (R2).');
  }
  if (env.STORAGE_DRIVER === 's3' && (!env.S3_BUCKET || !env.S3_ACCESS_KEY_ID || !env.S3_SECRET_ACCESS_KEY || !env.MEDIA_PUBLIC_URL)) {
    throw new Error('STORAGE_DRIVER=s3 requiere S3_BUCKET, S3_ACCESS_KEY_ID, S3_SECRET_ACCESS_KEY y MEDIA_PUBLIC_URL');
  }
  if (env.NODE_ENV === 'production' && env.EMAIL_FAKE) {
    throw new Error('EMAIL_FAKE no se permite en producción');
  }
  if (env.NODE_ENV === 'production' && env.LOOKUP_FAKE) {
    throw new Error('LOOKUP_FAKE no se permite en producción');
  }
  if (env.NODE_ENV === 'production' && env.EINVOICE_FAKE) {
    throw new Error('EINVOICE_FAKE no se permite en producción');
  }
  return env;
};

export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  if (source === process.env && typeof (process as any).loadEnvFile === 'function') {
    try {
      (process as any).loadEnvFile('.env');
    } catch (_) {
      // .env no existe o no pudo cargarse; se usan las variables del entorno del sistema
    }
  }
  const parsed = EnvSchema.safeParse(source);
  if (!parsed.success) {
    const issues = parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join('\n');
    throw new Error(`Configuración inválida:\n${issues}`);
  }
  const env = assertSafe(parsed.data);
  if (source.ADMIN_REQUIRE_2FA === undefined) env.ADMIN_REQUIRE_2FA = env.NODE_ENV === 'production';
  return env;
}

export const ENV = Symbol('ENV');
