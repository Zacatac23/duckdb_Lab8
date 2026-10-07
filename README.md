# Lab 8 - DuckDB

Repositorio base del laboratorio 8 del curso **CC3084 - Data Science**
(Universidad del Valle de Guatemala, Ciclo 2, 2026).

Este es el repositorio **proporcionado por el docente**. Contiene la estructura
del proyecto, el ambiente de ejecucion basado en Docker y un script que descarga
los datos de **2026**. Todo lo demas debe ser construido por cada equipo.

## Trabajo con fork

El laboratorio se desarrolla y se entrega sobre un **fork** de este repositorio.
No se trabaja directamente sobre el repositorio del docente.

1. Realice un fork de este repositorio:
   <https://github.com/menene/duckdb>

2. Clone **su propio fork** (no el del docente):

   ```bash
   git clone https://github.com/<su-usuario>/duckdb.git
   cd duckdb
   ```

3. Opcional, para recibir correcciones publicadas por el docente:

   ```bash
   git remote add upstream https://github.com/menene/duckdb.git
   git fetch upstream
   ```

Realice commits frecuentes y descriptivos: el historial del repositorio es parte
de la evaluacion. **La entrega del laboratorio es la URL de su fork.**

## Estructura

```text
duckdb/
|
+-- data/
|   +-- raw/
|   +-- processed/
|
+-- notebooks/
|
+-- scripts/
|
+-- sql/
|
+-- docs/
|
+-- Dockerfile
+-- metabase.Dockerfile
+-- docker-compose.yml
+-- README.md
```

## Requisitos

- Docker, con Docker Compose
- Git

La primera construccion del ambiente descarga varios cientos de MB y puede
tardar algunos minutos.

Considere el espacio en disco: las imagenes de Docker ocupan unos 3 GB y los
datos de los tres anios del laboratorio superan 1.5 GB, a los que se suma la
base materializada del Ejercicio 6. Se recomienda tener al menos 10 GB libres.

## Datos

El repositorio incluye `scripts/download_data.py`, que descarga los archivos de
2026 publicados por la TLC (`--help` muestra las opciones disponibles). Los
archivos se guardan en `data/raw/<tipo>/<anio>/`.

La TLC publica cada mes con varias semanas de atraso, por lo que los ultimos
meses de 2026 todavia no existen. El script consulta al servidor que meses estan
publicados, de modo que vuelve a ejecutarse sin problema conforme aparezcan
nuevos archivos.

Los datos descargados **no deben incluirse en el repositorio Git**. El archivo
`.gitignore` ya esta configurado para evitarlo.

Fuente de datos: NYC TLC Trip Record Data
<https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page>

Dentro de los contenedores, la carpeta `data/` del proyecto esta montada en
`/workspace/data`. Esa es la ruta que deben usar las herramientas que corren
dentro del ambiente, no la ruta de su computadora.

> **Nota sobre DuckDB:** un archivo `.duckdb` admite un solo proceso con permiso
> de escritura a la vez. Si conecta una herramienta externa a su base de datos,
> use el modo de solo lectura (`read_only`) en esa conexion; de lo contrario los
> demas procesos no podran abrir el archivo.

## Material a entregar

Al finalizar, su fork debe contener:

- el codigo fuente modificado y los scripts de descarga;
- las consultas SQL desarrolladas;
- el notebook o notebooks utilizados;
- la documentacion de las consultas;
- los scripts utilizados para los benchmarks;
- el codigo de los indicadores y visualizaciones;
- el tablero o la evidencia del tablero desarrollado;
- este `README.md`, completado segun la siguiente seccion.

Los archivos de datos descargados **no** deben incluirse.

---

# Documentacion del equipo

Las siguientes secciones deben ser completadas por cada equipo. El README final
debe permitir que una persona que no participo en el desarrollo pueda levantar el
ambiente, descargar los datos, ejecutar el analisis, reproducir los benchmarks y
generar los resultados principales.

## Como levantar el ambiente

Para inicializar los contenedores del laboratorio (JupyterLab y Metabase) usando Docker Compose:

```bash
docker compose up -d --build
```

Una vez levantados los servicios, se puede acceder a:
- **JupyterLab**: [http://localhost:8888](http://localhost:8888)
- **Metabase**: [http://localhost:3000](http://localhost:3000)

Para verificar el estado de los contenedores:
```bash
docker compose ps
```

Para detener los servicios:
```bash
docker compose down
```

## Como descargar los datos

El script `scripts/download_data.py` se encarga de descargar automáticamente los archivos Parquet del NYC TLC Trip Record Data para taxis amarillos (`yellow`) y verdes (`green`).

### Ejecución dentro del contenedor

La forma recomendada es ejecutar el script dentro del contenedor de análisis (`lab8-lab`):

```bash
# Descarga automatica de taxis amarillos y verdes de los anios del laboratorio
# (ANIOS_DEFAULT en el script: 2024 y 2026) + catalogo de zonas
docker exec -it lab8-lab python scripts/download_data.py

# Descargar varios anios explicitamente
docker exec -it lab8-lab python scripts/download_data.py --year 2024 2026

# Descargar solo taxis amarillos
docker exec -it lab8-lab python scripts/download_data.py --taxi yellow

# Descargar solo taxis verdes
docker exec -it lab8-lab python scripts/download_data.py --taxi green

# Descargar un anio especifico (p. ej. 2026, 2025 o 2024)
docker exec -it lab8-lab python scripts/download_data.py --year 2026

# Descargar meses especificos (p. ej. enero a marzo)
docker exec -it lab8-lab python scripts/download_data.py --months 1 2 3
```

### Características del sistema de descarga:
1. **Idempotencia y validación**: Verifica si los archivos ya existen localmente y valida su integridad mediante `pyarrow.parquet`. Si el archivo ya existe y es válido, se omite. Si está corrupto, se descarga nuevamente.
2. **Descarga atómica**: Los archivos se descargan primero con extensión temporal `.part` y se renombran únicamente cuando la transferencia y la validación son exitosas, evitando archivos corruptos por interrupciones.
3. **Detección dinámica de publicación**: Consulta el servidor mediante peticiones HTTP `HEAD` para determinar si el mes ya fue publicado por la TLC (código 200) o si aún no está disponible (código 403/404), evitando descargar archivos inexistentes.
4. **Estructura organizada**: Almacena los archivos en la jerarquía estándar: `data/raw/<tipo>/<anio>/<tipo>_tripdata_<anio>-<mes>.parquet`.
5. **Varios años (Ejercicio 5)**: `--year` acepta uno o varios años; por defecto descarga `ANIOS_DEFAULT = (2024, 2026)`. Para agregar un año nuevo basta con añadirlo a esa constante.
6. **Catálogo de zonas**: descarga `data/raw/taxi_zone_lookup.csv` (LocationID → borough/zona), usado por las vistas de análisis.

Detalle de la incorporación de 2024 y su validación: `docs/ejercicio5_incorporacion_2024.md`.

## Como ejecutar el analisis

### Consultas directas sobre Parquet (Ejercicio 3)

DuckDB permite ejecutar consultas analíticas de alto rendimiento directamente sobre los archivos Parquet sin requerir una importación previa a tablas (`read_parquet`).

Las consultas de exploración inicial se encuentran documentadas y estructuradas en el archivo:
- `sql/01_exploracion_parquet.sql`

#### Opciones para ejecutar el análisis:

1. **Desde la terminal con Python y DuckDB (dentro del contenedor):**
   ```bash
   docker exec -it lab8-lab python -c "
   import duckdb
   con = duckdb.connect()
   with open('sql/01_exploracion_parquet.sql') as f:
       queries = [q.strip() for q in f.read().split(';') if q.strip()]
   for i, q in enumerate(queries, 1):
       print(f'=== Ejecutando consulta {i} ===')
       print(con.execute(q).df().head())
   "
   ```

2. **Desde JupyterLab:**
   - Ingrese a [http://localhost:8888](http://localhost:8888).
   - Abra un nuevo notebook con kernel Python 3.
   - Conecte DuckDB y consulte los archivos directamente:
     ```python
     import duckdb
     con = duckdb.connect()
     # Consultar directamente los datos de 2026
     df = con.execute("SELECT * FROM read_parquet('data/raw/yellow/2026/*.parquet') LIMIT 10").df()
     display(df)
     ```

### Resumen de los datos explorados (2026):
- **Archivos disponibles**: 16 archivos Parquet (8 meses publicados, de enero a agosto de 2026).
- **Volumen total**: 30,040,469 registros (29,703,355 en Yellow Taxi y 337,114 en Green Taxi).
- **Esquema**:
  - Yellow: 20 columnas (`tpep_pickup_datetime`, `tpep_dropoff_datetime`, `Airport_fee`, etc.).
  - Green: 21 columnas (`lpep_pickup_datetime`, `lpep_dropoff_datetime`, `ehail_fee`, `trip_type`, etc.).
- **Hallazgos de calidad de datos**:
  - Valores nulos en `passenger_count`: ~26% en Yellow y ~14.5% en Green.
  - Tarifas negativas: 157,364 en Yellow y 999 en Green (disputas/reversiones contables).
  - Distancias no positivas (`trip_distance <= 0`): 952,231 en Yellow y 12,212 en Green.
  - Valores atípicos extremos: distancias registradas de más de 100,000 millas y marcas de tiempo fuera del año 2026 (errores de sincronización del hardware del taxímetro).

### Vistas base y organización del análisis (Ejercicios 4 en adelante)

Todas las consultas de análisis se escriben contra vistas, no contra rutas de archivos:

| Archivo | Contenido |
|---|---|
| `sql/00_vistas.sql` | `yellow_raw`, `green_raw` (Parquet de todos los años, `union_by_name`), `viajes` (yellow + green con nombres de columna unificados, `anio`/`mes` tomados del nombre del archivo), `viajes_limpios` (reglas de limpieza R1–R4 + columnas derivadas), `zonas`, `tipos_pago` |
| `sql/02_analisis_exploratorio.sql` | Ejercicio 4: 12 preguntas (P1–P12), una consulta por bloque `-- name:` |
| `sql/03_incorporacion_2024.sql` | Ejercicio 5: validación de la incorporación de 2024 (V1–V6) |
| `sql/04_benchmark.sql` | Ejercicio 6: consultas adicionales del benchmark |
| `scripts/lab_db.py` | `conectar()` crea las vistas; `cargar_consultas()` lee un `.sql` y devuelve sus consultas por nombre |

Los notebooks ejecutan las consultas **por nombre** desde los `.sql`, así que el SQL documentado y el ejecutado
son el mismo texto. Para usarlas desde Python:

```python
import sys; sys.path.insert(0, "scripts")
from lab_db import conectar, cargar_consultas
con = conectar()                                   # DuckDB en memoria + vistas sobre los Parquet
q = cargar_consultas("02_analisis_exploratorio.sql")
con.sql(q["p1_viajes_por_mes"]).df()
```

### Notebooks

Abrir JupyterLab en <http://localhost:8888> y ejecutar (*Run All*), en orden:

| Notebook | Ejercicio | Documentación |
|---|---|---|
| `notebooks/02_analisis_exploratorio.ipynb` | 4 — análisis exploratorio (genera `docs/img/ej4_*.png`) | `docs/ejercicio4_analisis_exploratorio.md` |
| `notebooks/03_incorporacion_2024.ipynb` | 5 — validación de 2024 y consulta conjunta | `docs/ejercicio5_incorporacion_2024.md` |

También se pueden ejecutar sin abrir JupyterLab:

```bash
docker exec -it lab8-lab jupyter nbconvert --to notebook --execute --inplace notebooks/02_analisis_exploratorio.ipynb
```

## Como reproducir los benchmarks

Ejercicio 6, Parquet directo vs tabla materializada. Detalle y análisis en `docs/ejercicio6_benchmark.md`.

```bash
# 6.2 Materializar todos los anios descargados en data/processed/taxis.duckdb (~1.9 GB, ~10 s)
docker exec -it lab8-lab python scripts/build_duckdb.py

# 6.4-6.7 Benchmark completo: 4 escenarios (1 mes, 3 meses, 2026, 2024+2026) x 9 consultas
#         x 2 estrategias, 1 calentamiento + 5 repeticiones (~10 min en Docker)
docker exec -it lab8-lab python scripts/benchmark.py

# Version corta
docker exec -it lab8-lab python scripts/benchmark.py --repeticiones 3 --escenarios 1_mes 2026
```

* En `taxis.duckdb`, `viajes` y `zonas` son **tablas** con los mismos nombres y columnas que las vistas de
  `sql/00_vistas.sql`. Por eso las consultas de `sql/` funcionan igual sobre los Parquet y sobre la base.
* El benchmark escribe `docs/benchmark/resultados_benchmark.csv` (cada ejecución), `docs/benchmark/escenarios.csv`,
  `docs/benchmark/resumen_benchmark.md` y `docs/img/ej6_benchmark.png`.
* Necesita ~2 GB libres en `data/processed/` para la base temporal del escenario más grande, que se borra al
  terminar.

> **Aviso (macOS):** no clone el repositorio dentro de una carpeta sincronizada con iCloud (p. ej. `~/Documents`
> con "Escritorio y Documentos" activado). macOS puede desalojar los Parquet a la nube y DuckDB falla al leerlos
> (`IO Error: Operation timed out`).

## Como generar los resultados principales

<!-- TODO (Ejercicios 7 y 8): completar con el tablero y el analisis de los tres anios. -->

Estado actual:

| Ejercicio | Resultado | Cómo generarlo |
|---|---|---|
| 3 | Exploración inicial de 2026 | `sql/01_exploracion_parquet.sql` |
| 4 | Análisis exploratorio, 12 preguntas, hallazgos | `notebooks/02_analisis_exploratorio.ipynb` → `docs/ejercicio4_analisis_exploratorio.md` |
| 5 | Incorporación y validación de 2024 | `scripts/download_data.py` + `notebooks/03_incorporacion_2024.ipynb` → `docs/ejercicio5_incorporacion_2024.md` |
| 6 | Benchmark Parquet vs tabla | `scripts/build_duckdb.py` + `scripts/benchmark.py` → `docs/ejercicio6_benchmark.md` |
| 7 | Indicadores y tablero (Metabase) | *pendiente* |
| 8 | Incorporación de 2025 y análisis de tres años | *pendiente* |
| 9 | Discusión | *pendiente* |
