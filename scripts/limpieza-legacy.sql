-- ============================================================
-- Limpieza legacy (post-migración a Supabase Auth)
-- ============================================================
-- YA APLICADO en producción vía MCP. Copia versionada.
--
-- 1) Eliminar columna password_hash de sistema_usuarios:
--    los hashes SHA-256 viejos ya no se usan (login = Supabase Auth);
--    se quita para cerrar su exposición a usuarios autenticados.
alter table public.sistema_usuarios drop column if exists password_hash;

-- 2) Eliminar tabla `usuarios` (legacy): 0 filas, sin uso en el código,
--    ventas.asesor_id vacío. Se quita la FK entrante y luego la tabla.
alter table public.ventas drop constraint if exists ventas_asesor_id_fkey;
drop table if exists public.usuarios;

-- PENDIENTE (no hecho, "parar aquí"): para eliminar sistema_usuarios falta
--   - mover el dropdown de asesores (cargarAsesoresActivos / línea ~7378) a `perfiles`
--   - reconstruir el módulo admin de usuarios sobre `perfiles`
--   - resolver crear/eliminar usuarios (Edge Function con service_role)
