-- ============================================================
-- Rollback de retoma-imei.sql
-- ============================================================
-- Deja el sistema como antes: un IMEI vendido vuelve a quedar quemado y no se
-- puede reingresar por retoma.
--
-- OJO: el unique sobre todo el historial solo se puede restaurar si ya no hay
-- IMEI repetidos. Si entre tanto se registro alguna retoma, hay que decidir
-- primero que hacer con esas filas; la creacion del indice fallara sola en vez
-- de borrar nada.
-- ============================================================

drop trigger if exists productos_validar_reingreso on public.productos;
drop function if exists public.productos_validar_reingreso();
drop function if exists public.estado_imei(text);

drop index if exists public.idx_productos_imei1_vigente;
drop index if exists public.idx_productos_imei1;

create unique index idx_productos_imei1 on public.productos (imei1)
  where imei1 is not null and imei1::text <> '';
