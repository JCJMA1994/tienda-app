ALTER TABLE promotions ENABLE ROW LEVEL SECURITY;
--> statement-breakpoint
CREATE POLICY tenant_isolation ON promotions USING (tenant_id = app_tenant_id()) WITH CHECK (tenant_id = app_tenant_id());
--> statement-breakpoint
GRANT SELECT, INSERT, UPDATE ON promotions TO percha_app;
--> statement-breakpoint
ALTER TABLE promotions ADD CONSTRAINT promotions_rules_ck CHECK (
  (kind = 'percent' AND percent_bp BETWEEN 1 AND 9000)
  OR (kind = 'buy_x_pay_y' AND buy_qty BETWEEN 2 AND 10 AND pay_qty BETWEEN 1 AND buy_qty - 1)
);
