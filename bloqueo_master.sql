-- CIBERSEGURIDAD: bloqueo de intentos en el ingreso y usuario MR Master
-- Ejecutar en Supabase > SQL Editor (todo junto).

create extension if not exists pgcrypto with schema extensions;

-- 1) Registro de intentos fallidos por usuario (solo lo usa la función, no el navegador)
create table if not exists public.tde_bloqueos (
  usuario         text primary key,
  fallos          int  not null default 0,
  ronda           int  not null default 0,
  bloqueado_hasta timestamptz
);
revoke all on public.tde_bloqueos from anon, authenticated;

-- 2) Ingreso: 3 intentos por ronda; cada ronda bloqueada suma 100 segundos (100, 200, 300...)
create or replace function public.ingresar_usuario(p_usuario text, p_clave text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  hasta   timestamptz;
  u       public.tde_usuarios%rowtype;
  t       uuid;
  f       int;
  r       int;
  seg     int;
begin
  p_usuario := btrim(coalesce(p_usuario, ''));

  insert into public.tde_bloqueos (usuario) values (p_usuario)
  on conflict (usuario) do nothing;

  select bloqueado_hasta into hasta from public.tde_bloqueos where usuario = p_usuario;
  if hasta is not null and hasta > now() then
    return jsonb_build_object('error', 'bloqueado',
                              'segundos', ceil(extract(epoch from (hasta - now())))::int);
  end if;

  select * into u from public.tde_usuarios where usuario = p_usuario;
  if found and u.clave_hash = extensions.crypt(p_clave, u.clave_hash) then
    delete from public.tde_bloqueos where usuario = p_usuario;
    insert into public.tde_sesiones (usuario_id) values (u.id) returning token into t;
    return jsonb_build_object('token', t, 'usuario', u.usuario,
                              'perfil', u.perfil_nombre, 'firma', u.firma);
  end if;

  -- Clave incorrecta (o usuario inexistente: misma respuesta para no revelar cuentas)
  update public.tde_bloqueos set fallos = fallos + 1
   where usuario = p_usuario
  returning fallos, ronda into f, r;

  if f >= 3 then
    r   := r + 1;
    seg := 100 * r;
    update public.tde_bloqueos
       set fallos = 0, ronda = r, bloqueado_hasta = now() + make_interval(secs => seg)
     where usuario = p_usuario;
    return jsonb_build_object('error', 'bloqueado', 'segundos', seg);
  end if;

  return jsonb_build_object('error', 'incorrecta', 'restantes', 3 - f);
end;
$$;

grant execute on function public.ingresar_usuario(text, text) to anon, authenticated;

-- 3) Usuario MASTER: MR Master (perfil MASTER, acceso total)
insert into public.tde_usuarios (perfil_id, perfil_nombre, firma, usuario, clave_hash)
select p.id, 'MASTER', 'MR Technology', 'MR Master',
       extensions.crypt('.MR&gato', extensions.gen_salt('bf'))
  from public.tde_perfiles p
 where p.nombre = 'MASTER'
 limit 1
on conflict (usuario) do update
   set clave_hash = excluded.clave_hash,
       perfil_id = excluded.perfil_id,
       perfil_nombre = 'MASTER',
       firma = 'MR Technology';

notify pgrst, 'reload schema';
