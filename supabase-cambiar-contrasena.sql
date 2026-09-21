-- ============================================================
-- Cambiar la contraseña de otra cuenta desde DIRIN
-- ------------------------------------------------------------
-- Con la llave pública el navegador no puede tocar auth.users.
-- Esta función corre del lado de la base con permisos elevados y
-- comprueba, antes de hacer nada, que quien la llama sea un
-- administrador activo. Ejecútala una sola vez en el SQL Editor
-- de Supabase.
-- ============================================================

create extension if not exists pgcrypto with schema extensions;

create or replace function public.admin_set_password(uid uuid, nueva text)
returns void
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  rol_quien text;
begin
  if nueva is null or length(nueva) < 6 then
    raise exception 'La contraseña debe tener al menos 6 caracteres.';
  end if;

  select p.rol into rol_quien
  from public.perfiles p
  where p.id = auth.uid() and p.activo;

  if rol_quien is null or rol_quien not in ('super', 'admin_inst', 'admin') then
    raise exception 'Sólo un administrador activo puede cambiar contraseñas.';
  end if;

  -- Un administrador de institución sólo alcanza a las cuentas de la suya.
  if rol_quien = 'admin_inst' or rol_quien = 'admin' then
    if not exists (
      select 1
      from public.perfiles destino, public.perfiles quien
      where destino.id = uid
        and quien.id = auth.uid()
        and destino.institucion_id is not distinct from quien.institucion_id
    ) then
      raise exception 'Esa cuenta no pertenece a tu institución.';
    end if;
  end if;

  update auth.users
     set encrypted_password = extensions.crypt(nueva, extensions.gen_salt('bf')),
         updated_at = now()
   where id = uid;

  if not found then
    raise exception 'No existe esa cuenta de acceso.';
  end if;
end;
$$;

revoke all on function public.admin_set_password(uuid, text) from public, anon;
grant execute on function public.admin_set_password(uuid, text) to authenticated;
