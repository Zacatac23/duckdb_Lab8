-- ==============================================================================
-- CC3084 - Lab 8: DuckDB
-- Vistas base sobre los archivos Parquet (usadas desde el Ejercicio 4 en adelante)
-- ==============================================================================
--
-- Todas las consultas de analisis se escriben contra estas vistas y NO contra
-- rutas de archivos concretas. Las vistas leen los Parquet con un patron glob
-- (data/raw/<tipo>/*/*.parquet), por lo que cualquier anio nuevo que el script
-- de descarga coloque en data/raw/<tipo>/<anio>/ queda incluido automaticamente
-- sin modificar ninguna consulta (ver Ejercicio 5).
--
-- Las rutas son relativas a la raiz del proyecto (/workspace dentro del
-- contenedor), que es el directorio de trabajo de los scripts y notebooks.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- Vistas crudas: una por tipo de taxi, todos los anios descargados.
--   union_by_name = true : los esquemas cambian entre anios (p. ej.
--                          cbd_congestion_fee aparece en 2025); las columnas se
--                          alinean por nombre y las faltantes quedan en NULL.
--   filename = true      : conserva el archivo de origen de cada fila, de donde
--                          se obtiene el anio/mes "oficial" del registro.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW yellow_raw AS
SELECT * FROM read_parquet('data/raw/yellow/*/*.parquet', union_by_name = true, filename = true);

CREATE OR REPLACE VIEW green_raw AS
SELECT * FROM read_parquet('data/raw/green/*/*.parquet', union_by_name = true, filename = true);


-- ------------------------------------------------------------------------------
-- Vista unificada: normaliza los nombres de columnas de ambos tipos de taxi.
--   - tpep_* (yellow) y lpep_* (green) -> pickup_datetime / dropoff_datetime
--   - Columnas exclusivas de un tipo quedan en NULL en el otro
--     (airport_fee solo yellow; ehail_fee y trip_type solo green).
--   - anio / mes provienen del NOMBRE del archivo, no de la fecha del viaje:
--     el Ejercicio 3 mostro que hay fechas fuera del periodo del archivo.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW viajes AS
SELECT
    'yellow'                                                             AS tipo_taxi,
    CAST(regexp_extract(filename, '_(\d{4})-\d{2}\.parquet$', 1) AS INTEGER) AS anio,
    CAST(regexp_extract(filename, '_\d{4}-(\d{2})\.parquet$', 1) AS INTEGER) AS mes,
    VendorID                AS vendor_id,
    tpep_pickup_datetime    AS pickup_datetime,
    tpep_dropoff_datetime   AS dropoff_datetime,
    passenger_count,
    trip_distance,
    RatecodeID              AS ratecode_id,
    store_and_fwd_flag,
    PULocationID            AS pu_location_id,
    DOLocationID            AS do_location_id,
    payment_type,
    fare_amount,
    extra,
    mta_tax,
    tip_amount,
    tolls_amount,
    improvement_surcharge,
    congestion_surcharge,
    Airport_fee             AS airport_fee,
    cbd_congestion_fee,
    CAST(NULL AS DOUBLE)    AS ehail_fee,
    CAST(NULL AS BIGINT)    AS trip_type,
    total_amount
FROM yellow_raw
UNION ALL
SELECT
    'green'                                                              AS tipo_taxi,
    CAST(regexp_extract(filename, '_(\d{4})-\d{2}\.parquet$', 1) AS INTEGER) AS anio,
    CAST(regexp_extract(filename, '_\d{4}-(\d{2})\.parquet$', 1) AS INTEGER) AS mes,
    VendorID                AS vendor_id,
    lpep_pickup_datetime    AS pickup_datetime,
    lpep_dropoff_datetime   AS dropoff_datetime,
    passenger_count,
    trip_distance,
    RatecodeID              AS ratecode_id,
    store_and_fwd_flag,
    PULocationID            AS pu_location_id,
    DOLocationID            AS do_location_id,
    payment_type,
    fare_amount,
    extra,
    mta_tax,
    tip_amount,
    tolls_amount,
    improvement_surcharge,
    congestion_surcharge,
    CAST(NULL AS DOUBLE)    AS airport_fee,
    cbd_congestion_fee,
    ehail_fee,
    trip_type,
    total_amount
FROM green_raw;


-- ------------------------------------------------------------------------------
-- Vista limpia: aplica las reglas de calidad derivadas del Ejercicio 3 y agrega
-- columnas derivadas. Se usa para las metricas de comportamiento; los conteos
-- de calidad se hacen sobre `viajes` (sin filtrar).
--
-- Reglas (cada una se cuantifica en sql/02_analisis_exploratorio.sql, q10):
--   R1. La fecha de inicio cae dentro del mes del archivo de origen.
--   R2. Duracion positiva y menor o igual a 4 horas.
--   R3. Distancia mayor que 0 y menor o igual a 100 millas.
--   R4. fare_amount y total_amount no negativos (excluye reversos/disputas).
-- passenger_count NULL se conserva: representa ~26% de yellow y eliminarlo
-- sesgaria todas las demas metricas.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW viajes_limpios AS
SELECT
    *,
    date_diff('second', pickup_datetime, dropoff_datetime) / 60.0  AS duracion_min,
    trip_distance / nullif(date_diff('second', pickup_datetime, dropoff_datetime) / 3600.0, 0)
                                                                    AS velocidad_mph,
    hour(pickup_datetime)                                           AS hora,
    isodow(pickup_datetime)                                         AS dia_semana   -- 1 = lunes ... 7 = domingo
FROM viajes
WHERE date_trunc('month', pickup_datetime) = make_date(anio, mes, 1)                -- R1
  AND dropoff_datetime > pickup_datetime                                            -- R2
  AND date_diff('second', pickup_datetime, dropoff_datetime) <= 4 * 3600            -- R2
  AND trip_distance > 0 AND trip_distance <= 100                                    -- R3
  AND fare_amount >= 0 AND total_amount >= 0;                                       -- R4


-- ------------------------------------------------------------------------------
-- Catalogos de referencia
-- ------------------------------------------------------------------------------
-- Zonas de taxi de la TLC (descargado por scripts/download_data.py).
CREATE OR REPLACE VIEW zonas AS
SELECT
    LocationID   AS location_id,
    Borough      AS borough,
    Zone         AS zona,
    service_zone
FROM read_csv('data/raw/taxi_zone_lookup.csv', header = true);

-- Tipos de pago segun el diccionario de datos de la TLC.
CREATE OR REPLACE VIEW tipos_pago AS
SELECT * FROM (VALUES
    (0, 'Flex fare'),
    (1, 'Tarjeta'),
    (2, 'Efectivo'),
    (3, 'Sin cargo'),
    (4, 'Disputa'),
    (5, 'Desconocido'),
    (6, 'Viaje anulado')
) AS t(payment_type, metodo_pago);
