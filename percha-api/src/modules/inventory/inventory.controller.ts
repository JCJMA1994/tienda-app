import { IdempotencyKey } from '../../common/idempotency';
import { Body, Controller, Get, Post, Put, Query } from '@nestjs/common';
import { z } from 'zod';
import { assertBranchAccess, AuthUser, CurrentUser } from '../../common/auth-user';
import { ZodPipe } from '../../common/zod.pipe';
import { RequirePermissions } from '../../common/authz/decorators';
import { AdjustmentSchema, InventoryService, MinStockSchema, MovementsQuerySchema, StockQuerySchema } from './inventory.service';

@Controller('inventory')
export class InventoryController {
  constructor(private readonly inventory: InventoryService) {}

  @Get('stock')
  @RequirePermissions('inventory.read')
  stock(@CurrentUser() user: AuthUser, @Query(new ZodPipe(StockQuerySchema)) q: z.infer<typeof StockQuerySchema>) {
    return this.inventory.stock(user, q);
  }

  @Get('movements')
  @RequirePermissions('inventory.read')
  movements(@CurrentUser() user: AuthUser, @Query(new ZodPipe(MovementsQuerySchema)) q: z.infer<typeof MovementsQuerySchema>) {
    return this.inventory.movements(user, q);
  }

  @Get('integrity')
  @RequirePermissions('inventory.adjust')
  integrity(@CurrentUser() user: AuthUser) {
    return this.inventory.integrity(user);
  }

  @Get('snapshot')
  @RequirePermissions('sales.create')
  snapshot(@CurrentUser() user: AuthUser, @Query(new ZodPipe(z.object({ branchId: z.string().uuid() }))) q: { branchId: string }) {
    assertBranchAccess(user, q.branchId);
    return this.inventory.snapshot(user, q.branchId);
  }

  @Post('adjustments')
  @RequirePermissions('inventory.adjust')
  adjust(@CurrentUser() user: AuthUser, @Body(new ZodPipe(AdjustmentSchema)) body: z.infer<typeof AdjustmentSchema>, @IdempotencyKey() idempotencyKey?: string) {
    return this.inventory.adjust(user, body, idempotencyKey);
  }

  @Put('min-stock')
  @RequirePermissions('inventory.adjust')
  minStock(@CurrentUser() user: AuthUser, @Body(new ZodPipe(MinStockSchema)) body: z.infer<typeof MinStockSchema>) {
    return this.inventory.setMinStock(user, body);
  }
}
