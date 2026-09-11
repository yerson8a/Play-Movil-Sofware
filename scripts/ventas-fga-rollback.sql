-- ============================================================================
-- ROLLBACK del FGA en la factura (ventas-fga.sql)
-- ============================================================================
-- Borra el valor del FGA guardado: las facturas ya impresas no cambian, pero
-- al reimprimirlas dejarían de mostrar la línea. Ningún total se altera,
-- porque el FGA nunca participó en los cálculos.
-- ============================================================================

alter table public.ventas drop column if exists fga_valor;
