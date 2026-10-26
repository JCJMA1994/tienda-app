-- Facturación electrónica: tablas por tienda con el mismo aislamiento RLS que el resto.
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['einvoice_settings', 'einvoice_series', 'einvoice_documents'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format(
      'CREATE POLICY tenant_isolation ON %I USING (tenant_id = app_tenant_id()) WITH CHECK (tenant_id = app_tenant_id())',
      t
    );
    EXECUTE format('GRANT SELECT, INSERT, UPDATE ON %I TO percha_app', t);
  END LOOP;
END $$;
--> statement-breakpoint
-- Un comprobante emitido no se borra nunca (SUNAT): se corrige con nota de crédito.
REVOKE DELETE ON einvoice_documents FROM percha_app;
