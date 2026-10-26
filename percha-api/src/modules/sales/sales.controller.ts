import { IdempotencyKey } from '../../common/idempotency';
import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { z } from 'zod';
import { AuthUser, CurrentUser } from '../../common/auth-user';
import { ZodPipe } from '../../common/zod.pipe';
import { RequirePermissions } from '../../common/authz/decorators';
import { CashService, CloseCashSchema, OpenCashSchema } from './cash.service';
import { CreateReturnSchema, ReturnsService } from './returns.service';
import { CreateSaleSchema, ListSalesSchema, SalesService, VoidSaleSchema } from './sales.service';

const BranchQuery = z.object({ branchId: z.string().uuid() });

@Controller()
export class SalesController {
  constructor(
    private readonly cash: CashService,
    private readonly sales: SalesService,
    private readonly returns: ReturnsService,
  ) {}

  // Caja
  @Post('cash-sessions')
  @RequirePermissions('cash.manage')
  open(@CurrentUser() u: AuthUser, @Body(new ZodPipe(OpenCashSchema)) b: z.infer<typeof OpenCashSchema>) {
    return this.cash.open(u, b);
  }

  @Get('cash-sessions/current')
  @RequirePermissions('cash.manage')
  current(@CurrentUser() u: AuthUser, @Query(new ZodPipe(BranchQuery)) q: z.infer<typeof BranchQuery>) {
    return this.cash.current(u, q.branchId);
  }

  @Get('cash-sessions')
  @RequirePermissions('cash.manage')
  listCash(@CurrentUser() u: AuthUser, @Query(new ZodPipe(BranchQuery)) q: z.infer<typeof BranchQuery>) {
    return this.cash.list(u, q.branchId);
  }

  /** Reporte para imprimir el cierre (o un corte parcial si sigue abierta). */
  @Get('cash-sessions/:id/report')
  @RequirePermissions('cash.manage')
  cashReport(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.cash.report(u, id);
  }

  @Post('cash-sessions/:id/close')
  @HttpCode(200)
  @RequirePermissions('cash.manage')
  close(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new ZodPipe(CloseCashSchema)) b: z.infer<typeof CloseCashSchema>) {
    return this.cash.close(u, id, b);
  }

  // Ventas
  /** Total exacto (con promociones) antes de cobrar. */
  @Post('sales/quote')
  @HttpCode(200)
  @RequirePermissions('sales.create')
  quote(@CurrentUser() u: AuthUser, @Body(new ZodPipe(CreateSaleSchema.pick({ branchId: true, items: true, discountCents: true }))) b: { branchId: string; items: { variantId: string; quantity: number }[]; discountCents: number }) {
    return this.sales.quote(u, b);
  }

  @Post('sales')
  @RequirePermissions('sales.create')
  create(@CurrentUser() u: AuthUser, @Body(new ZodPipe(CreateSaleSchema)) b: z.infer<typeof CreateSaleSchema>, @IdempotencyKey() idempotencyKey?: string) {
    return this.sales.create(u, b, idempotencyKey);
  }

  @Get('sales')
  @RequirePermissions('sales.read')
  list(@CurrentUser() u: AuthUser, @Query(new ZodPipe(ListSalesSchema)) q: z.infer<typeof ListSalesSchema>) {
    return this.sales.list(u, q);
  }

  @Get('sales/:id')
  @RequirePermissions('sales.read')
  get(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.sales.get(u, id);
  }

  /** Sin @RequirePermissions('sales.void'): un vendedor puede anular con el PIN de un supervisor. */
  @Post('sales/:id/void')
  @HttpCode(200)
  @RequirePermissions('sales.create')
  void(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new ZodPipe(VoidSaleSchema)) b: z.infer<typeof VoidSaleSchema>) {
    return this.sales.void(u, id, b);
  }

  // Devoluciones y cambios
  @Post('sales/:id/returns')
  @RequirePermissions('sales.return')
  createReturn(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new ZodPipe(CreateReturnSchema)) b: z.infer<typeof CreateReturnSchema>, @IdempotencyKey() idempotencyKey?: string) {
    return this.returns.create(u, id, b, idempotencyKey);
  }

  @Get('sales/:id/returns')
  @RequirePermissions('sales.read')
  listReturns(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.returns.listForSale(u, id);
  }
}
