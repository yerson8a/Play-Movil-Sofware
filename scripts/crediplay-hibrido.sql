-- ============================================================================
-- MODELO HÍBRIDO CREDIPLAY — SQL versionado (ya aplicado en producción)
-- ============================================================================
-- Aplicado el 2026-09-09 vía MCP. Migración en Supabase: crediplay_modelo_hibrido
-- Este archivo es la copia versionada; no se ejecuta automáticamente.
--
-- Modelo: el precio a crédito = precio de contado + sobreprecio según el plazo
-- (8% a 58%), y sobre el capital financiado corre el 2% mensual (1% quincenal,
-- EA ≈ 26,97%). Aplica SOLO a créditos nuevos: los 52 créditos Crediplay que ya
-- existían quedan con es_hibrido = false y no cambian de comportamiento.
--
-- Todas las columnas son nullable o con default, así que las filas viejas
-- siguen válidas sin tocarlas.
-- ============================================================================

-- Ventas: se guarda también el precio de contado del equipo. valor_venta sigue
-- siendo el precio a crédito (es el que suma a los informes del mes).
alter table public.ventas add column if not exists precio_contado       numeric(15,2);
alter table public.ventas add column if not exists es_crediplay_hibrido boolean default false;

-- Créditos: desglose del modelo. saldo_pendiente guarda el CAPITAL, no el
-- capital + intereses: los intereses se causan cuota a cuota sobre el saldo.
alter table public.creditos add column if not exists precio_contado      numeric(15,2);
alter table public.creditos add column if not exists precio_credito      numeric(15,2);
alter table public.creditos add column if not exists sobreprecio_credito numeric(15,2) default 0;
alter table public.creditos add column if not exists capital_financiado  numeric(15,2);
alter table public.creditos add column if not exists intereses_pactados  numeric(15,2) default 0;
alter table public.creditos add column if not exists tasa_mensual        numeric(5,2)  default 2.0;
alter table public.creditos add column if not exists es_hibrido          boolean       default false;

-- Abonos: cada pago queda desglosado entre interés del período y capital.
-- En créditos no híbridos capital = valor del abono e interes = 0.
alter table public.abonos add column if not exists capital             numeric(15,2) default 0;
alter table public.abonos add column if not exists interes             numeric(15,2) default 0;
alter table public.abonos add column if not exists sobreprecio_causado numeric(15,2) default 0;
