DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['store_credits', 'store_credit_movements', 'layaways', 'layaway_items'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY tenant_isolation ON %I USING (tenant_id = app_tenant_id()) WITH CHECK (tenant_id = app_tenant_id())', t);
  END LOOP;
END $$;
--> statement-breakpoint
GRANT SELECT, INSERT, UPDATE ON store_credits, layaways TO percha_app;
--> statement-breakpoint
GRANT SELECT, INSERT ON store_credit_movements, layaway_items TO percha_app;
--> statement-breakpoint
-- Movimientos de vales: inmutables (igual que el kardex).
CREATE TRIGGER store_credit_movements_immutable BEFORE UPDATE OR DELETE ON store_credit_movements
  FOR EACH ROW EXECUTE FUNCTION forbid_mutation();
--> statement-breakpoint
ALTER TABLE payments ADD CONSTRAINT payments_layaway_fk FOREIGN KEY (tenant_id, layaway_id) REFERENCES layaways (tenant_id, id);
--> statement-breakpoint
ALTER TABLE payments ADD CONSTRAINT payments_credit_fk FOREIGN KEY (tenant_id, store_credit_id) REFERENCES store_credits (tenant_id, id);
