import { IdempotencyKey } from '../../common/idempotency';
import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { z } from 'zod';
import { AuthUser, CurrentUser } from '../../common/auth-user';
import { ZodPipe } from '../../common/zod.pipe';
import { RequirePermissions } from '../../common/authz/decorators';
import { CreateTransferSchema, ListTransfersSchema, ReceiveTransferSchema, TransfersService } from './transfers.service';

@Controller('transfers')
export class TransfersController {
  constructor(private readonly transfers: TransfersService) {}

  @Get()
  @RequirePermissions('inventory.read')
  list(@CurrentUser() u: AuthUser, @Query(new ZodPipe(ListTransfersSchema)) q: z.infer<typeof ListTransfersSchema>) {
    return this.transfers.list(u, q);
  }

  @Get(':id')
  @RequirePermissions('inventory.read')
  get(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.transfers.get(u, id);
  }

  @Post()
  @RequirePermissions('inventory.adjust')
  send(@CurrentUser() u: AuthUser, @Body(new ZodPipe(CreateTransferSchema)) b: z.infer<typeof CreateTransferSchema>, @IdempotencyKey() idempotencyKey?: string) {
    return this.transfers.send(u, b, idempotencyKey);
  }

  @Post(':id/receive')
  @HttpCode(200)
  @RequirePermissions('inventory.adjust')
  receive(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new ZodPipe(ReceiveTransferSchema)) b: z.infer<typeof ReceiveTransferSchema>) {
    return this.transfers.receive(u, id, b);
  }

  @Post(':id/cancel')
  @HttpCode(200)
  @RequirePermissions('inventory.adjust')
  cancel(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.transfers.cancel(u, id);
  }
}
