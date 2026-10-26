-- CELULAR por usuario: se usa como número de notificación WhatsApp en el formulario de ALTA CLIENTE
-- Ejecutar en Supabase > SQL Editor.

alter table public.tde_usuarios add column if not exists celular text;

-- 1) MASTER guarda el celular de un usuario
drop function if exists public.guardar_celular_usuario(uuid, uuid, text);
create function public.guardar_celular_usuario(p_token uuid, p_id uuid, p_celular text)
returns void
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
    raise exception 'Solo MASTER con sesión vigente puede cargar celulares';
  end if;
  update public.tde_usuarios set celular = btrim(coalesce(p_celular, '')) where id = p_id;
  if not found then
    raise exception 'Usuario inexistente';
  end if;
end;
$$;
grant execute on function public.guardar_celular_usuario(uuid, uuid, text) to anon, authenticated;

-- 2) Celular del usuario con sesión vigente (para el formulario de ALTA CLIENTE)
drop function if exists public.celular_sesion(uuid);
create function public.celular_sesion(p_token uuid)
returns text
language sql
security definer
set search_path = public
as $$
  select u.celular
    from public.tde_sesiones s
    join public.tde_usuarios u on u.id = s.usuario_id
   where s.token = p_token and s.expira > now()
   limit 1;
$$;
grant execute on function public.celular_sesion(uuid) to anon, authenticated;

-- 3) La lista de usuarios incluye el celular
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
             'nombre', u.nombre, 'apellido', u.apellido, 'logo', u.logo,
             'celular', u.celular)
           order by u.perfil_nombre, u.apellido, u.nombre)
      from public.tde_usuarios u), '[]'::jsonb);
end;
$$;
grant execute on function public.listar_usuarios(uuid) to anon, authenticated;

notify pgrst, 'reload schema';
