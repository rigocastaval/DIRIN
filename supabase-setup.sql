-- =====================================================================
-- Sistema Integral de Administración Escolar
-- Ejecutar UNA VEZ en Supabase → SQL Editor → New query → Run
-- =====================================================================

-- 1. Tabla de perfiles (extiende auth.users con rol y área)
create table if not exists public.perfiles (
  id         uuid primary key references auth.users on delete cascade,
  nombre     text not null,
  correo     text,
  rol        text not null default 'docente',
  area       text,
  activo     boolean not null default true,
  creado_en  timestamptz not null default now()
);

alter table public.perfiles enable row level security;

-- 2. Helper con SECURITY DEFINER para evitar recursión en las políticas
create or replace function public.es_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.perfiles
    where id = auth.uid() and rol = 'admin' and activo
  );
$$;

-- 3. Políticas
drop policy if exists "leer propio perfil"   on public.perfiles;
drop policy if exists "admin lee todo"       on public.perfiles;
drop policy if exists "insertar perfil propio" on public.perfiles;
drop policy if exists "admin actualiza todo" on public.perfiles;

create policy "leer propio perfil" on public.perfiles
  for select using (id = auth.uid());

create policy "admin lee todo" on public.perfiles
  for select using (public.es_admin());

create policy "insertar perfil propio" on public.perfiles
  for insert with check (id = auth.uid());

create policy "admin actualiza todo" on public.perfiles
  for update using (public.es_admin()) with check (true);

-- =====================================================================
-- 4. CREAR TU CUENTA DE ADMINISTRADOR
--    a) Authentication → Users → Add user → Create new user
--       (marca "Auto Confirm User"), anota el correo y contraseña.
--    b) Copia el UUID que aparece en la lista de usuarios.
--    c) Sustituye abajo y ejecuta:
-- =====================================================================
-- insert into public.perfiles (id, nombre, correo, rol, area, activo)
-- values ('PEGA-AQUI-EL-UUID', 'Tu Nombre', 'tucorreo@dominio.com', 'admin', 'Dirección', true)
-- on conflict (id) do update set rol = 'admin', activo = true;

-- =====================================================================
-- 5. Módulo Reingreso · expedientes y evaluaciones
--    (los criterios y requisitos viven en el código; aquí se guarda
--     lo asentado por el usuario, en jsonb, para que el reglamento
--     pueda cambiar sin migrar la tabla)
-- =====================================================================
create table if not exists public.reingreso_expedientes (
  id                 text primary key,
  nombre             text not null,
  matricula          text,
  creditos           text,
  recibida           timestamptz not null default now(),
  req                jsonb not null default '{}'::jsonb,
  salud_psicologica  boolean not null default false,
  sel                jsonb not null default '{}'::jsonb,
  actualizado_en     timestamptz not null default now(),
  actualizado_por    uuid references auth.users on delete set null
);

alter table public.reingreso_expedientes enable row level security;

drop policy if exists "reingreso lee autenticado"     on public.reingreso_expedientes;
drop policy if exists "reingreso escribe autenticado" on public.reingreso_expedientes;
drop policy if exists "reingreso edita autenticado"   on public.reingreso_expedientes;
drop policy if exists "reingreso borra autenticado"   on public.reingreso_expedientes;

create policy "reingreso lee autenticado" on public.reingreso_expedientes
  for select to authenticated using (true);

create policy "reingreso escribe autenticado" on public.reingreso_expedientes
  for insert to authenticated with check (true);

create policy "reingreso edita autenticado" on public.reingreso_expedientes
  for update to authenticated using (true) with check (true);

create policy "reingreso borra autenticado" on public.reingreso_expedientes
  for delete to authenticated using (true);

-- =====================================================================
-- 6. Control Escolar · padrón estudiantil e historial por promoción
--    estudiantes  = la persona (dato permanente)
--    inscripciones = una capa por semestre: en qué promoción estuvo el
--                    estudiante y en qué grado y grupo. El histórico se
--                    consulta filtrando por periodo (2025A, 2025B, …).
-- =====================================================================
create table if not exists public.estudiantes (
  id          text primary key,
  nombre      text not null,
  matricula   text,
  generacion  text,
  estatus     text not null default 'aspirante',  -- aspirante | admitido | inscrito | baja | egresado
  nota        text,
  creado_en   timestamptz not null default now()
);

create unique index if not exists estudiantes_matricula_uniq
  on public.estudiantes (matricula) where matricula is not null and matricula <> '';

create table if not exists public.inscripciones (
  id            text primary key,
  estudiante_id text not null references public.estudiantes on delete cascade,
  periodo       text not null,                    -- '2025A' = Promoción A 2025 (ene–jul)
  grado         int  not null,                    -- 1..12 (semestre)
  grupo         text not null,                    -- 'A', 'B', …
  estatus       text not null default 'activo',   -- activo | baja
  creado_en     timestamptz not null default now(),
  unique (estudiante_id, periodo)
);

create index if not exists inscripciones_periodo_idx on public.inscripciones (periodo, grado, grupo);

alter table public.estudiantes   enable row level security;
alter table public.inscripciones enable row level security;

do $$
declare t text;
begin
  foreach t in array array['estudiantes','inscripciones'] loop
    execute format('drop policy if exists "%s lee autenticado" on public.%I', t, t);
    execute format('drop policy if exists "%s escribe autenticado" on public.%I', t, t);
    execute format('drop policy if exists "%s edita autenticado" on public.%I', t, t);
    execute format('drop policy if exists "%s borra autenticado" on public.%I', t, t);
    execute format('create policy "%s lee autenticado" on public.%I for select to authenticated using (true)', t, t);
    execute format('create policy "%s escribe autenticado" on public.%I for insert to authenticated with check (true)', t, t);
    execute format('create policy "%s edita autenticado" on public.%I for update to authenticated using (true) with check (true)', t, t);
    execute format('create policy "%s borra autenticado" on public.%I for delete to authenticated using (true)', t, t);
  end loop;
end $$;

-- =====================================================================
-- 7. Coordinación Académica · Carga horaria
--    El programador de horarios guarda aquí sus proyectos: docentes con
--    horas contratadas y perfil, plan de estudios (materias y horas por
--    semana) y las rejillas ya programadas, cada versión bajo su clave:
--      horarios:auto             → guardado automático
--      horarios:proyecto:<nombre> → proyecto con nombre, para reabrir y editar
--      horarios:historial:<fecha> → versiones anteriores
--    Leer: cualquier cuenta con sesión. Escribir: sólo admin y dirección.
-- =====================================================================
create or replace function public.edita_horarios()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.perfiles
    where id = auth.uid() and activo and rol in ('admin','direccion')
  );
$$;

create table if not exists public.horarios_almacen (
  clave           text primary key,
  valor           text not null,
  actualizado_en  timestamptz not null default now(),
  actualizado_por uuid references auth.users on delete set null
);

alter table public.horarios_almacen enable row level security;

drop policy if exists "horarios lee autenticado" on public.horarios_almacen;
drop policy if exists "horarios escribe"         on public.horarios_almacen;
drop policy if exists "horarios edita"           on public.horarios_almacen;
drop policy if exists "horarios borra"           on public.horarios_almacen;

create policy "horarios lee autenticado" on public.horarios_almacen
  for select to authenticated using (true);

create policy "horarios escribe" on public.horarios_almacen
  for insert to authenticated with check (public.edita_horarios());

create policy "horarios edita" on public.horarios_almacen
  for update to authenticated using (public.edita_horarios()) with check (public.edita_horarios());

create policy "horarios borra" on public.horarios_almacen
  for delete to authenticated using (public.edita_horarios());

-- =====================================================================
-- 8. Authentication → Providers → Email → desactiva "Confirm email"
--    para que las cuentas creadas desde el sistema entren de inmediato.
-- =====================================================================
