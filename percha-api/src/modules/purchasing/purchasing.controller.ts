import { IdempotencyKey } from '../../common/idempotency';
import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Patch, Post, Query } from '@nestjs/common';
import { z } from 'zod';
import { AuthUser, CurrentUser } from '../../common/auth-user';
import { ZodPipe } from '../../common/zod.pipe';
import { ReplenishmentService, SuggestionsQuerySchema } from './replenishment.service';
import { RequirePermissions } from '../../common/authz/decorators';
import { CreatePoSchema, ListPoSchema, PurchasingService, ReceiveSchema, SupplierSchema, UpdatePoSchema } from './purchasing.service';

@Controller()
export class PurchasingController {
  constructor(
    private readonly purchasing: PurchasingService,
    private readonly replenishment: ReplenishmentService,
  ) {}

  @Get('suppliers')
  @RequirePermissions('purchasing.read')
  suppliers(@CurrentUser() u: AuthUser) {
    return this.purchasing.listSuppliers(u);
  }

  @Post('suppliers')
  @RequirePermissions('purchasing.write')
  createSupplier(@CurrentUser() u: AuthUser, @Body(new ZodPipe(SupplierSchema)) b: z.infer<typeof SupplierSchema>) {
    return this.purchasing.createSupplier(u, b);
  }

  @Patch('suppliers/:id')
  @RequirePermissions('purchasing.write')
  updateSupplier(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new ZodPipe(SupplierSchema.partial())) b: Partial<z.infer<typeof SupplierSchema>>) {
    return this.purchasing.updateSupplier(u, id, b);
  }

  /** Reposición sugerida por talla y color, agrupada por proveedor. */
  @Get('purchasing/suggestions')
  @RequirePermissions('purchasing.write')
  suggestions(@CurrentUser() u: AuthUser, @Query(new ZodPipe(SuggestionsQuerySchema)) q: z.infer<typeof SuggestionsQuerySchema>) {
    return this.replenishment.suggestions(u, q);
  }

  @Get('purchase-orders')
  @RequirePermissions('purchasing.read')
  list(@CurrentUser() u: AuthUser, @Query(new ZodPipe(ListPoSchema)) q: z.infer<typeof ListPoSchema>) {
    return this.purchasing.list(u, q);
  }

  @Post('purchase-orders')
  @RequirePermissions('purchasing.write')
  create(@CurrentUser() u: AuthUser, @Body(new ZodPipe(CreatePoSchema)) b: z.infer<typeof CreatePoSchema>) {
    return this.purchasing.create(u, b);
  }

  @Get('purchase-orders/:id')
  @RequirePermissions('purchasing.read')
  get(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.purchasing.get(u, id);
  }

  @Patch('purchase-orders/:id')
  @RequirePermissions('purchasing.write')
  update(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new ZodPipe(UpdatePoSchema)) b: z.infer<typeof UpdatePoSchema>) {
    return this.purchasing.update(u, id, b);
  }

  @Post('purchase-orders/:id/confirm')
  @HttpCode(200)
  @RequirePermissions('purchasing.write')
  confirm(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.purchasing.confirm(u, id);
  }

  @Post('purchase-orders/:id/cancel')
  @HttpCode(200)
  @RequirePermissions('purchasing.write')
  cancel(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.purchasing.cancel(u, id);
  }

  @Post('purchase-orders/:id/receipts')
  @RequirePermissions('purchasing.receive')
  receive(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new ZodPipe(ReceiveSchema)) b: z.infer<typeof ReceiveSchema>, @IdempotencyKey() idempotencyKey?: string) {
    return this.purchasing.receive(u, id, b, idempotencyKey);
  }

  @Get('purchase-orders/:id/receipts')
  @RequirePermissions('purchasing.read')
  receipts(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.purchasing.receipts(u, id);
  }
}
