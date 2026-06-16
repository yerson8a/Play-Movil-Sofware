-- abonos-recibo.sql
-- Guardar los datos necesarios para reimprimir el recibo de cada abono.
-- La columna nro_transferencia almacena la referencia cuando el método es
-- Transferencia. notas y asesor ya existían en la tabla.
-- Aplicado en BD el 2026-06-16.

alter table public.abonos
  add column if not exists nro_transferencia varchar;
