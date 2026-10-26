import { Global, Module } from '@nestjs/common';
import { ENV, Env } from '../../config/env';
import { EInvoiceController } from './einvoice.controller';
import { EInvoiceHandlers } from './einvoice.handlers';
import { EInvoiceService } from './einvoice.service';
import { FakeOse } from './providers/fake.provider';
import { NubefactProvider } from './providers/nubefact.provider';
import { EINVOICE_PROVIDERS, EInvoiceProvider } from './providers/provider';

/**
 * OSE disponibles. Para sumar otro (Efact, SUNAT SEE-Del contribuyente, etc.) basta con
 * implementar EInvoiceProvider y registrarlo aquí; cada tienda elige el suyo en la configuración.
 */
@Global()
@Module({
  controllers: [EInvoiceController],
  providers: [
    {
      provide: EINVOICE_PROVIDERS,
      inject: [ENV],
      useFactory: (env: Env): EInvoiceProvider[] => [new NubefactProvider(), ...(env.EINVOICE_FAKE ? [new FakeOse()] : [])],
    },
    EInvoiceService,
    EInvoiceHandlers,
  ],
  exports: [EInvoiceService],
})
export class EInvoiceModule {}
