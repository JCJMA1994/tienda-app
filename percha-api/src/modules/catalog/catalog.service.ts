import {
  BadRequestException,
  ConflictException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { barcodeCandidates } from './barcodes';
import { and, asc, eq, ilike, inArray, or, sql } from 'drizzle-orm';
import { z } from 'zod';
import type { AuthUser } from '../../common/auth-user';
import { cents } from '../../common/schemas';
import { DatabaseService, Tx } from '../../database/database.service';
import { nextNumber } from '../../database/sequences';
import { attributes, AttributeValue, categories, products, stockLevels, variants } from '../../database/schema';
import { hasPermission } from '../../common/authz/permissions';
import { LimitsService } from '../billing/limits.service';
import { InventoryService } from '../inventory/inventory.service';
import { ImagesService } from './images.service';
import { cartesian, internalEan13, optionsKey, skuPrefix, uniqueCode } from './codes';

// ---------- esquemas ----------

export const AttributeSchema = z.object({
  name: z.string().trim().min(1).max(40),
  position: z.number().int().min(0).default(0),
  values: z
    .array(z.union([z.string().trim().min(1).max(40), z.object({ value: z.string().trim().min(1).max(40), code: z.string().trim().regex(/^[A-Z0-9]{1,6}$/).optional() })]))
    .min(1)
    .max(100),
});

export const CategorySchema = z.object({ name: z.string().trim().min(1).max(60) });

const matrix = z.record(z.string(), z.array(z.string()).min(1)).default({});

export const CreateProductSchema = z.object({
  name: z.string().trim().min(2).max(120),
  skuBase: z.string().trim().regex(/^[A-Z0-9-]{2,20}$/, 'SKU: mayúsculas, números y guiones').optional(),
  categoryId: z.string().uuid().nullable().optional(),
  description: z.string().max(2000).optional(),
  season: z.string().max(40).optional(),
  imageUrl: z.string().url().optional(),
  priceCents: cents,
  costCents: cents.default(0),
  /** Valores elegidos por atributo; se crean todas las combinaciones. Vacío = producto sin variantes. */
  matrix,
  initialStock: z
    .object({
      branchId: z.string().uuid(),
      items: z.array(z.object({ options: z.record(z.string(), z.string()), quantity: z.number().int().positive() })).min(1),
    })
    .optional(),
});

export const UpdateProductSchema = CreateProductSchema.pick({
  name: true,
  categoryId: true,
  description: true,
  season: true,
  imageUrl: true,
  priceCents: true,
  costCents: true,
})
  .extend({ active: z.boolean() })
  .partial();

export const AddVariantsSchema = z.object({ matrix });

export const UpdateVariantSchema = z
  .object({ priceCents: cents.nullable(), active: z.boolean(), barcode: z.string().regex(/^\d{8,14}$/) })
  .partial();

export const ListProductsSchema = z.object({
  search: z.string().trim().max(60).optional(),
  categoryId: z.string().uuid().optional(),
  active: z.enum(['true', 'false']).optional(),
  branchId: z.string().uuid().optional(),
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(30),
});

type AttributeRow = typeof attributes.$inferSelect;
type ProductRow = typeof products.$inferSelect;

export interface VariantSpec {
  options: Record<string, string>;
  barcode?: string;
  priceCents?: number | null;
}

@Injectable()
export class CatalogService {
  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(InventoryService) private readonly inventory: InventoryService,
    @Inject(LimitsService) private readonly limits: LimitsService,
    @Inject(ImagesService) private readonly images: ImagesService,
  ) {}

  // ---------- atributos ----------

  listAttributes(user: AuthUser) {
    return this.db.withTenant(user.tenantId, (tx) =>
      tx.select().from(attributes).orderBy(asc(attributes.position), asc(attributes.name)),
    );
  }

  createAttribute(user: AuthUser, input: z.infer<typeof AttributeSchema>) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [row] = await tx
        .insert(attributes)
        .values({ tenantId: user.tenantId, name: input.name, position: input.position, values: this.normalizeValues(input.values) })
        .returning();
      return row;
    });
  }

  /**
   * Reemplaza la lista de valores. Se puede agregar y reordenar libremente, pero no quitar
   * un valor que ya usa alguna variante (rompería SKUs y el historial de ventas).
   */
  updateAttribute(user: AuthUser, id: string, input: Partial<z.infer<typeof AttributeSchema>>) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [current] = await tx.select().from(attributes).where(eq(attributes.id, id)).for('update');
      if (!current) throw new NotFoundException('Atributo no encontrado');

      const usedCount = await tx
        .select({ c: sql<number>`count(*)::int` })
        .from(variants)
        .where(sql`${variants.options} ? ${current.name}`);
      if (input.name && input.name !== current.name && usedCount[0].c > 0) {
        throw new ConflictException('No se puede renombrar un atributo que ya usan variantes');
      }

      let values = current.values;
      if (input.values) {
        values = this.normalizeValues(input.values, current.values);
        const removed = current.values.filter((v) => !values.some((n) => n.value === v.value));
        for (const r of removed) {
          const [{ c }] = await tx
            .select({ c: sql<number>`count(*)::int` })
            .from(variants)
            .where(sql`${variants.options} ->> ${current.name} = ${r.value}`);
          if (c > 0) throw new ConflictException(`El valor "${r.value}" está en uso por ${c} variante(s)`);
        }
      }

      const [row] = await tx
        .update(attributes)
        .set({ name: input.name, position: input.position, values })
        .where(eq(attributes.id, id))
        .returning();
      return row;
    });
  }

  /** Conserva el código de valores existentes y genera códigos únicos para los nuevos. */
  normalizeValues(input: z.infer<typeof AttributeSchema>['values'], existing: AttributeValue[] = []): AttributeValue[] {
    const taken = new Set<string>();
    const seen = new Set<string>();
    const out: AttributeValue[] = [];
    const items = input.map((v) => (typeof v === 'string' ? { value: v, code: undefined } : v));
    // Primero reservamos los códigos explícitos o ya existentes.
    for (const v of items) {
      const prev = existing.find((e) => e.value === v.value);
      const code = v.code ?? prev?.code;
      if (code) {
        if (taken.has(code)) throw new BadRequestException(`Código repetido: ${code}`);
        taken.add(code);
      }
    }
    for (const v of items) {
      if (seen.has(v.value.toLowerCase())) throw new BadRequestException(`Valor repetido: ${v.value}`);
      seen.add(v.value.toLowerCase());
      const prev = existing.find((e) => e.value === v.value);
      out.push({ value: v.value, code: v.code ?? prev?.code ?? uniqueCode(v.value, taken) });
    }
    return out;
  }

  // ---------- categorías ----------

  listCategories(user: AuthUser) {
    return this.db.withTenant(user.tenantId, (tx) => tx.select().from(categories).orderBy(asc(categories.name)));
  }

  createCategory(user: AuthUser, input: z.infer<typeof CategorySchema>) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [row] = await tx.insert(categories).values({ tenantId: user.tenantId, name: input.name }).returning();
      return row;
    });
  }

  updateCategory(user: AuthUser, id: string, input: z.infer<typeof CategorySchema>) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [row] = await tx.update(categories).set(input).where(eq(categories.id, id)).returning();
      if (!row) throw new NotFoundException('Categoría no encontrada');
      return row;
    });
  }

  // ---------- productos ----------

  createProduct(user: AuthUser, input: z.infer<typeof CreateProductSchema>) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      await this.limits.assertCanAdd(tx, user.tenantId, 'products');
      const attrs = await tx.select().from(attributes);
      const combos = this.combosFromMatrix(input.matrix, attrs);
      const skuBase = input.skuBase ?? (await this.generateSkuBase(tx, user.tenantId, input.name));

      const [product] = await tx
        .insert(products)
        .values({
          tenantId: user.tenantId,
          name: input.name,
          skuBase,
          categoryId: input.categoryId ?? null,
          description: input.description,
          season: input.season,
          imageUrl: input.imageUrl,
          priceCents: input.priceCents,
          costCents: input.costCents,
        })
        .returning();

      const created = await this.insertVariants(tx, user, product, combos.map((options) => ({ options })), attrs);

      if (input.initialStock) {
        const byKey = new Map(created.map((v) => [optionsKey(v.options), v]));
        const movements = input.initialStock.items.map((item) => {
          const v = byKey.get(optionsKey(item.options));
          if (!v) throw new BadRequestException(`Stock inicial para una combinación inexistente: ${optionsKey(item.options)}`);
          return {
            variantId: v.id,
            quantity: item.quantity,
            type: 'initial' as const,
            unitCostCents: input.costCents,
            referenceType: 'product',
            referenceId: product.id,
          };
        });
        await this.inventory.apply(tx, user, input.initialStock.branchId, movements);
      }

      return this.loadProduct(tx, user, product.id);
    });
  }

  /** Agrega combinaciones nuevas (p. ej. llegó un color nuevo). Las existentes se ignoran. */
  addVariants(user: AuthUser, productId: string, input: z.infer<typeof AddVariantsSchema>) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [product] = await tx.select().from(products).where(eq(products.id, productId)).for('update');
      if (!product) throw new NotFoundException('Producto no encontrado');
      const attrs = await tx.select().from(attributes);
      const existing = await tx.select({ options: variants.options }).from(variants).where(eq(variants.productId, productId));
      const existingKeys = new Set(existing.map((e) => optionsKey(e.options)));

      const fresh = this.combosFromMatrix(input.matrix, attrs).filter((c) => !existingKeys.has(optionsKey(c)));
      const created = await this.insertVariants(tx, user, product, fresh.map((options) => ({ options })), attrs);
      return { created: created.length, variants: created };
    });
  }

  updateProduct(user: AuthUser, id: string, input: z.infer<typeof UpdateProductSchema>) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [row] = await tx.update(products).set({ ...input, updatedAt: new Date() }).where(eq(products.id, id)).returning();
      if (!row) throw new NotFoundException('Producto no encontrado');
      return this.loadProduct(tx, user, id);
    });
  }

  updateVariant(user: AuthUser, id: string, input: z.infer<typeof UpdateVariantSchema>) {
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [row] = await tx.update(variants).set(input).where(eq(variants.id, id)).returning();
      if (!row) throw new NotFoundException('Variante no encontrada');
      return this.hideCosts(user, row);
    });
  }

  listProducts(user: AuthUser, q: z.infer<typeof ListProductsSchema>) {
    const branchId = q.branchId ?? user.branchId ?? undefined;
    return this.db.withTenant(user.tenantId, async (tx) => {
      const where = and(
        q.search
          ? or(
              ilike(products.name, `%${q.search}%`),
              ilike(products.skuBase, `%${q.search}%`),
              sql`exists (select 1 from variants v where v.product_id = ${products.id} and (v.sku ilike ${'%' + q.search + '%'} or v.barcode = ${q.search}))`,
            )
          : undefined,
        q.categoryId ? eq(products.categoryId, q.categoryId) : undefined,
        q.active ? eq(products.active, q.active === 'true') : undefined,
      );
      const stockFilter = branchId ? sql`and s.branch_id = ${branchId}` : sql``;

      const rows = await tx
        .select({
          id: products.id,
          name: products.name,
          skuBase: products.skuBase,
          categoryId: products.categoryId,
          priceCents: products.priceCents,
          imageUrl: products.imageUrl,
          active: products.active,
          variantCount: sql<number>`(select count(*)::int from variants v where v.product_id = ${products.id})`,
          totalStock: sql<number>`(select coalesce(sum(s.quantity),0)::int from stock_levels s join variants v on v.id = s.variant_id where v.product_id = ${products.id} ${stockFilter})`,
          lowVariants: sql<number>`(select count(*)::int from stock_levels s join variants v on v.id = s.variant_id where v.product_id = ${products.id} and s.quantity <= s.min_quantity ${stockFilter})`,
        })
        .from(products)
        .where(where)
        .orderBy(asc(products.name))
        .limit(q.pageSize)
        .offset((q.page - 1) * q.pageSize);

      const [{ total }] = await tx.select({ total: sql<number>`count(*)::int` }).from(products).where(where);
      return { items: rows, page: q.page, pageSize: q.pageSize, total };
    });
  }

  getProduct(user: AuthUser, id: string) {
    return this.db.withTenant(user.tenantId, (tx) => this.loadProduct(tx, user, id));
  }

  /** Búsqueda para el POS: por código de barras o SKU exacto. */
  lookup(user: AuthUser, code: string, branchId?: string) {
    // Lectores y cámaras: se limpia el código y se prueba UPC-A ⇄ EAN-13.
    const codes = barcodeCandidates(code);
    return this.db.withTenant(user.tenantId, async (tx) => {
      const [row] = await tx
        .select({ variant: variants, productName: products.name, productPrice: products.priceCents, productActive: products.active })
        .from(variants)
        .innerJoin(products, eq(products.id, variants.productId))
        .where(
          or(
            inArray(variants.barcode, codes.length ? codes : ['']),
            sql`upper(${variants.sku}) = upper(${codes[0] ?? ''})`,
          ),
        )
        .limit(1);
      if (!row) throw new NotFoundException({ message: 'Código no encontrado', code: 'CODE_NOT_FOUND' });

      const bId = branchId ?? user.branchId;
      const stock = bId
        ? (
            await tx
              .select({ quantity: stockLevels.quantity })
              .from(stockLevels)
              .where(and(eq(stockLevels.variantId, row.variant.id), eq(stockLevels.branchId, bId)))
          )[0]?.quantity ?? 0
        : null;

      return {
        ...this.hideCosts(user, row.variant),
        productName: row.productName,
        effectivePriceCents: row.variant.priceCents ?? row.productPrice,
        sellable: row.variant.active && row.productActive,
        stock,
      };
    });
  }

  // ---------- helpers (también los usa ImportService) ----------

  /** Valida la matriz contra los atributos de la tienda y la expande en combinaciones. */
  combosFromMatrix(input: Record<string, string[]>, attrs: AttributeRow[]): Record<string, string>[] {
    const entries: [string, string[]][] = [];
    for (const attr of [...attrs].sort((a, b) => a.position - b.position)) {
      const chosen = input[attr.name];
      if (!chosen) continue;
      const unknown = chosen.filter((v) => !attr.values.some((av) => av.value === v));
      if (unknown.length) throw new BadRequestException(`Valores no definidos en "${attr.name}": ${unknown.join(', ')}`);
      entries.push([attr.name, [...new Set(chosen)]]);
    }
    const unknownAttrs = Object.keys(input).filter((k) => !attrs.some((a) => a.name === k));
    if (unknownAttrs.length) throw new BadRequestException(`Atributos inexistentes: ${unknownAttrs.join(', ')}`);
    const combos = cartesian(entries);
    if (combos.length > 300) throw new BadRequestException('Demasiadas combinaciones (máx. 300 por producto)');
    return combos;
  }

  async insertVariants(tx: Tx, user: AuthUser, product: ProductRow, specs: VariantSpec[], attrs: AttributeRow[]) {
    if (!specs.length) return [];
    const ordered = [...attrs].sort((a, b) => a.position - b.position);
    const rows = [];
    for (const spec of specs) {
      const codes = ordered
        .filter((a) => spec.options[a.name] !== undefined)
        .map((a) => a.values.find((v) => v.value === spec.options[a.name])!.code);
      rows.push({
        tenantId: user.tenantId,
        productId: product.id,
        sku: [product.skuBase, ...codes].join('-'),
        barcode: spec.barcode ?? internalEan13(await nextNumber(tx, user.tenantId, 'barcode')),
        options: spec.options,
        priceCents: spec.priceCents ?? null,
        avgCostCents: product.costCents,
      });
    }
    return tx.insert(variants).values(rows).returning();
  }

  async generateSkuBase(tx: Tx, tenantId: string, name: string) {
    const n = await nextNumber(tx, tenantId, 'product');
    return `${skuPrefix(name)}-${String(n).padStart(4, '0')}`;
  }

  /** Producto + variantes + stock por sucursal: lo que necesita la matriz talla × color. */
  private async loadProduct(tx: Tx, user: AuthUser, id: string) {
    const [product] = await tx.select().from(products).where(eq(products.id, id));
    if (!product) throw new NotFoundException('Producto no encontrado');
    const vs = await tx.select().from(variants).where(eq(variants.productId, id)).orderBy(asc(variants.sku));
    const levels = vs.length
      ? await tx.select().from(stockLevels).where(inArray(stockLevels.variantId, vs.map((v) => v.id)))
      : [];
    const attrs = await tx.select({ name: attributes.name, position: attributes.position, values: attributes.values }).from(attributes);
    const usedAttrs = attrs
      .filter((a) => vs.some((v) => a.name in v.options))
      .sort((a, b) => a.position - b.position)
      .map((a) => ({ name: a.name, values: a.values.filter((val) => vs.some((v) => v.options[a.name] === val.value)).map((val) => val.value) }));

    return {
      ...this.hideCosts(user, product),
      images: await this.images.list(tx, id),
      attributes: usedAttrs,
      variants: vs.map((v) => ({
        ...this.hideCosts(user, v),
        effectivePriceCents: v.priceCents ?? product.priceCents,
        stock: levels
          .filter((l) => l.variantId === v.id)
          .map((l) => ({ branchId: l.branchId, quantity: l.quantity, minQuantity: l.minQuantity })),
      })),
    };
  }

  /** Quien no tiene costs.read (vendedores) no ve costos ni márgenes. */
  hideCosts<T extends { costCents?: number; avgCostCents?: number }>(user: AuthUser, row: T): T {
    if (hasPermission(user.role, 'costs.read')) return row;
    const { costCents: _c, avgCostCents: _a, ...rest } = row;
    return rest as T;
  }
}
