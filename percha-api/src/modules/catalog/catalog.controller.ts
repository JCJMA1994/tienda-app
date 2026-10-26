import { Body, Controller, Delete, Get, Param, ParseUUIDPipe, Patch, Post, Put, Query } from '@nestjs/common';
import { z } from 'zod';
import { AuthUser, CurrentUser } from '../../common/auth-user';
import { ZodPipe } from '../../common/zod.pipe';
import { RequirePermissions } from '../../common/authz/decorators';
import {
  AddVariantsSchema,
  AttributeSchema,
  CatalogService,
  CategorySchema,
  CreateProductSchema,
  ListProductsSchema,
  UpdateProductSchema,
  UpdateVariantSchema,
} from './catalog.service';
import { ImagesService } from './images.service';
import { ImportSchema, ImportService } from './import.service';

const LookupSchema = z.object({ code: z.string().trim().min(1).max(40), branchId: z.string().uuid().optional() });

@Controller()
export class CatalogController {
  constructor(
    private readonly catalog: CatalogService,
    private readonly importer: ImportService,
    private readonly images: ImagesService,
  ) {}

  // Atributos
  @Get('attributes')
  @RequirePermissions('catalog.read')
  attributes(@CurrentUser() u: AuthUser) {
    return this.catalog.listAttributes(u);
  }

  @Post('attributes')
  @RequirePermissions('catalog.write')
  createAttribute(@CurrentUser() u: AuthUser, @Body(new ZodPipe(AttributeSchema)) b: z.infer<typeof AttributeSchema>) {
    return this.catalog.createAttribute(u, b);
  }

  @Put('attributes/:id')
  @RequirePermissions('catalog.write')
  updateAttribute(
    @CurrentUser() u: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body(new ZodPipe(AttributeSchema.partial())) b: Partial<z.infer<typeof AttributeSchema>>,
  ) {
    return this.catalog.updateAttribute(u, id, b);
  }

  // Categorías
  @Get('categories')
  @RequirePermissions('catalog.read')
  categories(@CurrentUser() u: AuthUser) {
    return this.catalog.listCategories(u);
  }

  @Post('categories')
  @RequirePermissions('catalog.write')
  createCategory(@CurrentUser() u: AuthUser, @Body(new ZodPipe(CategorySchema)) b: z.infer<typeof CategorySchema>) {
    return this.catalog.createCategory(u, b);
  }

  @Patch('categories/:id')
  @RequirePermissions('catalog.write')
  updateCategory(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new ZodPipe(CategorySchema)) b: z.infer<typeof CategorySchema>) {
    return this.catalog.updateCategory(u, id, b);
  }

  // Productos
  @Get('products')
  @RequirePermissions('catalog.read')
  list(@CurrentUser() u: AuthUser, @Query(new ZodPipe(ListProductsSchema)) q: z.infer<typeof ListProductsSchema>) {
    return this.catalog.listProducts(u, q);
  }

  @Post('products')
  @RequirePermissions('catalog.write')
  create(@CurrentUser() u: AuthUser, @Body(new ZodPipe(CreateProductSchema)) b: z.infer<typeof CreateProductSchema>) {
    return this.catalog.createProduct(u, b);
  }

  /** Sube una foto: el cuerpo es la imagen (image/jpeg, image/png, image/webp o image/heic). */
  @Post('products/:id/images')
  @RequirePermissions('catalog.write')
  addImage(
    @CurrentUser() u: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() body: Buffer,
    @Query(new ZodPipe(z.object({ option: z.string().max(60).optional() }))) q: { option?: string },
  ) {
    return this.images.add(u, id, Buffer.isBuffer(body) ? body : undefined, q.option);
  }

  @Delete('products/:id/images/:imageId')
  @RequirePermissions('catalog.write')
  removeImage(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Param('imageId', ParseUUIDPipe) imageId: string) {
    return this.images.remove(u, id, imageId);
  }

  @Put('products/:id/images/order')
  @RequirePermissions('catalog.write')
  reorderImages(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new ZodPipe(z.object({ ids: z.array(z.string().uuid()).max(8) }))) b: { ids: string[] }) {
    return this.images.reorder(u, id, b.ids);
  }

  @Get('products/:id')
  @RequirePermissions('catalog.read')
  get(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.catalog.getProduct(u, id);
  }

  @Patch('products/:id')
  @RequirePermissions('catalog.write')
  update(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new ZodPipe(UpdateProductSchema)) b: z.infer<typeof UpdateProductSchema>) {
    return this.catalog.updateProduct(u, id, b);
  }

  @Post('products/:id/variants')
  @RequirePermissions('catalog.write')
  addVariants(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new ZodPipe(AddVariantsSchema)) b: z.infer<typeof AddVariantsSchema>) {
    return this.catalog.addVariants(u, id, b);
  }

  @Patch('variants/:id')
  @RequirePermissions('catalog.write')
  updateVariant(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body(new ZodPipe(UpdateVariantSchema)) b: z.infer<typeof UpdateVariantSchema>) {
    return this.catalog.updateVariant(u, id, b);
  }

  @Get('variants/lookup')
  @RequirePermissions('catalog.read')
  lookup(@CurrentUser() u: AuthUser, @Query(new ZodPipe(LookupSchema)) q: z.infer<typeof LookupSchema>) {
    return this.catalog.lookup(u, q.code, q.branchId);
  }

  @Post('catalog/import')
  @RequirePermissions('catalog.write')
  import(@CurrentUser() u: AuthUser, @Body(new ZodPipe(ImportSchema)) b: z.infer<typeof ImportSchema>) {
    return this.importer.run(u, b);
  }
}
