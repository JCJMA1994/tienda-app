import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { applyPromotions, Promo, PromoLine } from '../src/modules/promotions/engine';

type Case = { name: string; promos: string[]; lines: PromoLine[]; expect: { lines: [number, string | null][]; total: number } };
const vectors = JSON.parse(readFileSync(join(__dirname, 'fixtures/promotions-vectors.json'), 'utf8')) as { promotions: Record<string, Promo>; cases: Case[] };

describe('Motor de promociones (casos compartidos con la app)', () => {
  const all = vectors.promotions;
  it.each(vectors.cases.map((c) => [c.name, c] as const))('%s', (_name, c) => {
    const r = applyPromotions(c.lines, c.promos.map((id) => all[id]));
    expect(r.lines.map((l) => [l.discountCents, l.promotionId])).toEqual(c.expect.lines);
    expect(r.totalCents).toBe(c.expect.total);
  });
});
