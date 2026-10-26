import type { EDoc } from '../document';
import type { EGuide } from '../guide';
import { EInvoiceProvider, OseResult, OseUnavailableError } from './provider';

/**
 * OSE simulado (solo con EINVOICE_FAKE=true). Rechaza si el cliente se llama "RECHAZO" y
 * simula una caída mientras `FakeOse.down` sea true. Guarda lo recibido para inspeccionarlo.
 */
export class FakeOse implements EInvoiceProvider {
  static down = false;
  static received: EDoc[] = [];
  static guides: EGuide[] = [];
  readonly name = 'fake';

  async send(doc: EDoc): Promise<OseResult> {
    if (FakeOse.down) throw new OseUnavailableError('OSE simulado caído');
    FakeOse.received.push(doc);
    if (doc.customer.name.includes('RECHAZO')) return { state: 'rejected', description: 'El RUC del receptor no existe (simulado)' };
    return { state: 'accepted', description: `${doc.serie}-${doc.numero} aceptado (simulado)`, pdfUrl: `https://ose.example/${doc.serie}-${doc.numero}.pdf`, hash: 'hash-simulado' };
  }

  async sendGuide(g: EGuide): Promise<OseResult> {
    if (FakeOse.down) throw new OseUnavailableError('OSE simulado caído');
    FakeOse.guides.push(g);
    return { state: 'accepted', description: `Guía ${g.serie}-${g.numero} aceptada (simulado)`, pdfUrl: `https://ose.example/${g.serie}-${g.numero}.pdf` };
  }

  async queryGuide(g: EGuide): Promise<OseResult | null> {
    return FakeOse.guides.some((x) => x.serie === g.serie && x.numero === g.numero) ? { state: 'accepted' } : null;
  }

  async query(doc: EDoc): Promise<OseResult | null> {
    const found = FakeOse.received.find((d) => d.serie === doc.serie && d.numero === doc.numero);
    return found ? { state: 'accepted', description: 'consultado (simulado)' } : null;
  }
}
