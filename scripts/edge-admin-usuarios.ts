// Edge Function `admin-usuarios` (copia versionada; la desplegada vive en Supabase).
// Gestión de cuentas (Supabase Auth) para Play Móvil.
// Solo un admin autenticado (perfiles.rol = 'admin' y activo) puede invocarla.
// Acciones: crear, reset_password, eliminar. Mantiene sincronizada la tabla
// legacy sistema_usuarios (dropdown de asesores) en crear/eliminar.
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

const EMAIL_DOMINIO = "playmovil.store";
const ROLES = ["admin", "asesor", "bodega", "consulta"];

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json(405, { error: "Método no permitido" });

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // Identificar al que llama con su propio JWT
  const authHeader = req.headers.get("Authorization") ?? "";
  const supaUser = createClient(url, anon, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: errUser } = await supaUser.auth.getUser();
  if (errUser || !user) return json(401, { error: "No autenticado" });

  // Verificar que sea admin activo (con service_role, sin depender de RLS)
  const admin = createClient(url, service);
  const { data: perfilAdmin } = await admin
    .from("perfiles")
    .select("rol,activo")
    .eq("id", user.id)
    .maybeSingle();
  if (!perfilAdmin || perfilAdmin.rol !== "admin" || perfilAdmin.activo === false) {
    return json(403, { error: "Solo un administrador puede gestionar usuarios" });
  }

  let body: any;
  try { body = await req.json(); } catch { return json(400, { error: "Cuerpo inválido" }); }
  const action = body?.action;

  // ── Crear cuenta: auth.users + perfiles + sistema_usuarios ──
  if (action === "crear") {
    const usuario = String(body.usuario || "").trim().toLowerCase();
    const nombre = String(body.nombre || "").trim().toUpperCase();
    const password = String(body.password || "");
    const rol = String(body.rol || "");
    const sede_id = body.sede_id ? parseInt(body.sede_id) : null;

    if (!/^[a-z0-9._-]{3,30}$/.test(usuario)) {
      return json(400, { error: "Usuario inválido: solo minúsculas, números, punto, guion o guion bajo (3-30 caracteres)" });
    }
    if (!nombre) return json(400, { error: "El nombre es obligatorio" });
    if (password.length < 6) return json(400, { error: "La contraseña debe tener mínimo 6 caracteres" });
    if (!ROLES.includes(rol)) return json(400, { error: "Rol inválido" });

    const { data: existente } = await admin
      .from("perfiles").select("id").eq("usuario", usuario).maybeSingle();
    if (existente) return json(409, { error: `Ya existe un usuario "${usuario}"` });

    const { data: creado, error: errCrear } = await admin.auth.admin.createUser({
      email: `${usuario}@${EMAIL_DOMINIO}`,
      password,
      email_confirm: true,
      user_metadata: { usuario, nombre },
    });
    if (errCrear || !creado?.user) {
      return json(400, { error: "No se pudo crear la cuenta: " + (errCrear?.message || "error desconocido") });
    }
    const uid = creado.user.id;

    const { error: errPerfil } = await admin.from("perfiles").insert({
      id: uid, usuario, nombre, rol, sede_id,
      activo: true, debe_cambiar_password: true, ver_costos: false,
    });
    if (errPerfil) {
      // revertir para no dejar una cuenta sin perfil
      await admin.auth.admin.deleteUser(uid);
      return json(400, { error: "No se pudo crear el perfil: " + errPerfil.message });
    }

    // Sync legacy (dropdown de asesores). Si ya existía la fila, se reactualiza.
    const { data: legacy } = await admin
      .from("sistema_usuarios").select("id").eq("usuario", usuario).maybeSingle();
    if (legacy) {
      await admin.from("sistema_usuarios")
        .update({ nombre, rol, sede_id, activo: true }).eq("id", legacy.id);
    } else {
      await admin.from("sistema_usuarios")
        .insert({ usuario, nombre, rol, sede_id, activo: true });
    }

    return json(200, { ok: true, id: uid });
  }

  // ── Cambiar contraseña (fuerza cambio en el próximo ingreso) ──
  if (action === "reset_password") {
    const uid = String(body.user_id || "");
    const password = String(body.password || "");
    if (!uid) return json(400, { error: "Falta user_id" });
    if (password.length < 6) return json(400, { error: "La contraseña debe tener mínimo 6 caracteres" });
    const { error } = await admin.auth.admin.updateUserById(uid, { password });
    if (error) return json(400, { error: "No se pudo cambiar la contraseña: " + error.message });
    // Si el admin se cambia su propia clave no se fuerza el modal obligatorio
    if (uid !== user.id) {
      await admin.from("perfiles").update({ debe_cambiar_password: true }).eq("id", uid);
    }
    return json(200, { ok: true });
  }

  // ── Eliminar cuenta: auth.users + perfiles + sistema_usuarios ──
  if (action === "eliminar") {
    const uid = String(body.user_id || "");
    if (!uid) return json(400, { error: "Falta user_id" });
    if (uid === user.id) return json(400, { error: "No puedes eliminar tu propia cuenta" });

    const { data: p } = await admin
      .from("perfiles").select("usuario").eq("id", uid).maybeSingle();

    const { error } = await admin.auth.admin.deleteUser(uid);
    if (error) return json(400, { error: "No se pudo eliminar la cuenta: " + error.message });
    await admin.from("perfiles").delete().eq("id", uid);
    if (p?.usuario) {
      await admin.from("sistema_usuarios").delete().eq("usuario", p.usuario);
    }
    return json(200, { ok: true });
  }

  return json(400, { error: "Acción no soportada" });
});
