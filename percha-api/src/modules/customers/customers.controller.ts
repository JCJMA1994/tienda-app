import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Patch, Post, Query } from '@nestjs/common';
import { z } from 'zod';
import { AuthUser, CurrentUser } from '../../common/auth-user';
import { ZodPipe } from '../../common/zod.pipe';
import { RequirePermissions } from '../../common/authz/decorators';
import { CustomerSchema, CustomersService, ListCustomersSchema, UpdateCustomerSchema } from './customers.service';

@Controller('customers')
export class CustomersController {
  constructor(private readonly customers: CustomersService) {}

  @Get()
  @RequirePermissions('customers.read')
  list(@CurrentUser() u: AuthUser, @Query(new ZodPipe(ListCustomersSchema)) q: z.infer<typeof ListCustomersSchema>) {
    return this.customers.list(u, q);
  }

  @Get(':id')
  @RequirePermissions('customers.read')
  get(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.customers.get(u, id);
  }

  @Post()
  @RequirePermissions('customers.write')
  create(@CurrentUser() u: AuthUser, @Body(new ZodPipe(CustomerSchema)) b: z.infer<typeof CustomerSchema>) {
    return this.customers.create(u, b);
  }

  @Patch(':id')
  @RequirePermissions('customers.write')
  update(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new ZodPipe(UpdateCustomerSchema)) b: z.infer<typeof UpdateCustomerSchema>) {
    return this.customers.update(u, id, b);
  }

  /** Anonimizar (derecho de cancelación). Solo quien administra la tienda. */
  @Delete(':id')
  @HttpCode(200)
  @RequirePermissions('settings.manage')
  anonymize(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.customers.anonymize(u, id);
  }
}
