import { INestApplication } from '@nestjs/common';
import { hasPermission, PERMISSIONS } from '../src/common/authz/permissions';
import { describeRoles } from '../src/modules/access/roles.controller';
import { api, createApp, resetDatabase } from './helpers';

describe('GET /roles', () => {
  let app: INestApplication;
  let token: string;

  beforeAll(async () => {
    await resetDatabase();
    app = await createApp();
    const res = await api(app).post('/auth/register', { storeName: 'Roles', ownerName: 'Ana', email: 'ana@roles.pe', password: 'clave-segura-1' });
    token = res.body.accessToken;
  });
  afterAll(async () => app?.close());

  it('exige sesión', async () => {
    expect((await api(app).get('/roles')).status).toBe(401);
  });

  it('describe roles, etiquetas y niveles de acceso', async () => {
    const res = await api(app, token).get('/roles');
    expect(res.status).toBe(200);
    expect(res.headers['cache-control']).toContain('max-age=3600');
    expect(res.body.permissions).toHaveLength(PERMISSIONS.length);

    const seller = res.body.roles.find((r: any) => r.key === 'seller');
    expect(seller.label).toBe('Vendedor');
    expect(seller.access['sales.void']).toBe('approval');
    expect(seller.access['costs.read']).toBe('no');
    expect(seller.assignable).toEqual([]);

    const manager = res.body.roles.find((r: any) => r.key === 'manager');
    expect(manager.access['team.manage']).toBe('own_branch');
    expect(manager.access['billing.manage']).toBe('no');
    expect(manager.assignable).toEqual(['seller', 'stock']);

    // El almacén no vende, así que tampoco puede anular "con aprobación".
    const stock = res.body.roles.find((r: any) => r.key === 'stock');
    expect(stock.access['sales.void']).toBe('no');
  });

  it('es coherente con la matriz que aplican los guards', () => {
    for (const role of describeRoles().roles) {
      for (const p of PERMISSIONS) {
        const granted = role.access[p] === 'yes' || role.access[p] === 'own_branch';
        expect(granted).toBe(hasPermission(role.key, p));
      }
    }
  });
});
