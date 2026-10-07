# Resultados del benchmark (generado por scripts/benchmark.py)

DuckDB 1.5.5, Python 3.11.14, Linux aarch64, 8 CPUs. Mediana de 5 repeticiones despues de 1 ejecucion de calentamiento.

## Escenarios

| escenario | archivos | filas | Parquet (MiB) | .duckdb (MiB) | carga de la tabla (s) |
|---|---:|---:|---:|---:|---:|
| 1_mes | 2 | 3,765,161 | 62.1 | 101.5 | 0.9 |
| 3_meses | 6 | 11,199,059 | 184.8 | 307.5 | 2.6 |
| 2026 | 16 | 30,040,469 | 495.7 | 808.5 | 5.6 |
| 2024_2026 | 40 | 71,870,407 | 1,171.7 | 1,923.5 | 13.6 |

## Tiempos por consulta (segundos)

`aceleracion` = mediana Parquet / mediana tabla (> 1: la tabla es mas rapida).

| consulta | escenario | Parquet 1a | Parquet mediana | tabla 1a | tabla mediana | aceleracion |
|---|---|---:|---:|---:|---:|---:|
| b1_conteo_total | 1_mes | 0.0059 | 0.0039 | 0.0048 | 0.0026 | 1.5x |
| b1_conteo_total | 3_meses | 0.0098 | 0.0074 | 0.0109 | 0.0064 | 1.2x |
| b1_conteo_total | 2026 | 0.0166 | 0.0163 | 0.0345 | 0.0152 | 1.1x |
| b1_conteo_total | 2024_2026 | 0.0430 | 0.0371 | 0.0785 | 0.0391 | 0.9x |
| b2_filtro_selectivo | 1_mes | 0.0441 | 0.0347 | 0.0022 | 0.0006 | 56.9x |
| b2_filtro_selectivo | 3_meses | 0.0304 | 0.0292 | 0.0034 | 0.0007 | 41.7x |
| b2_filtro_selectivo | 2026 | 0.0791 | 0.0478 | 0.0192 | 0.0011 | 43.8x |
| b2_filtro_selectivo | 2024_2026 | 0.2609 | 0.1353 | 0.0565 | 0.0015 | 87.3x |
| b3_agregacion_simple | 1_mes | 0.0299 | 0.0229 | 0.0191 | 0.0143 | 1.6x |
| b3_agregacion_simple | 3_meses | 0.0384 | 0.0299 | 0.0638 | 0.0363 | 0.8x |
| b3_agregacion_simple | 2026 | 0.1008 | 0.0753 | 0.2152 | 0.0710 | 1.1x |
| b3_agregacion_simple | 2024_2026 | 0.3168 | 0.1792 | 0.8745 | 0.1755 | 1.0x |
| p1_viajes_por_mes | 1_mes | 0.1525 | 0.1474 | 0.0655 | 0.0538 | 2.7x |
| p1_viajes_por_mes | 3_meses | 0.2254 | 0.2213 | 0.1869 | 0.1457 | 1.5x |
| p1_viajes_por_mes | 2026 | 0.5764 | 0.5358 | 0.6223 | 0.3601 | 1.5x |
| p1_viajes_por_mes | 2024_2026 | 1.3722 | 1.3229 | 5.0572 | 0.8345 | 1.6x |
| p2_hora_dia_semana | 1_mes | 0.1338 | 0.1344 | 0.0856 | 0.0849 | 1.6x |
| p2_hora_dia_semana | 3_meses | 0.2363 | 0.2420 | 0.2516 | 0.2494 | 1.0x |
| p2_hora_dia_semana | 2026 | 0.5707 | 0.5483 | 0.6491 | 0.6416 | 0.9x |
| p2_hora_dia_semana | 2024_2026 | 1.3761 | 1.3370 | 1.6221 | 1.7322 | 0.8x |
| p3_caracteristicas_viaje | 1_mes | 0.6926 | 0.5940 | 0.4874 | 0.5107 | 1.2x |
| p3_caracteristicas_viaje | 3_meses | 1.7649 | 1.6200 | 1.5921 | 1.5674 | 1.0x |
| p3_caracteristicas_viaje | 2026 | 4.6742 | 4.4670 | 4.5689 | 4.2341 | 1.1x |
| p3_caracteristicas_viaje | 2024_2026 | 10.1710 | 11.2310 | 15.1181 | 9.8416 | 1.1x |
| p5b_top_zonas_origen | 1_mes | 0.1801 | 0.1640 | 0.0671 | 0.0636 | 2.6x |
| p5b_top_zonas_origen | 3_meses | 0.3007 | 0.2925 | 0.2048 | 0.1682 | 1.7x |
| p5b_top_zonas_origen | 2026 | 0.6999 | 0.6782 | 0.5710 | 0.4399 | 1.5x |
| p5b_top_zonas_origen | 2024_2026 | 1.7447 | 1.6569 | 1.3097 | 1.1537 | 1.4x |
| p8a_propinas_por_metodo | 1_mes | 0.1835 | 0.1880 | 0.0878 | 0.0839 | 2.2x |
| p8a_propinas_por_metodo | 3_meses | 0.3615 | 0.3508 | 0.2417 | 0.2380 | 1.5x |
| p8a_propinas_por_metodo | 2026 | 0.9052 | 0.8075 | 0.6241 | 0.5601 | 1.4x |
| p8a_propinas_por_metodo | 2024_2026 | 2.4826 | 2.3731 | 1.9748 | 1.6141 | 1.5x |
| p9_composicion_total | 1_mes | 0.1830 | 0.1787 | 0.0801 | 0.0711 | 2.5x |
| p9_composicion_total | 3_meses | 0.3878 | 0.3907 | 0.2977 | 0.2088 | 1.9x |
| p9_composicion_total | 2026 | 0.9987 | 0.9631 | 0.7591 | 0.5731 | 1.7x |
| p9_composicion_total | 2024_2026 | 2.6665 | 2.3275 | 2.1362 | 1.4345 | 1.6x |

## Suma de medianas de todas las consultas por escenario

| escenario | Parquet (s) | tabla (s) | aceleracion |
|---|---:|---:|---:|
| 1_mes | 1.47 | 0.89 | 1.7x |
| 3_meses | 3.18 | 2.62 | 1.2x |
| 2026 | 8.14 | 6.90 | 1.2x |
| 2024_2026 | 20.60 | 16.83 | 1.2x |
