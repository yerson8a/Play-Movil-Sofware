-- ============================================================
-- ROLLBACK de la Etapa 2a — restaurar acceso total (público)
-- ============================================================
-- Úsalo SOLO si 2a rompe algo en producción y necesitas volver al
-- estado anterior de inmediato (vuelve a abrir todo a la anon key,
-- igual que antes de 2a). Ejecutar en Supabase → SQL Editor.
-- ============================================================

do $$
declare t text;
begin
  foreach t in array array[
    'productos','ventas','creditos','garantias','gastos','servicio_tecnico','cajas',
    'abonos','ventas_detalle','bitacora_creditos','movimientos_caja',
    'clientes','proveedores','financieras','sedes','tareas_pendientes','bonos_comisiones',
    'registros_gastos','configuracion_contabilidad','auditoria','usuarios','sistema_usuarios'
  ]
  loop
    execute format('drop policy if exists %I on public.%I', t||'_rls', t);
    execute format('drop policy if exists %I on public.%I', 'acceso_total', t);
    execute format('create policy %I on public.%I for all to public using (true) with check (true)', 'acceso_total', t);
  end loop;
  -- políticas extra de sistema_usuarios
  execute 'drop policy if exists "sistema_usuarios_select" on public.sistema_usuarios';
  execute 'drop policy if exists "sistema_usuarios_write_admin" on public.sistema_usuarios';
end $$;

-- Helpers (opcional dejarlos; no estorban). Para limpiar del todo:
-- drop function if exists public.mi_rol();
-- drop function if exists public.mi_sede();
