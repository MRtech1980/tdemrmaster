-- TDE MASTER: último ingreso en la pantalla de CIBERSEGURIDAD y modificación de usuarios
-- Ejecutar en Supabase > SQL Editor (todo junto). Requiere haber ejecutado antes bloqueo_master.sql.

-- 1) Fecha del último ingreso exitoso por usuario
alter table public.tde_usuarios add column if not exists ultimo_ingreso timestamptz;

-- 2) Ingreso: igual que antes, más 'ultimo' en las respuestas y registro del ingreso correcto
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

  select * into u from public.tde_usuarios where usuario = p_usuario;
  select bloqueado_hasta into hasta from public.tde_bloqueos where usuario = p_usuario;

  if hasta is not null and hasta > now() then
    return jsonb_build_object('error', 'bloqueado',
                              'segundos', ceil(extract(epoch from (hasta - now())))::int,
                              'ultimo', u.ultimo_ingreso);
  end if;

  if u.id is not null and u.clave_hash = extensions.crypt(p_clave, u.clave_hash) then
    delete from public.tde_bloqueos where usuario = p_usuario;
    update public.tde_usuarios set ultimo_ingreso = now() where id = u.id;
    insert into public.tde_sesiones (usuario_id) values (u.id) returning token into t;
    return jsonb_build_object('token', t, 'usuario', u.usuario,
                              'perfil', u.perfil_nombre, 'firma', u.firma);
  end if;

  update public.tde_bloqueos set fallos = fallos + 1
   where usuario = p_usuario
  returning fallos, ronda into f, r;

  if f >= 3 then
    r   := r + 1;
    seg := 100 * r;
    update public.tde_bloqueos
       set fallos = 0, ronda = r, bloqueado_hasta = now() + make_interval(secs => seg)
     where usuario = p_usuario;
    return jsonb_build_object('error', 'bloqueado', 'segundos', seg, 'ultimo', u.ultimo_ingreso);
  end if;

  return jsonb_build_object('error', 'incorrecta', 'restantes', 3 - f, 'ultimo', u.ultimo_ingreso);
end;
$$;

grant execute on function public.ingresar_usuario(text, text) to anon, authenticated;

-- 3) Modificar usuario (solo MASTER). La clave se cambia solo si se envía una nueva.
create or replace function public.modificar_usuario(
  p_token uuid, p_id uuid, p_perfil uuid, p_firma text, p_usuario text, p_clave text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not exists (
    select 1 from public.tde_sesiones s
      join public.tde_usuarios m on m.id = s.usuario_id
     where s.token = p_token and s.expira > now() and m.perfil_nombre = 'MASTER'
  ) then
    raise exception 'Solo MASTER con sesión vigente puede modificar usuarios';
  end if;

  update public.tde_usuarios
     set perfil_id     = p_perfil,
         perfil_nombre = (select nombre from public.tde_perfiles where id = p_perfil),
         firma         = p_firma,
         usuario       = btrim(p_usuario)
   where id = p_id;

  if p_clave is not null and p_clave <> '' then
    update public.tde_usuarios
       set clave_hash = extensions.crypt(p_clave, extensions.gen_salt('bf'))
     where id = p_id;
  end if;
end;
$$;

grant execute on function public.modificar_usuario(uuid, uuid, uuid, text, text, text) to anon, authenticated;

notify pgrst, 'reload schema';
