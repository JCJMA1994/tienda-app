import { Module } from '@nestjs/common';
import { InventoryModule } from '../inventory/inventory.module';
import { CatalogController } from './catalog.controller';
import { CatalogService } from './catalog.service';
import { ImagesService } from './images.service';
import { ImportService } from './import.service';

@Module({
  imports: [InventoryModule],
  controllers: [CatalogController],
  providers: [CatalogService, ImportService, ImagesService],
  exports: [CatalogService],
})
export class CatalogModule {}
