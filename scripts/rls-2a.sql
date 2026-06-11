-- ============================================================
-- RLS Etapa 2a — LECTURA por sede/rol + bloqueo de anon
-- ============================================================
-- YA APLICADO en producción (migraciones rls_2a_lectura_por_sede
-- y rls_2a_fix_sistema_usuarios_lectura). Este archivo es la copia
-- versionada para trazabilidad. El rollback está en rls-2a-rollback.sql.
--
-- Modelo:
--   - anon: sin políticas -> sin acceso (bloqueado).
--   - Tablas con sede_id: admin ve todo, no-admin solo su sede.
--   - Tablas hijas: heredan la sede del padre (abonos, ventas_detalle,
--     bitacora_creditos, movimientos_caja).
--   - Compartidas (clientes, proveedores, etc.): cualquier autenticado.
--   - sistema_usuarios: lectura autenticada (dropdown de asesores),
--     escritura solo admin.
--   - ESCRITURAS quedan permisivas (WITH CHECK true) -> se endurecen en 2b.
-- ============================================================

-- Helpers
create or replace function public.mi_rol() returns text
  language sql stable security definer set search_path = public as $$
  select rol from public.perfiles where id = auth.uid()
$$;
create or replace function public.mi_sede() returns integer
  language sql stable security definer set search_path = public as $$
  select sede_id from public.perfiles where id = auth.uid()
$$;

-- Tablas con sede_id
drop policy if exists "acceso_total" on public.productos;
create policy "productos_rls" on public.productos for all to authenticated
  using ( public.mi_rol() = 'admin' or sede_id = public.mi_sede() ) with check ( true );
drop policy if exists "acceso_total" on public.ventas;
create policy "ventas_rls" on public.ventas for all to authenticated
  using ( public.mi_rol() = 'admin' or sede_id = public.mi_sede() ) with check ( true );
drop policy if exists "acceso_total" on public.creditos;
create policy "creditos_rls" on public.creditos for all to authenticated
  using ( public.mi_rol() = 'admin' or sede_id = public.mi_sede() ) with check ( true );
drop policy if exists "acceso_total" on public.garantias;
create policy "garantias_rls" on public.garantias for all to authenticated
  using ( public.mi_rol() = 'admin' or sede_id = public.mi_sede() ) with check ( true );
drop policy if exists "acceso_total" on public.gastos;
create policy "gastos_rls" on public.gastos for all to authenticated
  using ( public.mi_rol() = 'admin' or sede_id = public.mi_sede() ) with check ( true );
drop policy if exists "acceso_total" on public.servicio_tecnico;
create policy "servicio_tecnico_rls" on public.servicio_tecnico for all to authenticated
  using ( public.mi_rol() = 'admin' or sede_id = public.mi_sede() ) with check ( true );
drop policy if exists "acceso_total" on public.cajas;
create policy "cajas_rls" on public.cajas for all to authenticated
  using ( public.mi_rol() = 'admin' or sede_id = public.mi_sede() ) with check ( true );

-- Tablas hijas (heredan sede del padre)
drop policy if exists "acceso_total" on public.abonos;
create policy "abonos_rls" on public.abonos for all to authenticated
  using ( public.mi_rol() = 'admin' or exists (
    select 1 from public.creditos c where c.id = abonos.credito_id and c.sede_id = public.mi_sede()
  )) with check ( true );
drop policy if exists "acceso_total" on public.ventas_detalle;
create policy "ventas_detalle_rls" on public.ventas_detalle for all to authenticated
  using ( public.mi_rol() = 'admin' or exists (
    select 1 from public.ventas v where v.id = ventas_detalle.venta_id and v.sede_id = public.mi_sede()
  )) with check ( true );
drop policy if exists "acceso_total" on public.bitacora_creditos;
create policy "bitacora_creditos_rls" on public.bitacora_creditos for all to authenticated
  using ( public.mi_rol() = 'admin' or exists (
    select 1 from public.creditos c where c.id = bitacora_creditos.credito_id and c.sede_id = public.mi_sede()
  )) with check ( true );
drop policy if exists "acceso_total" on public.movimientos_caja;
create policy "movimientos_caja_rls" on public.movimientos_caja for all to authenticated
  using ( public.mi_rol() = 'admin' or exists (
    select 1 from public.cajas k where k.id = movimientos_caja.caja_id and k.sede_id = public.mi_sede()
  )) with check ( true );

-- sistema_usuarios: lectura autenticada, escritura solo admin
drop policy if exists "acceso_total" on public.sistema_usuarios;
drop policy if exists "sistema_usuarios_rls" on public.sistema_usuarios;
create policy "sistema_usuarios_select" on public.sistema_usuarios
  for select to authenticated using ( true );
create policy "sistema_usuarios_write_admin" on public.sistema_usuarios
  for all to authenticated using ( public.mi_rol() = 'admin' ) with check ( public.mi_rol() = 'admin' );

-- Compartidas (sin sede): cualquier autenticado
drop policy if exists "acceso_total" on public.clientes;
create policy "clientes_rls" on public.clientes for all to authenticated using (true) with check (true);
drop policy if exists "acceso_total" on public.proveedores;
create policy "proveedores_rls" on public.proveedores for all to authenticated using (true) with check (true);
drop policy if exists "acceso_total" on public.financieras;
create policy "financieras_rls" on public.financieras for all to authenticated using (true) with check (true);
drop policy if exists "acceso_total" on public.sedes;
create policy "sedes_rls" on public.sedes for all to authenticated using (true) with check (true);
drop policy if exists "acceso_total" on public.tareas_pendientes;
create policy "tareas_pendientes_rls" on public.tareas_pendientes for all to authenticated using (true) with check (true);
drop policy if exists "acceso_total" on public.bonos_comisiones;
create policy "bonos_comisiones_rls" on public.bonos_comisiones for all to authenticated using (true) with check (true);
drop policy if exists "acceso_total" on public.registros_gastos;
create policy "registros_gastos_rls" on public.registros_gastos for all to authenticated using (true) with check (true);
drop policy if exists "acceso_total" on public.configuracion_contabilidad;
create policy "configuracion_contabilidad_rls" on public.configuracion_contabilidad for all to authenticated using (true) with check (true);
drop policy if exists "acceso_total" on public.auditoria;
create policy "auditoria_rls" on public.auditoria for all to authenticated using (true) with check (true);
drop policy if exists "acceso_total" on public.usuarios;
create policy "usuarios_rls" on public.usuarios for all to authenticated using (true) with check (true);
