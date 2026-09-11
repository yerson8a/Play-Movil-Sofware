-- ============================================================================
-- ROLLBACK del IVA en la factura (ventas-iva.sql)
-- ============================================================================
-- Al borrar las columnas, las facturas reimpresas vuelven a mostrar el IVA en
-- cero. Ningún total se altera: el IVA nunca participó en los cálculos.
-- ============================================================================

alter table public.ventas drop column if exists iva_valor;
alter table public.ventas drop column if exists iva_pct;
