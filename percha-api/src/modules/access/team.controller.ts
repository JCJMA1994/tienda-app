import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Patch, Post, Put } from '@nestjs/common';
import { z } from 'zod';
import { AuthUser, CurrentUser } from '../../common/auth-user';
import { ZodPipe } from '../../common/zod.pipe';
import { RequirePermissions } from '../../common/authz/decorators';
import { InviteSchema, SetPinSchema, TeamService, UpdateMemberSchema } from './team.service';

@Controller('team')
export class TeamController {
  constructor(private readonly team: TeamService) {}

  @Get('members')
  @RequirePermissions('team.manage')
  members(@CurrentUser() user: AuthUser) {
    return this.team.listMembers(user);
  }

  @Patch('members/:id')
  @RequirePermissions('team.manage')
  update(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body(new ZodPipe(UpdateMemberSchema)) body: z.infer<typeof UpdateMemberSchema>,
  ) {
    return this.team.updateMember(user, id, body);
  }

  /** Cualquiera puede fijar su propio PIN; para otros se valida team.manage en el servicio. */
  @Put('members/:id/pin')
  @HttpCode(204)
  async pin(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body(new ZodPipe(SetPinSchema)) body: z.infer<typeof SetPinSchema>,
  ) {
    await this.team.setPin(user, id, body.pin);
  }

  @Post('invitations')
  @RequirePermissions('team.manage')
  invite(@CurrentUser() user: AuthUser, @Body(new ZodPipe(InviteSchema)) body: z.infer<typeof InviteSchema>) {
    return this.team.invite(user, body);
  }

  @Get('invitations')
  @RequirePermissions('team.manage')
  invitations(@CurrentUser() user: AuthUser) {
    return this.team.listInvitations(user);
  }

  @Delete('invitations/:id')
  @HttpCode(204)
  @RequirePermissions('team.manage')
  async revoke(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    await this.team.revokeInvitation(user, id);
  }
}
