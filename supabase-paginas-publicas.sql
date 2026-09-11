-- DIRIN · Páginas públicas
-- Deja que cualquier visitante, sin cuenta, LEA únicamente el horario que la
-- escuela decidió publicar. Nada más: ni alumnos, ni pagos, ni el resto de
-- los renglones de horarios_almacen.
--
-- Ejecuta este archivo completo en el editor SQL de Supabase.

-- 1. Lectura anónima del renglón publicado, y sólo de ése.
drop policy if exists "horarios publicos lee" on public.horarios_almacen;
create policy "horarios publicos lee" on public.horarios_almacen
  for select to anon
  using (clave = 'publico:horarios');

-- 2. Nombre de la institución, para encabezar la página.
drop policy if exists "instituciones publicas lee" on public.instituciones;
create policy "instituciones publicas lee" on public.instituciones
  for select to anon
  using (
    exists (select 1 from public.horarios_almacen h
            where h.clave = 'publico:horarios'
              and h.institucion_id = instituciones.id)
  );

-- 3. Comprobación: como visitante anónimo debe devolver sólo esos renglones.
-- set role anon;
-- select institucion_id, actualizado_en from public.horarios_almacen;
-- reset role;
