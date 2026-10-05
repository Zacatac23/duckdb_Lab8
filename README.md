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
# Descarga automatica de taxis amarillos y verdes para 2026
docker exec -it lab8-lab python scripts/download_data.py

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

## Como reproducir los benchmarks

<!-- TODO (Ejercicio 6) -->

## Como generar los resultados principales

<!-- TODO -->
