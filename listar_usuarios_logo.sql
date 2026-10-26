-- USUARIOS: la lista incluye el logo de cada usuario (columna LOGO)
-- Ejecutar en Supabase > SQL Editor.
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
             'nombre', u.nombre, 'apellido', u.apellido, 'logo', u.logo)
           order by u.perfil_nombre, u.apellido, u.nombre)
      from public.tde_usuarios u), '[]'::jsonb);
end;
$$;
grant execute on function public.listar_usuarios(uuid) to anon, authenticated;
notify pgrst, 'reload schema';
