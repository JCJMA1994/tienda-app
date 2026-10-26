-- =====================================================================
-- Aislamiento multi-tenant con Row-Level Security (RLS)
-- ---------------------------------------------------------------------
-- * La API ejecuta cada operación de negocio dentro de una transacción que
--   hace:  SELECT set_config('app.tenant_id', '<uuid>', true)
-- * Las políticas filtran por esa variable. Si no está definida, la función
--   devuelve NULL y NO se ve ninguna fila (falla cerrado).
-- * El rol percha_app (el que usa la API) NO es dueño de las tablas, así que
--   RLS siempre se le aplica. El dueño (percha_owner) y sus miembros
--   (percha_system) lo omiten: se usan solo para migraciones y autenticación.
-- =====================================================================

CREATE OR REPLACE FUNCTION app_tenant_id() RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid
$$;
--> statement-breakpoint

DO $$
DECLARE
  t text;
  tenant_tables text[] := ARRAY[
    'branches','memberships','invitations','sequences','audit_logs',
    'categories','attributes','products','variants',
    'stock_levels','stock_movements',
    'cash_sessions','sales','sale_items','returns','return_items','payments',
    'suppliers','purchase_orders','purchase_order_items','goods_receipts','goods_receipt_items'
  ];
BEGIN
  FOREACH t IN ARRAY tenant_tables LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format(
      'CREATE POLICY tenant_isolation ON %I USING (tenant_id = app_tenant_id()) WITH CHECK (tenant_id = app_tenant_id())',
      t
    );
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON %I TO percha_app', t);
  END LOOP;
END $$;
--> statement-breakpoint

-- La tienda solo se ve y edita a sí misma (no puede crear ni borrar tiendas).
ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
--> statement-breakpoint
CREATE POLICY tenant_self ON tenants USING (id = app_tenant_id()) WITH CHECK (id = app_tenant_id());
--> statement-breakpoint
GRANT SELECT, UPDATE ON tenants TO percha_app;
--> statement-breakpoint

-- Usuarios: solo los que pertenecen a la tienda actual, y nunca el hash de contraseña.
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
--> statement-breakpoint
CREATE POLICY users_same_tenant ON users FOR SELECT
  USING (EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = users.id));
--> statement-breakpoint
GRANT SELECT (id, email, name, created_at) ON users TO percha_app;
--> statement-breakpoint

-- refresh_tokens: sin permisos para percha_app (solo el pool de sistema).
REVOKE ALL ON refresh_tokens FROM percha_app;
--> statement-breakpoint

-- Kardex y auditoría son inmutables: ni la API ni el dueño pueden editarlos.
REVOKE UPDATE, DELETE ON stock_movements, audit_logs FROM percha_app;
--> statement-breakpoint
CREATE OR REPLACE FUNCTION forbid_mutation() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION '% es de solo inserción', TG_TABLE_NAME USING ERRCODE = 'P0001';
END $$;
--> statement-breakpoint
CREATE TRIGGER stock_movements_append_only BEFORE UPDATE OR DELETE ON stock_movements
  FOR EACH ROW EXECUTE FUNCTION forbid_mutation();
--> statement-breakpoint
CREATE TRIGGER audit_logs_append_only BEFORE UPDATE OR DELETE ON audit_logs
  FOR EACH ROW EXECUTE FUNCTION forbid_mutation();
--> statement-breakpoint

GRANT USAGE ON SCHEMA public TO percha_app;
