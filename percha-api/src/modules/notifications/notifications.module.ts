import { Global, Module } from '@nestjs/common';
import { ENV, Env } from '../../config/env';
import { NotificationsController } from './notifications.controller';
import { NotificationRules } from './notification-rules';
import { NotificationsService } from './notifications.service';
import { FcmPushSender, NoopPushSender, PUSH_SENDER } from './push';

@Global()
@Module({
  controllers: [NotificationsController],
  providers: [
    {
      provide: PUSH_SENDER,
      inject: [ENV],
      useFactory: (env: Env) =>
        env.FCM_SERVICE_ACCOUNT_B64 ? new FcmPushSender(JSON.parse(Buffer.from(env.FCM_SERVICE_ACCOUNT_B64, 'base64').toString('utf8'))) : new NoopPushSender(),
    },
    NotificationsService,
    NotificationRules,
  ],
  exports: [NotificationsService],
})
export class NotificationsModule {}
