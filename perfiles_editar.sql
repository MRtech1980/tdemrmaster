-- PERFILES: lista para el ACCESO CIFRADO y modificación de perfiles
-- Ejecutar en Supabase > SQL Editor.

-- 1) Lista pública de nombres de perfiles (sin datos sensibles) para el desplegable del acceso
drop function if exists public.listar_perfiles_acceso();
create function public.listar_perfiles_acceso()
returns jsonb
language sql
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object('nombre', p.nombre) order by p.nombre), '[]'::jsonb)
    from public.tde_perfiles p;
$$;
grant execute on function public.listar_perfiles_acceso() to anon, authenticated;

-- 2) Modificar perfil (solo MASTER con sesión vigente)
drop function if exists public.modificar_perfil(uuid, uuid, text, text, text, jsonb);
create function public.modificar_perfil(p_token uuid, p_id uuid, p_nombre text, p_firma text,
                                        p_responsable text, p_permisos jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  viejo text;
begin
  if not exists (
    select 1 from public.tde_sesiones s
      join public.tde_usuarios m on m.id = s.usuario_id
     where s.token = p_token and s.expira > now() and m.perfil_nombre = 'MASTER'
  ) then
    raise exception 'Solo MASTER con sesión vigente puede modificar perfiles';
  end if;
  select nombre into viejo from public.tde_perfiles where id = p_id;
  if viejo is null then
    raise exception 'Perfil inexistente';
  end if;
  if viejo = 'MASTER' and btrim(p_nombre) <> 'MASTER' then
    raise exception 'El perfil MASTER no puede renombrarse';
  end if;
  update public.tde_perfiles
     set nombre = btrim(p_nombre),
         firma = coalesce(p_firma, ''),
         responsable = coalesce(p_responsable, ''),
         permisos = coalesce(p_permisos, '{}'::jsonb)
   where id = p_id;
  -- los usuarios de ese perfil toman el nombre nuevo
  update public.tde_usuarios
     set perfil_nombre = btrim(p_nombre)
   where perfil_id = p_id;
end;
$$;
grant execute on function public.modificar_perfil(uuid, uuid, text, text, text, jsonb) to anon, authenticated;

notify pgrst, 'reload schema';
