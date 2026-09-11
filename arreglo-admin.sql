-- DIRIN · corrige el candado y deja tu cuenta como administradora
-- Pega TODO esto en el SQL Editor de Supabase y presiona Run.
-- Cambia el correo de la última línea por el tuyo.

create or replace function public.perfiles_blindaje()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.es_admin() then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.id <> auth.uid() then
      raise exception 'Solo puedes crear tu propio perfil.';
    end if;
    new.rol := 'pendiente';
    new.activo := false;
    return new;
  end if;

  if new.id <> old.id or new.rol <> old.rol or new.activo <> old.activo then
    raise exception 'No tienes permiso para cambiar el rol o el estado de una cuenta.';
  end if;
  return new;
end $$;

-- Ahora sí: deja tu cuenta como administradora activa.
-- >>> CAMBIA EL CORREO <<<
insert into public.perfiles (id, nombre, correo, rol, area, activo)
select id, 'Administrador', email, 'admin', 'Direccion', true
from auth.users where email = 'tucorreo@universidad.mx'
on conflict (id) do update set rol = 'admin', activo = true;

-- Comprobación: debe mostrar tu correo con rol admin y activo = true
select correo, rol, activo from public.perfiles;
