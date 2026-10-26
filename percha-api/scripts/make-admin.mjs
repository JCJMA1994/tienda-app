// Da permisos de superadmin de la plataforma a un usuario existente.
//   DATABASE_OWNER_URL=... node scripts/make-admin.mjs tu@correo.com
import pg from 'pg';

const email = process.argv[2];
if (!email || !process.env.DATABASE_OWNER_URL) {
  console.error('Uso: DATABASE_OWNER_URL=... node scripts/make-admin.mjs <correo>');
  process.exit(1);
}
const client = new pg.Client({ connectionString: process.env.DATABASE_OWNER_URL });
await client.connect();
try {
  const res = await client.query(
    'INSERT INTO platform_admins (user_id) SELECT id FROM users WHERE lower(email) = lower($1) ON CONFLICT DO NOTHING RETURNING user_id',
    [email],
  );
  console.log(res.rowCount ? `${email} ahora es superadmin` : `No existe el usuario ${email} (o ya era admin)`);
} finally {
  await client.end();
}
