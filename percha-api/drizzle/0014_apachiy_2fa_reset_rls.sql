ALTER TABLE messaging_settings ENABLE ROW LEVEL SECURITY;
--> statement-breakpoint
CREATE POLICY tenant_isolation ON messaging_settings USING (tenant_id = app_tenant_id()) WITH CHECK (tenant_id = app_tenant_id());
--> statement-breakpoint
ALTER TABLE outbound_messages ENABLE ROW LEVEL SECURITY;
--> statement-breakpoint
CREATE POLICY tenant_isolation ON outbound_messages USING (tenant_id = app_tenant_id()) WITH CHECK (tenant_id = app_tenant_id());
--> statement-breakpoint
GRANT SELECT, INSERT, UPDATE ON messaging_settings, outbound_messages TO percha_app;
--> statement-breakpoint
-- Recuperación de contraseña y 2FA: solo el pool de sistema.
REVOKE ALL ON password_resets, recovery_codes FROM percha_app;
--> statement-breakpoint
-- La API de negocio nunca lee secretos de 2FA (ya no puede leer password_hash).
REVOKE SELECT ON users FROM percha_app;
--> statement-breakpoint
GRANT SELECT (id, email, name, created_at) ON users TO percha_app;
