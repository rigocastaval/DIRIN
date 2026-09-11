-- DIRIN · Reponer permisos y dejar que el PIN se guarde
--
-- IMPORTANTE: primero ejecuta COMPLETO el archivo `supabase-instituciones.sql`.
-- Ese archivo vuelve a crear las funciones y todas las políticas de lectura.
-- Ningún dato se borró: sólo dejaron de verse porque faltaban los permisos.
--
-- Después ejecuta este archivo. No borra nada; sólo agrega el permiso
-- del PIN propio.

alter table public.perfiles enable row level security;

drop policy if exists "perfil propio actualiza pin" on public.perfiles;
create policy "perfil propio actualiza pin" on public.perfiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- Comprobación: debe devolver tu renglón.
-- update public.perfiles set pin_hash = pin_hash where id = auth.uid() returning id;
