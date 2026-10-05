-- ==============================================================================
-- CC3084 - Lab 8: DuckDB
-- Ejercicio 3: Consultas directas sobre archivos Parquet (Exploracion Inicial)
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- Consulta 1: Conteo de archivos y registros por mes (Taxis Amarillos y Verdes)
-- ------------------------------------------------------------------------------
-- Objetivo: Determinar la cantidad de archivos disponibles y el volumen total de
--           registros por mes y por tipo de taxi.
-- Fuentes:  'data/raw/yellow/2026/*.parquet', 'data/raw/green/2026/*.parquet'
-- Decision: Se confirma que la TLC ha publicado 8 meses (01 a 08) para 2026,
--           totalizando 29,703,355 filas de yellow y 337,114 filas de green.
-- ------------------------------------------------------------------------------

-- Resumen de Yellow Taxi por archivo:
SELECT 
    filename,
    count(*) AS total_registros
FROM read_parquet('data/raw/yellow/2026/*.parquet', filename=true)
GROUP BY filename
ORDER BY filename;

-- Resumen de Green Taxi por archivo:
SELECT 
    filename,
    count(*) AS total_registros
FROM read_parquet('data/raw/green/2026/*.parquet', filename=true)
GROUP BY filename
ORDER BY filename;

-- Conteo total global de ambos tipos:
SELECT 
    'Yellow Taxi' AS tipo_taxi,
    count(DISTINCT filename) AS total_archivos,
    count(*) AS total_registros
FROM read_parquet('data/raw/yellow/2026/*.parquet', filename=true)
UNION ALL
SELECT 
    'Green Taxi' AS tipo_taxi,
    count(DISTINCT filename) AS total_archivos,
    count(*) AS total_registros
FROM read_parquet('data/raw/green/2026/*.parquet', filename=true);


-- ------------------------------------------------------------------------------
-- Consulta 2: Esquema y tipos de datos de las columnas
-- ------------------------------------------------------------------------------
-- Objetivo: Identificar los nombres de columnas, tipos de datos y compatibilidad
--           entre los esquemas de Yellow Taxi y Green Taxi.
-- Fuentes:  'data/raw/yellow/2026/*.parquet', 'data/raw/green/2026/*.parquet'
-- Decision: Se observa que los campos temporales difieren en prefijo:
--           Yellow usa tpep_pickup/dropoff_datetime mientras que Green usa
--           lpep_pickup/dropoff_datetime. Además, Green incluye 'trip_type' y
--           'ehail_fee', mientras que Yellow incluye 'Airport_fee'.
--           Cualquier vista unificada requerirá normalizar o mapear estos nombres.
-- ------------------------------------------------------------------------------

DESCRIBE SELECT * FROM read_parquet('data/raw/yellow/2026/*.parquet');

DESCRIBE SELECT * FROM read_parquet('data/raw/green/2026/*.parquet');


-- ------------------------------------------------------------------------------
-- Consulta 3: Muestra de registros representativos
-- ------------------------------------------------------------------------------
-- Objetivo: Inspeccionar visualmente la semántica de los datos, valores comunes y
--           formatos de fecha, distancia, tarifas y propinas.
-- Fuentes:  'data/raw/yellow/2026/yellow_tripdata_2026-01.parquet'
--           'data/raw/green/2026/green_tripdata_2026-01.parquet'
-- Decision: Se constata la presencia de métodos de pago (payment_type = 1: tarjeta,
--           2: efectivo), tarifas fijas y desglose de recargos (surcharges).
-- ------------------------------------------------------------------------------

-- Muestra Yellow Taxi:
SELECT 
    VendorID,
    tpep_pickup_datetime,
    tpep_dropoff_datetime,
    passenger_count,
    trip_distance,
    fare_amount,
    tip_amount,
    total_amount,
    payment_type
FROM read_parquet('data/raw/yellow/2026/yellow_tripdata_2026-01.parquet')
LIMIT 10;

-- Muestra Green Taxi:
SELECT 
    VendorID,
    lpep_pickup_datetime,
    lpep_dropoff_datetime,
    passenger_count,
    trip_distance,
    fare_amount,
    tip_amount,
    total_amount,
    payment_type,
    trip_type
FROM read_parquet('data/raw/green/2026/green_tripdata_2026-01.parquet')
LIMIT 10;


-- ------------------------------------------------------------------------------
-- Consulta 4: Detección de problemas de calidad en Yellow Taxi
-- ------------------------------------------------------------------------------
-- Objetivo: Cuantificar anomalías: valores nulos, tarifas negativas, distancias
--           cero o extremas, viajes con duración negativa o fechas fuera de 2026.
-- Fuentes:  'data/raw/yellow/2026/*.parquet'
-- Decision: Reglas de limpieza a aplicar en etapas posteriores:
--           1. Filtrar viajes con fechas fuera de 2026 (17 registros anomalos).
--           2. Filtrar viajes con duracion negativa (10 registros).
--           3. Tratar con cautela o filtrar tarifas negativas (157,364 disputas/reembolsos).
--           4. Imputar o filtrar nulos en passenger_count (7,716,688 registros nulos ~26%).
--           5. Excluir o segmentar distancias anomalas (maximo registrado: 328,522.2 millas).
-- ------------------------------------------------------------------------------

SELECT 
    count(*) AS total_filas,
    count(*) FILTER (WHERE passenger_count IS NULL) AS nulos_passenger_count,
    count(*) FILTER (WHERE passenger_count = 0) AS ceros_passenger_count,
    count(*) FILTER (WHERE trip_distance <= 0) AS distancia_no_positiva,
    count(*) FILTER (WHERE trip_distance > 100) AS distancia_extrema_mas_100mi,
    count(*) FILTER (WHERE fare_amount < 0) AS tarifa_negativa,
    count(*) FILTER (WHERE total_amount < 0) AS total_negativo,
    count(*) FILTER (WHERE tpep_dropoff_datetime < tpep_pickup_datetime) AS duracion_negativa,
    count(*) FILTER (WHERE tpep_pickup_datetime < '2026-01-01' OR tpep_pickup_datetime >= '2027-01-01') AS fechas_fuera_de_2026,
    min(trip_distance) AS min_distancia,
    max(trip_distance) AS max_distancia,
    min(fare_amount) AS min_tarifa,
    max(fare_amount) AS max_tarifa,
    min(total_amount) AS min_total,
    max(total_amount) AS max_total
FROM read_parquet('data/raw/yellow/2026/*.parquet');


-- ------------------------------------------------------------------------------
-- Consulta 5: Detección de problemas de calidad en Green Taxi
-- ------------------------------------------------------------------------------
-- Objetivo: Cuantificar anomalías análogas en el conjunto de Green Taxi.
-- Fuentes:  'data/raw/green/2026/*.parquet'
-- Decision: Se observan patrones de calidad similares a Yellow Taxi:
--           - 48,775 registros (14.5%) con passenger_count nulo.
--           - 999 viajes con tarifas negativas.
--           - 12,212 viajes con distancia <= 0.
--           - Distancias irreales de hasta 179,830.92 millas.
--           - 14 registros con fechas fuera del año 2026.
-- ------------------------------------------------------------------------------

SELECT 
    count(*) AS total_filas,
    count(*) FILTER (WHERE passenger_count IS NULL) AS nulos_passenger_count,
    count(*) FILTER (WHERE passenger_count = 0) AS ceros_passenger_count,
    count(*) FILTER (WHERE trip_distance <= 0) AS distancia_no_positiva,
    count(*) FILTER (WHERE trip_distance > 100) AS distancia_extrema_mas_100mi,
    count(*) FILTER (WHERE fare_amount < 0) AS tarifa_negativa,
    count(*) FILTER (WHERE total_amount < 0) AS total_negativo,
    count(*) FILTER (WHERE lpep_dropoff_datetime < lpep_pickup_datetime) AS duracion_negativa,
    count(*) FILTER (WHERE lpep_pickup_datetime < '2026-01-01' OR lpep_pickup_datetime >= '2027-01-01') AS fechas_fuera_de_2026,
    min(trip_distance) AS min_distancia,
    max(trip_distance) AS max_distancia,
    min(fare_amount) AS min_tarifa,
    max(fare_amount) AS max_tarifa,
    min(total_amount) AS min_total,
    max(total_amount) AS max_total
FROM read_parquet('data/raw/green/2026/*.parquet');
