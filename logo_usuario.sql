-- LOGO por usuario/partnership: se muestra en el encabezado de ALTA CLIENTE
-- Ejecutar en Supabase > SQL Editor.

alter table public.tde_usuarios add column if not exists logo text;

-- 1) MASTER guarda o cambia el logo de un usuario
drop function if exists public.guardar_logo_usuario(uuid, uuid, text);
create function public.guardar_logo_usuario(p_token uuid, p_id uuid, p_logo text)
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
    raise exception 'Solo MASTER con sesión vigente puede cargar logos';
  end if;
  update public.tde_usuarios set logo = p_logo where id = p_id;
  if not found then
    raise exception 'Usuario inexistente';
  end if;
end;
$$;
grant execute on function public.guardar_logo_usuario(uuid, uuid, text) to anon, authenticated;

-- 2) Logo del usuario con sesión vigente (para el encabezado)
drop function if exists public.logo_sesion(uuid);
create function public.logo_sesion(p_token uuid)
returns text
language sql
security definer
set search_path = public
as $$
  select u.logo
    from public.tde_sesiones s
    join public.tde_usuarios u on u.id = s.usuario_id
   where s.token = p_token and s.expira > now()
   limit 1;
$$;
grant execute on function public.logo_sesion(uuid) to anon, authenticated;

notify pgrst, 'reload schema';
