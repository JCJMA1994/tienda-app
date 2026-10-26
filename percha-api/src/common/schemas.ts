import { z } from 'zod';

export const uuid = z.string().uuid();
/** Montos siempre en céntimos (enteros) para evitar errores de redondeo con decimales. */
export const cents = z.number().int().min(0).max(100_000_000);
export const positiveQty = z.number().int().positive().max(100_000);
