import { ApachiyClient, ApachiyError } from '../integrations/apachiy.client';

/** Comprobante a validar (tal como figura en la factura física o PDF del proveedor). */
export interface CpeQuery {
  ruc: string;
  /** Catálogo SUNAT: 01 factura, 03 boleta, 07 nota de crédito, 08 nota de débito. */
  type: '01' | '03' | '07' | '08';
  serie: string;
  numero: number;
  /** YYYY-MM-DD */
  date: string;
  totalCents?: number;
}

export interface CpeResult {
  /** valid: existe y está aceptado/vigente. invalid: no existe, anulado o no autorizado. */
  verdict: 'valid' | 'invalid';
  status: string;
  rucStatus: string | null;
  rucCondition: string | null;
  observations: string[];
  requestId?: string;
}

export interface CpeValidator {
  validate(q: CpeQuery): Promise<CpeResult>;
}

export const CPE_VALIDATOR = Symbol('CPE_VALIDATOR');
export class CpeUnavailableError extends Error {}

/** Estados de comprobante que SUNAT considera válidos para sustentar una compra. */
const VALID = /ACEPTADO|AUTORIZADO|VALIDO|VÁLIDO/i;

export class ApachiyCpeValidator implements CpeValidator {
  constructor(private readonly client: ApachiyClient) {}

  async validate(q: CpeQuery): Promise<CpeResult> {
    const [y, m, d] = q.date.split('-');
    try {
      const { data, requestId } = await this.client.post<{
        comprobante?: { estado_codigo?: string; estado?: string };
        contribuyente?: { estado_ruc?: string; condicion_domicilio?: string };
        observaciones?: unknown[];
      }>('/api/v1/consulta/cpe', {
        numRuc: q.ruc,
        codComp: q.type,
        numeroSerie: q.serie,
        numero: q.numero,
        fechaEmision: `${d}/${m}/${y}`,
        ...(q.totalCents !== undefined && { monto: q.totalCents / 100 }),
      });
      const status = data.comprobante?.estado ?? 'DESCONOCIDO';
      return {
        verdict: VALID.test(status) && !/NO AUTORIZADO/i.test(status) ? 'valid' : 'invalid',
        status,
        rucStatus: data.contribuyente?.estado_ruc ?? null,
        rucCondition: data.contribuyente?.condicion_domicilio ?? null,
        observations: (data.observaciones ?? []).map(String),
        requestId,
      };
    } catch (e) {
      if (e instanceof ApachiyError && e.status === 422) {
        return { verdict: 'invalid', status: 'DATOS INVÁLIDOS', rucStatus: null, rucCondition: null, observations: [e.message], requestId: e.requestId };
      }
      throw new CpeUnavailableError(e instanceof Error ? e.message : String(e));
    }
  }
}

/** Pruebas: F001-1 del RUC de SUNAT existe; el número 999 figura anulado. */
export class FakeCpeValidator implements CpeValidator {
  async validate(q: CpeQuery): Promise<CpeResult> {
    const anulado = q.numero === 999;
    return {
      verdict: anulado ? 'invalid' : 'valid',
      status: anulado ? 'ANULADO' : 'ACEPTADO',
      rucStatus: 'ACTIVO',
      rucCondition: 'HABIDO',
      observations: [],
    };
  }
}
