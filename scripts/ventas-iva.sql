-- ============================================================================
-- IVA DE LA FACTURA — SQL versionado (ya aplicado en producción)
-- ============================================================================
-- Aplicado el 2026-09-11 vía MCP. Migración en Supabase: ventas_iva_factura
--
-- El IVA se imprimía en la factura pero no se guardaba en ninguna parte: al
-- volver a ver la factura de una venta ya hecha salía siempre en cero.
--
-- Igual que el FGA, es SOLO presentación: no suma al total de la factura ni
-- entra en valor_venta, ganancia, comisiones o informes. Se guardan el valor
-- y el porcentaje para reimprimir la factura igual que el día de la venta.
--
-- Nota: aplica de aquí en adelante. Las ventas anteriores quedan en 0 porque
-- ese dato nunca se almacenó.
-- ============================================================================

alter table public.ventas add column if not exists iva_valor numeric(15,2) default 0;
alter table public.ventas add column if not exists iva_pct   numeric(5,2)  default 0;
