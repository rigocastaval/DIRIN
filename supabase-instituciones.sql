-- =====================================================================
-- DIRIN · Instituciones y programas académicos
-- Ejecutar en Supabase → SQL Editor DESPUÉS de supabase-setup.sql
-- y supabase-seguridad.sql. Se puede volver a ejecutar sin romper nada.
--
-- Qué introduce:
--   1. Una tabla de instituciones: nombre, colores, logo, membrete y
--      programas académicos. Cada institución es un mundo aparte.
--   2. Dos roles nuevos: administrador supremo (ve y atiende todas las
--      instituciones) y administrador de institución (manda sólo en la suya).
--   3. Cada cuenta pertenece a una institución y puede tener uno o varios
--      programas académicos asignados.
--   4. Todos los datos académicos quedan marcados con su institución y su
--      programa, y la base de datos impide ver los de otra.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Columnas nuevas en las cuentas
-- ---------------------------------------------------------------------
alter table public.perfiles add column if not exists institucion_id text;
alter table public.perfiles add column if not exists programas text;   -- JSON: ["Medicina","Enfermería"]

alter table public.perfiles drop constraint if exists perfiles_rol_valido;
alter table public.perfiles add constraint perfiles_rol_valido
  check (rol in ('pendiente','super','admin_inst','admin','direccion','academica',
                 'docencia','control','docente','indicadores','estudiante'));

-- ---------------------------------------------------------------------
-- 2. Tabla de instituciones
-- ---------------------------------------------------------------------
create table if not exists public.instituciones (
  id          text primary key,
  nombre      text not null,
  colores     text,          -- JSON: ["#7a1f2b","#2C5F8A","#D9A441"]
  logo        text,          -- imagen en data URL
  membrete    text,          -- imagen en data URL
  programas   text,          -- JSON: [{"id":"pg1","nombre":"Medicina"}]
  creado_en   timestamptz not null default now(),
  creado_por  uuid
);

alter table public.instituciones enable row level security;

-- ---------------------------------------------------------------------
-- 3. Funciones de apoyo
-- ---------------------------------------------------------------------
create or replace function public.es_super()
returns boolean language sql security definer stable set search_path = public as $$
  select exists (select 1 from public.perfiles
                 where id = auth.uid() and activo and rol = 'super');
$$;

create or replace function public.mi_institucion()
returns text language sql security definer stable set search_path = public as $$
  select institucion_id from public.perfiles where id = auth.uid() and activo;
$$;

-- ¿Manda en esta institución? El supremo manda en todas.
create or replace function public.manda_en(inst text)
returns boolean language sql security definer stable set search_path = public as $$
  select public.es_super() or exists (
    select 1 from public.perfiles
    where id = auth.uid() and activo
      and rol in ('admin_inst','admin','direccion')
      and institucion_id = inst
  );
$$;

-- Programas asignados a la cuenta. Lista vacía = sin restricción por programa.
create or replace function public.mis_programas()
returns text[] language plpgsql security definer stable set search_path = public as $$
declare txt text; res text[];
begin
  select programas into txt from public.perfiles where id = auth.uid() and activo;
  if txt is null or txt = '' or txt = '[]' then return array[]::text[]; end if;
  begin
    select array_agg(x) into res from jsonb_array_elements_text(txt::jsonb) as t(x);
  exception when others then return array[]::text[];
  end;
  return coalesce(res, array[]::text[]);
end $$;

-- ¿Puede ver una fila de esta institución y este programa?
create or replace function public.alcance(inst text, prog text)
returns boolean language sql security definer stable set search_path = public as $$
  select public.es_super()
      or (inst is not distinct from public.mi_institucion()
          and (array_length(public.mis_programas(),1) is null
               or prog is null
               or prog = any(public.mis_programas())));
$$;

-- ---------------------------------------------------------------------
-- 4. Políticas de instituciones
-- ---------------------------------------------------------------------
drop policy if exists "instituciones lee"     on public.instituciones;
drop policy if exists "instituciones crea"    on public.instituciones;
drop policy if exists "instituciones edita"   on public.instituciones;
drop policy if exists "instituciones borra"   on public.instituciones;

-- Cada quien ve la suya; el supremo ve todas.
create policy "instituciones lee" on public.instituciones
  for select to authenticated
  using (public.es_super() or id = public.mi_institucion());

-- Sólo el supremo da de alta instituciones.
create policy "instituciones crea" on public.instituciones
  for insert to authenticated with check (public.es_super());

-- La identidad la puede editar el supremo y el administrador de la institución.
create policy "instituciones edita" on public.instituciones
  for update to authenticated using (public.manda_en(id)) with check (public.manda_en(id));

create policy "instituciones borra" on public.instituciones
  for delete to authenticated using (public.es_super());

-- ---------------------------------------------------------------------
-- 5. Perfiles: quién ve y administra a quién
-- ---------------------------------------------------------------------
drop policy if exists "leer propio perfil"      on public.perfiles;
drop policy if exists "admin lee todo"          on public.perfiles;
drop policy if exists "insertar perfil propio"  on public.perfiles;
drop policy if exists "actualiza propio perfil" on public.perfiles;
drop policy if exists "admin borra perfiles"    on public.perfiles;

create policy "leer propio perfil" on public.perfiles
  for select to authenticated using (id = auth.uid());

-- El supremo ve todas las cuentas; quien manda en una institución ve las de ella.
create policy "admin lee todo" on public.perfiles
  for select to authenticated
  using (public.es_super() or public.manda_en(institucion_id));

create policy "insertar perfil propio" on public.perfiles
  for insert to authenticated
  with check (id = auth.uid() or public.es_super() or public.manda_en(institucion_id));

create policy "actualiza propio perfil" on public.perfiles
  for update to authenticated
  using (id = auth.uid() or public.es_super() or public.manda_en(institucion_id))
  with check (true);

create policy "admin borra perfiles" on public.perfiles
  for delete to authenticated
  using (public.es_super() or public.manda_en(institucion_id));

-- El blindaje sigue vigente, pero ahora también lo pasa el supremo y quien
-- manda en la institución de esa cuenta.
create or replace function public.perfiles_blindaje()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.es_super() or public.manda_en(new.institucion_id) then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.id <> auth.uid() then
      raise exception 'Sólo puedes crear tu propio perfil.';
    end if;
    new.rol := 'pendiente';
    new.activo := false;
    return new;
  end if;

  if new.id <> old.id or new.rol <> old.rol or new.activo <> old.activo
     or new.institucion_id is distinct from old.institucion_id then
    raise exception 'No tienes permiso para cambiar el rol, el estado o la institución de una cuenta.';
  end if;
  return new;
end $$;

-- Nadie se nombra supremo a sí mismo: ese rol sólo se otorga desde aquí.
create or replace function public.solo_super_nombra_super()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.rol = 'super' and auth.uid() is not null and not public.es_super() then
    raise exception 'El rol de administrador supremo sólo lo otorga otro supremo.';
  end if;
  return new;
end $$;
drop trigger if exists solo_super_trg on public.perfiles;
create trigger solo_super_trg before insert or update on public.perfiles
  for each row execute function public.solo_super_nombra_super();

-- ---------------------------------------------------------------------
-- 6. Datos académicos marcados con institución y programa
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['reingreso_expedientes','estudiantes','inscripciones','horarios_almacen'] loop
    execute format('alter table public.%I add column if not exists institucion_id text', t);
    execute format('alter table public.%I add column if not exists programa text', t);
    execute format('create index if not exists %I on public.%I (institucion_id)', 'ix_' || t || '_inst', t);
  end loop;
end $$;

-- Reingreso, padrón e inscripciones: leer dentro de su alcance,
-- escribir sólo las áreas responsables de esa institución.
do $$
declare t text;
begin
  foreach t in array array['reingreso_expedientes','estudiantes','inscripciones'] loop
    execute format('drop policy if exists "%s lee" on public.%I', t, t);
    execute format('drop policy if exists "%s escribe" on public.%I', t, t);
    execute format('drop policy if exists "%s edita" on public.%I', t, t);
    execute format('drop policy if exists "%s borra" on public.%I', t, t);

    execute format('create policy "%s lee" on public.%I for select to authenticated
      using (public.alcance(institucion_id, programa))', t, t);
    execute format('create policy "%s escribe" on public.%I for insert to authenticated
      with check (public.alcance(institucion_id, programa)
                  and (public.es_super() or public.puede(array[''admin_inst'',''admin'',''direccion'',''control''])))', t, t);
    execute format('create policy "%s edita" on public.%I for update to authenticated
      using (public.alcance(institucion_id, programa)
             and (public.es_super() or public.puede(array[''admin_inst'',''admin'',''direccion'',''control''])))
      with check (public.alcance(institucion_id, programa))', t, t);
    execute format('create policy "%s borra" on public.%I for delete to authenticated
      using (public.alcance(institucion_id, programa)
             and (public.es_super() or public.puede(array[''admin_inst'',''admin'',''direccion'',''control''])))', t, t);
  end loop;
end $$;

-- Horarios y ajustes por institución.
drop policy if exists "horarios lee"     on public.horarios_almacen;
drop policy if exists "horarios escribe" on public.horarios_almacen;
drop policy if exists "horarios edita"   on public.horarios_almacen;
drop policy if exists "horarios borra"   on public.horarios_almacen;

-- Nadie lee fuera de su institución. El cajón sin dueño («») no es de todos:
-- es de nadie, y sólo lo alcanza el supremo hasta que se le asigne dueño.
create policy "horarios lee" on public.horarios_almacen
  for select to authenticated
  using (public.es_super()
         or (institucion_id <> '' and institucion_id = coalesce(public.mi_institucion(), '')));
create policy "horarios escribe" on public.horarios_almacen
  for insert to authenticated
  with check (public.es_super() or public.manda_en(institucion_id)
              or (institucion_id <> ''
                  and institucion_id = coalesce(public.mi_institucion(), '')
                  and public.puede(array['academica','docencia','control'])));
create policy "horarios edita" on public.horarios_almacen
  for update to authenticated
  using (public.es_super() or public.manda_en(institucion_id)
         or (institucion_id <> ''
             and institucion_id = coalesce(public.mi_institucion(), '')
             and public.puede(array['academica','docencia','control'])))
  with check (true);
create policy "horarios borra" on public.horarios_almacen
  for delete to authenticated
  using (public.es_super() or public.manda_en(institucion_id));

-- La clave del almacén ya no es única por sí sola: lo es por institución.
-- La columna se deja NOT NULL con cadena vacía por omisión para que el índice
-- sea de columnas simples: es la única forma en que «upsert» puede apuntarle.
alter table public.horarios_almacen drop constraint if exists horarios_almacen_pkey cascade;
update public.horarios_almacen set institucion_id = '' where institucion_id is null;
alter table public.horarios_almacen alter column institucion_id set default '';
alter table public.horarios_almacen alter column institucion_id set not null;
drop index if exists public.horarios_almacen_clave_inst;
create unique index horarios_almacen_clave_inst
  on public.horarios_almacen (clave, institucion_id);

-- ---------------------------------------------------------------------
-- 7. Deja tu cuenta como administrador supremo
--    Cambia el correo y ejecuta estas dos líneas.
-- ---------------------------------------------------------------------
-- update public.perfiles set rol = 'super', activo = true
-- where correo = 'tucorreo@universidad.mx';

-- ---------------------------------------------------------------------
-- 8. Comprobación
-- ---------------------------------------------------------------------
select correo, rol, activo, institucion_id from public.perfiles order by rol;
