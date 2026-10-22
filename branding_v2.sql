-- BRANDING v2: columna ALTA TDE, eliminar desde FINALIZADO
-- Ejecutar en Supabase > SQL Editor, en dos partes (parte 1 y parte 2), requiere branding.sql previo.

-- PARTE 1: nuevo estado ALTA TDE y eliminar
alter table public.tde_branding drop constraint if exists tde_branding_estado_chk;
alter table public.tde_branding add constraint tde_branding_estado_chk
  check (estado in ('ALTA TDE', 'DATA INICIAL', 'DESARROLLO', 'FINALIZADO'));

create or replace function public.eliminar_branding(p_token uuid, p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.exigir_master_branding(p_token);
  delete from public.tde_branding where id = p_id;
end;
$$;

grant execute on function public.eliminar_branding(uuid, uuid) to anon, authenticated;

-- PARTE 2: guardar acepta ALTA TDE
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
  if p_estado not in ('ALTA TDE', 'DATA INICIAL', 'DESARROLLO', 'FINALIZADO') then
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

notify pgrst, 'reload schema';
