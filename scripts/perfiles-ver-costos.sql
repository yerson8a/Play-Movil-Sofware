-- =====================================================================
-- Permiso individual "ver costos": el admin decide qué asesores pueden
-- ver precios de compra/costo (perfiles.ver_costos).
-- APLICADO en producción vía MCP el 2026-07-14 (migración perfiles_ver_costos).
-- Este archivo es la copia versionada.
-- =====================================================================

-- Permiso individual (asignado por el admin) para ver precios de costo
alter table public.perfiles add column if not exists ver_costos boolean not null default false;

-- El admin necesita listar y editar todos los perfiles para gestionar el permiso
create policy perfiles_select_admin on public.perfiles
  for select to authenticated
  using (public.mi_rol() = 'admin');

create policy perfiles_update_admin on public.perfiles
  for update to authenticated
  using (public.mi_rol() = 'admin')
  with check (public.mi_rol() = 'admin');

-- Blindaje: la política perfiles_update_propio permite editar la fila completa,
-- así que un no-admin podría escalar privilegios (rol, ver_costos, etc.).
-- Este trigger bloquea cambios a campos sensibles salvo para admin/service_role.
create or replace function public.perfiles_protege_privilegios()
returns trigger
language plpgsql security definer set search_path to 'public'
as $$
begin
  -- service_role o SQL directo (sin JWT de usuario): permitido
  if auth.uid() is null then return new; end if;
  if public.mi_rol() = 'admin' then return new; end if;
  if new.rol                is distinct from old.rol
     or new.sede_id            is distinct from old.sede_id
     or new.modulos_permitidos is distinct from old.modulos_permitidos
     or new.cajas_permitidas   is distinct from old.cajas_permitidas
     or new.activo             is distinct from old.activo
     or new.ver_costos         is distinct from old.ver_costos
     or new.usuario            is distinct from old.usuario then
    raise exception 'No autorizado para modificar campos de permisos del perfil';
  end if;
  return new;
end $$;

drop trigger if exists trg_perfiles_protege_privilegios on public.perfiles;
create trigger trg_perfiles_protege_privilegios
  before update on public.perfiles
  for each row execute function public.perfiles_protege_privilegios();

-- ============================== ROLLBACK ==============================
-- drop trigger if exists trg_perfiles_protege_privilegios on public.perfiles;
-- drop function if exists public.perfiles_protege_privilegios();
-- drop policy if exists perfiles_update_admin on public.perfiles;
-- drop policy if exists perfiles_select_admin on public.perfiles;
-- alter table public.perfiles drop column if exists ver_costos;
