import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Patch, Post } from '@nestjs/common';
import { z } from 'zod';
import { AuthUser, CurrentUser } from '../../common/auth-user';
import { ZodPipe } from '../../common/zod.pipe';
import { RequirePermissions } from '../../common/authz/decorators';
import { BranchSchema, StoreService, UpdateStoreSchema } from './store.service';

@Controller()
export class StoreController {
  constructor(private readonly store: StoreService) {}

  @Get('store')
  get(@CurrentUser() user: AuthUser) {
    return this.store.get(user);
  }

  @Patch('store')
  @RequirePermissions('settings.manage')
  update(@CurrentUser() user: AuthUser, @Body(new ZodPipe(UpdateStoreSchema)) body: z.infer<typeof UpdateStoreSchema>) {
    return this.store.update(user, body);
  }

  @Get('store/onboarding')
  onboarding(@CurrentUser() user: AuthUser) {
    return this.store.onboarding(user);
  }

  @Post('store/onboarding/dismiss')
  @HttpCode(204)
  @RequirePermissions('settings.manage')
  async dismiss(@CurrentUser() user: AuthUser) {
    await this.store.dismissOnboarding(user);
  }

  @Get('branches')
  branches(@CurrentUser() user: AuthUser) {
    return this.store.listBranches(user);
  }

  @Post('branches')
  @RequirePermissions('settings.manage')
  createBranch(@CurrentUser() user: AuthUser, @Body(new ZodPipe(BranchSchema)) body: z.infer<typeof BranchSchema>) {
    return this.store.createBranch(user, body);
  }

  @Patch('branches/:id')
  @RequirePermissions('settings.manage')
  updateBranch(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body(new ZodPipe(BranchSchema.partial())) body: Partial<z.infer<typeof BranchSchema>>,
  ) {
    return this.store.updateBranch(user, id, body);
  }
}
