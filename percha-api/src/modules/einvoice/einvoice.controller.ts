import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Post, Put, Query, UseGuards } from '@nestjs/common';
import { z } from 'zod';
import { AuthUser, CurrentUser } from '../../common/auth-user';
import { ZodPipe } from '../../common/zod.pipe';
import { RequirePermissions } from '../../common/authz/decorators';
import { PlatformAdminGuard } from '../billing/admin.guard';
import { EInvoiceService, ListSchema, SettingsSchema } from './einvoice.service';

@Controller()
export class EInvoiceController {
  constructor(private readonly einvoice: EInvoiceService) {}

  /** Solo "¿emite comprobantes?": lo necesitan el POS y quien envía transferencias (guías). */
  @Get('einvoice/status')
  status(@CurrentUser() u: AuthUser) {
    return this.einvoice.status(u);
  }

  @Get('einvoice/settings')
  @RequirePermissions('settings.manage')
  settings(@CurrentUser() u: AuthUser) {
    return this.einvoice.getSettings(u);
  }

  @Put('einvoice/settings')
  @RequirePermissions('settings.manage')
  save(@CurrentUser() u: AuthUser, @Body(new ZodPipe(SettingsSchema)) b: z.infer<typeof SettingsSchema>) {
    return this.einvoice.saveSettings(u, b);
  }

  @Get('einvoices')
  @RequirePermissions('sales.read')
  list(@CurrentUser() u: AuthUser, @Query(new ZodPipe(ListSchema)) q: z.infer<typeof ListSchema>) {
    return this.einvoice.list(u, q);
  }

  /** Reintenta el envío al OSE (si ya se había enviado, primero consulta: no duplica). */
  @Post('einvoices/:id/retry')
  @HttpCode(200)
  @RequirePermissions('sales.read')
  retry(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.einvoice.retry(u, id);
  }

  /** Job de reenvío (además del cron `npm run einvoice:run`). */
  @Post('admin/einvoice/run')
  @HttpCode(200)
  @UseGuards(PlatformAdminGuard)
  run() {
    return this.einvoice.run();
  }
}
