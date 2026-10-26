import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Post, Query, UseGuards } from '@nestjs/common';
import { z } from 'zod';
import { AuthUser, CurrentUser } from '../../common/auth-user';
import { ZodPipe } from '../../common/zod.pipe';
import { PlatformAdminGuard } from '../billing/admin.guard';
import { ListNotificationsSchema, NotificationsService, RegisterDeviceSchema } from './notifications.service';

/** Cada persona ve solo SUS notificaciones; no requiere permisos especiales. */
@Controller()
export class NotificationsController {
  constructor(private readonly notifications: NotificationsService) {}

  @Get('notifications')
  list(@CurrentUser() u: AuthUser, @Query(new ZodPipe(ListNotificationsSchema)) q: z.infer<typeof ListNotificationsSchema>) {
    return this.notifications.list(u, q);
  }

  @Get('notifications/unread-count')
  unread(@CurrentUser() u: AuthUser) {
    return this.notifications.unreadCount(u);
  }

  @Post('notifications/read-all')
  @HttpCode(200)
  readAll(@CurrentUser() u: AuthUser) {
    return this.notifications.markAllRead(u);
  }

  @Post('notifications/:id/read')
  @HttpCode(200)
  read(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.notifications.markRead(u, id);
  }

  @Post('devices')
  @HttpCode(200)
  register(@CurrentUser() u: AuthUser, @Body(new ZodPipe(RegisterDeviceSchema)) b: z.infer<typeof RegisterDeviceSchema>) {
    return this.notifications.registerDevice(u, b);
  }

  @Delete('devices/:token')
  @HttpCode(204)
  async unregister(@CurrentUser() u: AuthUser, @Param('token') token: string) {
    await this.notifications.unregisterDevice(u, token);
  }

  @Post('admin/notifications/push')
  @HttpCode(200)
  @UseGuards(PlatformAdminGuard)
  push() {
    return this.notifications.dispatchPush();
  }
}
