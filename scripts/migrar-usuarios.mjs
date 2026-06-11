// ============================================================
// Play Móvil — Migración de usuarios a Supabase Auth
// ============================================================
// Lee los usuarios de `sistema_usuarios`, crea su equivalente en
// auth.users (email sintético + contraseña temporal aleatoria) y
// rellena la tabla `perfiles`. Cada usuario deberá cambiar su
// contraseña en el primer ingreso (debe_cambiar_password = true).
//
// NO migra contraseñas: los hashes actuales son SHA-256 sin sal y no
// son reutilizables por Supabase Auth. Cada quien recibe una temporal.
//
// REQUISITOS:
//   1) Haber ejecutado antes scripts/perfiles.sql en el SQL Editor.
//   2) Node 18+ y haber corrido `npm install` dentro de scripts/.
//   3) La service_role en la variable de entorno (NUNCA hardcodeada):
//
//      cd scripts
//      npm install
//      SUPABASE_SERVICE_ROLE_KEY="...tu_service_role..." node migrar-usuarios.mjs
//
// Es idempotente: si un usuario ya existe en Auth, se omite su creación
// y solo se asegura/actualiza su fila en `perfiles`.
// ============================================================

import { createClient } from '@supabase/supabase-js';
import { writeFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';

const SUPABASE_URL = 'https://gopwheqqxxiafpdgpjrp.supabase.co';
const SERVICE_ROLE = process.env.SUPABASE_SERVICE_ROLE_KEY;
const EMAIL_DOMINIO = 'playmovil.store';

if (!SERVICE_ROLE) {
  console.error('\n❌ Falta la variable de entorno SUPABASE_SERVICE_ROLE_KEY.');
  console.error('   Úsala así (sin dejarla en el historial si puedes):');
  console.error('   SUPABASE_SERVICE_ROLE_KEY="..." node migrar-usuarios.mjs\n');
  process.exit(1);
}

// Cliente admin con service_role: bypassa RLS. SOLO se usa en este script local.
const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
  auth: { persistSession: false, autoRefreshToken: false }
});

const usuarioAEmail = u => `${String(u).trim().toLowerCase()}@${EMAIL_DOMINIO}`;

// Contraseña temporal: 16+ caracteres, mezcla de letras/números + sufijo fijo
// que garantiza variedad. Supera cualquier política de longitud razonable.
function passTemporal() {
  const base = randomBytes(15).toString('base64').replace(/[+/=]/g, '');
  return (base.slice(0, 14) + 'Pm9!');
}

// Busca un usuario de Auth por email (para idempotencia). Pagina por si acaso.
async function buscarAuthUserPorEmail(email) {
  for (let page = 1; page <= 20; page++) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 200 });
    if (error) throw error;
    const found = data.users.find(u => (u.email || '').toLowerCase() === email.toLowerCase());
    if (found) return found;
    if (data.users.length < 200) break; // última página
  }
  return null;
}

async function main() {
  console.log('→ Leyendo usuarios de sistema_usuarios...');
  const { data: usuarios, error } = await admin
    .from('sistema_usuarios')
    .select('usuario, nombre, rol, sede_id, activo, modulos_permitidos, cajas_permitidas')
    .order('usuario', { ascending: true });

  if (error) { console.error('❌ Error leyendo sistema_usuarios:', error.message); process.exit(1); }
  console.log(`  ${usuarios.length} usuarios encontrados.\n`);

  const credenciales = [];

  for (const u of usuarios) {
    const email = usuarioAEmail(u.usuario);
    const tempPass = passTemporal();
    let authUser = null;
    let nuevoTemp = tempPass; // contraseña a reportar

    // 1) Crear cuenta en Auth (o recuperarla si ya existe)
    const { data: created, error: errCreate } = await admin.auth.admin.createUser({
      email,
      password: tempPass,
      email_confirm: true,
      user_metadata: { usuario: u.usuario, nombre: u.nombre }
    });

    if (errCreate) {
      const yaExiste = /already|registered|exists|duplicate/i.test(errCreate.message);
      if (yaExiste) {
        authUser = await buscarAuthUserPorEmail(email);
        if (!authUser) { console.error(`  ✗ ${u.usuario}: ya existe en Auth pero no se pudo localizar. Omitido.`); continue; }
        nuevoTemp = '(ya existía — sin cambios)';
        console.warn(`  • ${u.usuario.padEnd(14)} ya existía en Auth, se conserva su cuenta.`);
      } else {
        console.error(`  ✗ ${u.usuario}: error creando en Auth → ${errCreate.message}`);
        continue;
      }
    } else {
      authUser = created.user;
    }

    // 2) Insertar/actualizar el perfil (service_role bypassa RLS)
    const { error: errPerf } = await admin.from('perfiles').upsert({
      id: authUser.id,
      usuario: u.usuario,
      nombre: u.nombre,
      rol: u.rol,
      sede_id: u.sede_id,
      modulos_permitidos: u.modulos_permitidos,
      cajas_permitidas: u.cajas_permitidas,
      activo: u.activo ?? true,
      debe_cambiar_password: true
    }, { onConflict: 'id' });

    if (errPerf) { console.error(`  ✗ ${u.usuario}: error en perfiles → ${errPerf.message}`); continue; }

    credenciales.push({
      usuario: u.usuario,
      email,
      password_temporal: nuevoTemp,
      rol: u.rol,
      activo: u.activo
    });
    console.log(`  ✓ ${u.usuario.padEnd(14)} → ${email}`);
  }

  // 3) Guardar credenciales temporales en un CSV (gitignored)
  const csv = 'usuario,email,password_temporal,rol,activo\n' +
    credenciales.map(c => `${c.usuario},${c.email},${c.password_temporal},${c.rol},${c.activo}`).join('\n');
  const outPath = new URL('./credenciales-temporales.csv', import.meta.url);
  writeFileSync(outPath, csv + '\n');

  console.log('\n================= CONTRASEÑAS TEMPORALES =================');
  console.table(credenciales);
  console.log('Guardadas en: scripts/credenciales-temporales.csv');
  console.log('⚠️  NO subas ese archivo a git. Entrégalas por canal seguro y bórralo.');
  console.log('Cada usuario deberá cambiar su contraseña al primer ingreso.\n');
}

main().catch(e => { console.error('❌ Error inesperado:', e); process.exit(1); });
