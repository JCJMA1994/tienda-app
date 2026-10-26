import { BadRequestException, HttpException, HttpStatus, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { and, eq } from 'drizzle-orm';
import { DatabaseService } from '../../database/database.service';
import { identityCache } from '../../database/schema';
import { isValidRuc } from '../../common/peru';
import { CPE_VALIDATOR, CpeQuery, CpeUnavailableError, CpeValidator } from './cpe';
import { CompanyInfo, IDENTITY_PROVIDERS, IdentityProvider, LookupUnavailableError, PersonInfo } from './providers';

const DAY = 86_400_000;
/** El estado de un RUC cambia (baja, no habido): caché corta. Un nombre en RENIEC casi nunca. */
const TTL = { ruc: 7 * DAY, dni: 180 * DAY };

/**
 * Consulta de RUC (SUNAT) y DNI (RENIEC) para autocompletar clientes y proveedores.
 *
 * - Se valida el formato (y el dígito verificador del RUC) ANTES de llamar afuera: un error
 *   de tipeo no consume una consulta pagada.
 * - Caché global en la BD: si dos tiendas consultan el mismo RUC, se paga una sola vez.
 * - Si el servicio externo cae, el vendedor puede escribir el nombre a mano: nunca bloquea
 *   una venta.
 * - Advierte si el RUC no está ACTIVO o el contribuyente no está HABIDO (riesgo al facturar).
 */
@Injectable()
export class LookupService {
  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(IDENTITY_PROVIDERS) private readonly providers: IdentityProvider[],
    @Inject(CPE_VALIDATOR) private readonly cpe: CpeValidator | null,
  ) {}

  /**
   * Validez de un comprobante en SUNAT (p. ej. la factura del proveedor antes de registrar la
   * compra). `null` si el servicio no está configurado o no responde: quien llama decide.
   */
  async validateCpe(q: CpeQuery) {
    if (!isValidRuc(q.ruc)) throw new BadRequestException({ message: 'RUC del emisor inválido', code: 'INVALID_RUC' });
    if (!this.cpe) return null;
    try {
      return await this.cpe.validate(q);
    } catch (e) {
      if (e instanceof CpeUnavailableError) return null;
      throw e;
    }
  }

  async ruc(numero: string) {
    if (!isValidRuc(numero)) throw new BadRequestException({ message: 'RUC inválido', code: 'INVALID_RUC' });
    const info = await this.cached<CompanyInfo>('ruc', numero, (p) => p.ruc(numero));
    const warnings = [
      info.status && info.status !== 'ACTIVO' ? `RUC en estado ${info.status}` : null,
      info.condition && info.condition !== 'HABIDO' ? `Contribuyente ${info.condition}` : null,
    ].filter((w): w is string => Boolean(w));
    return { ...info, warnings };
  }

  async dni(numero: string) {
    if (!/^\d{8}$/.test(numero)) throw new BadRequestException({ message: 'El DNI tiene 8 dígitos', code: 'INVALID_DNI' });
    return this.cached<PersonInfo>('dni', numero, (p) => p.dni(numero));
  }

  /**
   * Fuentes en orden (p. ej. padrón SUNAT → decolecta → peru-consult). Se usa la primera que
   * encuentre el documento. Una fuente caída no detiene la búsqueda: se prueba la siguiente.
   */
  private async cached<T>(type: 'ruc' | 'dni', numero: string, fetcher: (p: IdentityProvider) => Promise<T | null>): Promise<T> {
    const sources = this.providers;
    // 1) Fuentes locales (padrón): gratis e instantáneas.
    for (const p of sources.filter((x) => x.local)) {
      const local = await fetcher(p);
      if (local) return local;
    }

    // 2) Caché de consultas externas.
    const [hit] = await this.db.withSystem((tx) =>
      tx.select().from(identityCache).where(and(eq(identityCache.docType, type), eq(identityCache.docNumber, numero))),
    );
    if (hit && Date.now() - hit.fetchedAt.getTime() < TTL[type]) return hit.data as T;

    // 3) Fuentes externas, en orden.
    const remote = sources.filter((x) => !x.local);
    let unavailable = false;
    for (const p of remote) {
      try {
        const data = await fetcher(p);
        if (data) {
          await this.db.withSystem((tx) =>
            tx
              .insert(identityCache)
              .values({ docType: type, docNumber: numero, data: data as object })
              .onConflictDoUpdate({ target: [identityCache.docType, identityCache.docNumber], set: { data: data as object, fetchedAt: new Date() } }),
          );
          return data;
        }
      } catch (e) {
        if (!(e instanceof LookupUnavailableError)) throw e;
        unavailable = true;
      }
    }
    if (hit) return hit.data as T; // mejor un dato algo viejo que nada
    if (type === 'dni' && remote.length === 0) {
      throw new HttpException({ message: 'Consulta de DNI no configurada. Ingresa el nombre a mano.', code: 'LOOKUP_UNAVAILABLE' }, HttpStatus.SERVICE_UNAVAILABLE);
    }
    if (unavailable) {
      throw new HttpException({ message: 'El servicio de consulta no responde. Ingresa los datos a mano.', code: 'LOOKUP_UNAVAILABLE' }, HttpStatus.SERVICE_UNAVAILABLE);
    }
    throw new NotFoundException({ message: `No se encontró el ${type.toUpperCase()} ${numero}`, code: 'NOT_FOUND' });
  }
}
