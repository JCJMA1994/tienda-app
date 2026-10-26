import { Body, Controller, Get, Headers, HttpCode, Param, ParseUUIDPipe, Patch, Post, Query, Req, Res, UseGuards } from '@nestjs/common';
import type { RawBodyRequest } from '@nestjs/common';
import type { Request, Response } from 'express';
import { culqiCardSetupPage, culqiPayPage } from './pay-page';
import { SkipThrottle } from '@nestjs/throttler';
import { z } from 'zod';
import { AuthUser, CurrentUser } from '../../common/auth-user';
import { ZodPipe } from '../../common/zod.pipe';
import { Public, RequirePermissions } from '../../common/authz/decorators';
import { PlatformAdminGuard } from './admin.guard';
import { AdminService, AdminUpdateTenantSchema, MarkPaidSchema } from './admin.service';
import { BillingService, ChangePlanSchema, PaySchema, SaveCardSchema } from './billing.service';

/** CSP de las páginas de Culqi: solo sus scripts y llamadas a nuestra propia API. */
const CULQI_CSP =
  "default-src 'self'; script-src 'self' 'unsafe-inline' https://js.culqi.com https://*.culqi.com; frame-src https://*.culqi.com; connect-src 'self' https://*.culqi.com; img-src * data:; style-src 'self' 'unsafe-inline' https:";

const CardSetupSchema = SaveCardSchema.extend({ t: z.string().min(20) });

@Controller('billing')
export class BillingController {
  constructor(private readonly billing: BillingService) {}

  /** Cualquier miembro ve el estado (para mostrar avisos); solo el dueño paga o cambia el plan. */
  @Get()
  overview(@CurrentUser() u: AuthUser) {
    return this.billing.overview(u);
  }

  @Get('plans')
  plans() {
    return this.billing.plans();
  }

  @Post('plan')
  @HttpCode(200)
  @RequirePermissions('billing.manage')
  changePlan(@CurrentUser() u: AuthUser, @Body(new ZodPipe(ChangePlanSchema)) b: z.infer<typeof ChangePlanSchema>) {
    return this.billing.changePlan(u, b.planCode);
  }

  @Post('invoices/:id/pay')
  @HttpCode(200)
  @RequirePermissions('billing.manage')
  pay(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new ZodPipe(PaySchema)) b: z.infer<typeof PaySchema>) {
    return this.billing.pay(u, id, b);
  }

  @Post('card')
  @HttpCode(200)
  @RequirePermissions('billing.manage')
  saveCard(@CurrentUser() u: AuthUser, @Body(new ZodPipe(SaveCardSchema)) b: z.infer<typeof SaveCardSchema>) {
    return this.billing.saveCard(u, b);
  }

  /** Enlace para registrar la tarjeta en el navegador (cobro automático). */
  @Post('card/setup-link')
  @HttpCode(200)
  @RequirePermissions('billing.manage')
  cardSetupLink(@CurrentUser() u: AuthUser) {
    return this.billing.cardSetupLink(u);
  }

  @Public()
  @Get('card-setup')
  cardSetupPage(@Query('t') t: string, @Res() res: Response) {
    const data = this.billing.cardSetupPageData(t);
    res
      .status(200)
      .setHeader('Content-Type', 'text/html; charset=utf-8')
      .setHeader('Cache-Control', 'no-store')
      .setHeader('Content-Security-Policy', CULQI_CSP)
      .send(culqiCardSetupPage(data));
  }

  /** La página envía aquí el token de Culqi.js. Autoriza el enlace firmado, no una sesión. */
  @Public()
  @Post('card-setup')
  @HttpCode(200)
  completeCardSetup(@Body(new ZodPipe(CardSetupSchema)) b: z.infer<typeof CardSetupSchema>) {
    const { t, ...card } = b;
    return this.billing.completeCardSetup(t, card);
  }

  @Post('cancel')
  @HttpCode(200)
  @RequirePermissions('billing.manage')
  cancel(@CurrentUser() u: AuthUser) {
    return this.billing.setCancel(u, true);
  }

  @Post('resume')
  @HttpCode(200)
  @RequirePermissions('billing.manage')
  resume(@CurrentUser() u: AuthUser) {
    return this.billing.setCancel(u, false);
  }

  /**
   * Página que abre la app para pagar con Culqi Checkout (Yape, billeteras, agentes).
   * Pública pero protegida por un enlace firmado de 1 hora. CSP propia: solo permite los
   * scripts de Culqi en esta página.
   */
  @Public()
  @Get('pay/:invoiceId')
  async payPage(@Param('invoiceId', ParseUUIDPipe) id: string, @Query('t') token: string, @Res() res: Response) {
    const data = await this.billing.payPageData(id, token ?? '');
    res
      .status(200)
      .setHeader('Content-Type', 'text/html; charset=utf-8')
      .setHeader('Cache-Control', 'no-store')
      .setHeader('Content-Security-Policy', CULQI_CSP)
      .send(culqiPayPage(data));
  }

  /**
   * Webhooks de las pasarelas. Públicos, pero cada adaptador verifica la autenticidad
   * (firma HMAC en Stripe y la simulada; consulta de vuelta a la API en Culqi).
   * Necesitan el cuerpo CRUDO: main.ts crea la app con rawBody: true.
   */
  @Public()
  @SkipThrottle()
  @Post('webhooks/:provider')
  @HttpCode(200)
  webhook(@Param('provider') provider: string, @Req() req: RawBodyRequest<Request>, @Headers() headers: Record<string, string>) {
    if (!['culqi', 'stripe', 'fake'].includes(provider)) return { ignored: true };
    return this.billing.handleWebhook(provider as 'culqi' | 'stripe' | 'fake', req.rawBody, headers);
  }
}

const RunSchema = z.object({ now: z.string().datetime().optional() });

@Controller('admin')
@UseGuards(PlatformAdminGuard)
export class AdminController {
  constructor(private readonly admin: AdminService) {}

  @Get('tenants')
  tenants() {
    return this.admin.tenants();
  }

  @Get('metrics')
  metrics() {
    return this.admin.metrics();
  }

  @Get('tenants/:id/invoices')
  invoices(@Param('id', ParseUUIDPipe) id: string) {
    return this.admin.invoices(id);
  }

  @Patch('tenants/:id')
  update(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new ZodPipe(AdminUpdateTenantSchema)) b: z.infer<typeof AdminUpdateTenantSchema>) {
    return this.admin.updateTenant(u, id, b);
  }

  @Post('invoices/:id/mark-paid')
  @HttpCode(200)
  markPaid(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new ZodPipe(MarkPaidSchema)) b: z.infer<typeof MarkPaidSchema>) {
    return this.admin.markPaid(u, id, b);
  }

  /** Dispara el ciclo de facturación (el cron llama a scripts/billing-run.mjs o a este endpoint). */
  @Post('billing/run')
  @HttpCode(200)
  run(@Body(new ZodPipe(RunSchema)) b: z.infer<typeof RunSchema>) {
    return this.admin.run(b.now);
  }
}
