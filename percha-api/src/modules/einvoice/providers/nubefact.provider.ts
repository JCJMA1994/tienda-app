import type { EDoc } from '../document';
import type { EGuide } from '../guide';
import { EInvoiceProvider, OseConfig, OseResult, OseUnavailableError } from './provider';

const soles = (cents: number) => Math.round(cents) / 100;
/** Valores unitarios: Nubefact admite hasta 10 decimales. */
const unit = (cents: number, qty: number) => Number((cents / 100 / qty).toFixed(10));

const DOC_TYPE: Record<EDoc['kind'], number> = { factura: 1, boleta: 2, nota_credito: 3 };
const CUSTOMER_DOC: Record<string, string> = { ruc: '6', dni: '1', ce: '4', none: '-' };

/**
 * Adaptador para Nubefact (OSE/PSE). Cada tienda usa SU ruta y token (desde su cuenta
 * Nubefact → API). Operaciones: generar_comprobante y consultar_comprobante.
 *
 * Verificar con la cuenta DEMO de Nubefact antes de producción (series de prueba FFF1/BBB1).
 * Nubefact exige que el número sea correlativo (no más de 200 por encima del último).
 */
export class NubefactProvider implements EInvoiceProvider {
  readonly name = 'nubefact';

  toJson(doc: EDoc) {
    const [y, m, d] = doc.issueDate.split('-');
    return {
      operacion: 'generar_comprobante',
      tipo_de_comprobante: DOC_TYPE[doc.kind],
      serie: doc.serie,
      numero: doc.numero,
      sunat_transaction: 1, // venta interna
      cliente_tipo_de_documento: CUSTOMER_DOC[doc.customer.docType],
      cliente_numero_de_documento: doc.customer.docNumber ?? '-',
      cliente_denominacion: doc.customer.name,
      cliente_direccion: doc.customer.address ?? '',
      fecha_de_emision: `${d}-${m}-${y}`,
      moneda: doc.currency === 'USD' ? 2 : 1,
      porcentaje_de_igv: doc.taxRateBp / 100,
      total_gravada: soles(doc.totals.gravadaCents) || undefined,
      total_exonerada: soles(doc.totals.exoneradaCents) || undefined,
      total_igv: soles(doc.totals.igvCents),
      total: soles(doc.totals.totalCents),
      ...(doc.reference && {
        documento_que_se_modifica_tipo: DOC_TYPE[doc.reference.kind],
        documento_que_se_modifica_serie: doc.reference.serie,
        documento_que_se_modifica_numero: doc.reference.numero,
        tipo_de_nota_de_credito: Number(doc.reference.reasonCode),
        observaciones: doc.reference.reasonText,
      }),
      enviar_automaticamente_a_la_sunat: true,
      enviar_automaticamente_al_cliente: false,
      items: doc.items.map((i) => ({
        unidad_de_medida: 'NIU',
        codigo: i.code,
        descripcion: i.description,
        cantidad: i.quantity,
        valor_unitario: unit(i.subtotalCents, i.quantity),
        precio_unitario: unit(i.totalCents, i.quantity),
        subtotal: soles(i.subtotalCents),
        tipo_de_igv: i.igvType === 'gravado' ? 1 : 8, // 1 gravado-onerosa, 8 exonerado-onerosa
        igv: soles(i.igvCents),
        total: soles(i.totalCents),
        anticipo_regularizacion: false,
      })),
    };
  }

  /**
   * Guía de remisión remitente (operación generar_guia, serie que empieza con T).
   * Campos según la integración de Nubefact; verificar con la cuenta demo (serie TTT1).
   */
  toGuideJson(g: EGuide) {
    const dmy = (iso: string) => iso.split('-').reverse().join('-');
    const t = g.transport;
    return {
      operacion: 'generar_guia',
      tipo_de_comprobante: 7, // guía de remisión remitente
      serie: g.serie,
      numero: g.numero,
      cliente_tipo_de_documento: 6,
      cliente_numero_de_documento: g.recipient.ruc,
      cliente_denominacion: g.recipient.name,
      cliente_direccion: g.destination.address,
      fecha_de_emision: dmy(g.issueDate),
      observaciones: g.note ?? '',
      motivo_de_traslado: g.reasonCode,
      peso_bruto_total: Number(g.weightKg.toFixed(3)),
      peso_bruto_unidad_de_medida: 'KGM',
      numero_de_bultos: g.packages,
      tipo_de_transporte: t.mode === 'public' ? '01' : '02',
      fecha_de_inicio_de_traslado: dmy(g.startDate),
      ...(t.mode === 'public' && t.carrier && {
        transportista_documento_tipo: 6,
        transportista_documento_numero: t.carrier.ruc,
        transportista_denominacion: t.carrier.name,
      }),
      ...(t.mode === 'private' && {
        transportista_placa_numero: t.vehiclePlate,
        conductor_documento_tipo: 1,
        conductor_documento_numero: t.driver?.dni,
        conductor_nombre: t.driver?.firstName,
        conductor_apellidos: t.driver?.lastName,
        conductor_numero_licencia: t.driver?.license ?? '',
      }),
      punto_de_partida_ubigeo: g.origin.ubigeo,
      punto_de_partida_direccion: g.origin.address,
      punto_de_llegada_ubigeo: g.destination.ubigeo,
      punto_de_llegada_direccion: g.destination.address,
      enviar_automaticamente_a_la_sunat: true,
      enviar_automaticamente_al_cliente: false,
      items: g.items.map((i) => ({ unidad_de_medida: 'NIU', codigo: i.code, descripcion: i.description, cantidad: i.quantity })),
    };
  }

  async sendGuide(g: EGuide, cfg: OseConfig): Promise<OseResult> {
    const res = await this.call(cfg, this.toGuideJson(g));
    if (res.errors && /exist/i.test(String(res.errors))) return (await this.queryGuide(g, cfg)) ?? { state: 'sent', raw: res };
    if (res.errors) return { state: 'rejected', description: String(res.errors), raw: res };
    return this.map(res);
  }

  async queryGuide(g: EGuide, cfg: OseConfig): Promise<OseResult | null> {
    const res = await this.call(cfg, { operacion: 'consultar_guia', tipo_de_comprobante: 7, serie: g.serie, numero: g.numero });
    return res.errors ? null : this.map(res);
  }

  async send(doc: EDoc, cfg: OseConfig): Promise<OseResult> {
    const res = await this.call(cfg, this.toJson(doc));
    // Ya existe (reintento después de un corte): se consulta en lugar de fallar.
    if (res.errors && /exist/i.test(String(res.errors))) return (await this.query(doc, cfg)) ?? { state: 'sent', raw: res };
    if (res.errors) return { state: 'rejected', description: String(res.errors), raw: res };
    return this.map(res);
  }

  async query(doc: EDoc, cfg: OseConfig): Promise<OseResult | null> {
    const res = await this.call(cfg, { operacion: 'consultar_comprobante', tipo_de_comprobante: DOC_TYPE[doc.kind], serie: doc.serie, numero: doc.numero });
    if (res.errors) return null;
    return this.map(res);
  }

  private map(res: Record<string, unknown>): OseResult {
    const accepted = res.aceptada_por_sunat === true;
    const code = res.sunat_responsecode == null ? null : String(res.sunat_responsecode);
    const rejected = !accepted && code !== null && code !== '0' && code !== '';
    return {
      state: accepted ? 'accepted' : rejected ? 'rejected' : 'sent',
      description: (res.sunat_description as string) ?? undefined,
      pdfUrl: (res.enlace_del_pdf as string) ?? undefined,
      hash: (res.codigo_hash as string) ?? undefined,
      qr: (res.cadena_para_codigo_qr as string) ?? undefined,
      raw: res,
    };
  }

  private async call(cfg: OseConfig, body: unknown): Promise<Record<string, unknown>> {
    let res: Response;
    try {
      res = await fetch(cfg.apiUrl, {
        method: 'POST',
        headers: { Authorization: `Token token="${cfg.token}"`, 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(20_000),
      });
    } catch (e) {
      throw new OseUnavailableError(`No se pudo contactar al OSE: ${e instanceof Error ? e.message : e}`);
    }
    if (res.status >= 500) throw new OseUnavailableError(`OSE respondió ${res.status}`);
    return (await res.json().catch(() => ({ errors: `Respuesta inválida (${res.status})` }))) as Record<string, unknown>;
  }
}
