# Migración a Supabase Auth — Play Móvil

Pasos para activar el nuevo login (email sintético `usuario@playmovil.store` + Supabase Auth).
Todo se ejecuta **localmente**; nada se despliega automáticamente.

## 1. Crear la tabla `perfiles`

En el panel de Supabase → **SQL Editor**, pega y ejecuta el contenido de:

```
scripts/perfiles.sql
```

Crea la tabla `perfiles` (enlazada a `auth.users`) con RLS por `auth.uid()`.

## 2. Migrar los usuarios

```bash
cd scripts
npm install
SUPABASE_SERVICE_ROLE_KEY="<tu_service_role>" node migrar-usuarios.mjs
```

- La **service_role** se pasa por variable de entorno; **nunca** se hardcodea ni se sube a git.
- El script:
  - lee los usuarios de `sistema_usuarios`,
  - crea cada cuenta en Auth con email `usuario@playmovil.store`, `email_confirm: true` y una **contraseña temporal aleatoria**,
  - marca `debe_cambiar_password = true`,
  - rellena `perfiles` (rol, sede, permisos, `activo`).
- Es **idempotente**: si lo corres de nuevo, omite las cuentas ya creadas.

### Contraseñas temporales

Se imprimen en consola (tabla) y se guardan en:

```
scripts/credenciales-temporales.csv
```

Ese archivo está en `.gitignore`. Entrégalas por un canal seguro y **bórralo** después.
Cada usuario deberá cambiar su contraseña en el primer ingreso (modal bloqueante).

## 3. Probar

Abre `index.html` y entra con un `usuario` y su contraseña temporal. Debe forzar el cambio.

## Pendiente (pasos posteriores — NO incluidos aquí)

- Endurecer RLS del resto de tablas (hoy siguen accesibles con la anon key).
- Migrar la capa de datos (`sbFetch`) para usar el token autenticado.
- Construir un panel admin que cree/edite usuarios vía Auth (el módulo viejo quedó deshabilitado).
- Eliminar `sistema_usuarios` cuando todo esté validado.
