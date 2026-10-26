import { Module } from '@nestjs/common';
import { APP_FILTER, APP_GUARD, APP_INTERCEPTOR } from '@nestjs/core';
import { WebSessionInterceptor } from './common/web-session.interceptor';
import { JwtModule } from '@nestjs/jwt';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { AppExceptionFilter } from './common/pg-error.filter';
import { ConfigModule } from './config/config.module';
import { EventsModule } from './common/events';
import { IdempotencyModule } from './common/idempotency';
import { ENV, Env } from './config/env';
import { DatabaseModule } from './database/database.module';
import { AccessModule } from './modules/access/access.module';
import { AuthGuard, PermissionsGuard } from './modules/access/guards';
import { AuditModule } from './modules/audit/audit.module';
import { AuthModule } from './modules/auth/auth.module';
import { BillingModule } from './modules/billing/billing.module';
import { SubscriptionGuard } from './modules/billing/subscription.guard';
import { CatalogModule } from './modules/catalog/catalog.module';
import { EInvoiceModule } from './modules/einvoice/einvoice.module';
import { InventoryModule } from './modules/inventory/inventory.module';
import { LookupModule } from './modules/lookup/lookup.module';
import { MessagingModule } from './modules/messaging/messaging.module';
import { CreditsModule } from './modules/credits/credits.module';
import { CustomersModule } from './modules/customers/customers.module';
import { EmailModule } from './modules/email/email.module';
import { NotificationsModule } from './modules/notifications/notifications.module';
import { SecurityModule } from './modules/security/security.module';
import { StorageModule } from './modules/storage/storage.module';
import { StorefrontModule } from './modules/storefront/storefront.module';
import { PromotionsModule } from './modules/promotions/promotions.module';
import { TransfersModule } from './modules/transfers/transfers.module';
import { PurchasingModule } from './modules/purchasing/purchasing.module';
import { ReportsModule } from './modules/reports/reports.module';
import { SalesModule } from './modules/sales/sales.module';
import { StoreModule } from './modules/store/store.module';

@Module({
  imports: [
    ConfigModule,
    DatabaseModule,
    JwtModule.registerAsync({
      global: true,
      inject: [ENV],
      // Algoritmo, emisor y audiencia fijos: un token de otro sistema con el mismo secreto no sirve aquí.
      useFactory: (env: Env) => ({
        secret: env.JWT_ACCESS_SECRET,
        signOptions: { algorithm: 'HS256', issuer: 'percha-api', audience: 'percha-app' },
        verifyOptions: { algorithms: ['HS256'], issuer: 'percha-api', audience: 'percha-app' },
      }),
    }),
    ThrottlerModule.forRoot([{ ttl: 60_000, limit: 300 }]),
    AuditModule,
    SecurityModule,
    EventsModule,
    IdempotencyModule,
    StorageModule,
    EmailModule,
    BillingModule,
    NotificationsModule,
    EInvoiceModule,
    AuthModule,
    AccessModule,
    StoreModule,
    CatalogModule,
    InventoryModule,
    SalesModule,
    PurchasingModule,
    ReportsModule,
    TransfersModule,
    LookupModule,
    MessagingModule,
    CustomersModule,
    CreditsModule,
    StorefrontModule,
    PromotionsModule,
  ],
  providers: [
    // Orden importa: primero se autentica, luego se verifican permisos.
    // Límite global por IP (además de los límites estrictos de login, PIN y consultas).
    { provide: APP_INTERCEPTOR, useClass: WebSessionInterceptor },
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    { provide: APP_GUARD, useClass: AuthGuard },
    { provide: APP_GUARD, useClass: PermissionsGuard },
    // Al final: solo se evalúa para requests ya autenticados y autorizados.
    { provide: APP_GUARD, useExisting: SubscriptionGuard },
    { provide: APP_FILTER, useClass: AppExceptionFilter },
  ],
})
export class AppModule {}
