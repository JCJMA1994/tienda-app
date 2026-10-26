import { Global, Module } from '@nestjs/common';
import { ENV, Env } from '../../config/env';
import { LookupController } from './lookup.controller';
import { LookupService } from './lookup.service';
import { DatabaseService } from '../../database/database.service';
import { PadronProvider } from './padron.provider';
import { ApachiyClient } from '../integrations/apachiy.client';
import { ApachiyCpeValidator, CPE_VALIDATOR, FakeCpeValidator } from './cpe';
import { ApachiyIdentityProvider, DecolectaProvider, FakeIdentityProvider, IDENTITY_PROVIDERS, IdentityProvider, PeruConsultApiProvider } from './providers';

@Global()
@Module({
  controllers: [LookupController],
  providers: [
    {
      // Orden: padrón SUNAT local (gratis) → Apachiy → decolecta (plan gratuito o pagado) → peru-consult
      // autoalojado (respaldo). Solo se registran las que tengan configuración.
      provide: IDENTITY_PROVIDERS,
      inject: [ENV, DatabaseService],
      useFactory: (env: Env, db: DatabaseService): IdentityProvider[] => [
        new PadronProvider(db),
        ...(env.LOOKUP_FAKE ? [new FakeIdentityProvider()] : []),
        ...(env.APACHIY_TOKEN ? [new ApachiyIdentityProvider(new ApachiyClient(env.APACHIY_BASE_URL, env.APACHIY_TOKEN))] : []),
        ...(env.DECOLECTA_TOKEN ? [new DecolectaProvider(env.DECOLECTA_TOKEN)] : []),
        ...(env.PERU_CONSULT_URL && env.PERU_CONSULT_TOKEN ? [new PeruConsultApiProvider(env.PERU_CONSULT_URL, env.PERU_CONSULT_TOKEN)] : []),
      ],
    },
    {
      provide: CPE_VALIDATOR,
      inject: [ENV],
      useFactory: (env: Env) =>
        env.LOOKUP_FAKE ? new FakeCpeValidator() : env.APACHIY_TOKEN ? new ApachiyCpeValidator(new ApachiyClient(env.APACHIY_BASE_URL, env.APACHIY_TOKEN)) : null,
    },
    LookupService,
  ],
  exports: [LookupService, CPE_VALIDATOR],
})
export class LookupModule {}
