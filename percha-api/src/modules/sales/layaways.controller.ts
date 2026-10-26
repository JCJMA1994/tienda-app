import { IdempotencyKey } from '../../common/idempotency';
import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { z } from 'zod';
import { AuthUser, CurrentUser } from '../../common/auth-user';
import { ZodPipe } from '../../common/zod.pipe';
import { RequirePermissions } from '../../common/authz/decorators';
import { GiftCardsService, SellGiftCardSchema } from './giftcards.service';
import {
  CancelLayawaySchema,
  CompleteLayawaySchema,
  CreateLayawaySchema,
  LayawayPaymentSchema,
  LayawaysService,
  ListLayawaysSchema,
} from './layaways.service';

@Controller()
export class LayawaysController {
  constructor(
    private readonly layaways: LayawaysService,
    private readonly giftCards: GiftCardsService,
  ) {}

  @Get('layaways')
  @RequirePermissions('sales.read')
  list(@CurrentUser() u: AuthUser, @Query(new ZodPipe(ListLayawaysSchema)) q: z.infer<typeof ListLayawaysSchema>) {
    return this.layaways.list(u, q);
  }

  @Get('layaways/:id')
  @RequirePermissions('sales.read')
  get(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.layaways.get(u, id);
  }

  @Post('layaways')
  @RequirePermissions('sales.create')
  create(@CurrentUser() u: AuthUser, @Body(new ZodPipe(CreateLayawaySchema)) b: z.infer<typeof CreateLayawaySchema>, @IdempotencyKey() idempotencyKey?: string) {
    return this.layaways.create(u, b, idempotencyKey);
  }

  @Post('layaways/:id/payments')
  @HttpCode(200)
  @RequirePermissions('sales.create')
  pay(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new ZodPipe(LayawayPaymentSchema)) b: z.infer<typeof LayawayPaymentSchema>, @IdempotencyKey() idempotencyKey?: string) {
    return this.layaways.pay(u, id, b, idempotencyKey);
  }

  @Post('layaways/:id/complete')
  @HttpCode(200)
  @RequirePermissions('sales.create')
  complete(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new ZodPipe(CompleteLayawaySchema)) b: z.infer<typeof CompleteLayawaySchema>) {
    return this.layaways.complete(u, id, b);
  }

  /** Cancelar devuelve dinero: mismo permiso que una devolución. */
  @Post('layaways/:id/cancel')
  @HttpCode(200)
  @RequirePermissions('sales.return')
  cancel(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new ZodPipe(CancelLayawaySchema)) b: z.infer<typeof CancelLayawaySchema>) {
    return this.layaways.cancel(u, id, b);
  }

  @Post('gift-cards')
  @RequirePermissions('sales.create')
  sellGiftCard(@CurrentUser() u: AuthUser, @Body(new ZodPipe(SellGiftCardSchema)) b: z.infer<typeof SellGiftCardSchema>, @IdempotencyKey() idempotencyKey?: string) {
    return this.giftCards.sell(u, b, idempotencyKey);
  }
}
