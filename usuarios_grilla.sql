-- USUARIOS: nombre y apellido, y listado en grilla
-- Ejecutar en Supabase > SQL Editor, en dos partes (parte 1 y parte 2).

-- PARTE 1: columnas y listado
alter table public.tde_usuarios add column if not exists nombre text not null default '';
alter table public.tde_usuarios add column if not exists apellido text not null default '';

drop function if exists public.listar_usuarios(uuid);
create function public.listar_usuarios(p_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.tde_sesiones s
      join public.tde_usuarios m on m.id = s.usuario_id
     where s.token = p_token and s.expira > now() and m.perfil_nombre = 'MASTER'
  ) then
    raise exception 'Solo MASTER con sesión vigente puede ver usuarios';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', u.id, 'usuario', u.usuario, 'perfil_id', u.perfil_id,
             'perfil_nombre', u.perfil_nombre, 'firma', u.firma,
             'nombre', u.nombre, 'apellido', u.apellido)
           order by u.perfil_nombre, u.apellido, u.nombre)
      from public.tde_usuarios u), '[]'::jsonb);
end;
$$;
grant execute on function public.listar_usuarios(uuid) to anon, authenticated;

-- PARTE 2: alta y modificación con nombre y apellido
drop function if exists public.crear_usuario(uuid, uuid, text, text, text);
create function public.crear_usuario(p_token uuid, p_perfil uuid, p_firma text, p_usuario text,
                                     p_clave text, p_nombre text, p_apellido text)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v uuid;
  pn text;
begin
  if not exists (
    select 1 from public.tde_sesiones s
      join public.tde_usuarios m on m.id = s.usuario_id
     where s.token = p_token and s.expira > now() and m.perfil_nombre = 'MASTER'
  ) then
    raise exception 'Solo MASTER con sesión vigente puede crear usuarios';
  end if;
  select nombre into pn from public.tde_perfiles where id = p_perfil;
  if pn is null then
    raise exception 'Perfil inexistente';
  end if;
  insert into public.tde_usuarios (perfil_id, perfil_nombre, firma, usuario, clave_hash, nombre, apellido)
  values (p_perfil, pn, coalesce(p_firma, ''), btrim(p_usuario),
          extensions.crypt(p_clave, extensions.gen_salt('bf')),
          btrim(coalesce(p_nombre, '')), btrim(coalesce(p_apellido, '')))
  returning id into v;
  return v;
end;
$$;
grant execute on function public.crear_usuario(uuid, uuid, text, text, text, text, text) to anon, authenticated;

drop function if exists public.modificar_usuario(uuid, uuid, uuid, text, text, text);
create function public.modificar_usuario(p_token uuid, p_id uuid, p_perfil uuid, p_firma text,
                                         p_usuario text, p_clave text, p_nombre text, p_apellido text)
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
         usuario       = btrim(p_usuario),
         nombre        = btrim(coalesce(p_nombre, nombre)),
         apellido      = btrim(coalesce(p_apellido, apellido))
   where id = p_id;
  if p_clave is not null and p_clave <> '' then
    update public.tde_usuarios
       set clave_hash = extensions.crypt(p_clave, extensions.gen_salt('bf'))
     where id = p_id;
  end if;
end;
$$;
grant execute on function public.modificar_usuario(uuid, uuid, uuid, text, text, text, text, text) to anon, authenticated;

notify pgrst, 'reload schema';
