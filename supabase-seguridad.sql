-- =====================================================================
-- DIRIN · Endurecimiento de seguridad
-- Ejecutar en Supabase → SQL Editor DESPUÉS de supabase-setup.sql
-- Se puede volver a ejecutar cuantas veces quieras (no rompe nada).
--
-- Qué logra:
--   1. Nadie sin sesión puede leer ni escribir nada.
--   2. Una cuenta nueva nace INACTIVA con rol 'pendiente': existe, pero no
--      ve nada hasta que un administrador la autoriza.
--   3. Nadie puede darse a sí mismo el rol de administrador.
--   4. Cada rol escribe sólo en los módulos que le corresponden.
--   5. Queda registro de quién autorizó o cambió cada cuenta.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Roles válidos y estado inicial
-- ---------------------------------------------------------------------
alter table public.perfiles
  alter column rol set default 'pendiente';

alter table public.perfiles
  alter column activo set default false;

alter table public.perfiles drop constraint if exists perfiles_rol_valido;
alter table public.perfiles add constraint perfiles_rol_valido
  check (rol in ('pendiente','admin','direccion','academica','docencia','control','docente','indicadores','estudiante'));

-- ---------------------------------------------------------------------
-- 2. Funciones de apoyo (SECURITY DEFINER: leen perfiles sin recursión)
-- ---------------------------------------------------------------------
create or replace function public.mi_rol()
returns text language sql security definer stable set search_path = public as $$
  select rol from public.perfiles where id = auth.uid() and activo;
$$;

create or replace function public.cuenta_activa()
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.perfiles
    where id = auth.uid() and activo and rol <> 'pendiente'
  );
$$;

create or replace function public.es_admin()
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.perfiles where id = auth.uid() and activo and rol = 'admin'
  );
$$;

-- ¿Mi rol está en la lista que se le pasa?
create or replace function public.puede(roles text[])
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.perfiles
    where id = auth.uid() and activo and rol = any(roles)
  );
$$;

create or replace function public.edita_horarios()
returns boolean language sql security definer stable set search_path = public as $$
  select public.puede(array['admin','direccion']);
$$;

-- ---------------------------------------------------------------------
-- 3. Blindaje de la tabla perfiles
--    Sin esto, cualquiera que se registre podría escribir rol='admin'.
-- ---------------------------------------------------------------------
create or replace function public.perfiles_blindaje()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- Sin sesión de usuario (SQL Editor de Supabase o clave de servicio)
  -- o siendo administrador: pasa sin restricciones.
  if auth.uid() is null or public.es_admin() then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.id <> auth.uid() then
      raise exception 'Sólo puedes crear tu propio perfil.';
    end if;
    new.rol := 'pendiente';           -- nace sin permisos
    new.activo := false;              -- y sin acceso
    return new;
  end if;

  -- UPDATE hecho por el propio usuario: puede corregir su nombre y área,
  -- nunca su rol ni su estado.
  if new.id <> old.id
     or new.rol <> old.rol
     or new.activo <> old.activo then
    raise exception 'No tienes permiso para cambiar el rol o el estado de una cuenta.';
  end if;
  return new;
end $$;

drop trigger if exists perfiles_blindaje_trg on public.perfiles;
create trigger perfiles_blindaje_trg
  before insert or update on public.perfiles
  for each row execute function public.perfiles_blindaje();

-- Políticas de perfiles
drop policy if exists "leer propio perfil"     on public.perfiles;
drop policy if exists "admin lee todo"         on public.perfiles;
drop policy if exists "insertar perfil propio" on public.perfiles;
drop policy if exists "admin actualiza todo"   on public.perfiles;
drop policy if exists "admin inserta perfiles" on public.perfiles;
drop policy if exists "actualiza propio perfil" on public.perfiles;
drop policy if exists "admin borra perfiles"   on public.perfiles;

create policy "leer propio perfil" on public.perfiles
  for select to authenticated using (id = auth.uid());

create policy "admin lee todo" on public.perfiles
  for select to authenticated using (public.es_admin());

create policy "insertar perfil propio" on public.perfiles
  for insert to authenticated with check (id = auth.uid() or public.es_admin());

create policy "actualiza propio perfil" on public.perfiles
  for update to authenticated using (id = auth.uid() or public.es_admin()) with check (true);

create policy "admin borra perfiles" on public.perfiles
  for delete to authenticated using (public.es_admin());

-- ---------------------------------------------------------------------
-- 4. Datos académicos: leer sólo con cuenta autorizada,
--    escribir sólo el área responsable.
-- ---------------------------------------------------------------------
do $$
declare
  t text;
  escritores text;
begin
  foreach t in array array['reingreso_expedientes','estudiantes','inscripciones'] loop
    -- Reingreso y padrón: Dirección, Control Escolar y administración
    escritores := 'array[''admin'',''direccion'',''control'']';

    execute format('alter table public.%I enable row level security', t);

    execute format('drop policy if exists "%s lee autenticado" on public.%I', t, t);
    execute format('drop policy if exists "%s escribe autenticado" on public.%I', t, t);
    execute format('drop policy if exists "%s edita autenticado" on public.%I', t, t);
    execute format('drop policy if exists "%s borra autenticado" on public.%I', t, t);
    execute format('drop policy if exists "%s lee" on public.%I', t, t);
    execute format('drop policy if exists "%s escribe" on public.%I', t, t);
    execute format('drop policy if exists "%s edita" on public.%I', t, t);
    execute format('drop policy if exists "%s borra" on public.%I', t, t);

    execute format('create policy "%s lee" on public.%I for select to authenticated using (public.cuenta_activa())', t, t);
    execute format('create policy "%s escribe" on public.%I for insert to authenticated with check (public.puede(%s))', t, t, escritores);
    execute format('create policy "%s edita" on public.%I for update to authenticated using (public.puede(%s)) with check (public.puede(%s))', t, t, escritores, escritores);
    execute format('create policy "%s borra" on public.%I for delete to authenticated using (public.puede(%s))', t, t, escritores);
  end loop;
end $$;

-- Carga horaria: lectura para cuentas autorizadas, escritura admin y dirección
drop policy if exists "horarios lee autenticado" on public.horarios_almacen;
drop policy if exists "horarios lee"     on public.horarios_almacen;
drop policy if exists "horarios escribe" on public.horarios_almacen;
drop policy if exists "horarios edita"   on public.horarios_almacen;
drop policy if exists "horarios borra"   on public.horarios_almacen;

create policy "horarios lee" on public.horarios_almacen
  for select to authenticated using (public.cuenta_activa());
create policy "horarios escribe" on public.horarios_almacen
  for insert to authenticated with check (public.edita_horarios());
create policy "horarios edita" on public.horarios_almacen
  for update to authenticated using (public.edita_horarios()) with check (public.edita_horarios());
create policy "horarios borra" on public.horarios_almacen
  for delete to authenticated using (public.edita_horarios());

-- ---------------------------------------------------------------------
-- 5. Cerrar la puerta a visitantes sin sesión (rol 'anon')
-- ---------------------------------------------------------------------
revoke all on all tables    in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke all on all functions in schema public from anon;
alter default privileges in schema public revoke all on tables from anon;

-- ---------------------------------------------------------------------
-- 6. Bitácora de cambios en cuentas (quién autorizó a quién)
-- ---------------------------------------------------------------------
create table if not exists public.bitacora_cuentas (
  id          bigserial primary key,
  perfil_id   uuid,
  correo      text,
  rol_antes   text,
  rol_despues text,
  activo_antes   boolean,
  activo_despues boolean,
  hecho_por   uuid,
  hecho_en    timestamptz not null default now()
);

alter table public.bitacora_cuentas enable row level security;
drop policy if exists "bitacora admin" on public.bitacora_cuentas;
create policy "bitacora admin" on public.bitacora_cuentas
  for select to authenticated using (public.es_admin());

create or replace function public.bitacora_perfiles()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' or new.rol <> old.rol or new.activo <> old.activo then
    insert into public.bitacora_cuentas
      (perfil_id, correo, rol_antes, rol_despues, activo_antes, activo_despues, hecho_por)
    values (new.id, new.correo,
            case when tg_op = 'INSERT' then null else old.rol end, new.rol,
            case when tg_op = 'INSERT' then null else old.activo end, new.activo,
            auth.uid());
  end if;
  return null;
end $$;

drop trigger if exists bitacora_perfiles_trg on public.perfiles;
create trigger bitacora_perfiles_trg
  after insert or update on public.perfiles
  for each row execute function public.bitacora_perfiles();

-- ---------------------------------------------------------------------
-- 7. OPCIONAL · aceptar solamente correos de tu dominio
--    Quita los guiones de comentario y cambia el dominio.
-- ---------------------------------------------------------------------
-- create or replace function public.solo_dominio_institucional()
-- returns trigger language plpgsql security definer set search_path = public as $$
-- begin
--   if new.email not like '%@universidad.mx' then
--     raise exception 'Sólo se permiten correos @universidad.mx';
--   end if;
--   return new;
-- end $$;
-- drop trigger if exists solo_dominio_trg on auth.users;
-- create trigger solo_dominio_trg before insert on auth.users
--   for each row execute function public.solo_dominio_institucional();

-- ---------------------------------------------------------------------
-- 8. Deja activa tu propia cuenta de administrador
--    (sustituye el correo por el tuyo y ejecuta esta línea)
-- ---------------------------------------------------------------------
-- update public.perfiles set rol = 'admin', activo = true
-- where correo = 'tucorreo@universidad.mx';
