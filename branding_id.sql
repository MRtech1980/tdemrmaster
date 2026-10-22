-- BRANDING: columna ID de tarjeta (tarjeta_id) en tde_branding y guardado desde la app
-- Ejecutar en Supabase > SQL Editor (todo junto). Requiere branding.sql y branding_v2.sql previos.

-- 1) Columna propia para el ID de la tarjeta
alter table public.tde_branding add column if not exists tarjeta_id text;

-- 2) guardar_branding recibe el ID (se quita la versión anterior de 6 parámetros)
drop function if exists public.guardar_branding(uuid, uuid, text, jsonb, jsonb, jsonb);

create or replace function public.guardar_branding(
  p_token uuid, p_id uuid, p_estado text, p_datos jsonb, p_archivos jsonb, p_checklist jsonb,
  p_tarjeta_id text default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v uuid;
begin
  perform public.exigir_master_branding(p_token);
  if p_estado not in ('ALTA TDE', 'DATA INICIAL', 'DESARROLLO', 'FINALIZADO') then
    raise exception 'Etapa de branding inválida';
  end if;
  if p_id is not null and exists (select 1 from public.tde_branding where id = p_id) then
    update public.tde_branding
       set estado = p_estado,
           datos = coalesce(p_datos, '{}'::jsonb),
           archivos = coalesce(p_archivos, '{}'::jsonb),
           checklist = coalesce(p_checklist, '{}'::jsonb),
           tarjeta_id = p_tarjeta_id
     where id = p_id
    returning id into v;
  else
    insert into public.tde_branding (id, estado, datos, archivos, checklist, tarjeta_id)
    values (coalesce(p_id, gen_random_uuid()), p_estado,
            coalesce(p_datos, '{}'::jsonb), coalesce(p_archivos, '{}'::jsonb),
            coalesce(p_checklist, '{}'::jsonb), p_tarjeta_id)
    returning id into v;
  end if;
  return v;
end;
$$;

grant execute on function public.guardar_branding(uuid, uuid, text, jsonb, jsonb, jsonb, text) to anon, authenticated;

notify pgrst, 'reload schema';
