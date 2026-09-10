-- ============================================================
-- Retoma / trade-in: reingresar al sistema un equipo ya vendido
-- ============================================================
-- Copia versionada de la migracion `retoma_imei`. Rollback: retoma-imei-rollback.sql.
--
-- Play Movil recompra equipos que ya vendio (retoma o trade-in). Hasta ahora el
-- IMEI quedaba quemado: cualquier registro previo en `productos` bloqueaba el
-- ingreso, asi el cliente ya hubiera pagado todo (caso credito #20, ANDRES
-- GIRALDO GALLEGO, IPHONE 13 PRO MAX: credito pagado, equipo sin poder volver
-- a entrar).
--
-- Un equipo solo se vuelve a ingresar cuando el ciclo anterior esta cerrado,
-- es decir cuando el negocio ya cobro:
--   · venta de CONTADO activa, o
--   · venta a credito cuyo credito quedo pagado (estado pagado o saldo <= 0)
-- Con el equipo todavia en inventario, con la venta anulada, o con un credito
-- vivo (al_dia / mora), el reingreso se rechaza.
--
-- Cada retoma es una COMPRA NUEVA: entra otra fila en `productos` con su propio
-- costo y su propia sede. La fila vieja no se toca, para no alterar la ganancia
-- ni el historial de la venta anterior. De ahi la nocion de CICLO VIGENTE: el
-- registro de `productos` de id mas alto para ese IMEI, y las ventas ligadas a
-- el (por producto_id, o por IMEI a partir de su fecha de ingreso). Las ventas
-- del ciclo anterior dejan de contar, y por eso el equipo retomado se puede
-- volver a vender sin chocar con su propia venta antigua.
--
-- La regla vive aqui y no en el navegador porque decide sobre datos que la RLS
-- le puede ocultar al asesor (un credito de otra sede) y porque el insert en
-- `productos` es un POST directo de PostgREST: sin el trigger, cualquiera desde
-- la consola puede saltarse la validacion del cliente.
-- ============================================================

-- ── Estado real de un IMEI ──────────────────────────────────────────────────
-- Responde dos preguntas sobre una sola nocion de ciclo:
--   reingreso_permitido -> se puede volver a comprar (retoma)
--   venta_permitida     -> se puede vender el que hay ahora en inventario
-- SECURITY DEFINER: el veredicto no puede depender de lo que la RLS deje ver.
create or replace function public.estado_imei(p_imei text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_imei      text := nullif(btrim(p_imei), '');
  v_prod      productos%rowtype;
  v_venta     ventas%rowtype;   -- venta activa mas reciente del ciclo vigente
  v_viva      ventas%rowtype;   -- activa o pendiente: el equipo ya salio
  v_credito   creditos%rowtype;
  v_desde     timestamp;
  v_imeis     text[];
  v_saldo     numeric;
  v_estado    text;
  v_prodj     jsonb := null;
  v_ventaj    jsonb := null;
  v_credj     jsonb := null;
  v_ok_venta  boolean;
  v_mot_venta text;
  v_msg_venta text := null;
  v_ok_rein   boolean := false;
  v_mot_rein  text;
  v_msg_rein  text := null;
begin
  if v_imei is null or length(v_imei) < 5 then
    return jsonb_build_object(
      'imei', p_imei,
      'reingreso_permitido', true, 'reingreso_motivo', 'sin_imei',
      'venta_permitida',     true, 'venta_motivo',     'sin_imei');
  end if;

  -- Ciclo vigente: el ultimo registro de ese IMEI en productos
  select * into v_prod
  from productos
  where btrim(coalesce(imei1,'')) = v_imei
     or btrim(coalesce(imei2,'')) = v_imei
  order by id desc
  limit 1;

  if not found then
    return jsonb_build_object(
      'imei', v_imei,
      'reingreso_permitido', true, 'reingreso_motivo', 'libre',
      'venta_permitida',     true, 'venta_motivo',     'sin_registro');
  end if;

  v_desde := coalesce(v_prod.created_at, v_prod.fecha_compra::timestamp, '-infinity'::timestamp);
  -- Las ventas guardan un solo IMEI (casi siempre el 1). Al preguntar por el IMEI 2
  -- del mismo equipo hay que reconocer igual su venta, asi que se buscan los dos.
  v_imeis := array_remove(array[nullif(btrim(coalesce(v_prod.imei1,'')), ''),
                               nullif(btrim(coalesce(v_prod.imei2,'')), ''),
                               v_imei], null);
  v_prodj := jsonb_build_object(
    'id', v_prod.id, 'producto', v_prod.producto, 'estado', v_prod.estado,
    'sede_id', v_prod.sede_id, 'fecha_compra', v_prod.fecha_compra);

  -- Ventas del ciclo vigente. `estado` manda; observaciones solo cubre las filas
  -- viejas que no lo tienen, igual que normalizarEstadoVenta() en el cliente.
  select * into v_venta
  from ventas v
  where (v.producto_id = v_prod.id
         or (btrim(coalesce(v.imei,'')) = any(v_imeis)
             and coalesce(v.created_at, v.fecha_venta::timestamp, '-infinity'::timestamp) >= v_desde))
    and coalesce(nullif(lower(btrim(coalesce(v.estado,''))), ''),
                 case when upper(coalesce(v.observaciones,'')) like 'ANULADA%'
                      then 'anulada' else 'activa' end) = 'activa'
  order by coalesce(v.created_at, v.fecha_venta::timestamp) desc nulls last, v.id desc
  limit 1;

  select * into v_viva
  from ventas v
  where (v.producto_id = v_prod.id
         or (btrim(coalesce(v.imei,'')) = any(v_imeis)
             and coalesce(v.created_at, v.fecha_venta::timestamp, '-infinity'::timestamp) >= v_desde))
    and coalesce(nullif(lower(btrim(coalesce(v.estado,''))), ''),
                 case when upper(coalesce(v.observaciones,'')) like 'ANULADA%'
                      then 'anulada' else 'activa' end) in ('activa','pendiente')
  order by coalesce(v.created_at, v.fecha_venta::timestamp) desc nulls last, v.id desc
  limit 1;

  if v_venta.id is not null then
    v_ventaj := jsonb_build_object(
      'id', v_venta.id, 'estado', v_venta.estado, 'forma_pago', v_venta.forma_pago,
      'fecha_venta', v_venta.fecha_venta, 'cliente', v_venta.cliente);
  end if;

  -- ── Se puede VENDER el equipo que hay ahora en inventario? ────────────────
  if v_viva.id is not null then
    v_ok_venta  := false;
    v_mot_venta := 'venta_viva';
    v_msg_venta := format('El IMEI %s ya tiene la venta #%s registrada y sin anular.',
                          v_imei, v_viva.id);
  elsif coalesce(v_prod.estado,'') = 'DISPONIBLE' then
    v_ok_venta  := true;
    v_mot_venta := 'disponible';
  else
    v_ok_venta  := false;
    v_mot_venta := lower(coalesce(nullif(btrim(v_prod.estado),''), 'sin_estado'));
    v_msg_venta := case coalesce(v_prod.estado,'')
      when 'VENDIDO'  then format('El equipo %s con IMEI %s ya fue vendido anteriormente y no esta disponible en inventario.', v_prod.producto, v_imei)
      when 'GARANTIA' then format('El equipo %s con IMEI %s esta actualmente en proceso de garantia.', v_prod.producto, v_imei)
      when 'DEVUELTO' then format('El equipo %s con IMEI %s fue dado de baja del inventario.', v_prod.producto, v_imei)
      else format('El equipo %s con IMEI %s esta en estado %s y no se puede vender.',
                  v_prod.producto, v_imei, coalesce(nullif(btrim(v_prod.estado),''), 'SIN ESTADO'))
    end;
  end if;

  -- ── Se puede REINGRESAR por retoma? ───────────────────────────────────────
  -- Solo un equipo que salio vendido: lo que sigue en inventario (DISPONIBLE),
  -- en garantia o dado de baja no se recompra, ya esta adentro.
  if coalesce(v_prod.estado, '') <> 'VENDIDO' then
    v_mot_rein := 'en_inventario';
    v_msg_rein := format(
      'El IMEI %s ya esta registrado en %s (estado %s). Solo se puede reingresar un equipo vendido y pagado.',
      v_imei, v_prod.producto, coalesce(nullif(btrim(v_prod.estado),''), 'SIN ESTADO'));

  elsif v_venta.id is null then
    -- Marcado VENDIDO pero sin venta activa: o la venta se anulo (y el equipo
    -- debio volver a inventario) o el registro quedo descuadrado. No se adivina.
    v_mot_rein := 'sin_venta';
    v_msg_rein := format(
      'El IMEI %s figura VENDIDO pero no tiene una venta activa que respalde el pago. Revisa la venta antes de reingresarlo.',
      v_imei);

  elsif upper(coalesce(v_venta.forma_pago, '')) not like '%CREDITO%'
    and upper(coalesce(v_venta.forma_pago, '')) not like '%CRÉDITO%' then
    -- Contado: se pago al momento de la venta.
    v_ok_rein  := true;
    v_mot_rein := 'contado_pagado';
    v_msg_rein := format('Retoma: el IMEI %s se vendio de contado (venta #%s, %s).',
                         v_imei, v_venta.id, coalesce(v_venta.cliente, 'sin cliente'));

  else
    -- Credito: la mitad de las filas viejas no guardan venta_id ni imei, asi que
    -- se busca por varias vias y se prefiere la mas confiable.
    select * into v_credito
    from creditos c
    where c.venta_id = v_venta.id
       or (c.imei is not null and btrim(c.imei) = any(v_imeis))
       or (c.producto_id is not null and c.producto_id = v_prod.id)
       or (c.cedula_cliente is not null
           and c.cedula_cliente = v_venta.cedula_cliente
           and upper(btrim(coalesce(c.producto_desc,''))) = upper(btrim(coalesce(v_venta.producto,'')))
           and c.fecha_inicio between v_venta.fecha_venta - 7 and v_venta.fecha_venta + 7)
    order by
      case
        when c.venta_id = v_venta.id                                 then 0
        when c.imei is not null and btrim(c.imei) = any(v_imeis)      then 1
        when c.producto_id is not null and c.producto_id = v_prod.id  then 2
        else 3
      end,
      c.id desc
    limit 1;

    if v_credito.id is null then
      v_mot_rein := 'credito_no_encontrado';
      v_msg_rein := format(
        'La venta #%s del IMEI %s fue a credito y no se encontro el credito para verificar que este pagado.',
        v_venta.id, v_imei);
    else
      v_estado := lower(coalesce(v_credito.estado, ''));
      v_saldo  := coalesce(v_credito.saldo_pendiente, 0);
      v_credj  := jsonb_build_object(
        'id', v_credito.id, 'estado', v_credito.estado, 'saldo_pendiente', v_saldo,
        'cliente', v_credito.cliente, 'financiera', v_credito.financiera,
        'cuotas_pagadas', v_credito.cuotas_pagadas, 'cuotas_total', v_credito.cuotas_total);

      if v_estado = 'pagado' or v_saldo <= 0 then
        v_ok_rein  := true;
        v_mot_rein := 'credito_pagado';
        v_msg_rein := format('Retoma: el credito #%s de %s quedo pagado en su totalidad.',
                             v_credito.id, coalesce(v_credito.cliente, 'sin cliente'));
      elsif v_estado = 'anulado' then
        v_mot_rein := 'credito_anulado';
        v_msg_rein := format(
          'El credito #%s del IMEI %s esta anulado: el equipo debe volver al inventario por la anulacion, no por una retoma.',
          v_credito.id, v_imei);
      else
        v_mot_rein := 'credito_pendiente';
        v_msg_rein := format(
          'El credito #%s de %s esta %s con saldo pendiente de $%s. El equipo no se puede reingresar hasta que quede pagado.',
          v_credito.id, coalesce(v_credito.cliente, 'sin cliente'),
          upper(coalesce(nullif(v_credito.estado,''), 'ABIERTO')),
          to_char(v_saldo, 'FM999G999G999'));
      end if;
    end if;
  end if;

  return jsonb_build_object(
    'imei', v_imei,
    'producto', v_prodj, 'venta', v_ventaj, 'credito', v_credj,
    'venta_permitida', v_ok_venta, 'venta_motivo', v_mot_venta, 'venta_mensaje', v_msg_venta,
    'reingreso_permitido', v_ok_rein, 'reingreso_motivo', v_mot_rein, 'reingreso_mensaje', v_msg_rein);
end;
$function$;

-- La anon key viaja en el HTML y estado_imei() devuelve cliente y saldo del
-- credito, asi que solo la puede llamar una sesion iniciada.
revoke all on function public.estado_imei(text) from public, anon;
grant execute on function public.estado_imei(text) to authenticated;

-- ── Unicidad del equipo vigente ─────────────────────────────────────────────
-- El bloqueo de fondo no estaba en el cliente sino aqui: idx_productos_imei1
-- era UNIQUE sobre todas las filas, asi que un IMEI vendido quedaba quemado
-- para siempre. La unicidad que si hace falta es la del equipo VIGENTE: un
-- mismo IMEI puede tener varias filas historicas (vendidas), pero solo una sin
-- vender a la vez. Que el ciclo anterior este cobrado lo verifica el trigger.
drop index if exists public.idx_productos_imei1;

create unique index idx_productos_imei1_vigente on public.productos (imei1)
  where imei1 is not null and imei1::text <> '' and estado is distinct from 'VENDIDO';

-- Se conserva la busqueda por IMEI sobre todo el historial, ya sin unicidad.
create index if not exists idx_productos_imei1 on public.productos (imei1)
  where imei1 is not null and imei1::text <> '';

-- ── Blindaje del insert ─────────────────────────────────────────────────────
-- La validacion del navegador es una cortesia; esta es la que manda.
create or replace function public.productos_validar_reingreso()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_imei text;
  v_est  jsonb;
begin
  if nullif(btrim(coalesce(new.imei1,'')), '') is not null
     and btrim(coalesce(new.imei1,'')) = btrim(coalesce(new.imei2,'')) then
    raise exception 'El IMEI 1 y el IMEI 2 no pueden ser iguales.' using errcode = '23505';
  end if;

  foreach v_imei in array array[nullif(btrim(coalesce(new.imei1,'')), ''),
                               nullif(btrim(coalesce(new.imei2,'')), '')]
  loop
    continue when v_imei is null or length(v_imei) < 5;
    v_est := estado_imei(v_imei);
    if not coalesce((v_est->>'reingreso_permitido')::boolean, false) then
      raise exception '%', coalesce(
        v_est->>'reingreso_mensaje',
        format('El IMEI %s ya esta registrado y no se puede volver a ingresar.', v_imei))
        using errcode = '23505';
    end if;
  end loop;

  return new;
end;
$function$;

-- Funcion de trigger: nadie la llama directamente.
revoke all on function public.productos_validar_reingreso() from public, anon, authenticated;

drop trigger if exists productos_validar_reingreso on public.productos;
create trigger productos_validar_reingreso
  before insert on public.productos
  for each row execute function public.productos_validar_reingreso();
