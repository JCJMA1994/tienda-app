import { Module } from '@nestjs/common';
import { CountsController } from './counts.controller';
import { CountsService } from './counts.service';
import { InventoryController } from './inventory.controller';
import { InventoryService } from './inventory.service';

@Module({
  controllers: [InventoryController, CountsController],
  providers: [InventoryService, CountsService],
  exports: [InventoryService],
})
export class InventoryModule {}
