import { Inject, Injectable, UnprocessableEntityException } from '@nestjs/common';
import { eq, inArray } from 'drizzle-orm';
import { z } from 'zod';
import { assertBranchAccess, AuthUser } from '../../common/auth-user';
import { cents } from '../../common/schemas';
import { DatabaseService, Tx } from '../../database/database.service';
import { attributes, categories, products, variants } from '../../database/schema';
import { LimitsService } from '../billing/limits.service';
import { InventoryService, MovementInput } from '../inventory/inventory.service';
import { CatalogService } from './catalog.service';
import { optionsKey } from './codes';

/**
 * Una fila = una variante. La app lee el Excel en el dispositivo (p. ej. con SheetJS)
 * y envía JSON: el servidor no parsea archivos binarios (menos superficie de ataque).
 */
const ImportRow = z.object({
  name: z.string().trim().min(2).max(120),
  skuBase: z.string().trim().regex(/^[A-Z0-9-]{2,20}$/).optional(),
  category: z.string().trim().max(60).optional(),
  priceCents: cents,
  costCents: cents.default(0),
  options: z.record(z.string().trim().min(1), z.string().trim().min(1)).default({}),
  barcode: z.string().regex(/^\d{8,14}$/).optional(),
  quantity: z.number().int().min(0).default(0),
});

export const ImportSchema = z.object({
  branchId: z.string().uuid(),
  rows: z.array(ImportRow).min(1).max(2000),
});

type Row = z.infer<typeof ImportRow> & { index: number };
type ImportError = { row: number; message: string };

/** Agrupa filas en productos: por SKU base o, si no viene, por nombre. (Puro.) */
export function groupRows(rows: Row[]) {
  const groups = new Map<string, Row[]>();
  for (const r of rows) {
    const key = r.skuBase ?? `name:${r.name.toLowerCase()}`;
    groups.set(key, [...(groups.get(key) ?? []), r]);
  }
  return groups;
}

/** Errores dentro del archivo: combinaciones repetidas, precios contradictorios, códigos duplicados. (Puro.) */
export function validateFile(rows: Row[], groups: Map<string, Row[]>): ImportError[] {
  const errors: ImportError[] = [];
  for (const group of groups.values()) {
    const seen = new Set<string>();
    for (const r of group) {
      const k = optionsKey(r.options);
      if (seen.has(k)) errors.push({ row: r.index, message: 'Combinación repetida dentro del mismo producto' });
      seen.add(k);
      if (r.priceCents !== group[0].priceCents && Object.keys(r.options).length === 0) {
        errors.push({ row: r.index, message: 'Precio distinto para el mismo producto' });
      }
    }
  }
  const barcodes = rows.map((r) => r.barcode).filter((b): b is string => Boolean(b));
  if (new Set(barcodes).size !== barcodes.length) errors.push({ row: -1, message: 'Hay códigos de barras repetidos en el archivo' });
  return errors;
}

@Injectable()
export class ImportService {
  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(CatalogService) private readonly catalog: CatalogService,
    @Inject(InventoryService) private readonly inventory: InventoryService,
    @Inject(LimitsService) private readonly limits: LimitsService,
  ) {}

  /**
   * Todo o nada: primero se validan TODAS las filas y se devuelven todos los errores juntos
   * (más útil que corregir uno por uno); si no hay errores, se escribe en una transacción.
   *   1. validar el archivo   2. conflictos con lo existente   3. cupo del plan
   *   4. atributos y categorías   5. productos, variantes y stock inicial
   */
  run(user: AuthUser, input: z.infer<typeof ImportSchema>) {
    assertBranchAccess(user, input.branchId);
    const rows: Row[] = input.rows.map((r, index) => ({ ...r, index }));
    const groups = groupRows(rows);

    return this.db.withTenant(user.tenantId, async (tx) => {
      const errors = [...validateFile(rows, groups), ...(await this.conflictsWithExisting(tx, rows))];
      if (errors.length) throw new UnprocessableEntityException({ message: 'El archivo tiene errores', errors });

      await this.limits.assertCanAdd(tx, user.tenantId, 'products', groups.size);
      const attrs = await this.ensureAttributes(tx, user.tenantId, rows);
      const cats = await this.ensureCategories(tx, user.tenantId, rows);

      const movements: MovementInput[] = [];
      let variantCount = 0;
      for (const group of groups.values()) {
        const created = await this.createProduct(tx, user, group, attrs, cats);
        variantCount += created.variants;
        movements.push(...created.movements);
      }
      await this.inventory.apply(tx, user, input.branchId, movements);
      return { products: groups.size, variants: variantCount, unitsLoaded: movements.reduce((a, m) => a + m.quantity, 0) };
    });
  }

  /** SKU base o códigos de barras que ya existen en la tienda. */
  private async conflictsWithExisting(tx: Tx, rows: Row[]): Promise<ImportError[]> {
    const errors: ImportError[] = [];
    const skuBases = rows.map((r) => r.skuBase).filter((s): s is string => Boolean(s));
    if (skuBases.length) {
      for (const e of await tx.select({ sku: products.skuBase }).from(products).where(inArray(products.skuBase, skuBases))) {
        rows.filter((r) => r.skuBase === e.sku).forEach((r) => errors.push({ row: r.index, message: `El SKU ${e.sku} ya existe` }));
      }
    }
    const barcodes = rows.map((r) => r.barcode).filter((b): b is string => Boolean(b));
    if (barcodes.length) {
      for (const e of await tx.select({ barcode: variants.barcode }).from(variants).where(inArray(variants.barcode, barcodes))) {
        rows.filter((r) => r.barcode === e.barcode).forEach((r) => errors.push({ row: r.index, message: `El código ${e.barcode} ya existe` }));
      }
    }
    return errors;
  }

  /** Crea los atributos y valores que falten (p. ej. una talla nueva). */
  private async ensureAttributes(tx: Tx, tenantId: string, rows: Row[]) {
    const attrValues = new Map<string, Set<string>>();
    rows.forEach((r) => Object.entries(r.options).forEach(([k, v]) => attrValues.set(k, (attrValues.get(k) ?? new Set()).add(v))));
    const current = await tx.select().from(attributes);
    let position = current.length;
    for (const [name, values] of attrValues) {
      const attr = current.find((a) => a.name === name);
      if (!attr) {
        await tx.insert(attributes).values({ tenantId, name, position: position++, values: this.catalog.normalizeValues([...values]) });
        continue;
      }
      const missing = [...values].filter((v) => !attr.values.some((av) => av.value === v));
      if (missing.length) {
        const merged = this.catalog.normalizeValues([...attr.values, ...missing.map((value) => ({ value }))], attr.values);
        await tx.update(attributes).set({ values: merged }).where(eq(attributes.id, attr.id));
      }
    }
    return tx.select().from(attributes);
  }

  private async ensureCategories(tx: Tx, tenantId: string, rows: Row[]) {
    const names = [...new Set(rows.map((r) => r.category).filter((c): c is string => Boolean(c)))];
    if (names.length) await tx.insert(categories).values(names.map((name) => ({ tenantId, name }))).onConflictDoNothing();
    return tx.select().from(categories);
  }

  private async createProduct(
    tx: Tx,
    user: AuthUser,
    group: Row[],
    attrs: (typeof attributes.$inferSelect)[],
    cats: (typeof categories.$inferSelect)[],
  ) {
    const first = group[0];
    const [product] = await tx
      .insert(products)
      .values({
        tenantId: user.tenantId,
        name: first.name,
        skuBase: first.skuBase ?? (await this.catalog.generateSkuBase(tx, user.tenantId, first.name)),
        categoryId: cats.find((c) => c.name === first.category)?.id ?? null,
        priceCents: first.priceCents,
        costCents: first.costCents,
      })
      .returning();
    const created = await this.catalog.insertVariants(
      tx,
      user,
      product,
      group.map((r) => ({ options: r.options, barcode: r.barcode, priceCents: r.priceCents !== first.priceCents ? r.priceCents : null })),
      attrs,
    );
    // Se empareja por combinación, no por posición: RETURNING no garantiza orden.
    const rowByKey = new Map(group.map((r) => [optionsKey(r.options), r]));
    const movements: MovementInput[] = [];
    for (const v of created) {
      const r = rowByKey.get(optionsKey(v.options))!;
      if (r.quantity > 0) movements.push({ variantId: v.id, quantity: r.quantity, type: 'initial', unitCostCents: r.costCents, referenceType: 'import' });
    }
    return { variants: created.length, movements };
  }
}
