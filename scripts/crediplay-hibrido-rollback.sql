-- ============================================================================
-- ROLLBACK del modelo híbrido Crediplay (crediplay-hibrido.sql)
-- ============================================================================
-- OJO: borra los datos del modelo híbrido de los créditos y ventas que ya lo
-- usen. Revisa antes con:
--   select count(*) from creditos where es_hibrido;
--   select count(*) from ventas   where es_crediplay_hibrido;
-- El resto de columnas (monto_total, saldo_pendiente, valor de los abonos) no
-- se toca, así que los créditos siguen existiendo como créditos normales.
-- ============================================================================

alter table public.ventas   drop column if exists precio_contado;
alter table public.ventas   drop column if exists es_crediplay_hibrido;

alter table public.creditos drop column if exists precio_contado;
alter table public.creditos drop column if exists precio_credito;
alter table public.creditos drop column if exists sobreprecio_credito;
alter table public.creditos drop column if exists capital_financiado;
alter table public.creditos drop column if exists intereses_pactados;
alter table public.creditos drop column if exists tasa_mensual;
alter table public.creditos drop column if exists es_hibrido;

alter table public.abonos   drop column if exists capital;
alter table public.abonos   drop column if exists interes;
alter table public.abonos   drop column if exists sobreprecio_causado;
