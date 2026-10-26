import { groupRows, validateFile } from '../src/modules/catalog/import.service';

/** Reglas puras de la importación (sin base de datos). */
const row = (index: number, r: Partial<Parameters<typeof groupRows>[0][number]>) => ({ name: 'Vestido', priceCents: 18990, costCents: 0, options: {}, quantity: 0, index, ...r });

describe('Importación: reglas del archivo', () => {
  it('agrupa por SKU base o, si falta, por nombre (sin distinguir mayúsculas)', () => {
    const g = groupRows([row(0, { options: { Talla: 'S' } }), row(1, { name: 'VESTIDO', options: { Talla: 'M' } }), row(2, { skuBase: 'BLU-1', name: 'Blusa' })]);
    expect([...g.keys()]).toEqual(['name:vestido', 'BLU-1']);
    expect(g.get('name:vestido')).toHaveLength(2);
  });

  it('detecta combinaciones repetidas, precios contradictorios y códigos duplicados', () => {
    const rows = [
      row(0, { options: { Talla: 'S' }, barcode: '2000000000015' }),
      row(1, { options: { Talla: 'S' }, barcode: '2000000000015' }),
      row(2, { name: 'Blusa' }),
      row(3, { name: 'Blusa', priceCents: 1 }),
    ];
    const errors = validateFile(rows, groupRows(rows));
    expect(errors).toEqual(
      expect.arrayContaining([
        { row: 1, message: 'Combinación repetida dentro del mismo producto' },
        { row: 3, message: 'Combinación repetida dentro del mismo producto' },
        { row: 3, message: 'Precio distinto para el mismo producto' },
        { row: -1, message: 'Hay códigos de barras repetidos en el archivo' },
      ]),
    );
  });
});
