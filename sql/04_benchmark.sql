-- ==============================================================================
-- CC3084 - Lab 8: DuckDB
-- Ejercicio 6: Consultas adicionales del benchmark Parquet vs tabla DuckDB
-- ==============================================================================
--
-- El benchmark (scripts/benchmark.py) ejecuta estas consultas y ademas un
-- subconjunto representativo de sql/02_analisis_exploratorio.sql:
--   p1_viajes_por_mes, p2_hora_dia_semana, p3_caracteristicas_viaje,
--   p5b_top_zonas_origen, p8a_propinas_por_metodo, p9_composicion_total
--
-- Todas usan las vistas `viajes` / `viajes_limpios`. En la estrategia Parquet,
-- `viajes` es una vista sobre read_parquet(); en la estrategia tabla, `viajes`
-- es una tabla con el mismo nombre y columnas (scripts/build_duckdb.py). Por lo
-- tanto el texto SQL ejecutado es identico en ambas estrategias.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- B1. Conteo total de registros.
-- Mide el costo minimo de "tocar" todo el conjunto. En Parquet el numero de
-- filas esta en los metadatos de cada archivo, pero la vista unificada hace
-- UNION ALL y extrae anio/mes del nombre del archivo.
-- ------------------------------------------------------------------------------
-- name: b1_conteo_total
SELECT tipo_taxi, count(*) AS registros
FROM viajes
GROUP BY tipo_taxi
ORDER BY tipo_taxi;


-- ------------------------------------------------------------------------------
-- B2. Consulta muy selectiva: viajes desde JFK (LocationID 132) el 15 de enero
-- de 2026 entre 17:00 y 18:00. Pocas filas cumplen; permite observar el efecto
-- de las estadisticas min/max (zone maps / row group statistics) de cada formato.
-- ------------------------------------------------------------------------------
-- name: b2_filtro_selectivo
SELECT
    tipo_taxi,
    count(*)                    AS viajes,
    round(avg(total_amount), 2) AS total_prom,
    round(avg(trip_distance), 2) AS distancia_prom
FROM viajes
WHERE pu_location_id = 132
  AND pickup_datetime >= TIMESTAMP '2026-01-15 17:00:00'
  AND pickup_datetime <  TIMESTAMP '2026-01-15 18:00:00'
GROUP BY tipo_taxi;


-- ------------------------------------------------------------------------------
-- B3. Agregacion simple sobre pocas columnas (barrido de 3 columnas).
-- ------------------------------------------------------------------------------
-- name: b3_agregacion_simple
SELECT
    tipo_taxi,
    anio,
    round(sum(total_amount), 0)   AS recaudacion,
    round(avg(trip_distance), 3)  AS distancia_prom
FROM viajes
GROUP BY tipo_taxi, anio
ORDER BY tipo_taxi, anio;
