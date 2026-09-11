-- DIRIN · arregla la recursión infinita en las políticas de «perfiles»
-- Ejecutar completo en Supabase → SQL Editor.
-- Sustituye a la sección 4 de supabase-pin-y-supremo.sql.

-- El problema: una política sobre «perfiles» que consulta «perfiles» se llama
-- a sí misma. La salida es leer el rol con una función SECURITY DEFINER, que
-- no pasa por RLS.

create or replace function public.mi_rol()
returns text language sql stable security definer set search_path = public as $$
  select rol from public.perfiles where id = auth.uid()
$$;

-- Sólo tiene sentido si ya corriste supabase-instituciones.sql; si no,
-- se crea devolviendo nulo para que el resto del archivo funcione igual.
do $$
begin
  if exists (select 1 from information_schema.columns
              where table_schema='public' and table_name='perfiles'
                and column_name='institucion_id') then
    execute $q$
      create or replace function public.mi_institucion()
      returns text language sql stable security definer set search_path = public as $f$
        select institucion_id::text from public.perfiles where id = auth.uid()
      $f$
    $q$;
  else
    execute $q$
      create or replace function public.mi_institucion()
      returns text language sql stable as $f$ select null::text $f$
    $q$;
  end if;
end $$;

grant execute on function public.mi_rol() to authenticated;
grant execute on function public.mi_institucion() to authenticated;

-- ---------------------------------------------------------------
-- Políticas de lectura y actualización
-- ---------------------------------------------------------------

do $$
declare hay_inst boolean;
begin
  select exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='perfiles'
                    and column_name='institucion_id') into hay_inst;

  execute 'drop policy if exists "perfiles visibles" on public.perfiles';
  execute 'drop policy if exists "solo supremo toca supremo" on public.perfiles';

  if hay_inst then
    execute $q$
      create policy "perfiles visibles" on public.perfiles
        for select using (
          id = auth.uid()
          or public.mi_rol() = 'super'
          or (rol is distinct from 'super'
              and institucion_id::text is not distinct from public.mi_institucion())
        )
    $q$;
  else
    execute $q$
      create policy "perfiles visibles" on public.perfiles
        for select using (
          id = auth.uid()
          or public.mi_rol() = 'super'
          or rol is distinct from 'super'
        )
    $q$;
  end if;

  execute $q$
    create policy "solo supremo toca supremo" on public.perfiles
      for update using (
        id = auth.uid()
        or public.mi_rol() = 'super'
        or rol is distinct from 'super'
      )
  $q$;
end $$;

-- Nadie se asciende a supremo por su cuenta (versión sin recursión).
create or replace function public.impedir_auto_supremo()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.rol = 'super'
     and (old.rol is distinct from 'super')
     and coalesce(public.mi_rol(), '') <> 'super' then
    raise exception 'Sólo el administrador supremo puede otorgar ese rol';
  end if;
  return new;
end $$;

-- ---------------------------------------------------------------
-- Deja lista la cuenta supremo
-- ---------------------------------------------------------------

update public.perfiles set rol = 'super', activo = true
 where lower(correo) = 'rigocastaval@gmail.com';

-- Comprueba que quedó:
select correo, rol, activo from public.perfiles
 where lower(correo) = 'rigocastaval@gmail.com';
