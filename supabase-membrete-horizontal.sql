-- Hoja membretada horizontal
-- La institución guarda dos hojas membretadas: la vertical (carta de pie) y la
-- horizontal (carta acostada). Cada documento usa la que corresponde a su
-- orientación, de modo que todo lo que se imprime o descarga lleve la misma
-- imagen institucional.
--
-- Ejecútalo una vez en el editor SQL de Supabase.

alter table public.instituciones
  add column if not exists membrete_h text default '';

update public.instituciones set membrete_h = '' where membrete_h is null;
