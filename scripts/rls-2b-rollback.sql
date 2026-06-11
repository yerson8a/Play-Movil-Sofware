-- ============================================================
-- ROLLBACK de la Etapa 2b -> vuelve al estado 2a
-- ============================================================
-- Deja las LECTURAS por sede (2a) intactas, pero AFLOJA las escrituras
-- (WITH CHECK true) y quita los triggers que fuerzan la sede.
-- Úsalo si 2b bloquea alguna escritura legítima. SQL Editor.
-- (Para revertir TODO a acceso público, usa rls-2a-rollback.sql.)
-- ============================================================

-- Quitar triggers
drop trigger if exists trg_forzar_sede on public.productos;
drop trigger if exists trg_forzar_sede on public.ventas;
drop trigger if exists trg_forzar_sede on public.creditos;
drop trigger if exists trg_forzar_sede on public.garantias;
drop trigger if exists trg_forzar_sede on public.gastos;
drop trigger if exists trg_forzar_sede on public.servicio_tecnico;
drop trigger if exists trg_forzar_sede on public.cajas;
drop function if exists public.forzar_sede_insert();

-- Aflojar WITH CHECK (escrituras abiertas otra vez)
alter policy "productos_rls"          on public.productos          with check ( true );
alter policy "ventas_rls"             on public.ventas             with check ( true );
alter policy "creditos_rls"           on public.creditos           with check ( true );
alter policy "garantias_rls"          on public.garantias          with check ( true );
alter policy "gastos_rls"             on public.gastos             with check ( true );
alter policy "servicio_tecnico_rls"   on public.servicio_tecnico   with check ( true );
alter policy "cajas_rls"              on public.cajas              with check ( true );
alter policy "abonos_rls"             on public.abonos             with check ( true );
alter policy "ventas_detalle_rls"     on public.ventas_detalle     with check ( true );
alter policy "bitacora_creditos_rls"  on public.bitacora_creditos  with check ( true );
alter policy "movimientos_caja_rls"   on public.movimientos_caja   with check ( true );
