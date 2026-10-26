import { Body, Controller, Get, HttpCode, HttpException, HttpStatus, Param, Post } from '@nestjs/common';
import { z } from 'zod';
import { ZodPipe } from '../../common/zod.pipe';
import { Throttle } from '@nestjs/throttler';
import { RequirePermissions } from '../../common/authz/decorators';
import { LookupService } from './lookup.service';

/** Límite por IP: cada consulta externa tiene costo. */
export const CpeSchema = z.object({
  ruc: z.string().regex(/^\d{11}$/),
  type: z.enum(['01', '03', '07', '08']),
  serie: z.string().regex(/^[A-Z0-9]{1,4}$/i).transform((s) => s.toUpperCase()),
  numero: z.number().int().positive().max(99_999_999),
  date: z.string().date(),
  totalCents: z.number().int().min(0).optional(),
});

@Controller('lookup')
@RequirePermissions('catalog.read')
export class LookupController {
  constructor(private readonly lookup: LookupService) {}

  @Get('ruc/:numero')
  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  ruc(@Param('numero') numero: string) {
    return this.lookup.ruc(numero.trim());
  }

  /** Validar un comprobante en SUNAT (vía Apachiy). */
  @Post('cpe')
  @HttpCode(200)
  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  async cpe(@Body(new ZodPipe(CpeSchema)) b: z.infer<typeof CpeSchema>) {
    const r = await this.lookup.validateCpe(b);
    if (!r) throw new HttpException({ message: 'La validación de comprobantes no está disponible ahora', code: 'LOOKUP_UNAVAILABLE' }, HttpStatus.SERVICE_UNAVAILABLE);
    return r;
  }

  @Get('dni/:numero')
  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  dni(@Param('numero') numero: string) {
    return this.lookup.dni(numero.trim());
  }
}
