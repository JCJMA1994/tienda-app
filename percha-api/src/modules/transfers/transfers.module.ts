import { Module } from '@nestjs/common';
import { InventoryModule } from '../inventory/inventory.module';
import { TransfersController } from './transfers.controller';
import { TransfersService } from './transfers.service';

@Module({ imports: [InventoryModule], controllers: [TransfersController], providers: [TransfersService] })
export class TransfersModule {}
