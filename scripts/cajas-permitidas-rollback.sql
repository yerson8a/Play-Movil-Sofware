-- ============================================================
-- ROLLBACK de cajas-permitidas.sql -> vuelve al criterio por sede
-- ============================================================
-- Restaura las políticas que había antes: cada usuario ve y opera solo
-- las cajas de su sede, y cualquier rol distinto de 'consulta' podía
-- crear/borrar cajas de su sede. Úsalo si el nuevo criterio bloquea algo.
-- Nota: al volver aquí, las cajas marcadas a un usuario de otra sede
-- dejan de funcionar (el módulo le queda vacío).
-- ============================================================

drop trigger if exists trg_cajas_solo_saldo on public.cajas;
drop function if exists public.cajas_solo_saldo();

drop policy if exists cajas_select on public.cajas;
drop policy if exists cajas_insert on public.cajas;
drop policy if exists cajas_update on public.cajas;
drop policy if exists cajas_delete on public.cajas;

create policy cajas_select on public.cajas
  for select to authenticated
  using ((public.mi_rol() = 'admin') or (sede_id = public.mi_sede()));

create policy cajas_insert on public.cajas
  for insert to authenticated
  with check (((public.mi_rol() = 'admin') or (sede_id = public.mi_sede()))
              and public.mi_rol() is distinct from 'consulta');

create policy cajas_update on public.cajas
  for update to authenticated
  using (((public.mi_rol() = 'admin') or (sede_id = public.mi_sede()))
         and public.mi_rol() is distinct from 'consulta')
  with check (((public.mi_rol() = 'admin') or (sede_id = public.mi_sede()))
              and public.mi_rol() is distinct from 'consulta');

create policy cajas_delete on public.cajas
  for delete to authenticated
  using (((public.mi_rol() = 'admin') or (sede_id = public.mi_sede()))
         and public.mi_rol() is distinct from 'consulta');

drop policy if exists movimientos_caja_select on public.movimientos_caja;
drop policy if exists movimientos_caja_insert on public.movimientos_caja;
drop policy if exists movimientos_caja_update on public.movimientos_caja;
drop policy if exists movimientos_caja_delete on public.movimientos_caja;

create policy movimientos_caja_select on public.movimientos_caja
  for select to authenticated
  using ((public.mi_rol() = 'admin') or exists (
    select 1 from public.cajas k where k.id = movimientos_caja.caja_id and k.sede_id = public.mi_sede()));

create policy movimientos_caja_insert on public.movimientos_caja
  for insert to authenticated
  with check (((public.mi_rol() = 'admin') or exists (
    select 1 from public.cajas k where k.id = movimientos_caja.caja_id and k.sede_id = public.mi_sede()))
    and public.mi_rol() is distinct from 'consulta');

create policy movimientos_caja_update on public.movimientos_caja
  for update to authenticated
  using (((public.mi_rol() = 'admin') or exists (
    select 1 from public.cajas k where k.id = movimientos_caja.caja_id and k.sede_id = public.mi_sede()))
    and public.mi_rol() is distinct from 'consulta')
  with check (((public.mi_rol() = 'admin') or exists (
    select 1 from public.cajas k where k.id = movimientos_caja.caja_id and k.sede_id = public.mi_sede()))
    and public.mi_rol() is distinct from 'consulta');

create policy movimientos_caja_delete on public.movimientos_caja
  for delete to authenticated
  using (((public.mi_rol() = 'admin') or exists (
    select 1 from public.cajas k where k.id = movimientos_caja.caja_id and k.sede_id = public.mi_sede()))
    and public.mi_rol() is distinct from 'consulta');
