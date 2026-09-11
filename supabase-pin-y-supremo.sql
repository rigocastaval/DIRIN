-- DIRIN · PIN de edición y cuenta de administrador supremo
-- Ejecutar en Supabase → SQL Editor, DESPUÉS de supabase-setup.sql,
-- supabase-seguridad.sql y supabase-instituciones.sql.

-- ---------------------------------------------------------------
-- 0. Roles permitidos
-- ---------------------------------------------------------------
-- Amplía la lista de roles válidos para que acepte «super» y
-- «admin_inst» aunque todavía no hayas corrido supabase-instituciones.sql.

alter table public.perfiles drop constraint if exists perfiles_rol_valido;
alter table public.perfiles add constraint perfiles_rol_valido
  check (rol in ('pendiente','super','admin_inst','admin','direccion',
                 'control','academica','docencia','docente','indicadores','estudiante'));

-- ---------------------------------------------------------------
-- 1. Columna del PIN de edición
-- ---------------------------------------------------------------
-- El PIN nunca se guarda tal cual: se guarda su huella (SHA-256).
-- Nadie, ni el administrador, puede leerlo.

alter table public.perfiles add column if not exists pin_hash text;

-- Cada quien puede cambiar su propio PIN; nadie puede cambiar el de otro.
drop policy if exists "perfil propio actualiza pin" on public.perfiles;
create policy "perfil propio actualiza pin" on public.perfiles
  for update using (id = auth.uid()) with check (id = auth.uid());

-- ---------------------------------------------------------------
-- 2. Administrador supremo
-- ---------------------------------------------------------------
-- ANTES de correr esto: Authentication → Users → Add user
--   correo: rigocastaval@gmail.com   (marca "Auto Confirm User")
-- Después ejecuta:

update public.perfiles
   set rol = 'super', activo = true, nombre = coalesce(nullif(nombre,''), 'Administración DIRIN')
 where lower(correo) = 'rigocastaval@gmail.com';

-- Si la línea anterior dice "0 rows": entra una vez a DIRIN con ese correo
-- (dirá que no estás autorizado, pero deja creado el perfil) y repítela.

-- ---------------------------------------------------------------
-- 3. Administrador de la Universidad José Martí
-- ---------------------------------------------------------------
-- Cambia el correo por el completo de esa cuenta si es distinto.
-- Si todavía no has corrido supabase-instituciones.sql, esta parte se salta
-- sola: sólo le pone el rol. Vuelve a correr el archivo después de crear la
-- institución para amarrarle la Universidad José Martí.

do $$
begin
  update public.perfiles
     set rol = 'admin_inst', activo = true
   where lower(correo) like 'dr.ramses.univer%';

  if to_regclass('public.instituciones') is not null then
    execute $q$
      update public.perfiles p
         set institucion_id = (select id from public.instituciones
                                where nombre ilike '%José Martí%'
                                order by creado_en limit 1)
       where lower(p.correo) like 'dr.ramses.univer%'
         and exists (select 1 from public.instituciones where nombre ilike '%José Martí%')
    $q$;
  end if;
end $$;

-- ---------------------------------------------------------------
-- 4. La cuenta supremo no se ve desde abajo
-- ---------------------------------------------------------------
-- Sólo un supremo puede leer, cambiar o desactivar el perfil de otro supremo.
-- La regla por institución sólo se agrega si ya corriste supabase-instituciones.sql.

do $$
declare hay_inst boolean;
begin
  select exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='perfiles'
                    and column_name='institucion_id') into hay_inst;

  execute 'drop policy if exists "perfiles visibles" on public.perfiles';
  if hay_inst then
    execute $q$
      create policy "perfiles visibles" on public.perfiles
        for select using (
          id = auth.uid()
          or (select rol from public.perfiles me where me.id = auth.uid()) = 'super'
          or (rol is distinct from 'super'
              and institucion_id is not distinct from
                  (select institucion_id from public.perfiles me where me.id = auth.uid()))
        )
    $q$;
  else
    execute $q$
      create policy "perfiles visibles" on public.perfiles
        for select using (
          id = auth.uid()
          or (select rol from public.perfiles me where me.id = auth.uid()) = 'super'
          or rol is distinct from 'super'
        )
    $q$;
  end if;
end $$;

drop policy if exists "solo supremo toca supremo" on public.perfiles;
create policy "solo supremo toca supremo" on public.perfiles
  for update using (
    id = auth.uid()
    or (select rol from public.perfiles me where me.id = auth.uid()) = 'super'
    or rol is distinct from 'super'
  );

-- Nadie se asciende a supremo por su cuenta.
create or replace function public.impedir_auto_supremo()
returns trigger language plpgsql security definer as $$
begin
  if new.rol = 'super'
     and (old.rol is distinct from 'super')
     and coalesce((select rol from public.perfiles me where me.id = auth.uid()), '') <> 'super' then
    raise exception 'Sólo el administrador supremo puede otorgar ese rol';
  end if;
  return new;
end $$;

drop trigger if exists trg_impedir_auto_supremo on public.perfiles;
create trigger trg_impedir_auto_supremo before update on public.perfiles
  for each row execute function public.impedir_auto_supremo();
