// Aplica las migraciones de ./drizzle con el rol dueño (DATABASE_OWNER_URL).
import { drizzle } from 'drizzle-orm/node-postgres';
import { migrate } from 'drizzle-orm/node-postgres/migrator';
import pg from 'pg';

const url = process.env.DATABASE_OWNER_URL;
if (!url) {
  console.error('Falta DATABASE_OWNER_URL');
  process.exit(1);
}
const pool = new pg.Pool({ connectionString: url, max: 1 });
try {
  await migrate(drizzle(pool), { migrationsFolder: './drizzle' });
  console.log('Migraciones aplicadas');
} finally {
  await pool.end();
}
