// Carga el PADRÓN REDUCIDO DEL RUC de SUNAT (gratuito, oficial, se actualiza a diario).
//
//   1) Descarga: https://www.sunat.gob.pe/descargaPRR/mrc137_padron_reducido.html
//      (archivo padron_reducido_ruc.zip, ~14 millones de filas)
//   2) unzip padron_reducido_ruc.zip
//   3) DATABASE_OWNER_URL=... node scripts/import-padron.mjs padron_reducido_ruc.txt [--only-active]
//
// Se carga en una tabla temporal con COPY (rápido) y al final se reemplaza la tabla en una
// transacción: la consulta de RUC nunca ve el padrón a medias. Con --only-active solo se
// guardan contribuyentes ACTIVOS (ocupa bastante menos espacio).
import fs from 'node:fs';
import readline from 'node:readline';
import pg from 'pg';
import { from as copyFrom } from 'pg-copy-streams';

const [file, ...flags] = process.argv.slice(2);
const onlyActive = flags.includes('--only-active');
if (!file || !process.env.DATABASE_OWNER_URL) {
  console.error('Uso: DATABASE_OWNER_URL=... node scripts/import-padron.mjs <padron.txt> [--only-active]');
  process.exit(1);
}

/** Campos: RUC|NOMBRE|ESTADO|CONDICIÓN|UBIGEO|TIPO VÍA|NOMBRE VÍA|CÓD. ZONA|TIPO ZONA|NÚMERO|INTERIOR|LOTE|DPTO|MANZANA|KM| */
const clean = (v) => {
  const t = (v ?? '').trim();
  return t === '' || t === '-' ? null : t;
};
const esc = (v) => (v == null ? '\\N' : v.replace(/\\/g, '\\\\').replace(/[\t\r\n]/g, ' '));

export function parseLine(line) {
  const f = line.split('|');
  const ruc = clean(f[0]);
  if (!ruc || !/^\d{11}$/.test(ruc)) return null;
  const via = [clean(f[5]), clean(f[6])].filter(Boolean).join(' ');
  const zona = [clean(f[8]), clean(f[7])].filter(Boolean).join(' ');
  const parts = [
    via,
    clean(f[9]) && `NRO. ${clean(f[9])}`,
    clean(f[10]) && `INT. ${clean(f[10])}`,
    clean(f[12]) && `DPTO. ${clean(f[12])}`,
    clean(f[13]) && `MZA. ${clean(f[13])}`,
    clean(f[11]) && `LOTE ${clean(f[11])}`,
    clean(f[14]) && `KM. ${clean(f[14])}`,
    zona,
  ].filter(Boolean);
  return { ruc, name: clean(f[1]) ?? '', status: clean(f[2]), condition: clean(f[3]), ubigeo: clean(f[4]), address: parts.join(' ') || null };
}

const client = new pg.Client({ connectionString: process.env.DATABASE_OWNER_URL });
await client.connect();
const started = Date.now();
let read = 0;
let kept = 0;
try {
  await client.query('DROP TABLE IF EXISTS sunat_padron_staging');
  await client.query('CREATE UNLOGGED TABLE sunat_padron_staging (LIKE sunat_padron INCLUDING DEFAULTS)');
  const copy = client.query(copyFrom('COPY sunat_padron_staging (ruc, name, status, condition, ubigeo, address) FROM STDIN'));
  const done = new Promise((resolve, reject) => {
    copy.on('finish', resolve);
    copy.on('error', reject);
  });

  // El archivo de SUNAT viene en Latin-1.
  const lines = readline.createInterface({ input: fs.createReadStream(file, { encoding: 'latin1' }), crlfDelay: Infinity });
  for await (const line of lines) {
    read++;
    if (read === 1 && !/^\d{11}\|/.test(line)) continue; // encabezado
    const r = parseLine(line);
    if (!r || (onlyActive && r.status !== 'ACTIVO')) continue;
    kept++;
    const row = [r.ruc, r.name, r.status, r.condition, r.ubigeo, r.address].map(esc).join('\t') + '\n';
    if (!copy.write(row)) await new Promise((res) => copy.once('drain', res));
    if (kept % 1_000_000 === 0) console.log(`  ${kept.toLocaleString('es-PE')} filas…`);
  }
  copy.end();
  await done;

  // Duplicados en el archivo (raro): gana la última fila.
  await client.query(`
    BEGIN;
    DELETE FROM sunat_padron;
    INSERT INTO sunat_padron (ruc, name, status, condition, ubigeo, address, updated_at)
      SELECT DISTINCT ON (ruc) ruc, name, status, condition, ubigeo, address, now() FROM sunat_padron_staging ORDER BY ruc;
    COMMIT;`);
  await client.query('DROP TABLE sunat_padron_staging');
  await client.query('ANALYZE sunat_padron');
  console.log(`Padrón cargado: ${kept.toLocaleString('es-PE')} RUC (${read.toLocaleString('es-PE')} líneas) en ${Math.round((Date.now() - started) / 1000)} s`);
} catch (e) {
  await client.query('ROLLBACK').catch(() => {});
  console.error('Error al importar el padrón:', e.message);
  process.exitCode = 1;
} finally {
  await client.end();
}
