import { ApachiyClient, ApachiyError } from '../integrations/apachiy.client';
/** Datos mínimos para un comprobante. No se guarda nada más (datos personales: Ley 29733). */
export interface PersonInfo {
  dni: string;
  name: string;
}

export interface CompanyInfo {
  ruc: string;
  name: string;
  address: string | null;
  /** ACTIVO, BAJA DE OFICIO, SUSPENSION TEMPORAL... */
  status: string | null;
  /** HABIDO, NO HABIDO, NO HALLADO... */
  condition: string | null;
}

export interface IdentityProvider {
  readonly name: string;
  /** Fuente local (padrón en la BD): no pasa por la caché. */
  readonly local?: boolean;
  dni(numero: string): Promise<PersonInfo | null>;
  ruc(numero: string): Promise<CompanyInfo | null>;
}

export class LookupUnavailableError extends Error {}

/** Lista ordenada: se usa la primera fuente que encuentre el documento. */
export const IDENTITY_PROVIDERS = Symbol('IDENTITY_PROVIDERS');

const pick = (o: Record<string, unknown>, ...keys: string[]) => {
  for (const k of keys) if (o[k] != null && String(o[k]).trim() !== '') return String(o[k]).trim();
  return null;
};

/**
 * decolecta.com: RENIEC (DNI) y SUNAT (RUC) con un token Bearer.
 * El mapeo acepta varios nombres de campo porque estos servicios los han cambiado entre
 * versiones; verifica la respuesta real con tu token antes de producción.
 */
export class DecolectaProvider implements IdentityProvider {
  readonly name = 'decolecta';
  constructor(private readonly token: string) {}

  async dni(numero: string): Promise<PersonInfo | null> {
    const j = await this.get(`https://api.decolecta.com/v1/reniec/dni?numero=${numero}`);
    if (!j) return null;
    const full =
      pick(j, 'full_name', 'nombre_completo', 'nombreCompleto') ??
      [pick(j, 'first_name', 'nombres'), pick(j, 'first_last_name', 'apellido_paterno', 'apellidoPaterno'), pick(j, 'second_last_name', 'apellido_materno', 'apellidoMaterno')]
        .filter(Boolean)
        .join(' ');
    return full ? { dni: numero, name: full } : null;
  }

  async ruc(numero: string): Promise<CompanyInfo | null> {
    const j = await this.get(`https://api.decolecta.com/v1/sunat/ruc?numero=${numero}`);
    if (!j) return null;
    const name = pick(j, 'razon_social', 'razonSocial', 'nombre');
    if (!name) return null;
    const address = [pick(j, 'direccion'), pick(j, 'distrito'), pick(j, 'provincia'), pick(j, 'departamento')].filter(Boolean).join(', ') || null;
    return { ruc: numero, name, address, status: pick(j, 'estado'), condition: pick(j, 'condicion') };
  }

  private async get(url: string): Promise<Record<string, unknown> | null> {
    let res: Response;
    try {
      res = await fetch(url, { headers: { Authorization: `Bearer ${this.token}`, Accept: 'application/json' }, signal: AbortSignal.timeout(8_000) });
    } catch (e) {
      throw new LookupUnavailableError(`Servicio de consulta no disponible: ${e instanceof Error ? e.message : e}`);
    }
    if (res.status === 404 || res.status === 422) return null;
    if (!res.ok) throw new LookupUnavailableError(`Servicio de consulta respondió ${res.status}`);
    return (await res.json()) as Record<string, unknown>;
  }
}

/** Simulado (pruebas): DNI 45678912 y el RUC de SUNAT; 20100070970 figura como NO HABIDO. */
export class FakeIdentityProvider implements IdentityProvider {
  static calls = 0;
  readonly name = 'fake';

  async dni(numero: string) {
    FakeIdentityProvider.calls++;
    return numero === '45678912' ? { dni: numero, name: 'LUCIA RAMOS TORRES' } : null;
  }

  async ruc(numero: string) {
    FakeIdentityProvider.calls++;
    if (numero === '20131312955') return { ruc: numero, name: 'SUPERINTENDENCIA NACIONAL DE ADUANAS Y DE ADMINISTRACION TRIBUTARIA - SUNAT', address: 'AV. GARCILASO DE LA VEGA 1472, LIMA', status: 'ACTIVO', condition: 'HABIDO' };
    if (numero === '20100070970') return { ruc: numero, name: 'EMPRESA DE PRUEBA S.A.C.', address: null, status: 'ACTIVO', condition: 'NO HABIDO' };
    return null;
  }
}

/**
 * peru-consult-api (github.com/giansalex/peru-consult-api), proyecto libre que puedes
 * levantar tú mismo con Docker. OJO: obtiene los datos de páginas públicas, así que puede
 * dejar de funcionar si SUNAT/RENIEC cambian su web (el proyecto no se actualiza hace años).
 * Úsalo como respaldo, no como fuente principal.
 */
export class PeruConsultApiProvider implements IdentityProvider {
  readonly name = 'peru-consult';
  constructor(
    private readonly baseUrl: string,
    private readonly token: string,
  ) {}

  async dni(numero: string): Promise<PersonInfo | null> {
    const j = await this.get(`/api/v1/dni/${numero}`);
    if (!j) return null;
    const name = [pick(j, 'nombres'), pick(j, 'apellidoPaterno'), pick(j, 'apellidoMaterno')].filter(Boolean).join(' ');
    return name ? { dni: numero, name } : null;
  }

  async ruc(numero: string): Promise<CompanyInfo | null> {
    const j = await this.get(`/api/v1/ruc/${numero}`);
    const name = j && pick(j, 'razonSocial');
    if (!j || !name) return null;
    return { ruc: numero, name, address: pick(j, 'direccion'), status: pick(j, 'estado'), condition: pick(j, 'condicion') };
  }

  private async get(path: string): Promise<Record<string, unknown> | null> {
    let res: Response;
    try {
      res = await fetch(`${this.baseUrl.replace(/\/$/, '')}${path}?token=${encodeURIComponent(this.token)}`, {
        headers: { Accept: 'application/json' },
        signal: AbortSignal.timeout(8_000),
      });
    } catch (e) {
      throw new LookupUnavailableError(`peru-consult-api no disponible: ${e instanceof Error ? e.message : e}`);
    }
    if (res.status === 404) return null;
    if (!res.ok) throw new LookupUnavailableError(`peru-consult-api respondió ${res.status}`);
    const j = (await res.json().catch(() => null)) as Record<string, unknown> | null;
    return j && Object.keys(j).length ? j : null;
  }
}

/**
 * Apachiy (apachiy.mytems.cloud): DNI (RENIEC) y RUC (SUNAT) en una sola API, con 130
 * consultas gratis al mes y planes económicos. Respuesta documentada:
 *   { success, data: { documento, nombre_o_razon_social, direccion, estado_contribuyente, condicion_domicilio, ... }, request_id }
 * El estado del RUC puede venir como CÓDIGO de SUNAT: solo se usa si es texto legible, para no
 * mostrar advertencias falsas.
 */
export class ApachiyIdentityProvider implements IdentityProvider {
  readonly name = 'apachiy';
  constructor(private readonly client: ApachiyClient) {}

  async dni(numero: string): Promise<PersonInfo | null> {
    const j = await this.fetch(`/api/v1/consulta/dni/${numero}`);
    if (!j) return null;
    const name =
      pick(j, 'nombre_o_razon_social') ?? [pick(j, 'nombres'), pick(j, 'apellido_paterno'), pick(j, 'apellido_materno')].filter(Boolean).join(' ');
    return name ? { dni: numero, name } : null;
  }

  async ruc(numero: string): Promise<CompanyInfo | null> {
    const j = await this.fetch(`/api/v1/consulta/ruc/${numero}`);
    const name = j && pick(j, 'nombre_o_razon_social');
    if (!j || !name) return null;
    const ubigeo = (j.ubigeo ?? {}) as Record<string, unknown>;
    const address = [pick(j, 'direccion'), pick(ubigeo, 'distrito'), pick(ubigeo, 'provincia'), pick(ubigeo, 'departamento')].filter(Boolean).join(', ') || null;
    const readable = (v: string | null) => (v && /[A-Za-z]/.test(v) ? v.toUpperCase() : null);
    return { ruc: numero, name, address, status: readable(pick(j, 'estado_contribuyente')), condition: readable(pick(j, 'condicion_domicilio')) };
  }

  private async fetch(path: string): Promise<Record<string, unknown> | null> {
    try {
      return (await this.client.get<Record<string, unknown>>(path)).data ?? null;
    } catch (e) {
      if (e instanceof ApachiyError && (e.status === 404 || e.status === 422)) return null;
      // Token inválido, sin permiso, cupo agotado o caído: se prueba la siguiente fuente.
      throw new LookupUnavailableError(e instanceof Error ? e.message : String(e));
    }
  }
}
