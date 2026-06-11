-- ============================================================
-- Play Móvil — Tabla `perfiles` para Supabase Auth
-- ============================================================
-- Enlaza cada usuario de auth.users con su rol/sede/permisos.
-- Ejecuta este script UNA vez en: Supabase → SQL Editor.
-- Es idempotente (puedes correrlo de nuevo sin romper nada).
--
-- Orden recomendado:
--   1) Ejecutar este SQL (crea la tabla y sus políticas).
--   2) Correr scripts/migrar-usuarios.mjs (crea las cuentas Auth y
--      rellena `perfiles` con la service_role).
-- ============================================================

create table if not exists public.perfiles (
  id                    uuid primary key references auth.users(id) on delete cascade,
  usuario               text    not null unique,        -- el "usuario" original (ej: admin, 1088303360)
  nombre                text    not null,
  rol                   text    not null default 'asesor',
  sede_id               integer references public.sedes(id),
  modulos_permitidos    text,                            -- JSON array (igual que en sistema_usuarios)
  cajas_permitidas      text,                            -- JSON array (igual que en sistema_usuarios)
  activo                boolean not null default true,
  debe_cambiar_password boolean not null default true,
  ultimo_acceso         timestamptz,
  created_at            timestamptz not null default now()
);

-- ── Row Level Security ──────────────────────────────────────
alter table public.perfiles enable row level security;

-- Cada usuario autenticado solo PUEDE LEER su propio perfil.
drop policy if exists "perfiles_select_propio" on public.perfiles;
create policy "perfiles_select_propio" on public.perfiles
  for select to authenticated
  using (auth.uid() = id);

-- Cada usuario autenticado solo PUEDE ACTUALIZAR su propio perfil...
drop policy if exists "perfiles_update_propio" on public.perfiles;
create policy "perfiles_update_propio" on public.perfiles
  for update to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- ── Permisos de tabla (PostgREST) ───────────────────────────
-- IMPORTANTE: se concede UPDATE solo sobre 2 columnas. Así, aunque la RLS
-- permita editar la fila propia, el usuario NO puede auto-asignarse rol/sede/
-- permisos desde el frontend. El INSERT lo hace el script con service_role
-- (bypassa RLS), por eso aquí no se concede insert a authenticated.
grant select on public.perfiles to authenticated;
grant update (debe_cambiar_password, ultimo_acceso) on public.perfiles to authenticated;

-- (No se concede nada a `anon`: la tabla solo se accede con sesión iniciada.)
