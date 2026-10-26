-- PERMISOS: cada usuario recibe los permisos de su perfil (solo lectura, con sesión vigente)
-- Ejecutar en Supabase > SQL Editor.
drop function if exists public.mis_permisos(uuid);
create function public.mis_permisos(p_token uuid)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select coalesce((
    select p.permisos
      from public.tde_sesiones s
      join public.tde_usuarios u on u.id = s.usuario_id
      join public.tde_perfiles p on p.id = u.perfil_id
     where s.token = p_token and s.expira > now()
     limit 1), '{}'::jsonb);
$$;
grant execute on function public.mis_permisos(uuid) to anon, authenticated;
notify pgrst, 'reload schema';
