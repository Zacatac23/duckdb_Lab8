-- ==============================================================================
-- CC3084 - Lab 8: DuckDB
-- Ejercicio 4: Analisis exploratorio utilizando DuckDB
-- ==============================================================================
--
-- Requiere las vistas de sql/00_vistas.sql (viajes, viajes_limpios, zonas,
-- tipos_pago). Las consultas no mencionan rutas ni anios: trabajan sobre todos
-- los archivos Parquet descargados. Los resultados documentados en
-- docs/ejercicio4_analisis_exploratorio.md corresponden a 2026 (enero-agosto),
-- que eran los unicos datos disponibles al momento de este ejercicio.
--
-- Cada consulta esta marcada con `-- name: <id>`; el notebook
-- notebooks/02_analisis_exploratorio.ipynb las ejecuta por nombre desde este
-- mismo archivo (scripts/lab_db.py:cargar_consultas).
--
-- Preguntas de analisis (justificacion en la documentacion):
--   P1  Comportamiento temporal: como evoluciona el volumen mensual de viajes?
--   P2  Comportamiento temporal: en que horas y dias se concentra la demanda?
--   P3  Caracteristicas: como son los viajes tipicos (distancia, duracion,
--       pasajeros, velocidad) de cada tipo de taxi?
--   P4  Caracteristicas: como cambia la velocidad a lo largo del dia?
--   P5  Yellow vs green: donde se originan los viajes de cada servicio?
--   P6  Yellow vs green: que peso tienen los viajes a/desde aeropuertos?
--   P7  Pago: que metodos de pago se usan y como cambia la mezcla?
--   P8  Pago: como se comportan las propinas?
--   P9  Pago: como se compone el monto total y es consistente con sus partes?
--   P10 Distribucion: como se distribuye el monto total y cuantos atipicos hay?
--   P11 Calidad: cuantos registros elimina cada regla de limpieza?
--   P12 Calidad: los nulos de passenger_count son aleatorios o sistematicos?
-- ==============================================================================


-- ------------------------------------------------------------------------------
-- P1. Volumen mensual de viajes por tipo de taxi
-- Fuente: viajes_limpios (todos los Parquet de data/raw/{yellow,green}/*/)
-- Se reporta tambien el promedio diario para no penalizar meses mas cortos.
-- ------------------------------------------------------------------------------
-- name: p1_viajes_por_mes
SELECT
    tipo_taxi,
    anio,
    mes,
    count(*)                                                    AS viajes,
    round(count(*) / count(DISTINCT CAST(pickup_datetime AS DATE)), 0) AS viajes_por_dia
FROM viajes_limpios
GROUP BY ALL
ORDER BY tipo_taxi, anio, mes;


-- ------------------------------------------------------------------------------
-- P2. Distribucion de viajes por dia de la semana y hora (porcentaje del total
-- de cada tipo, para poder comparar yellow y green en la misma escala).
-- ------------------------------------------------------------------------------
-- name: p2_hora_dia_semana
SELECT
    tipo_taxi,
    dia_semana,
    hora,
    count(*)                                                        AS viajes,
    100.0 * count(*) / sum(count(*)) OVER (PARTITION BY tipo_taxi)  AS pct_viajes
FROM viajes_limpios
GROUP BY tipo_taxi, dia_semana, hora
ORDER BY tipo_taxi, dia_semana, hora;


-- ------------------------------------------------------------------------------
-- P3. Perfil del viaje tipico. Se usan medianas y percentiles porque las
-- distribuciones tienen colas largas (ver P10).
-- ------------------------------------------------------------------------------
-- name: p3_caracteristicas_viaje
SELECT
    tipo_taxi,
    count(*)                                            AS viajes,
    round(median(trip_distance), 2)                     AS mediana_distancia_mi,
    round(quantile_cont(trip_distance, 0.9), 2)         AS p90_distancia_mi,
    round(median(duracion_min), 1)                      AS mediana_duracion_min,
    round(quantile_cont(duracion_min, 0.9), 1)          AS p90_duracion_min,
    round(median(velocidad_mph), 1)                     AS mediana_velocidad_mph,
    round(avg(passenger_count), 2)                      AS prom_pasajeros,
    round(100.0 * avg(CASE WHEN passenger_count = 1 THEN 1 ELSE 0 END)
          FILTER (WHERE passenger_count IS NOT NULL), 1) AS pct_un_pasajero,
    round(median(fare_amount), 2)                       AS mediana_tarifa,
    round(median(total_amount), 2)                      AS mediana_total
FROM viajes_limpios
GROUP BY ALL
ORDER BY tipo_taxi DESC;


-- ------------------------------------------------------------------------------
-- P4. Velocidad, duracion y distancia medianas por hora del dia.
-- La velocidad es un indicador indirecto de congestion vial.
-- ------------------------------------------------------------------------------
-- name: p4_velocidad_por_hora
SELECT
    tipo_taxi,
    hora,
    count(*)                            AS viajes,
    round(median(velocidad_mph), 2)     AS mediana_velocidad_mph,
    round(median(duracion_min), 2)      AS mediana_duracion_min,
    round(median(trip_distance), 2)     AS mediana_distancia_mi
FROM viajes_limpios
WHERE velocidad_mph IS NOT NULL
GROUP BY ALL
ORDER BY tipo_taxi, hora;


-- ------------------------------------------------------------------------------
-- P5a. Distribucion de origenes por borough.
-- ------------------------------------------------------------------------------
-- name: p5a_borough_origen
SELECT
    v.tipo_taxi,
    coalesce(z.borough, 'Sin zona')                                     AS borough,
    count(*)                                                            AS viajes,
    round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY v.tipo_taxi), 2) AS pct_viajes
FROM viajes_limpios v
LEFT JOIN zonas z ON v.pu_location_id = z.location_id
GROUP BY v.tipo_taxi, coalesce(z.borough, 'Sin zona')
ORDER BY v.tipo_taxi DESC, viajes DESC;


-- ------------------------------------------------------------------------------
-- P5b. Las 10 zonas de origen con mas viajes por tipo de taxi.
-- ------------------------------------------------------------------------------
-- name: p5b_top_zonas_origen
WITH por_zona AS (
    SELECT
        v.tipo_taxi,
        z.borough,
        z.zona,
        count(*) AS viajes
    FROM viajes_limpios v
    LEFT JOIN zonas z ON v.pu_location_id = z.location_id
    GROUP BY ALL
)
SELECT
    tipo_taxi,
    borough,
    zona,
    viajes,
    round(100.0 * viajes / sum(viajes) OVER (PARTITION BY tipo_taxi), 2) AS pct_viajes
FROM por_zona
QUALIFY row_number() OVER (PARTITION BY tipo_taxi ORDER BY viajes DESC) <= 10
ORDER BY tipo_taxi DESC, viajes DESC;


-- ------------------------------------------------------------------------------
-- P6. Viajes que inician o terminan en un aeropuerto (zonas con
-- service_zone = 'Airports' o EWR) y su ticket promedio.
-- ------------------------------------------------------------------------------
-- name: p6_aeropuertos
WITH aeropuertos AS (
    SELECT location_id FROM zonas WHERE service_zone IN ('Airports', 'EWR')
)
SELECT
    tipo_taxi,
    count(*)                                                                AS viajes,
    count(*) FILTER (WHERE pu_location_id IN (SELECT location_id FROM aeropuertos)
                        OR do_location_id IN (SELECT location_id FROM aeropuertos))  AS viajes_aeropuerto,
    round(100.0 * viajes_aeropuerto / viajes, 2)                            AS pct_aeropuerto,
    round(avg(total_amount) FILTER (WHERE pu_location_id IN (SELECT location_id FROM aeropuertos)
                                       OR do_location_id IN (SELECT location_id FROM aeropuertos)), 2) AS total_prom_aeropuerto,
    round(avg(total_amount) FILTER (WHERE pu_location_id NOT IN (SELECT location_id FROM aeropuertos)
                                      AND do_location_id NOT IN (SELECT location_id FROM aeropuertos)), 2) AS total_prom_resto
FROM viajes_limpios
GROUP BY ALL
ORDER BY tipo_taxi DESC;


-- ------------------------------------------------------------------------------
-- P7. Mezcla de metodos de pago por tipo de taxi y mes. Se usa `viajes` (sin
-- limpiar) porque las disputas y anulaciones son justamente parte del analisis.
-- ------------------------------------------------------------------------------
-- name: p7_metodo_pago
SELECT
    v.tipo_taxi,
    v.anio,
    v.mes,
    coalesce(tp.metodo_pago, 'NULL (no registrado)')                    AS metodo_pago,
    count(*)                                                            AS viajes,
    round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY v.tipo_taxi, v.anio, v.mes), 2) AS pct_viajes
FROM viajes v
LEFT JOIN tipos_pago tp USING (payment_type)
GROUP BY v.tipo_taxi, v.anio, v.mes, coalesce(tp.metodo_pago, 'NULL (no registrado)')
ORDER BY v.tipo_taxi DESC, v.anio, v.mes, viajes DESC;


-- ------------------------------------------------------------------------------
-- P8a. Propinas por metodo de pago. La TLC solo registra propinas pagadas con
-- tarjeta; la propina en efectivo no queda en los datos.
-- Porcentaje de propina = tip / (total - tip), es decir, sobre lo cobrado.
-- ------------------------------------------------------------------------------
-- name: p8a_propinas_por_metodo
SELECT
    v.tipo_taxi,
    tp.metodo_pago,
    count(*)                                                        AS viajes,
    round(100.0 * avg(CASE WHEN tip_amount > 0 THEN 1 ELSE 0 END), 2) AS pct_con_propina,
    round(avg(tip_amount), 2)                                       AS propina_prom,
    round(median(100.0 * tip_amount / nullif(total_amount - tip_amount, 0))
          FILTER (WHERE tip_amount > 0), 2)                         AS mediana_pct_propina_si_hay
FROM viajes_limpios v
JOIN tipos_pago tp USING (payment_type)
WHERE v.payment_type IN (1, 2)
GROUP BY ALL
ORDER BY v.tipo_taxi DESC, tp.metodo_pago DESC;


-- ------------------------------------------------------------------------------
-- P8b. Histograma del porcentaje de propina (pagos con tarjeta, total > $5),
-- redondeado al punto porcentual mas cercano, entre 0% y 40%. Permite ver si los
-- montos sugeridos de la pantalla del taxi concentran las propinas.
-- ------------------------------------------------------------------------------
-- name: p8b_histograma_pct_propina
SELECT
    tipo_taxi,
    CAST(round(100.0 * tip_amount / (total_amount - tip_amount)) AS INTEGER) AS pct_propina,
    count(*)                                                                 AS viajes,
    round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY tipo_taxi), 3) AS pct_viajes
FROM viajes_limpios
WHERE payment_type = 1
  AND total_amount - tip_amount > 5
  AND 100.0 * tip_amount / (total_amount - tip_amount) < 40.5
GROUP BY tipo_taxi, pct_propina
ORDER BY tipo_taxi, pct_propina;


-- ------------------------------------------------------------------------------
-- P9. Composicion promedio del monto total y consistencia aritmetica:
-- total_amount deberia ser la suma de sus componentes.
-- ------------------------------------------------------------------------------
-- name: p9_composicion_total
SELECT
    tipo_taxi,
    round(avg(fare_amount), 2)                      AS tarifa,
    round(avg(extra), 2)                            AS extra,
    round(avg(mta_tax), 2)                          AS mta_tax,
    round(avg(improvement_surcharge), 2)            AS improvement_surcharge,
    round(avg(coalesce(congestion_surcharge, 0)), 2) AS congestion_surcharge,
    round(avg(coalesce(cbd_congestion_fee, 0)), 2)  AS cbd_congestion_fee,
    round(avg(coalesce(airport_fee, 0)), 2)         AS airport_fee,
    round(avg(coalesce(ehail_fee, 0)), 2)           AS ehail_fee,
    round(avg(tolls_amount), 2)                     AS peajes,
    round(avg(tip_amount), 2)                       AS propina,
    round(avg(total_amount), 2)                     AS total,
    round(100.0 * avg(CASE WHEN coalesce(cbd_congestion_fee, 0) > 0 THEN 1 ELSE 0 END), 2) AS pct_con_cargo_cbd,
    count(*) FILTER (WHERE abs(total_amount - (
        fare_amount + extra + mta_tax + improvement_surcharge + tolls_amount + tip_amount
        + coalesce(congestion_surcharge, 0) + coalesce(cbd_congestion_fee, 0)
        + coalesce(airport_fee, 0) + coalesce(ehail_fee, 0))) > 0.01)                 AS viajes_total_inconsistente,
    round(100.0 * viajes_total_inconsistente / count(*), 3)                            AS pct_total_inconsistente
FROM viajes_limpios
GROUP BY ALL
ORDER BY tipo_taxi DESC;


-- ------------------------------------------------------------------------------
-- P9b. Inconsistencias del total por proveedor y la diferencia mas frecuente.
-- diferencia = total_amount - suma de componentes. Una diferencia negativa
-- indica que algun cargo se cuenta dos veces (p. ej. dentro de `extra` y en su
-- propia columna); una positiva, que falta un componente (columna NULL).
-- ------------------------------------------------------------------------------
-- name: p9b_inconsistencia_por_proveedor
WITH d AS (
    SELECT
        tipo_taxi,
        vendor_id,
        round(total_amount - (
            fare_amount + extra + mta_tax + improvement_surcharge + tolls_amount + tip_amount
            + coalesce(congestion_surcharge, 0) + coalesce(cbd_congestion_fee, 0)
            + coalesce(airport_fee, 0) + coalesce(ehail_fee, 0)), 2) AS diferencia
    FROM viajes_limpios
)
SELECT
    tipo_taxi,
    vendor_id,
    count(*)                                                AS viajes,
    count(*) FILTER (WHERE abs(diferencia) > 0.01)          AS inconsistentes,
    round(100.0 * inconsistentes / count(*), 1)             AS pct_inconsistentes,
    mode(diferencia) FILTER (WHERE abs(diferencia) > 0.01)  AS diferencia_mas_frecuente
FROM d
GROUP BY ALL
ORDER BY tipo_taxi DESC, vendor_id;


-- ------------------------------------------------------------------------------
-- P10a. Percentiles del monto total y atipicos segun la regla de Tukey
-- (por encima de Q3 + 1.5*IQR). Tambien se cuentan tarifas por milla
-- implausibles (> $50/mi en viajes de mas de 1 milla).
-- ------------------------------------------------------------------------------
-- name: p10a_distribucion_total
WITH stats AS (
    SELECT
        tipo_taxi,
        quantile_cont(total_amount, 0.25) AS q1,
        quantile_cont(total_amount, 0.50) AS q2,
        quantile_cont(total_amount, 0.75) AS q3,
        quantile_cont(total_amount, 0.99) AS p99,
        max(total_amount)                 AS maximo
    FROM viajes_limpios
    GROUP BY ALL
)
SELECT
    s.tipo_taxi,
    round(s.q1, 2)                                          AS q1,
    round(s.q2, 2)                                          AS mediana,
    round(s.q3, 2)                                          AS q3,
    round(s.q3 + 1.5 * (s.q3 - s.q1), 2)                    AS limite_tukey,
    round(s.p99, 2)                                         AS p99,
    round(s.maximo, 2)                                      AS maximo,
    count(*) FILTER (WHERE v.total_amount > s.q3 + 1.5 * (s.q3 - s.q1))     AS atipicos_tukey,
    round(100.0 * atipicos_tukey / count(*), 2)                             AS pct_atipicos_tukey,
    count(*) FILTER (WHERE v.trip_distance > 1 AND v.fare_amount / v.trip_distance > 50) AS tarifa_por_milla_extrema
FROM viajes_limpios v
JOIN stats s USING (tipo_taxi)
GROUP BY ALL
ORDER BY s.tipo_taxi DESC;


-- ------------------------------------------------------------------------------
-- P10b. Histograma del monto total en intervalos de $5 (hasta $150).
-- ------------------------------------------------------------------------------
-- name: p10b_histograma_total
SELECT
    tipo_taxi,
    CAST(floor(total_amount / 5) * 5 AS INTEGER)                            AS desde_usd,
    count(*)                                                                AS viajes,
    round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY tipo_taxi), 3) AS pct_viajes
FROM viajes_limpios
WHERE total_amount < 150
GROUP BY tipo_taxi, desde_usd
ORDER BY tipo_taxi, desde_usd;


-- ------------------------------------------------------------------------------
-- P11. Impacto de cada regla de limpieza de viajes_limpios sobre `viajes`.
-- Las reglas no son excluyentes: un registro puede fallar varias.
-- ------------------------------------------------------------------------------
-- name: p11_impacto_limpieza
SELECT
    tipo_taxi,
    count(*)                                                                    AS registros,
    count(*) FILTER (WHERE date_trunc('month', pickup_datetime) <> make_date(anio, mes, 1)) AS r1_fuera_de_periodo,
    count(*) FILTER (WHERE dropoff_datetime <= pickup_datetime
                        OR date_diff('second', pickup_datetime, dropoff_datetime) > 4 * 3600) AS r2_duracion_invalida,
    count(*) FILTER (WHERE trip_distance <= 0 OR trip_distance > 100)           AS r3_distancia_invalida,
    count(*) FILTER (WHERE fare_amount < 0 OR total_amount < 0)                 AS r4_monto_negativo,
    count(*) FILTER (WHERE NOT (
            date_trunc('month', pickup_datetime) = make_date(anio, mes, 1)
        AND dropoff_datetime > pickup_datetime
        AND date_diff('second', pickup_datetime, dropoff_datetime) <= 4 * 3600
        AND trip_distance > 0 AND trip_distance <= 100
        AND fare_amount >= 0 AND total_amount >= 0))                            AS excluidos_total,
    round(100.0 * excluidos_total / count(*), 2)                                AS pct_excluidos
FROM viajes
GROUP BY ALL
ORDER BY tipo_taxi DESC;


-- ------------------------------------------------------------------------------
-- P12. Relacion entre passenger_count nulo, payment_type y proveedor.
-- Si los nulos se concentran en ciertos proveedores / tipos de pago, el
-- faltante es sistematico (no aleatorio) y no conviene imputarlo a ciegas.
-- VendorID: 1 = Creative Mobile Technologies, 2 = Curb Mobility,
--           6 = Myle Technologies, 7 = Helix.
-- ------------------------------------------------------------------------------
-- name: p12_nulos_passenger_count
SELECT
    tipo_taxi,
    vendor_id,
    coalesce(CAST(payment_type AS VARCHAR), 'NULL')         AS payment_type,
    count(*)                                                AS viajes,
    count(*) FILTER (WHERE passenger_count IS NULL)         AS passenger_count_nulo,
    round(100.0 * passenger_count_nulo / count(*), 1)       AS pct_nulo,
    count(*) FILTER (WHERE ratecode_id IS NULL)             AS ratecode_nulo
FROM viajes
GROUP BY ALL
HAVING count(*) > 1000
ORDER BY tipo_taxi DESC, vendor_id, payment_type;
