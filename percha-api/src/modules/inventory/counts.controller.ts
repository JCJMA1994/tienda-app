import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { z } from 'zod';
import { AuthUser, CurrentUser } from '../../common/auth-user';
import { RequirePermissions } from '../../common/authz/decorators';
import { ZodPipe } from '../../common/zod.pipe';
import { ApplyCountSchema, CountsService, ScanSchema, StartCountSchema } from './counts.service';

@Controller('stock-counts')
export class CountsController {
  constructor(private readonly counts: CountsService) {}

  @Post()
  @RequirePermissions('inventory.adjust')
  start(@CurrentUser() u: AuthUser, @Body(new ZodPipe(StartCountSchema)) b: z.infer<typeof StartCountSchema>) {
    return this.counts.start(u, b);
  }

  @Get()
  @RequirePermissions('inventory.adjust')
  list(@CurrentUser() u: AuthUser, @Query(new ZodPipe(z.object({ branchId: z.string().uuid() }))) q: { branchId: string }) {
    return this.counts.list(u, q.branchId);
  }

  @Get(':id')
  @RequirePermissions('inventory.adjust')
  get(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.counts.get(u, id);
  }

  @Post(':id/items')
  @HttpCode(200)
  @RequirePermissions('inventory.adjust')
  scan(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new ZodPipe(ScanSchema)) b: z.infer<typeof ScanSchema>) {
    return this.counts.scan(u, id, b);
  }

  @Delete(':id/items/:variantId')
  @RequirePermissions('inventory.adjust')
  remove(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Param('variantId', ParseUUIDPipe) variantId: string) {
    return this.counts.removeItem(u, id, variantId);
  }

  @Post(':id/apply')
  @HttpCode(200)
  @RequirePermissions('inventory.adjust')
  apply(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new ZodPipe(ApplyCountSchema)) b: z.infer<typeof ApplyCountSchema>) {
    return this.counts.apply(u, id, b);
  }

  @Post(':id/cancel')
  @HttpCode(200)
  @RequirePermissions('inventory.adjust')
  cancel(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.counts.cancel(u, id);
  }
}
