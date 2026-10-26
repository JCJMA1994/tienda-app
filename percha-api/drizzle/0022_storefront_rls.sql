DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['catalog_settings', 'catalog_orders', 'catalog_order_items'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY tenant_isolation ON %I USING (tenant_id = app_tenant_id()) WITH CHECK (tenant_id = app_tenant_id())', t);
  END LOOP;
END $$;
--> statement-breakpoint
GRANT SELECT, INSERT, UPDATE ON catalog_settings, catalog_orders TO percha_app;
--> statement-breakpoint
GRANT SELECT, INSERT ON catalog_order_items TO percha_app;
