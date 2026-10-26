import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Put } from '@nestjs/common';
import { z } from 'zod';
import { AuthUser, CurrentUser } from '../../common/auth-user';
import { RequirePermissions } from '../../common/authz/decorators';
import { ZodPipe } from '../../common/zod.pipe';
import { PromotionSchema, PromotionsService } from './promotions.service';

@Controller('promotions')
export class PromotionsController {
  constructor(private readonly promos: PromotionsService) {}

  /** Lectura: también la necesita el POS (para mostrar el total correcto). */
  @Get()
  @RequirePermissions('sales.create')
  list(@CurrentUser() u: AuthUser) {
    return this.promos.list(u);
  }

  @Post()
  @RequirePermissions('catalog.write')
  create(@CurrentUser() u: AuthUser, @Body(new ZodPipe(PromotionSchema)) b: z.infer<typeof PromotionSchema>) {
    return this.promos.create(u, b);
  }

  @Put(':id')
  @RequirePermissions('catalog.write')
  update(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new ZodPipe(PromotionSchema)) b: z.infer<typeof PromotionSchema>) {
    return this.promos.update(u, id, b);
  }
}
