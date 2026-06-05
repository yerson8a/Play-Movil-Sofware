# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`index.html.html` is the **entire application** — a ~12,800-line single-file SPA for "Play Móvil", a mobile-phone retail business management system (sales, credit/financing, inventory, repairs, accounting, commissions). The whole codebase is one file; there is no build step, no package manager, no dependencies, and no tests.

Note the file is literally named `index.html.html` (double extension) — do not rename it without updating any deploy/hosting config.

The entire codebase, UI, comments, commit messages, and identifiers are in **Spanish**. Match this when writing new code.

## Running

Open `index.html.html` directly in a browser — `open index.html.html` on macOS. There is nothing to build or compile. Edit the file and reload the page.

## File layout (single file)

- Lines ~8–465: `<style>` block — all CSS, design tokens in `:root` (pink/purple brand).
- Lines ~467–4490: `<body>` — login screen, sidebar, and one `<div id="mod-NAME" class="module">` per module.
- Lines ~4491–12809: `<script>` block — all application logic.

When editing, jump by line number. Functions are grouped loosely: Supabase layer (~4493–5040), helpers (~5160–5360), render functions (~5367+), per-module logic after that, auth at the end (~12573+).

## Architecture

**Persistence — Supabase REST (PostgREST).** `SUPABASE_URL` and `SUPABASE_KEY` (anon key) are hardcoded at the top of the script (~line 4497). All database access goes through one wrapper:

```js
sbFetch(tabla, { method, filter, body, select, order })
```

- `GET` builds `?select=...&filter&order`. If `tabla` already contains `?`, it is treated as a raw query (e.g. `sbFetch('sedes?id=eq.3')`).
- Mutations pass `method: 'POST' | 'PATCH' | 'DELETE'` and a `body` object.
- Tables: `proveedores`, `productos`, `ventas`, `creditos`, `abonos`, `garantias`, `gastos`, `tareas`, `sistema_usuarios`, `sedes`, `financieras`, `cajas`, `configuracion_contabilidad`, plus servicio/bitácora/bonos.

**In-memory cache.** Global `db` object (~line 4532) holds arrays: `inventario, ventas, clientes, tareas, creditos, gastos, garantias, compras, proveedores`. Populated on login by `cargarDatosPorSede(user)`; cleared on logout. Render functions read from `db`, not from Supabase directly.

**Row mapping.** Supabase rows are translated into the internal shape by `mapProveedor`, `mapProductoACompra`, `mapProductoAInventario`, `mapVenta`, `mapCredito`, `mapGarantia`, `mapGasto`, `mapTarea`. Notably the single `productos` table feeds **both** `db.compras` and `db.inventario`. Writes go through `guardar*DB` / `registrarAbonoDB` / `eliminarProductoDB` functions — these mutate Supabase, not just the cache.

**Navigation.** SPA with no router. `showModule(name)` hides all `.module` divs, shows `#mod-<name>`, sets the topbar title, and calls that module's render function (`renderDashboard`, `renderInventario`, `renderVentas`, `renderCreditos`, etc.). Sidebar `.nav-item` elements call `showModule` via inline `onclick`. Adding a module means adding: a sidebar `nav-item`, a `#mod-NAME` div, a render function, and a `showModule` branch.

**Auth & permissions.** `hacerLogin()` SHA-256-hashes the password (Web Crypto `sha256()`) and matches it against `sistema_usuarios`. The session is stored in `sessionStorage` under key `pm_sesion`; `init()` restores it on load. `sesionActiva` is the global current-user object.
- Roles: `admin`, `asesor`, `bodega`, `consulta`. The body gets class `rol-<rol>` for CSS-driven gating; `consulta` has primary actions disabled.
- Per-user `modulos_permitidos` (JSON array of module names) and `cajas_permitidas` gate access — `aplicarPermisosNavegacion` / `aplicarPermisosRol` enforce it, and `showModule` re-checks.
- **Sedes (branches):** `sede_id` 1 = `LOCAL PEREIRA`, 2 = `LOCAL ARMENIA`. Admin sees all sedes; other roles get data filtered to their `sede_id`. `window.SEDE_ACTIVA` / `window.SEDE_ID_ACTIVA` hold the active branch for new records.

## Conventions

- **Helpers:** `$('id')` = `getElementById`; `fmt(n)` = COP currency formatting; `toast(msg, type)`, `openModal(id)`, `closeModal(id)`, `showLoader/hideLoader`.
- **Money inputs:** use `fmtMoneyInput`, `getMoneyValue(id)`, `setMoneyValue(id, num)` — do not read `.value` directly on currency fields.
- **Dates:** Colombia timezone via `fechaColombia()` and `mesColombia()`; `fmtFechaCorta()` for display.
- **IMEI fields:** validate/clean with `validarCampoIMEI(el, requerido)` and `limpiarIMEI(el)`.
- **Text inputs auto-uppercase** via CSS (all `input.form-control` and `textarea` except `email`/`date`/`password`/`number`). Account for this — stored text is uppercase.
- **Invoices** are generated as HTML strings (`generarHTMLFactura`), opened in a new window, and printed (`imprimirFactura`).
- Module/tab state is tracked in module-scoped globals (e.g. `tabCreditosActual`) so re-renders preserve the active tab.
