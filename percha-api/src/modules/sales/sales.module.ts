import { Module } from '@nestjs/common';
import { InventoryModule } from '../inventory/inventory.module';
import { CashService } from './cash.service';
import { GiftCardsService } from './giftcards.service';
import { LayawaysController } from './layaways.controller';
import { LayawaysService } from './layaways.service';
import { ReturnsService } from './returns.service';
import { SalesController } from './sales.controller';
import { SalesService } from './sales.service';

@Module({
  imports: [InventoryModule],
  controllers: [SalesController, LayawaysController],
  providers: [CashService, SalesService, ReturnsService, LayawaysService, GiftCardsService],
  exports: [LayawaysService],
})
export class SalesModule {}
