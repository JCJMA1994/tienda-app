import { Global, Module } from '@nestjs/common';
import { ENV, Env } from '../../config/env';
import { PlatformAdminGuard } from './admin.guard';
import { AdminService } from './admin.service';
import { AdminController, BillingController } from './billing.controller';
import { BillingService } from './billing.service';
import { LimitsService } from './limits.service';
import { CulqiProvider } from './providers/culqi.provider';
import { FakeProvider } from './providers/fake.provider';
import { PAYMENT_PROVIDERS, PaymentProvider } from './providers/provider';
import { StripeProvider } from './providers/stripe.provider';
import { SubscriptionGuard } from './subscription.guard';

/** Solo se registran las pasarelas con llaves configuradas. */
function providersFrom(env: Env): PaymentProvider[] {
  const list: PaymentProvider[] = [];
  if (env.CULQI_SECRET_KEY && env.CULQI_PUBLIC_KEY) list.push(new CulqiProvider(env.CULQI_SECRET_KEY, env.CULQI_PUBLIC_KEY));
  if (env.STRIPE_SECRET_KEY && env.STRIPE_WEBHOOK_SECRET) list.push(new StripeProvider(env.STRIPE_SECRET_KEY, env.STRIPE_WEBHOOK_SECRET, env.APP_URL));
  if (env.BILLING_FAKE_SECRET) list.push(new FakeProvider(env.BILLING_FAKE_SECRET));
  return list;
}

@Global()
@Module({
  controllers: [BillingController, AdminController],
  providers: [
    { provide: PAYMENT_PROVIDERS, inject: [ENV], useFactory: providersFrom },
    BillingService,
    LimitsService,
    AdminService,
    PlatformAdminGuard,
    SubscriptionGuard,
  ],
  exports: [BillingService, LimitsService, SubscriptionGuard],
})
export class BillingModule {}
