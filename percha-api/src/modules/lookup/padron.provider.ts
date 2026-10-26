import { eq } from 'drizzle-orm';
import type { DatabaseService } from '../../database/database.service';
import { sunatPadron } from '../../database/schema';
import type { CompanyInfo, IdentityProvider } from './providers';

/**
 * RUC desde el PADRÓN REDUCIDO de SUNAT cargado en nuestra BD: oficial, gratuito, sin
 * límites de consultas y sin depender de terceros. Se actualiza con `npm run padron:import`
 * (SUNAT lo publica a diario). No incluye DNI: para eso no existe una fuente pública gratuita.
 */
export class PadronProvider implements IdentityProvider {
  readonly name = 'sunat-padron';
  /** Ya es una tabla local: no tiene sentido cachearla otra vez. */
  readonly local = true;

  constructor(private readonly db: DatabaseService) {}

  async dni() {
    return null;
  }

  async ruc(numero: string): Promise<CompanyInfo | null> {
    const [row] = await this.db.withSystem((tx) => tx.select().from(sunatPadron).where(eq(sunatPadron.ruc, numero)));
    return row ? { ruc: row.ruc, name: row.name, address: row.address, status: row.status, condition: row.condition } : null;
  }
}
