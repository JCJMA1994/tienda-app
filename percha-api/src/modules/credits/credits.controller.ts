import { Body, Controller, Get, Post, Query } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { z } from 'zod';
import { AuthUser, CurrentUser } from '../../common/auth-user';
import { ZodPipe } from '../../common/zod.pipe';
import { RequirePermissions } from '../../common/authz/decorators';
import { CreditsService, IssueCreditSchema } from './credits.service';

@Controller('store-credits')
export class CreditsController {
  constructor(private readonly credits: CreditsService) {}

  /** Saldo y vigencia de un vale antes de cobrar. */
  @Get('lookup')
  @RequirePermissions('sales.create')
  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  lookup(@CurrentUser() u: AuthUser, @Query(new ZodPipe(z.object({ code: z.string().min(8).max(30) }))) q: { code: string }) {
    return this.credits.lookup(u, q.code);
  }

  @Get()
  @RequirePermissions('customers.read')
  forCustomer(@CurrentUser() u: AuthUser, @Query(new ZodPipe(z.object({ customerId: z.string().uuid() }))) q: { customerId: string }) {
    return this.credits.forCustomer(u, q.customerId);
  }

  /** Vale de cortesía (sin cobro): solo quien puede anular ventas; queda en la auditoría. */
  @Post('courtesy')
  @RequirePermissions('sales.void')
  courtesy(@CurrentUser() u: AuthUser, @Body(new ZodPipe(IssueCreditSchema)) b: z.infer<typeof IssueCreditSchema>) {
    return this.credits.issueCourtesy(u, b);
  }
}
