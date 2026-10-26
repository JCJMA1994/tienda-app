import { DomainError } from '../../common/domain-error';
import { z } from 'zod';
import { isValidRuc } from '../../common/peru';

/**
 * Guía de remisión electrónica REMITENTE para traslados entre establecimientos de la misma
 * empresa (catálogo SUNAT 20, motivo 04). Formato neutro: el adaptador del OSE lo traduce.
 */
export interface EGuide {
  kind: 'guia_remitente';
  serie: string;
  numero: number;
  issueDate: string; // YYYY-MM-DD
  startDate: string; // inicio del traslado
  reasonCode: '04';
  reasonText: string;
  /** En un traslado propio, el destinatario es la misma empresa. */
  recipient: { ruc: string; name: string };
  origin: { ubigeo: string; address: string };
  destination: { ubigeo: string; address: string };
  transport: {
    /** 01 público (empresa de transporte) · 02 privado (vehículo propio, taxi, moto). */
    mode: 'public' | 'private';
    lightVehicle: boolean;
    vehiclePlate?: string;
    driver?: { dni: string; firstName: string; lastName: string; license?: string };
    carrier?: { ruc: string; name: string };
  };
  weightKg: number;
  packages: number;
  items: { code: string; description: string; quantity: number }[];
  note?: string;
}

const plate = z
  .string()
  .trim()
  .transform((s) => s.toUpperCase().replace(/[\s-]/g, ''))
  .pipe(z.string().regex(/^[A-Z0-9]{5,8}$/, 'Placa inválida'));

/** Datos del traslado que ingresa quien envía la mercadería. */
export const ShipmentSchema = z
  .object({
    mode: z.enum(['private', 'public']).default('private'),
    /** Auto, taxi o moto (vehículos M1 o L). */
    lightVehicle: z.boolean().default(true),
    vehiclePlate: plate.optional(),
    driver: z
      .object({
        dni: z.string().regex(/^\d{8}$/, 'DNI de 8 dígitos'),
        firstName: z.string().trim().min(2).max(60),
        lastName: z.string().trim().min(2).max(60),
        license: z.string().trim().max(15).optional(),
      })
      .optional(),
    carrier: z.object({ ruc: z.string().regex(/^\d{11}$/), name: z.string().trim().min(2).max(200) }).optional(),
    weightKg: z.number().positive().max(10_000),
    packages: z.number().int().min(1).max(1000).default(1),
    /** YYYY-MM-DD; por defecto, hoy. */
    startDate: z.string().date().optional(),
  });

export type Shipment = z.infer<typeof ShipmentSchema>;

/**
 * Reglas del traslado (GRE): transporte privado exige vehículo y conductor; el brevete puede
 * omitirse en vehículos livianos (M1/L). Transporte público exige el RUC de la empresa de
 * transporte. Se valida ANTES de numerar.
 */
export function validateShipment(s: Shipment) {
  if (s.mode === 'public') {
    if (!s.carrier || !isValidRuc(s.carrier.ruc)) throw DomainError.invalid('SHIPMENT_CARRIER_REQUIRED', 'Transporte público: indica el RUC y la razón social de la empresa de transporte');
    return;
  }
  if (!s.vehiclePlate) throw DomainError.invalid('SHIPMENT_PLATE_REQUIRED', 'Indica la placa del vehículo');
  if (!s.driver) throw DomainError.invalid('SHIPMENT_DRIVER_REQUIRED', 'Indica el DNI y el nombre de quien conduce');
  if (!s.lightVehicle && !s.driver.license) throw DomainError.invalid('SHIPMENT_LICENSE_REQUIRED', 'Indica el brevete del conductor');
}
