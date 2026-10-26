import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Post, Put } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { z } from 'zod';
import { AuthUser, CurrentUser } from '../../common/auth-user';
import { ZodPipe } from '../../common/zod.pipe';
import { RequirePermissions } from '../../common/authz/decorators';
import { MessagingService, MessagingSettingsSchema, SendReceiptSchema } from './messaging.service';

@Controller()
export class MessagingController {
  constructor(private readonly messaging: MessagingService) {}

  @Get('messaging/status')
  @RequirePermissions('sales.create')
  status(@CurrentUser() u: AuthUser) {
    return this.messaging.status(u);
  }

  @Get('messaging/settings')
  @RequirePermissions('settings.manage')
  settings(@CurrentUser() u: AuthUser) {
    return this.messaging.getSettings(u);
  }

  @Put('messaging/settings')
  @RequirePermissions('settings.manage')
  save(@CurrentUser() u: AuthUser, @Body(new ZodPipe(MessagingSettingsSchema)) b: z.infer<typeof MessagingSettingsSchema>) {
    return this.messaging.saveSettings(u, b);
  }

  @Post('sales/:id/whatsapp')
  @HttpCode(200)
  @RequirePermissions('sales.create')
  @Throttle({ default: { limit: 20, ttl: 60_000 } })
  send(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new ZodPipe(SendReceiptSchema)) b: z.infer<typeof SendReceiptSchema>) {
    return this.messaging.sendSaleReceipt(u, id, b);
  }
}
