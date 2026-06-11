-- ============================================================
-- RLS Etapa 2b — ESCRITURA por sede (trigger + WITH CHECK)
-- ============================================================
-- YA APLICADO en producción (migración rls_2b_escritura_por_sede).
-- Copia versionada. Rollback: rls-2b-rollback.sql (vuelve a 2a).
--
-- Idea: la BD es la fuente de verdad de la sede, no el frontend.
--   - trigger BEFORE INSERT fuerza sede_id = mi_sede() para no-admin
--     (admin y service_role no se tocan).
--   - WITH CHECK por sede en tablas con sede_id y en hijas (vía padre).
-- ============================================================

create or replace function public.forzar_sede_insert() returns trigger
  language plpgsql as $$
begin
  if public.mi_rol() is not null and public.mi_rol() <> 'admin' then
    new.sede_id := public.mi_sede();
  end if;
  return new;
end $$;

-- Triggers en tablas con sede_id
drop trigger if exists trg_forzar_sede on public.productos;
create trigger trg_forzar_sede before insert on public.productos for each row execute function public.forzar_sede_insert();
drop trigger if exists trg_forzar_sede on public.ventas;
create trigger trg_forzar_sede before insert on public.ventas for each row execute function public.forzar_sede_insert();
drop trigger if exists trg_forzar_sede on public.creditos;
create trigger trg_forzar_sede before insert on public.creditos for each row execute function public.forzar_sede_insert();
drop trigger if exists trg_forzar_sede on public.garantias;
create trigger trg_forzar_sede before insert on public.garantias for each row execute function public.forzar_sede_insert();
drop trigger if exists trg_forzar_sede on public.gastos;
create trigger trg_forzar_sede before insert on public.gastos for each row execute function public.forzar_sede_insert();
drop trigger if exists trg_forzar_sede on public.servicio_tecnico;
create trigger trg_forzar_sede before insert on public.servicio_tecnico for each row execute function public.forzar_sede_insert();
drop trigger if exists trg_forzar_sede on public.cajas;
create trigger trg_forzar_sede before insert on public.cajas for each row execute function public.forzar_sede_insert();

-- WITH CHECK por sede (tablas con sede_id)
alter policy "productos_rls"        on public.productos        with check ( public.mi_rol()='admin' or sede_id = public.mi_sede() );
alter policy "ventas_rls"           on public.ventas           with check ( public.mi_rol()='admin' or sede_id = public.mi_sede() );
alter policy "creditos_rls"         on public.creditos         with check ( public.mi_rol()='admin' or sede_id = public.mi_sede() );
alter policy "garantias_rls"        on public.garantias        with check ( public.mi_rol()='admin' or sede_id = public.mi_sede() );
alter policy "gastos_rls"           on public.gastos           with check ( public.mi_rol()='admin' or sede_id = public.mi_sede() );
alter policy "servicio_tecnico_rls" on public.servicio_tecnico with check ( public.mi_rol()='admin' or sede_id = public.mi_sede() );
alter policy "cajas_rls"            on public.cajas            with check ( public.mi_rol()='admin' or sede_id = public.mi_sede() );

-- WITH CHECK por sede (tablas hijas, vía padre)
alter policy "abonos_rls" on public.abonos with check (
  public.mi_rol()='admin' or exists (select 1 from public.creditos c where c.id = abonos.credito_id and c.sede_id = public.mi_sede()) );
alter policy "ventas_detalle_rls" on public.ventas_detalle with check (
  public.mi_rol()='admin' or exists (select 1 from public.ventas v where v.id = ventas_detalle.venta_id and v.sede_id = public.mi_sede()) );
alter policy "bitacora_creditos_rls" on public.bitacora_creditos with check (
  public.mi_rol()='admin' or exists (select 1 from public.creditos c where c.id = bitacora_creditos.credito_id and c.sede_id = public.mi_sede()) );
alter policy "movimientos_caja_rls" on public.movimientos_caja with check (
  public.mi_rol()='admin' or exists (select 1 from public.cajas k where k.id = movimientos_caja.caja_id and k.sede_id = public.mi_sede()) );
