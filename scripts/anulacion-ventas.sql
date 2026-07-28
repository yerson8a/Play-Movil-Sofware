-- ============================================================================
-- MÓDULO DE ANULACIÓN DE VENTAS — SQL versionado (ya aplicado en producción)
-- ============================================================================
-- Aplicado el 2026-07-28 vía MCP. Este archivo es la copia versionada de las
-- migraciones; no se ejecuta automáticamente. Migraciones en Supabase:
--
--   20260728223720  ventas_historial_estados_y_trazabilidad
--   20260728223736  trigger_auditoria_estado_ventas
--   20260728223745  vista_ventas_activas
--   20260728223827  funcion_anular_venta_transaccional
--   20260728223852  ventas_sin_borrado_fisico_y_abonos_bloqueados
--   20260728224207  fix_mensaje_bloqueo_delete_ventas
--   20260728225319  proteger_ventas_anuladas_de_edicion
--
-- Ninguna migración anterior fue modificada. Ninguna tabla ni fila se eliminó.
--
-- RESUMEN DE LA ARQUITECTURA
-- --------------------------
-- Antes: la anulación eran ~8 fetch sueltos desde el navegador. Si el proceso
-- se interrumpía, quedaba a medias (evidencia: 53 ventas anuladas con su
-- equipo todavía en estado VENDIDO). Además la validación de permisos vivía
-- solo en JavaScript, saltable desde la consola del navegador.
--
-- Ahora: todo ocurre dentro de anular_venta(), una única transacción en
-- PostgreSQL. Si cualquier paso falla, ROLLBACK total. Los permisos se validan
-- en el motor. El frontend solo llama la RPC y muestra el resultado.
--
-- ORDEN DE EJECUCIÓN si se recrea desde cero: tal como está en este archivo.
-- ============================================================================


-- ────────────────────────────────────────────────────────────────────────────
-- 1. TRAZABILIDAD: usuario real, estado de comisión, historial append-only
-- ────────────────────────────────────────────────────────────────────────────

alter table public.ventas
  add column if not exists usuario_estado_id uuid references auth.users(id);

alter table public.ventas
  add column if not exists comision_estado text not null default 'pendiente';

alter table public.ventas drop constraint if exists ventas_comision_estado_check;
alter table public.ventas
  add constraint ventas_comision_estado_check
  check (comision_estado in ('pendiente','pagada','revertida'));

update public.ventas
   set comision_estado = 'revertida'
 where estado <> 'activa' and comision_estado = 'pendiente';

create table if not exists public.ventas_historial_estados (
  id              bigserial primary key,
  venta_id        integer not null references public.ventas(id) on delete cascade,
  estado_anterior text,
  estado_nuevo    text not null,
  usuario_id      uuid,
  usuario         text,
  motivo          text,
  observaciones   text,
  ip              text,
  created_at      timestamptz not null default now()
);

create index if not exists idx_vhe_venta on public.ventas_historial_estados (venta_id, created_at desc);
create index if not exists idx_vhe_fecha on public.ventas_historial_estados (created_at desc);

alter table public.ventas_historial_estados enable row level security;

-- Solo lectura. Nadie escribe a mano: las filas las pone el trigger.
drop policy if exists vhe_select on public.ventas_historial_estados;
create policy vhe_select on public.ventas_historial_estados
  for select using (
    mi_rol() = 'admin'
    or exists (select 1 from public.ventas v
                where v.id = ventas_historial_estados.venta_id
                  and v.sede_id = mi_sede())
  );


-- ────────────────────────────────────────────────────────────────────────────
-- 2. AUDITORÍA AUTOMÁTICA: no depende del frontend
-- ────────────────────────────────────────────────────────────────────────────

create or replace function public.ventas_registrar_cambio_estado()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_usuario_id uuid;
  v_nombre     text;
  v_ip         text;
begin
  if new.estado is not distinct from old.estado then
    return new;
  end if;

  v_usuario_id := auth.uid();
  select p.nombre into v_nombre from public.perfiles p where p.id = v_usuario_id;
  v_nombre := coalesce(v_nombre, new.usuario_estado, 'SISTEMA');

  begin
    v_ip := split_part(
      coalesce(current_setting('request.headers', true)::json ->> 'x-forwarded-for', ''), ',', 1);
  exception when others then
    v_ip := null;
  end;

  insert into public.ventas_historial_estados
    (venta_id, estado_anterior, estado_nuevo, usuario_id, usuario, motivo, observaciones, ip)
  values
    (new.id, old.estado, new.estado, v_usuario_id, v_nombre,
     new.motivo_estado, new.observaciones, nullif(v_ip, ''));

  insert into public.auditoria
    (tabla, registro_id, accion, datos_antes, datos_despues, usuario, ip)
  values
    ('ventas', new.id, 'cambio_estado',
     jsonb_build_object('estado', old.estado, 'valor_venta', old.valor_venta,
                        'ganancia', old.ganancia, 'comision_asesor', old.comision_asesor,
                        'comision_estado', old.comision_estado),
     jsonb_build_object('estado', new.estado, 'valor_venta', new.valor_venta,
                        'ganancia', new.ganancia, 'comision_asesor', new.comision_asesor,
                        'comision_estado', new.comision_estado,
                        'motivo', new.motivo_estado),
     v_nombre, nullif(v_ip, ''));

  return new;
end;
$$;

drop trigger if exists trg_ventas_historial_estado on public.ventas;
create trigger trg_ventas_historial_estado
  after update of estado on public.ventas
  for each row execute function public.ventas_registrar_cambio_estado();


-- ────────────────────────────────────────────────────────────────────────────
-- 3. VISTA ventas_activas — fuente única para cifras
-- ────────────────────────────────────────────────────────────────────────────

create or replace view public.ventas_activas
with (security_invoker = true) as
select v.* from public.ventas v where v.estado = 'activa';


-- ────────────────────────────────────────────────────────────────────────────
-- 4. anular_venta() — proceso único y transaccional
-- ────────────────────────────────────────────────────────────────────────────
-- NOTA: la reversión de caja (FASE 8 del pedido) NO se implementa porque las
-- ventas de esta aplicación no generan movimientos de caja: los 91 movimientos
-- existentes son manuales desde el módulo Cajas. No hay ingreso que revertir.

create or replace function public.anular_venta(
  p_venta_id integer,
  p_estado   text default 'anulada',
  p_motivo   text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rol            text;
  v_usuario_id     uuid;
  v_nombre         text;
  v_venta          public.ventas%rowtype;
  v_nota           text;
  v_equipos        text[] := '{}';
  v_creditos       text[] := '{}';
  v_abonos_rev     integer := 0;
  v_prod           record;
  v_cred           record;
  v_prod_id        integer;
  v_imei_limpio    text;
begin
  -- Permisos validados en PostgreSQL, no en el navegador
  v_usuario_id := auth.uid();
  if v_usuario_id is null then
    raise exception 'Sesion no valida: debes iniciar sesion para anular una venta.'
      using errcode = '28000';
  end if;

  select rol, nombre into v_rol, v_nombre from public.perfiles where id = v_usuario_id;

  if v_rol is distinct from 'admin' then
    raise exception 'Solo un administrador puede anular ventas (tu rol: %).', coalesce(v_rol,'sin rol')
      using errcode = '42501';
  end if;

  if p_estado not in ('anulada','devuelta','reversada') then
    raise exception 'Estado no valido para anulacion: %. Debe ser anulada, devuelta o reversada.', p_estado
      using errcode = '22023';
  end if;

  -- FOR UPDATE serializa dos anulaciones simultáneas de la misma venta
  select * into v_venta from public.ventas where id = p_venta_id for update;

  if not found then
    raise exception 'La venta #% no existe.', p_venta_id using errcode = 'P0002';
  end if;

  -- Evitar doble ejecución: si ya está revertida, no se toca NADA
  if v_venta.estado in ('anulada','devuelta','reversada') then
    raise exception 'La venta #% ya esta % desde %. No se modifica inventario, creditos ni comisiones.',
      p_venta_id, upper(v_venta.estado), coalesce(v_venta.fecha_estado::text, 'fecha desconocida')
      using errcode = '23505';
  end if;

  v_nota := upper(p_estado) || ': ' || coalesce(nullif(trim(p_motivo), ''), 'Sin motivo especificado');

  -- valor_venta y ganancia se CONSERVAN (los reportes excluyen por estado, así
  -- se puede informar cuánto se anuló). La comisión sí se revierte.
  update public.ventas
     set estado            = p_estado,
         motivo_estado     = v_nota,
         fecha_estado      = now(),
         usuario_estado    = coalesce(v_nombre, 'ADMIN'),
         usuario_estado_id = v_usuario_id,
         comision_asesor   = 0,
         comision_estado   = 'revertida',
         observaciones     = v_nota
   where id = p_venta_id;

  -- Inventario: solo productos en VENDIDO. Si ya fue reintegrado o revendido,
  -- su estado ya no es VENDIDO y se omite: nunca se cuenta dos veces.
  for v_prod in
    select coalesce(d.imei, '') as imei, coalesce(d.producto, '') as producto
      from public.ventas_detalle d where d.venta_id = p_venta_id
    union all
    select coalesce(v_venta.imei, ''), coalesce(v_venta.producto, '')
     where not exists (select 1 from public.ventas_detalle d where d.venta_id = p_venta_id)
  loop
    v_prod_id := null;
    v_imei_limpio := regexp_replace(v_prod.imei, '[^0-9A-Za-z]', '', 'g');

    if length(v_imei_limpio) >= 5 then
      select p.id into v_prod_id from public.productos p
       where (p.imei1 = v_imei_limpio or p.imei2 = v_imei_limpio or p.serial = v_imei_limpio)
         and p.estado = 'VENDIDO'
       limit 1;
    end if;

    if v_prod_id is null and length(v_imei_limpio) < 5 and v_prod.producto <> '' then
      select p.id into v_prod_id from public.productos p
       where p.producto = v_prod.producto and p.estado = 'VENDIDO' limit 1;
    end if;

    if v_prod_id is not null then
      update public.productos set estado = 'DISPONIBLE' where id = v_prod_id;
      select array_append(v_equipos, p.producto) into v_equipos
        from public.productos p where p.id = v_prod_id;
    end if;
  end loop;

  -- Crédito: vínculo exacto por venta_id; respaldo por IMEI solo para créditos
  -- antiguos. Nunca se anula cartera por cédula sola.
  for v_cred in
    select c.id, c.cliente from public.creditos c
     where c.estado <> 'anulado'
       and (c.venta_id = p_venta_id
            or (c.venta_id is null
                and v_venta.imei is not null and v_venta.imei <> ''
                and c.imei = v_venta.imei))
     order by c.venta_id nulls last, c.created_at desc
  loop
    update public.creditos
       set estado = 'anulado',
           observaciones = v_nota || ' (venta #' || p_venta_id || ')'
     where id = v_cred.id;

    -- Los pagos recibidos se marcan revertidos: se conserva la trazabilidad,
    -- no se borra ningún abono.
    update public.abonos
       set notas = coalesce(notas || ' | ', '') || 'REVERTIDO: ' || v_nota
     where credito_id = v_cred.id
       and coalesce(notas, '') not like 'REVERTIDO:%'
       and coalesce(notas, '') not like '%| REVERTIDO:%';
    get diagnostics v_abonos_rev = row_count;

    insert into public.bitacora_creditos (credito_id, fecha, tipo, resultado, nota, usuario)
    values (v_cred.id, current_date, 'anulacion', 'anulado',
            v_nota || ' (venta #' || p_venta_id || ')', coalesce(v_nombre,'ADMIN'));

    v_creditos := array_append(v_creditos, '#' || v_cred.id || ' ' || coalesce(v_cred.cliente,''));
  end loop;

  return jsonb_build_object(
    'ok', true, 'venta_id', p_venta_id, 'estado', p_estado, 'motivo', v_nota,
    'usuario', coalesce(v_nombre,'ADMIN'),
    'equipos_devueltos', to_jsonb(v_equipos),
    'creditos_anulados', to_jsonb(v_creditos),
    'abonos_revertidos', v_abonos_rev
  );
end;
$$;

revoke all on function public.anular_venta(integer, text, text) from public, anon;
grant execute on function public.anular_venta(integer, text, text) to authenticated;


-- ────────────────────────────────────────────────────────────────────────────
-- 5. SIN BORRADO FÍSICO + abonos bloqueados en créditos anulados
-- ────────────────────────────────────────────────────────────────────────────

drop policy if exists ventas_delete on public.ventas;
drop policy if exists ventas_detalle_delete on public.ventas_detalle;

revoke delete on public.ventas         from authenticated, anon;
revoke delete on public.ventas_detalle from authenticated, anon;

create or replace function public.ventas_bloquear_delete()
returns trigger language plpgsql as $$
begin
  raise exception 'Las ventas no se eliminan. Usa anular_venta(%) para anular, devolver o reversar.', old.id
    using errcode = '42501';
end;
$$;

drop trigger if exists trg_ventas_no_delete on public.ventas;
create trigger trg_ventas_no_delete
  before delete on public.ventas
  for each row execute function public.ventas_bloquear_delete();

create or replace function public.abonos_bloquear_credito_anulado()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_estado text;
begin
  select estado into v_estado from public.creditos where id = new.credito_id;
  if v_estado = 'anulado' then
    raise exception 'El credito #% esta ANULADO: no admite nuevos abonos.', new.credito_id
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_abonos_credito_anulado on public.abonos;
create trigger trg_abonos_credito_anulado
  before insert on public.abonos
  for each row execute function public.abonos_bloquear_credito_anulado();


-- ────────────────────────────────────────────────────────────────────────────
-- 6. Las ventas no activas son de solo consulta
-- ────────────────────────────────────────────────────────────────────────────

create or replace function public.ventas_proteger_no_activas()
returns trigger language plpgsql as $$
begin
  if old.estado not in ('anulada','devuelta','reversada') then
    return new;
  end if;

  if coalesce(current_setting('app.anulacion_en_curso', true), '') = 'si' then
    return new;
  end if;

  if new.comision_asesor is distinct from old.comision_asesor then
    raise exception 'La venta #% esta % y no genera comision.', old.id, upper(old.estado)
      using errcode = '42501';
  end if;

  if new.valor_venta is distinct from old.valor_venta
     or new.ganancia is distinct from old.ganancia
     or new.valor_compra is distinct from old.valor_compra then
    raise exception 'La venta #% esta % : sus cifras no se pueden modificar.', old.id, upper(old.estado)
      using errcode = '42501';
  end if;

  if new.estado = 'activa' and mi_rol() is distinct from 'admin' then
    raise exception 'Solo un administrador puede reactivar la venta #%.', old.id
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_ventas_proteger_no_activas on public.ventas;
create trigger trg_ventas_proteger_no_activas
  before update on public.ventas
  for each row execute function public.ventas_proteger_no_activas();


-- ============================================================================
-- PENDIENTES CONOCIDOS (decisión del negocio: no corregir el histórico)
-- ============================================================================
-- · 53 ventas anuladas antes de este cambio tienen su equipo todavía en estado
--   VENDIDO. Se dejaron como están por decisión explícita: reintegrarlas a
--   ciegas podría crear inventario fantasma si alguna ya se revendió.
--   Consulta para listarlas:
--     select v.id, v.producto, v.imei, v.fecha_venta
--       from ventas v join productos p on p.imei1 = v.imei
--      where v.estado <> 'activa' and p.estado = 'VENDIDO';
--
-- · 2 créditos anulados conservan abonos por $3.658.333 sin marcar como
--   revertidos (los anteriores a este cambio). Consulta:
--     select c.id, c.cliente, sum(a.valor)
--       from creditos c join abonos a on a.credito_id = c.id
--      where c.estado = 'anulado' and coalesce(a.notas,'') not like '%REVERTIDO%'
--      group by 1,2;
--
-- · Las 61 anulaciones históricas tienen valor_venta = 0 (el código anterior lo
--   ponía en cero). No se puede recuperar el monto original, así que los
--   informes las muestran con $0. Las nuevas sí conservan el valor.
-- ============================================================================
