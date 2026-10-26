import { CallHandler, ExecutionContext, Inject, Injectable, NestInterceptor } from '@nestjs/common';
import type { Request, Response } from 'express';
import { map } from 'rxjs';
import { ENV, Env } from '../config/env';

export const REFRESH_COOKIE = 'percha_rt';

/** Rutas que reciben el refresh token: en web lo toman de la cookie. */
const READS_REFRESH = new Set(['/v1/auth/refresh', '/v1/auth/logout']);
const CLEARS_COOKIE = new Set(['/v1/auth/logout', '/v1/auth/logout-all']);

function readCookie(req: Request, name: string) {
  for (const part of (req.headers.cookie ?? '').split(';')) {
    const [k, ...v] = part.trim().split('=');
    if (k === name) return decodeURIComponent(v.join('='));
  }
  return undefined;
}

/**
 * Sesión del PANEL WEB: el refresh token NUNCA llega al JavaScript del navegador.
 *
 * Si la petición trae `X-Client: web`:
 *  - toda respuesta con `refreshToken` lo entrega en una cookie `HttpOnly` (y lo quita del
 *    JSON): un script inyectado (XSS) no puede robarlo; el access token (15 min) vive solo en
 *    memoria;
 *  - `/auth/refresh` y `/auth/logout` lo leen de la cookie;
 *  - cerrar sesión borra la cookie.
 *
 * CSRF: la cookie es `SameSite=Strict`, se envía solo a `/v1/auth`, y estas rutas exigen la
 * cabecera `X-Client` (un formulario de otro sitio no puede ponerla sin pasar por CORS).
 * Las apps móviles no envían `X-Client: web` y siguen igual (token en Keychain/Keystore).
 */
@Injectable()
export class WebSessionInterceptor implements NestInterceptor {
  constructor(@Inject(ENV) private readonly env: Env) {}

  intercept(ctx: ExecutionContext, next: CallHandler) {
    if (ctx.getType() !== 'http') return next.handle();
    const req = ctx.switchToHttp().getRequest<Request>();
    const res = ctx.switchToHttp().getResponse<Response>();
    const web = req.headers['x-client'] === 'web';
    if (!web) return next.handle();

    const path = req.path;
    if (READS_REFRESH.has(path) && !req.body?.refreshToken) {
      const fromCookie = readCookie(req, REFRESH_COOKIE);
      if (fromCookie) req.body = { ...(req.body ?? {}), refreshToken: fromCookie };
    }

    const options = {
      httpOnly: true,
      secure: this.env.NODE_ENV === 'production',
      sameSite: this.env.WEB_COOKIE_SAMESITE,
      path: '/v1/auth',
      ...(this.env.WEB_COOKIE_DOMAIN && { domain: this.env.WEB_COOKIE_DOMAIN }),
    } as const;

    return next.handle().pipe(
      map((body: unknown) => {
        if (CLEARS_COOKIE.has(path)) res.clearCookie(REFRESH_COOKIE, options);
        if (body && typeof body === 'object' && typeof (body as { refreshToken?: unknown }).refreshToken === 'string') {
          const { refreshToken, ...rest } = body as { refreshToken: string };
          res.cookie(REFRESH_COOKIE, refreshToken, { ...options, maxAge: this.env.REFRESH_TOKEN_TTL_DAYS * 86_400_000 });
          return rest;
        }
        return body;
      }),
    );
  }
}
