DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['stock_counts', 'stock_count_items'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY tenant_isolation ON %I USING (tenant_id = app_tenant_id()) WITH CHECK (tenant_id = app_tenant_id())', t);
  END LOOP;
END $$;
--> statement-breakpoint
GRANT SELECT, INSERT, UPDATE ON stock_counts, stock_count_items TO percha_app;
--> statement-breakpoint
GRANT DELETE ON stock_count_items TO percha_app;
--> statement-breakpoint
ALTER TABLE stock_count_items ADD CONSTRAINT stock_count_items_counted_ck CHECK (counted >= 0);
--> statement-breakpoint
ALTER TABLE memberships ADD CONSTRAINT memberships_commission_ck CHECK (commission_bp IS NULL OR commission_bp BETWEEN 0 AND 5000);
