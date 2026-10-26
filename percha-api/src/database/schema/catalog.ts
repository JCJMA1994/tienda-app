import {
  boolean,
  index,
  integer,
  jsonb,
  pgTable,
  text,
  unique,
  uuid,
} from 'drizzle-orm/pg-core';
import { createdAt, id, tenantFk, updatedAt } from './_helpers';
import { tenants } from './identity';

export const categories = pgTable(
  'categories',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    name: text('name').notNull(),
    createdAt: createdAt(),
  },
  (t) => [
    unique('categories_tenant_id_uq').on(t.tenantId, t.id),
    unique('categories_tenant_name_uq').on(t.tenantId, t.name),
  ],
);

export type AttributeValue = { value: string; code: string };

/**
 * Atributos de variante definidos por cada tienda (Talla, Color, Material...).
 * `code` de cada valor se usa para construir el SKU (VST-014-M-NEG).
 */
export const attributes = pgTable(
  'attributes',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    name: text('name').notNull(),
    position: integer('position').notNull().default(0),
    values: jsonb('values').$type<AttributeValue[]>().notNull().default([]),
    createdAt: createdAt(),
  },
  (t) => [unique('attributes_tenant_name_uq').on(t.tenantId, t.name)],
);

/** Producto "padre": nombre, precio base y categoría. El stock vive en las variantes. */
export const products = pgTable(
  'products',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    categoryId: uuid('category_id'),
    name: text('name').notNull(),
    skuBase: text('sku_base').notNull(),
    description: text('description'),
    season: text('season'),
    priceCents: integer('price_cents').notNull(),
    costCents: integer('cost_cents').notNull().default(0),
    imageUrl: text('image_url'),
    active: boolean('active').notNull().default(true),
    /** Visible en el catálogo público de la tienda. */
    published: boolean('published').notNull().default(false),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [
    unique('products_tenant_id_uq').on(t.tenantId, t.id),
    unique('products_tenant_sku_uq').on(t.tenantId, t.skuBase),
    tenantFk('products_category_fk', [t.tenantId, t.categoryId], [categories.tenantId, categories.id]),
    index('products_tenant_name_idx').on(t.tenantId, t.name),
  ],
);

/** Variante vendible: combinación de atributos con SKU y código de barras propios. */
export const variants = pgTable(
  'variants',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    productId: uuid('product_id').notNull(),
    sku: text('sku').notNull(),
    barcode: text('barcode').notNull(),
    /** Ej: { "Talla": "M", "Color": "Negro" } */
    options: jsonb('options').$type<Record<string, string>>().notNull(),
    /** null = usa el precio del producto. */
    priceCents: integer('price_cents'),
    /** Costo promedio ponderado, recalculado en cada recepción. */
    avgCostCents: integer('avg_cost_cents').notNull().default(0),
    active: boolean('active').notNull().default(true),
    createdAt: createdAt(),
  },
  (t) => [
    unique('variants_tenant_id_uq').on(t.tenantId, t.id),
    unique('variants_tenant_sku_uq').on(t.tenantId, t.sku),
    unique('variants_tenant_barcode_uq').on(t.tenantId, t.barcode),
    tenantFk('variants_product_fk', [t.tenantId, t.productId], [products.tenantId, products.id]),
    index('variants_product_idx').on(t.productId),
  ],
);

/**
 * Fotos de producto. Se guardan procesadas (sin metadatos como GPS, en WebP) en el almacén de
 * objetos: `key` (1200 px) y `thumbKey` (400 px). Opcionalmente asociadas a un valor de
 * atributo (p. ej. Color = Negro) para mostrar la foto correcta de cada variante.
 */
export const productImages = pgTable(
  'product_images',
  {
    id: id(),
    tenantId: uuid('tenant_id').notNull().references(() => tenants.id),
    productId: uuid('product_id').notNull(),
    key: text('key').notNull(),
    thumbKey: text('thumb_key').notNull(),
    width: integer('width').notNull(),
    height: integer('height').notNull(),
    position: integer('position').notNull().default(0),
    /** Valor de atributo al que corresponde (p. ej. "Negro"); null = foto general. */
    optionValue: text('option_value'),
    createdAt: createdAt(),
  },
  (t) => [
    tenantFk('product_images_product_fk', [t.tenantId, t.productId], [products.tenantId, products.id]),
    index('product_images_product_idx').on(t.productId, t.position),
  ],
);
