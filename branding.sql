-- TDE MASTER · BRANDING (DATA INICIAL → DESARROLLO → FINALIZADO)
-- Ejecutar en Supabase > SQL Editor (todo junto). Requiere bloqueo_master.sql y ultimo_y_modificar.sql.

create table if not exists public.tde_branding (
  id        uuid primary key default gen_random_uuid(),
  creado_en timestamptz not null default now(),
  estado    text not null default 'DATA INICIAL',
  datos     jsonb not null default '{}'::jsonb,
  archivos  jsonb not null default '{}'::jsonb,
  checklist jsonb not null default '{}'::jsonb,
  constraint tde_branding_estado_chk check (estado in ('DATA INICIAL', 'DESARROLLO', 'FINALIZADO'))
);
revoke all on public.tde_branding from anon, authenticated;

-- Verifica sesión vigente de un usuario MASTER
create or replace function public.exigir_master_branding(p_token uuid)
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
    raise exception 'Solo MASTER con sesión vigente puede gestionar BRANDING';
  end if;
end;
$$;

-- Crea (p_id null) o actualiza una ficha de branding
create or replace function public.guardar_branding(
  p_token uuid, p_id uuid, p_estado text, p_datos jsonb, p_archivos jsonb, p_checklist jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v uuid;
begin
  perform public.exigir_master_branding(p_token);
  if p_estado not in ('DATA INICIAL', 'DESARROLLO', 'FINALIZADO') then
    raise exception 'Etapa de branding inválida';
  end if;

  if p_id is not null and exists (select 1 from public.tde_branding where id = p_id) then
    update public.tde_branding
       set estado = p_estado,
           datos = coalesce(p_datos, '{}'::jsonb),
           archivos = coalesce(p_archivos, '{}'::jsonb),
           checklist = coalesce(p_checklist, '{}'::jsonb)
     where id = p_id
    returning id into v;
  else
    insert into public.tde_branding (id, estado, datos, archivos, checklist)
    values (coalesce(p_id, gen_random_uuid()), p_estado,
            coalesce(p_datos, '{}'::jsonb), coalesce(p_archivos, '{}'::jsonb),
            coalesce(p_checklist, '{}'::jsonb))
    returning id into v;
  end if;
  return v;
end;
$$;

-- Lista todas las fichas de branding (solo MASTER)
create or replace function public.listar_branding(p_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.exigir_master_branding(p_token);
  return coalesce(
    (select jsonb_agg(to_jsonb(b) order by b.creado_en desc) from public.tde_branding b),
    '[]'::jsonb);
end;
$$;

grant execute on function public.exigir_master_branding(uuid) to anon, authenticated;
grant execute on function public.guardar_branding(uuid, uuid, text, jsonb, jsonb, jsonb) to anon, authenticated;
grant execute on function public.listar_branding(uuid) to anon, authenticated;

notify pgrst, 'reload schema';
