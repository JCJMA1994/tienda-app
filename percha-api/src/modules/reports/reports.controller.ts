import { Controller, Get, Query } from '@nestjs/common';
import { z } from 'zod';
import { AuthUser, CurrentUser } from '../../common/auth-user';
import { ZodPipe } from '../../common/zod.pipe';
import { RequirePermissions } from '../../common/authz/decorators';
import { AttributesSchema, DeadStockSchema, RangeSchema, ReportsService, TopSchema, ValuationSchema } from './reports.service';

@Controller('reports')
@RequirePermissions('reports.read')
export class ReportsController {
  constructor(private readonly reports: ReportsService) {}

  /** Comisiones por vendedora (sobre ventas netas sin IGV). */
  @Get('commissions')
  @RequirePermissions('reports.read')
  commissions(@CurrentUser() u: AuthUser, @Query(new ZodPipe(RangeSchema)) q: z.infer<typeof RangeSchema>) {
    return this.reports.commissions(u, q);
  }

  @Get('summary')
  summary(@CurrentUser() u: AuthUser, @Query(new ZodPipe(RangeSchema)) q: z.infer<typeof RangeSchema>) {
    return this.reports.summary(u, q);
  }

  @Get('daily')
  daily(@CurrentUser() u: AuthUser, @Query(new ZodPipe(RangeSchema)) q: z.infer<typeof RangeSchema>) {
    return this.reports.daily(u, q);
  }

  @Get('top-products')
  top(@CurrentUser() u: AuthUser, @Query(new ZodPipe(TopSchema)) q: z.infer<typeof TopSchema>) {
    return this.reports.topProducts(u, q);
  }

  @Get('attributes')
  attributes(@CurrentUser() u: AuthUser, @Query(new ZodPipe(AttributesSchema)) q: z.infer<typeof AttributesSchema>) {
    return this.reports.attributes(u, q);
  }

  @Get('dead-stock')
  deadStock(@CurrentUser() u: AuthUser, @Query(new ZodPipe(DeadStockSchema)) q: z.infer<typeof DeadStockSchema>) {
    return this.reports.deadStock(u, q);
  }

  @Get('valuation')
  valuation(@CurrentUser() u: AuthUser, @Query(new ZodPipe(ValuationSchema)) q: z.infer<typeof ValuationSchema>) {
    return this.reports.valuation(u, q);
  }
}
