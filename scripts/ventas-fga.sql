-- ============================================================================
-- FGA EN LA FACTURA — SQL versionado (ya aplicado en producción)
-- ============================================================================
-- Aplicado el 2026-09-11 vía MCP. Migración en Supabase: ventas_fga_factura
--
-- El FGA es un seguro que se imprime en la factura para justificarle los
-- valores al cliente, igual que la línea del IVA. Es SOLO presentación:
--   · no suma al total de la factura
--   · no entra en valor_venta, ganancia, comisiones ni en ningún informe
--   · no toca el crédito ni la cartera
-- Se guarda el valor (no el porcentaje) para poder reimprimir la factura
-- exactamente igual meses después, aunque el porcentaje cambie.
-- ============================================================================

alter table public.ventas add column if not exists fga_valor numeric(15,2) default 0;
