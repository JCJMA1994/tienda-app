import { Global, Module } from '@nestjs/common';
import { ApprovalService } from './approval.service';
import { RolesController } from './roles.controller';
import { TeamController } from './team.controller';
import { TeamService } from './team.service';

@Global()
@Module({
  controllers: [TeamController, RolesController],
  providers: [TeamService, ApprovalService],
  exports: [ApprovalService],
})
export class AccessModule {}
