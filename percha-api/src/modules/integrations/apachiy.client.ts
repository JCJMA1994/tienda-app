/**
 * Cliente HTTP de Apachiy (apachiy.mytems.cloud, API v1). Un solo lugar para autenticación,
 * tiempos de espera y traducción de errores; lo usan la consulta DNI/RUC, la validación de
 * comprobantes y WhatsApp.
 *
 * Errores documentados: { success: false, error: { code, message } } con 401 (token),
 * 403 (permiso/servicio inactivo), 422 (datos), 429 (cupo o ritmo) y 502 provider_error.
 */
export class ApachiyError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly code?: string,
    readonly requestId?: string,
  ) {
    super(message);
  }

  /** Sin red, caído o cupo agotado: probar otra fuente o reintentar más tarde. */
  get unavailable() {
    return this.status === 0 || this.status === 429 || this.status >= 500;
  }

  /**
   * WhatsApp: el proveedor puede haber enviado el mensaje aunque no confirmó. NO reintentar
   * automáticamente (duplicaría el mensaje).
   */
  get uncertain() {
    return this.status === 502;
  }
}

export class ApachiyClient {
  constructor(
    private readonly baseUrl: string,
    private readonly token: string,
  ) {}

  get<T>(path: string) {
    return this.call<T>('GET', path);
  }

  post<T>(path: string, body: unknown, timeoutMs?: number) {
    return this.call<T>('POST', path, body, timeoutMs);
  }

  private async call<T>(method: string, path: string, body?: unknown, timeoutMs = 10_000): Promise<{ data: T; requestId?: string; status: number }> {
    let res: Response;
    try {
      res = await fetch(`${this.baseUrl.replace(/\/$/, '')}${path}`, {
        method,
        headers: {
          Authorization: `Bearer ${this.token}`,
          Accept: 'application/json',
          ...(body !== undefined && { 'Content-Type': 'application/json' }),
        },
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch (e) {
      throw new ApachiyError(`Apachiy no responde: ${e instanceof Error ? e.message : e}`, 0);
    }
    const json = (await res.json().catch(() => ({}))) as { success?: boolean; data?: T; error?: { code?: string; message?: string }; request_id?: string };
    if (!res.ok || json.success === false) {
      throw new ApachiyError(json.error?.message ?? `Apachiy respondió ${res.status}`, res.status, json.error?.code, json.request_id);
    }
    return { data: json.data as T, requestId: json.request_id, status: res.status };
  }
}
