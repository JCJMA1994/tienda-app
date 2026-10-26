-- Facturación: la escribe solo el pool de sistema (BillingService, webhooks, job).
-- La API de negocio (percha_app) solo LEE la suscripción y facturas de su propia tienda.
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
--> statement-breakpoint
CREATE POLICY tenant_read ON subscriptions FOR SELECT USING (tenant_id = app_tenant_id());
--> statement-breakpoint
GRANT SELECT ON subscriptions TO percha_app;
--> statement-breakpoint
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
--> statement-breakpoint
CREATE POLICY tenant_read ON invoices FOR SELECT USING (tenant_id = app_tenant_id());
--> statement-breakpoint
GRANT SELECT ON invoices TO percha_app;
--> statement-breakpoint
-- El catálogo de planes es público para cualquier tienda.
GRANT SELECT ON plans TO percha_app;
--> statement-breakpoint
REVOKE ALL ON payment_events, platform_admins FROM percha_app;
--> statement-breakpoint
-- Planes iniciales. Precios y límites son de EJEMPLO: ajústalos (UPDATE plans ...) antes de lanzar.
INSERT INTO plans (code, name, price_cents, currency, limits, position) VALUES
  ('emprende', 'Emprende', 7900,  'PEN', '{"branches": 1, "members": 3,  "products": 500}', 0),
  ('crece',    'Crece',    14900, 'PEN', '{"branches": 3, "members": 10, "products": 5000}', 1),
  ('pro',      'Pro',      29900, 'PEN', '{"branches": null, "members": null, "products": null}', 2);
