ALTER TABLE transfers ENABLE ROW LEVEL SECURITY;
--> statement-breakpoint
CREATE POLICY tenant_isolation ON transfers USING (tenant_id = app_tenant_id()) WITH CHECK (tenant_id = app_tenant_id());
--> statement-breakpoint
ALTER TABLE transfer_items ENABLE ROW LEVEL SECURITY;
--> statement-breakpoint
CREATE POLICY tenant_isolation ON transfer_items USING (tenant_id = app_tenant_id()) WITH CHECK (tenant_id = app_tenant_id());
--> statement-breakpoint
GRANT SELECT, INSERT, UPDATE ON transfers, transfer_items TO percha_app;
--> statement-breakpoint
-- La caché de RUC/DNI es de la plataforma: solo el pool de sistema la usa.
REVOKE ALL ON identity_cache FROM percha_app;
