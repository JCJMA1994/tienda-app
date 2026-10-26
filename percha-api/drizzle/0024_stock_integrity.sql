ALTER TABLE idempotency_keys ENABLE ROW LEVEL SECURITY;
--> statement-breakpoint
CREATE POLICY tenant_isolation ON idempotency_keys USING (tenant_id = app_tenant_id()) WITH CHECK (tenant_id = app_tenant_id());
--> statement-breakpoint
GRANT SELECT, INSERT, UPDATE ON idempotency_keys TO percha_app;
--> statement-breakpoint
-- Defensa en la base: una misma operación (venta, devolución, recepción, transferencia,
-- apartado) no puede generar dos movimientos del mismo tipo para la misma variante.
-- Aunque un bug llamara dos veces a InventoryService.apply, la segunda falla.
CREATE UNIQUE INDEX stock_movements_once_per_operation_uq
  ON stock_movements (tenant_id, reference_type, reference_id, variant_id, type)
  WHERE reference_id IS NOT NULL;
