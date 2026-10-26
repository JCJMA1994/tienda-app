import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';

/**
 * Reglas de arquitectura verificadas en cada corrida (no dependen de la disciplina):
 * 1. El dominio puro no conoce el framework ni la base de datos.
 * 2. No hay dependencias circulares entre módulos.
 */
const SRC = resolve(__dirname, '../src');
const walk = (dir: string): string[] =>
  readdirSync(dir).flatMap((f) => {
    const p = join(dir, f);
    return statSync(p).isDirectory() ? walk(p) : p.endsWith('.ts') ? [p] : [];
  });
const files = walk(SRC);
const importsOf = (file: string) => [...readFileSync(file, 'utf8').matchAll(/from '([^']+)'/g)].map((m) => m[1]);

/** Lógica de negocio pura: reglas, cálculos y formatos. */
const DOMAIN = [
  'common/money.ts',
  'common/dates.ts',
  'common/peru.ts',
  'common/domain-error.ts',
  'modules/einvoice/document.ts',
  'modules/einvoice/guide.ts',
  'modules/auth/totp.ts',
  'modules/catalog/codes.ts',
];

describe('Arquitectura', () => {
  it.each(DOMAIN)('%s no importa NestJS, Drizzle ni la base de datos', (f) => {
    const forbidden = importsOf(join(SRC, f)).filter((i) => /^@nestjs\/|^drizzle-orm|\/database\//.test(i));
    expect(forbidden).toEqual([]);
  });

  it('no hay dependencias circulares entre módulos', () => {
    const moduleOf = (p: string) => /^modules\/([^/]+)\//.exec(relative(SRC, p))?.[1];
    const graph = new Map<string, Set<string>>();
    for (const f of files) {
      const from = moduleOf(f);
      if (!from) continue;
      for (const spec of importsOf(f).filter((s) => s.startsWith('.'))) {
        const to = moduleOf(resolve(f, '..', spec) + '.ts');
        if (to && to !== from) (graph.get(from) ?? graph.set(from, new Set()).get(from)!).add(to);
      }
    }
    const cycles: string[] = [];
    const visit = (node: string, path: string[]) => {
      for (const next of graph.get(node) ?? []) {
        if (path.includes(next)) cycles.push([...path.slice(path.indexOf(next)), next].join(' → '));
        else if (path.length < 8) visit(next, [...path, next]);
      }
    };
    for (const m of graph.keys()) visit(m, [m]);
    expect([...new Set(cycles)]).toEqual([]);
  });
});
