-- DIRIN · el administrador supremo no pertenece a ninguna institución
-- y es el único que crea, edita o borra instituciones.
-- Ejecutar en Supabase → SQL Editor, después de supabase-arregla-recursion.sql.

-- El supremo es apoyo técnico de todas: no se le amarra a ninguna.
update public.perfiles set institucion_id = null where rol = 'super';

-- ---------------------------------------------------------------
-- Instituciones: lectura para todos, escritura sólo para el supremo
-- ---------------------------------------------------------------

alter table public.instituciones enable row level security;

drop policy if exists "instituciones visibles" on public.instituciones;
create policy "instituciones visibles" on public.instituciones
  for select using (
    public.mi_rol() = 'super'
    or id::text = public.mi_institucion()
  );

drop policy if exists "supremo crea instituciones" on public.instituciones;
create policy "supremo crea instituciones" on public.instituciones
  for insert with check (public.mi_rol() = 'super');

drop policy if exists "supremo borra instituciones" on public.instituciones;
create policy "supremo borra instituciones" on public.instituciones
  for delete using (public.mi_rol() = 'super');

-- El supremo edita cualquiera; el administrador de institución sólo la suya
-- (nombre, colores, logo, membrete y programas).
drop policy if exists "edita su institucion" on public.instituciones;
create policy "edita su institucion" on public.instituciones
  for update using (
    public.mi_rol() = 'super'
    or (public.mi_rol() = 'admin_inst' and id::text = public.mi_institucion())
  );

-- ---------------------------------------------------------------
-- Roles: «super» y «admin_inst» sólo los otorga el supremo
-- ---------------------------------------------------------------

create or replace function public.impedir_auto_supremo()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.rol in ('super','admin_inst')
     and (old.rol is distinct from new.rol)
     and coalesce(public.mi_rol(), '') <> 'super' then
    raise exception 'Sólo el administrador supremo otorga ese rol';
  end if;
  return new;
end $$;

drop trigger if exists trg_impedir_auto_supremo on public.perfiles;
create trigger trg_impedir_auto_supremo before update on public.perfiles
  for each row execute function public.impedir_auto_supremo();
