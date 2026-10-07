-- ==============================================================================
-- CC3084 - Lab 8: DuckDB
-- Ejercicio 5: Validacion de la incorporacion de los datos de 2024
-- ==============================================================================
--
-- V1-V3 trabajan sobre los metadatos y el esquema de los archivos Parquet
-- (parquet_file_metadata / parquet_schema): no leen los datos, solo los pies de
-- pagina de cada archivo, por lo que son casi instantaneas.
-- V4-V6 usan las vistas de sql/00_vistas.sql para comprobar que 2024 y 2026 se
-- pueden consultar conjuntamente con el mismo SQL.
-- Ejecutadas desde notebooks/03_incorporacion_2024.ipynb.
-- ==============================================================================


-- ------------------------------------------------------------------------------
-- V1. Inventario de archivos por tipo y anio (desde los metadatos Parquet).
-- Objetivo: confirmar que 2024 tiene sus 12 meses para ambos tipos y que los
--           archivos de 2026 siguen presentes.
-- ------------------------------------------------------------------------------
-- name: v1_inventario_archivos
SELECT
    regexp_extract(file_name, '/(yellow|green)/', 1)                         AS tipo_taxi,
    CAST(regexp_extract(file_name, '_(\d{4})-\d{2}\.parquet$', 1) AS INTEGER) AS anio,
    count(*)                                                                 AS archivos,
    string_agg(regexp_extract(file_name, '-(\d{2})\.parquet$', 1), ',' ORDER BY file_name) AS meses,
    sum(num_rows)                                                            AS registros_metadatos,
    round(sum(file_size_bytes) / 1024 ^ 2, 1)                                AS mib
FROM parquet_file_metadata('data/raw/*/*/*.parquet')
GROUP BY ALL
ORDER BY tipo_taxi DESC, anio;


-- ------------------------------------------------------------------------------
-- V2. Conteo a traves de la vista unificada vs conteo en metadatos.
-- Objetivo: verificar que la vista `viajes` lee todas las filas de todos los
--           archivos (ninguno se omite y union_by_name no pierde registros).
-- ------------------------------------------------------------------------------
-- name: v2_conteo_vista_vs_metadatos
WITH metadatos AS (
    SELECT
        regexp_extract(file_name, '/(yellow|green)/', 1)                         AS tipo_taxi,
        CAST(regexp_extract(file_name, '_(\d{4})-\d{2}\.parquet$', 1) AS INTEGER) AS anio,
        sum(num_rows)                                                            AS registros_metadatos
    FROM parquet_file_metadata('data/raw/*/*/*.parquet')
    GROUP BY ALL
),
vista AS (
    SELECT tipo_taxi, anio, count(*) AS registros_vista, count(DISTINCT mes) AS meses
    FROM viajes
    GROUP BY ALL
)
SELECT
    tipo_taxi, anio, meses, registros_metadatos, registros_vista,
    registros_metadatos = registros_vista AS coincide
FROM metadatos
FULL JOIN vista USING (tipo_taxi, anio)
ORDER BY tipo_taxi DESC, anio;


-- ------------------------------------------------------------------------------
-- V3. Evolucion del esquema: columnas que NO estan en todos los archivos de su
-- tipo de taxi, o que cambian de tipo fisico entre archivos.
-- Objetivo: decidir si la vista unificada necesita cambios para 2024.
-- ------------------------------------------------------------------------------
-- name: v3_evolucion_esquema
WITH columnas AS (
    SELECT DISTINCT
        file_name,
        regexp_extract(file_name, '/(yellow|green)/', 1)    AS tipo_taxi,
        regexp_extract(file_name, '_(\d{4}-\d{2})\.parquet$', 1) AS periodo,
        name                                                AS columna,
        type                                                AS tipo_fisico
    FROM parquet_schema('data/raw/*/*/*.parquet')
    WHERE name NOT IN ('schema', 'duckdb_schema')
),
total AS (
    SELECT tipo_taxi, count(DISTINCT file_name) AS archivos_tipo FROM columnas GROUP BY ALL
)
SELECT
    c.tipo_taxi,
    c.columna,
    count(DISTINCT c.file_name)                                   AS archivos_con_columna,
    any_value(t.archivos_tipo)                                    AS archivos_del_tipo,
    min(c.periodo)                                                AS primer_periodo,
    max(c.periodo)                                                AS ultimo_periodo,
    string_agg(DISTINCT c.tipo_fisico, ', ')                      AS tipos_fisicos
FROM columnas c
JOIN total t USING (tipo_taxi)
GROUP BY c.tipo_taxi, c.columna
HAVING count(DISTINCT c.file_name) < any_value(t.archivos_tipo)
    OR count(DISTINCT c.tipo_fisico) > 1
ORDER BY c.tipo_taxi DESC, c.columna;


-- ------------------------------------------------------------------------------
-- V4. Calidad por anio: las reglas de limpieza del Ejercicio 4 aplicadas a
-- cada anio por separado.
-- Objetivo: comprobar que 2024 no introduce problemas de calidad nuevos que
--           obliguen a cambiar las reglas de `viajes_limpios`.
-- ------------------------------------------------------------------------------
-- name: v4_calidad_por_anio
SELECT
    tipo_taxi,
    anio,
    count(*)                                                                    AS registros,
    count(*) FILTER (WHERE date_trunc('month', pickup_datetime) <> make_date(anio, mes, 1)) AS r1_fuera_de_periodo,
    count(*) FILTER (WHERE dropoff_datetime <= pickup_datetime
                        OR date_diff('second', pickup_datetime, dropoff_datetime) > 4 * 3600) AS r2_duracion_invalida,
    count(*) FILTER (WHERE trip_distance <= 0 OR trip_distance > 100)           AS r3_distancia_invalida,
    count(*) FILTER (WHERE fare_amount < 0 OR total_amount < 0)                 AS r4_monto_negativo,
    round(100.0 * count(*) FILTER (WHERE NOT (
            date_trunc('month', pickup_datetime) = make_date(anio, mes, 1)
        AND dropoff_datetime > pickup_datetime
        AND date_diff('second', pickup_datetime, dropoff_datetime) <= 4 * 3600
        AND trip_distance > 0 AND trip_distance <= 100
        AND fare_amount >= 0 AND total_amount >= 0)) / count(*), 2)    AS pct_excluidos,
    round(100.0 * count(*) FILTER (WHERE passenger_count IS NULL) / count(*), 2) AS pct_passenger_nulo,
    min(pickup_datetime)                                                        AS pickup_min,
    max(pickup_datetime)                                                        AS pickup_max
FROM viajes
GROUP BY ALL
ORDER BY tipo_taxi DESC, anio;


-- ------------------------------------------------------------------------------
-- V5. Comparacion conjunta 2024 vs 2026 para los mismos meses (enero-agosto),
-- para que la comparacion no dependa de la estacionalidad.
-- Objetivo: demostrar que ambos anios se consultan en una sola consulta y
--           obtener una primera vista de los cambios entre anios.
-- ------------------------------------------------------------------------------
-- name: v5_comparacion_anual_ene_ago
SELECT
    tipo_taxi,
    anio,
    count(*)                                                                AS viajes,
    round(count(*) / count(DISTINCT CAST(pickup_datetime AS DATE)), 0)      AS viajes_por_dia,
    round(median(trip_distance), 2)                                         AS mediana_distancia_mi,
    round(median(duracion_min), 1)                                          AS mediana_duracion_min,
    round(median(total_amount), 2)                                          AS mediana_total,
    round(100.0 * avg(CASE WHEN payment_type = 1 THEN 1 ELSE 0 END), 1)     AS pct_tarjeta,
    round(100.0 * avg(CASE WHEN payment_type = 2 THEN 1 ELSE 0 END), 1)     AS pct_efectivo,
    round(100.0 * avg(CASE WHEN payment_type = 0 OR payment_type IS NULL THEN 1 ELSE 0 END), 1) AS pct_pago_no_registrado,
    round(100.0 * avg(CASE WHEN coalesce(cbd_congestion_fee, 0) > 0 THEN 1 ELSE 0 END), 1) AS pct_con_cargo_cbd
FROM viajes_limpios
WHERE mes BETWEEN 1 AND 8
GROUP BY ALL
ORDER BY tipo_taxi DESC, anio;


-- ------------------------------------------------------------------------------
-- V6. Viajes promedio por dia, mes a mes, ambos anios en la misma tabla.
-- Objetivo: verificar la continuidad de la serie y que cada mes de 2024 tiene
--           un volumen razonable (ningun archivo truncado o vacio).
-- ------------------------------------------------------------------------------
-- name: v6_viajes_por_dia_mes_anio
SELECT
    tipo_taxi,
    mes,
    round(count(*) FILTER (WHERE anio = 2024)
          / count(DISTINCT CAST(pickup_datetime AS DATE)) FILTER (WHERE anio = 2024), 0) AS por_dia_2024,
    round(count(*) FILTER (WHERE anio = 2026)
          / count(DISTINCT CAST(pickup_datetime AS DATE)) FILTER (WHERE anio = 2026), 0) AS por_dia_2026,
    round(100.0 * (por_dia_2026 / por_dia_2024 - 1), 1)                                  AS variacion_pct
FROM viajes_limpios
GROUP BY ALL
ORDER BY tipo_taxi DESC, mes;
