/**
 * Error de NEGOCIO, independiente del transporte (HTTP, colas, scripts).
 *
 * Las reglas de dominio lanzan `DomainError` con un código estable (el que lee la app) y un
 * tipo; el filtro HTTP lo traduce al status correspondiente. Así el dominio no conoce NestJS y
 * las mismas reglas sirven en un job o en un script sin cambiar nada.
 */
export type DomainErrorKind =
  | 'invalid' // datos que no cumplen una regla → 400
  | 'not_found' // → 404
  | 'conflict' // estado incompatible (ya cancelado, falta configurar algo) → 409
  | 'rule'; // regla de negocio (saldo insuficiente, stock) → 422

export class DomainError extends Error {
  constructor(
    readonly kind: DomainErrorKind,
    readonly code: string,
    message: string,
    /** Datos útiles para la app (p. ej. saldo disponible). */
    readonly details: Record<string, unknown> = {},
  ) {
    super(message);
    this.name = 'DomainError';
  }

  static invalid(code: string, message: string, details?: Record<string, unknown>) {
    return new DomainError('invalid', code, message, details);
  }
  static notFound(code: string, message: string, details?: Record<string, unknown>) {
    return new DomainError('not_found', code, message, details);
  }
  static conflict(code: string, message: string, details?: Record<string, unknown>) {
    return new DomainError('conflict', code, message, details);
  }
  static rule(code: string, message: string, details?: Record<string, unknown>) {
    return new DomainError('rule', code, message, details);
  }
}

export const DOMAIN_ERROR_STATUS: Record<DomainErrorKind, number> = { invalid: 400, not_found: 404, conflict: 409, rule: 422 };
