import { INestApplication } from '@nestjs/common';
import { EventBus } from '../src/common/events';
import { DatabaseService } from '../src/database/database.service';
import { createApp, resetDatabase } from './helpers';

describe('Eventos de dominio y tareas posteriores al commit', () => {
  let app: INestApplication;
  beforeAll(async () => {
    await resetDatabase();
    app = await createApp();
  });
  afterAll(async () => app?.close());

  it('cada hecho tiene sus suscriptores (las reacciones no viven en el servicio que publica)', () => {
    const bus = app.get(EventBus);
    expect(bus.subscribers('sale.recorded')).toEqual(expect.arrayContaining(['emitir boleta o factura', 'asociar cliente a la venta']));
    expect(bus.subscribers('transfer.sent')).toEqual(expect.arrayContaining(['guía de remisión (motivo 04)', 'notificar a la sucursal destino']));
    expect(bus.subscribers('stock.below_minimum')).toEqual(['avisar stock bajo']);
  });

  it('afterCommit corre solo si la transacción se confirma', async () => {
    const db = app.get(DatabaseService);
    const ran: string[] = [];
    await db.withSystem(async (tx) => {
      db.afterCommit(tx, async () => void ran.push('confirmada'));
    });
    await expect(
      db.withSystem(async (tx) => {
        db.afterCommit(tx, async () => void ran.push('revertida'));
        throw new Error('falla a mitad');
      }),
    ).rejects.toThrow('falla a mitad');
    expect(ran).toEqual(['confirmada']);
  });
});
