-- ============================================================
-- ROLLBACK del cambio de equipo con refinanciación
-- ============================================================
-- Quita la función y devuelve el CHECK de ventas a sus cinco estados.
--
-- ¡OJO! Antes de correrlo hay que reclasificar las ventas que ya estén en
-- estado 'cambio', o el ALTER falla por filas que violan la restricción:
--
--   select id, cliente, fecha_venta from ventas where estado = 'cambio';
--   -- decidir a qué estado pasan (normalmente 'devuelta') y actualizarlas:
--   -- update ventas set estado = 'devuelta' where estado = 'cambio';
--
-- Los créditos en CERRADO_POR_CAMBIO no bloquean nada (esa columna no tiene
-- CHECK), pero dejarán de verse en el módulo si además se revierte el cliente.
-- ============================================================

drop function if exists public.cambio_equipo_refinanciado(integer,integer,numeric,integer,numeric,text,date,date,numeric,text,text,boolean);

alter table public.ventas drop constraint if exists ventas_estado_check;
alter table public.ventas add constraint ventas_estado_check
  check (estado = any (array['activa','pendiente','anulada','devuelta','reversada']));

create or replace function public.ventas_proteger_no_activas()
returns trigger language plpgsql set search_path to 'public'
as $function$
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
$function$;
