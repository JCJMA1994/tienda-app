import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus, Logger } from '@nestjs/common';
import { DOMAIN_ERROR_STATUS, DomainError } from './domain-error';
import type { Response } from 'express';

type PgError = { code?: string; constraint?: string; detail?: string };

/**
 * Traduce errores de Postgres a respuestas HTTP útiles y evita filtrar detalles internos.
 * Las restricciones de BD (únicos, FKs) son la última línea de defensa: aunque el servicio
 * valide, la BD garantiza la integridad ante condiciones de carrera.
 */
@Catch()
export class AppExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger('Exceptions');

  catch(exception: unknown, host: ArgumentsHost) {
    const res = host.switchToHttp().getResponse<Response>();

    // Errores de negocio: el dominio decide el código; aquí solo se traduce a HTTP.
    if (exception instanceof DomainError) {
      res.status(DOMAIN_ERROR_STATUS[exception.kind]).json({ message: exception.message, code: exception.code, ...exception.details });
      return;
    }

    if (exception instanceof HttpException) {
      const status = exception.getStatus();
      const raw = exception.getResponse();
      const body = (typeof raw === 'string' ? { message: raw } : raw) as Record<string, unknown>;
      res.status(status).json(this.humanize(status, body));
      return;
    }

    // Errores del parser de Express (cuerpo demasiado grande, JSON mal formado).
    const parser = exception as { status?: number; type?: string };
    if (typeof parser?.status === 'number' && parser.status >= 400 && parser.status < 500 && typeof parser.type === 'string') {
      const message = parser.status === 413 ? 'La solicitud es demasiado grande' : 'Solicitud mal formada';
      res.status(parser.status).json({ message });
      return;
    }

    const pg = this.findPgError(exception);
    if (pg?.code === '23505') {
      res.status(HttpStatus.CONFLICT).json({ message: 'Ya existe un registro con esos datos', constraint: pg.constraint });
      return;
    }
    if (pg?.code === '23503') {
      res.status(HttpStatus.UNPROCESSABLE_ENTITY).json({ message: 'Referencia inválida', constraint: pg.constraint });
      return;
    }
    if (pg?.code === '42501') {
      // Violación de RLS: alguien intentó escribir datos de otra tienda.
      this.logger.warn(`Violación de RLS: ${pg.detail ?? ''}`);
      res.status(HttpStatus.FORBIDDEN).json({ message: 'Operación no permitida' });
      return;
    }

    this.logger.error(exception instanceof Error ? exception.stack : String(exception));
    res.status(HttpStatus.INTERNAL_SERVER_ERROR).json({ message: 'Error interno' });
  }

  /**
   * Los errores genéricos de NestJS/Express llegan en inglés o con detalles técnicos
   * ("Unauthorized", "Cannot GET /x", "ThrottlerException…", errores del parser de JSON).
   * La app muestra `message` tal cual: aquí se reemplazan por textos claros en español y
   * un `code` estable. Los mensajes propios (ya en español) no se tocan.
   */
  private humanize(status: number, body: Record<string, unknown>) {
    const message = typeof body.message === 'string' ? body.message : undefined;
    const generic = !message || /^(Unauthorized|Forbidden resource|Forbidden|Not Found|Too Many Requests|ThrottlerException.*|Cannot (GET|POST|PUT|PATCH|DELETE) .*|Expected .* in JSON.*|Unexpected .* JSON.*|.* is not valid JSON.*|Bad Request|Internal Server Error)$/.test(message);
    if (!generic) return body;
    const map: Record<number, [string, string]> = {
      400: ['BAD_REQUEST', 'Los datos enviados no son válidos'],
      401: ['UNAUTHENTICATED', 'Tu sesión venció. Vuelve a iniciar sesión.'],
      403: ['FORBIDDEN', 'No tienes permiso para hacer esto'],
      404: ['NOT_FOUND', 'No encontramos lo que buscas'],
      429: ['TOO_MANY_REQUESTS', 'Demasiados intentos seguidos. Espera un momento y vuelve a intentar.'],
    };
    const [code, text] = map[status] ?? ['ERROR', 'Ocurrió un error. Intenta de nuevo.'];
    return { message: text, code: body.code ?? code };
  }

  /** Drizzle envuelve el error del driver en `cause`. */
  private findPgError(e: unknown): PgError | undefined {
    let current: unknown = e;
    for (let i = 0; i < 3 && current; i++) {
      const c = current as PgError & { cause?: unknown };
      if (typeof c.code === 'string' && /^[0-9A-Z]{5}$/.test(c.code)) return c;
      current = c.cause;
    }
    return undefined;
  }
}
