-- ============================================================
-- Cajas: la asignación por usuario manda sobre la sede
-- ============================================================
-- YA APLICADO en producción (migración cajas_permitidas_mandan_sobre_sede).
-- Copia versionada. Rollback: cajas-permitidas-rollback.sql.
--
-- Antes: un usuario solo veía las cajas de SU sede. Marcarle en el panel
-- una caja de otra sede se guardaba, pero la RLS se la seguía negando y
-- el módulo le quedaba vacío sin explicación.
--
-- Ahora, para un no-admin:
--   - con cajas marcadas  -> ve y opera exactamente esas, sea cual sea su sede
--   - sin cajas marcadas  -> las de su sede (comportamiento anterior)
-- Y solo puede mover dinero: crear, renombrar, activar o borrar cajas
-- queda reservado al rol admin (política + trigger cajas_solo_saldo).
-- ============================================================

-- Lista de cajas asignadas al usuario actual, o NULL si no tiene ninguna marcada.
create or replace function public.mis_cajas_permitidas()
returns int[]
language plpgsql stable security definer set search_path to 'public'
as $$
declare
  crudo text;
  res   int[];
begin
  select cajas_permitidas into crudo from public.perfiles where id = auth.uid();
  if crudo is null or btrim(crudo) in ('', 'null', '[]') then
    return null;
  end if;
  begin
    select array_agg(v::int) into res
      from jsonb_array_elements_text(crudo::jsonb) v;
  exception when others then
    -- Valor corrupto: se ignora y se cae al criterio por sede
    return null;
  end;
  if res is null or array_length(res, 1) is null then
    return null;
  end if;
  return res;
end;
$$;

-- ¿Puede el usuario actual ver/operar esta caja?
create or replace function public.puede_operar_caja(p_caja_id integer)
returns boolean
language plpgsql stable security definer set search_path to 'public'
as $$
declare
  permitidas int[];
  sede_caja  integer;
begin
  if public.mi_rol() = 'admin' then
    return true;
  end if;
  permitidas := public.mis_cajas_permitidas();
  if permitidas is not null then
    return p_caja_id = any(permitidas);
  end if;
  select sede_id into sede_caja from public.cajas where id = p_caja_id;
  return coalesce(sede_caja = public.mi_sede(), false);
end;
$$;

grant execute on function public.mis_cajas_permitidas() to authenticated;
grant execute on function public.puede_operar_caja(integer) to authenticated;

-- ---------- Políticas de cajas ----------
drop policy if exists cajas_select on public.cajas;
drop policy if exists cajas_insert on public.cajas;
drop policy if exists cajas_update on public.cajas;
drop policy if exists cajas_delete on public.cajas;

create policy cajas_select on public.cajas
  for select to authenticated
  using (public.puede_operar_caja(id));

-- Crear y eliminar cajas es solo del admin
create policy cajas_insert on public.cajas
  for insert to authenticated
  with check (public.mi_rol() = 'admin');

create policy cajas_delete on public.cajas
  for delete to authenticated
  using (public.mi_rol() = 'admin');

-- Un no-admin solo actualiza el saldo (lo restringe el trigger de abajo)
create policy cajas_update on public.cajas
  for update to authenticated
  using (public.puede_operar_caja(id) and public.mi_rol() is distinct from 'consulta')
  with check (public.puede_operar_caja(id) and public.mi_rol() is distinct from 'consulta');

-- Solo el admin cambia nombre, sede, estado o descripción de una caja.
-- Al resto la política de update le sirve únicamente para ingresos y salidas.
create or replace function public.cajas_solo_saldo()
returns trigger
language plpgsql security definer set search_path to 'public'
as $$
begin
  if public.mi_rol() = 'admin' then
    return new;
  end if;
  if new.nombre is distinct from old.nombre
     or new.sede_id is distinct from old.sede_id
     or new.estado is distinct from old.estado
     or new.descripcion is distinct from old.descripcion then
    raise exception 'Solo el administrador puede modificar los datos de una caja; tu permiso es unicamente para registrar ingresos y salidas';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_cajas_solo_saldo on public.cajas;
create trigger trg_cajas_solo_saldo
  before update on public.cajas
  for each row execute function public.cajas_solo_saldo();

-- ---------- Políticas de movimientos_caja ----------
drop policy if exists movimientos_caja_select on public.movimientos_caja;
drop policy if exists movimientos_caja_insert on public.movimientos_caja;
drop policy if exists movimientos_caja_update on public.movimientos_caja;
drop policy if exists movimientos_caja_delete on public.movimientos_caja;

create policy movimientos_caja_select on public.movimientos_caja
  for select to authenticated
  using (public.puede_operar_caja(caja_id));

create policy movimientos_caja_insert on public.movimientos_caja
  for insert to authenticated
  with check (public.puede_operar_caja(caja_id) and public.mi_rol() is distinct from 'consulta');

-- El historial es append-only: nadie lo edita, solo el admin puede corregirlo
create policy movimientos_caja_update on public.movimientos_caja
  for update to authenticated
  using (public.mi_rol() = 'admin')
  with check (public.mi_rol() = 'admin');

create policy movimientos_caja_delete on public.movimientos_caja
  for delete to authenticated
  using (public.mi_rol() = 'admin');
