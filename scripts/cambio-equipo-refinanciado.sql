-- ============================================================
-- Cambio de equipo CON refinanciación
-- ============================================================
-- YA APLICADO en producción (migraciones `ventas_estado_cambio_de_equipo`
-- y `cambio_equipo_refinanciado`).
-- Copia versionada. Rollback: cambio-equipo-refinanciado-rollback.sql.
--
-- Distinto del cambio simple que ya existía en el cliente (sustituir el aparato
-- dentro de la misma venta, por garantía o falla, sin tocar el precio): aquí el
-- cliente se lleva un equipo de OTRO precio, lo ya pagado (inicial + abonos
-- reales) se convierte en la inicial de una VENTA NUEVA y se renegocian las
-- cuotas.
--
-- Son 8 escrituras en 5 tablas. Hechas como fetch sueltos desde el navegador,
-- un fallo a mitad deja un crédito cerrado sin venta nueva, o un equipo vendido
-- sin crédito. Aquí o pasa todo o no pasa nada.
--
-- Reglas que hace cumplir:
--   · solo rol admin (validado en SQL, no en el navegador)
--   · el equipo que entra debe estar DISPONIBLE
--   · el crédito origen no puede estar pagado/anulado/CERRADO_POR_CAMBIO
--     (SELECT FOR UPDATE serializa dos cambios simultáneos de lo mismo)
--   · la inicial trasladada sale SIEMPRE de sum(abonos), nunca de un contador
--   · cuotas x valor_cuota debe igualar el saldo (tolerancia: 1 peso por cuota)
--   · saldo a favor -> se rechaza; esa devolución se gestiona aparte
--   · saldo 0 -> la venta queda de contado y no se crea crédito nuevo
--   · la comisión de la venta original SE CONSERVA: esa venta sí se concretó
-- ============================================================

-- ── Parte 1: sexto estado de venta ──────────────────────────────────────────
alter table public.ventas drop constraint if exists ventas_estado_check;
alter table public.ventas add constraint ventas_estado_check
  check (estado = any (array['activa','pendiente','anulada','devuelta','reversada','cambio']));

-- Una venta marcada como cambio queda protegida igual que las anuladas, pero
-- conservando la comisión del asesor.
create or replace function public.ventas_proteger_no_activas()
returns trigger language plpgsql set search_path to 'public'
as $function$
begin
  if old.estado not in ('anulada','devuelta','reversada','cambio') then
    return new;
  end if;
  if coalesce(current_setting('app.anulacion_en_curso', true), '') = 'si' then
    return new;
  end if;
  if old.estado <> 'cambio' and new.comision_asesor is distinct from old.comision_asesor then
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

-- ── Parte 2: la operación completa, en una sola transacción ─────────────────
-- El cuerpo vive en la migración `cambio_equipo_refinanciado`; para reinstalarlo
-- desde cero, recuperar la definición con:
--   select pg_get_functiondef(oid) from pg_proc
--    where proname = 'cambio_equipo_refinanciado';
-- Firma:
--   cambio_equipo_refinanciado(
--     p_credito_id integer, p_producto_nuevo_id integer, p_valor_venta numeric,
--     p_cuotas integer default 0, p_valor_cuota numeric default 0,
--     p_frecuencia text default 'Quincenal',
--     p_fecha_primer_pago date default null, p_fecha_segundo_pago date default null,
--     p_comision_asesor numeric default 0, p_motivo text default null,
--     p_observaciones text default null, p_devolver_disponible boolean default true
--   ) returns jsonb  -- SECURITY DEFINER
--
-- Devuelve: ok, credito_anterior, venta_anterior, venta_nueva, credito_nuevo,
--           equipo_entra, equipo_sale_id, inicial_trasladada, abonos_sumados,
--           saldo_financiar, ganancia, avisos[]

revoke all on function public.cambio_equipo_refinanciado(integer,integer,numeric,integer,numeric,text,date,date,numeric,text,text,boolean) from public;
grant execute on function public.cambio_equipo_refinanciado(integer,integer,numeric,integer,numeric,text,date,date,numeric,text,text,boolean) to authenticated;
