-- DIRIN · Activación de módulos por institución
-- La llave 'modulos:activos' de horarios_almacen guarda qué funciones dejó
-- encendidas el administrador supremo en cada institución. Sólo él escribe ahí;
-- los miembros de la institución únicamente la leen.

alter table public.horarios_almacen enable row level security;

-- Lectura: cualquiera de la institución (y el supremo, en cualquiera).
drop policy if exists "lee almacen de su institucion" on public.horarios_almacen;
create policy "lee almacen de su institucion" on public.horarios_almacen
  for select using (
    public.mi_rol() = 'super'
    or institucion_id = public.mi_institucion()
  );

-- Escritura de la llave de módulos: exclusiva del supremo.
drop policy if exists "supremo activa modulos" on public.horarios_almacen;
create policy "supremo activa modulos" on public.horarios_almacen
  for all using (
    case when clave = 'modulos:activos'
      then public.mi_rol() = 'super'
      else public.mi_rol() in ('super','admin_inst','admin')
           and (public.mi_rol() = 'super' or institucion_id = public.mi_institucion())
    end
  ) with check (
    case when clave = 'modulos:activos'
      then public.mi_rol() = 'super'
      else public.mi_rol() in ('super','admin_inst','admin')
           and (public.mi_rol() = 'super' or institucion_id = public.mi_institucion())
    end
  );

-- Una sola fila por llave e institución (upsert de la app).
create unique index if not exists horarios_almacen_clave_inst
  on public.horarios_almacen (clave, institucion_id);
