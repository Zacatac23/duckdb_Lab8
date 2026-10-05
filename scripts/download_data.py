#!/usr/bin/env python3
"""Descarga los archivos Parquet del NYC TLC Trip Record Data.

Descarga los registros de viajes de taxis amarillos (yellow) y verdes (green)
correspondientes al anio 2026 (y configurable para otros anios requeridos por
el laboratorio).

Fuente oficial de los datos:
    https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page

Uso:
    python scripts/download_data.py                     # amarillos y verdes, 2026
    python scripts/download_data.py --taxi yellow       # solo amarillos, 2026
    python scripts/download_data.py --taxi green        # solo verdes, 2026
    python scripts/download_data.py --year 2026         # anio especifico
    python scripts/download_data.py --months 1 2 3      # meses especificos

Los archivos se guardan en:
    data/raw/<tipo>/<anio>/<nombre-original>.parquet

Comportamiento:
  - La TLC publica cada mes con varias semanas de atraso, por lo que no todos
    los meses del anio actual existen todavia. El script consulta al servidor
    que meses estan publicados en lugar de suponerlos mediante peticiones HEAD.
  - Un archivo que ya existe localmente y es valido no se vuelve a descargar.
  - La descarga se realiza sobre un archivo temporal (.part) y se renombra solo
    al finalizar satisfactoriamente la transferencia y validacion.
  - Opcionalmente verifica la integridad de los archivos Parquet (pyarrow).
"""

import argparse
import sys
import time
from pathlib import Path

import requests

ANIO_DEFAULT = 2026
TIPOS_TAXI = ("yellow", "green")
URL_BASE = "https://d37ci6vzurychx.cloudfront.net/trip-data"
DIR_DESTINO = Path("data/raw")

TIEMPO_ESPERA = 60          # segundos por peticion
INTENTOS = 3                # intentos por archivo antes de darse por vencido
BLOQUE = 1024 * 1024        # 1 MiB por bloque de descarga
SUFIJO_TEMPORAL = ".part"


def construir_nombre(tipo: str, anio: int, mes: int) -> str:
    """Nombre del archivo publicado por la TLC, p. ej. yellow_tripdata_2026-01.parquet."""
    return f"{tipo}_tripdata_{anio}-{mes:02d}.parquet"


def construir_url(tipo: str, anio: int, mes: int) -> str:
    """URL completa del archivo Parquet mensual."""
    return f"{URL_BASE}/{construir_nombre(tipo, anio, mes)}"


def ruta_destino(tipo: str, anio: int, mes: int, dir_destino: Path = DIR_DESTINO) -> Path:
    """Ruta local donde se guarda el archivo: data/raw/<tipo>/<anio>/<archivo>."""
    return dir_destino / tipo / str(anio) / construir_nombre(tipo, anio, mes)


def esta_publicado(url: str) -> bool:
    """Indica si el archivo existe en el servidor mediante peticion HTTP HEAD."""
    try:
        respuesta = requests.head(url, timeout=TIEMPO_ESPERA, allow_redirects=True)
    except requests.RequestException:
        return False
    return respuesta.ok


def formato_tamanio(n: float) -> str:
    """Formatea bytes a representacion legible (B, KiB, MiB, GiB)."""
    for unidad in ("B", "KiB", "MiB", "GiB"):
        if n < 1024 or unidad == "GiB":
            return f"{n:.1f} {unidad}"
        n /= 1024
    return f"{n:.1f} GiB"


def es_parquet_valido(ruta: Path) -> bool:
    """Verifica si el archivo Parquet existe, tiene contenido y es legible."""
    if not ruta.exists() or ruta.stat().st_size == 0:
        return False
    try:
        import pyarrow.parquet as pq
        parquet_file = pq.ParquetFile(ruta)
        return parquet_file.metadata.num_rows >= 0
    except Exception:
        # Si pyarrow no puede parsear los metadatos, el archivo esta corrupto
        return False


def descargar_archivo(url: str, destino: Path) -> int:
    """Descarga `url` en `destino` de forma atomica. Devuelve bytes escritos."""
    destino.parent.mkdir(parents=True, exist_ok=True)
    temporal = destino.with_name(destino.name + SUFIJO_TEMPORAL)

    ultimo_error = None
    for intento in range(1, INTENTOS + 1):
        try:
            with requests.get(url, stream=True, timeout=TIEMPO_ESPERA) as respuesta:
                respuesta.raise_for_status()
                escritos = 0
                with temporal.open("wb") as archivo:
                    for bloque in respuesta.iter_content(chunk_size=BLOQUE):
                        if bloque:
                            archivo.write(bloque)
                            escritos += len(bloque)

            if escritos == 0:
                raise requests.RequestException("el servidor devolvio un archivo vacio")

            # Validar integridad antes de mover
            if not es_parquet_valido(temporal):
                raise requests.RequestException("el archivo Parquet descargado esta corrupto o incompleto")

            temporal.replace(destino)
            return escritos
        except requests.RequestException as error:
            ultimo_error = error
            temporal.unlink(missing_ok=True)
            if intento < INTENTOS:
                print(f"      intento {intento}/{INTENTOS} fallido ({error}); reintentando...")
                time.sleep(2)

    raise requests.RequestException(f"no se pudo descargar {url}: {ultimo_error}")


def descargar(tipo: str, anio: int, meses: list[int], dir_destino: Path) -> dict:
    """Descarga todos los meses especificados de un tipo de taxi para el anio dado."""
    print(f"\n=== {tipo.upper()} {anio} ===")
    resumen = {"descargados": 0, "omitidos": 0, "no_publicados": [], "fallidos": [], "bytes": 0}

    for mes in meses:
        etiqueta = f"{anio}-{mes:02d}"
        destino = ruta_destino(tipo, anio, mes, dir_destino)

        # Verificar si ya existe y es valido
        if destino.exists() and destino.stat().st_size > 0:
            if es_parquet_valido(destino):
                print(f"  {etiqueta}  ya existe localmente y es valido, se omite")
                resumen["omitidos"] += 1
                continue
            else:
                print(f"  {etiqueta}  archivo local corrupto, se volvera a descargar")

        url = construir_url(tipo, anio, mes)
        if not esta_publicado(url):
            print(f"  {etiqueta}  aun no publicado por la TLC (HTTP 404/403)")
            resumen["no_publicados"].append(etiqueta)
            continue

        print(f"  {etiqueta}  descargando...", end="", flush=True)
        inicio = time.time()
        try:
            escritos = descargar_archivo(url, destino)
            duracion = time.time() - inicio
        except requests.RequestException as error:
            print(f"\n  {etiqueta}  ERROR: {error}")
            resumen["fallidos"].append(etiqueta)
        else:
            velocidad = (escritos / (1024 * 1024)) / duracion if duracion > 0 else 0
            print(f" listo ({formato_tamanio(escritos)} en {duracion:.1f}s, {velocidad:.1f} MB/s) -> {destino}")
            resumen["descargados"] += 1
            resumen["bytes"] += escritos

    return resumen


def main() -> int:
    parser = argparse.ArgumentParser(
        description=f"Descarga los datos de taxis del NYC TLC Trip Record Data."
    )
    parser.add_argument(
        "--taxi",
        choices=(*TIPOS_TAXI, "all"),
        default="all",
        help="tipo de taxi a descargar: yellow, green o all (por defecto: all)",
    )
    parser.add_argument(
        "--year", "--anio",
        type=int,
        default=ANIO_DEFAULT,
        help=f"anio de los datos a descargar (por defecto: {ANIO_DEFAULT})",
    )
    parser.add_argument(
        "--months", "--meses",
        type=int,
        nargs="+",
        default=list(range(1, 13)),
        help="lista de meses a descargar (1-12, por defecto: todos)",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DIR_DESTINO,
        help=f"directorio base de destino (por defecto: {DIR_DESTINO})",
    )

    argumentos = parser.parse_args()

    # Validar meses
    meses_validos = [m for m in argumentos.months if 1 <= m <= 12]
    if not meses_validos:
        print("Error: Debe especificar meses validos entre 1 y 12.")
        return 1

    tipos = TIPOS_TAXI if argumentos.taxi == "all" else (argumentos.taxi,)

    total = {"descargados": 0, "omitidos": 0, "no_publicados": [], "fallidos": [], "bytes": 0}
    for tipo in tipos:
        resumen = descargar(tipo, argumentos.year, meses_validos, argumentos.output_dir)
        total["descargados"] += resumen["descargados"]
        total["omitidos"] += resumen["omitidos"]
        total["bytes"] += resumen["bytes"]
        total["no_publicados"] += [f"{tipo} {m}" for m in resumen["no_publicados"]]
        total["fallidos"] += [f"{tipo} {m}" for m in resumen["fallidos"]]

    print("\n" + "=" * 60)
    print("RESUMEN DE DESCARGA")
    print("=" * 60)
    print(f"  Anio analizado : {argumentos.year}")
    print(f"  Descargados    : {total['descargados']} ({formato_tamanio(total['bytes'])})")
    print(f"  Ya existian    : {total['omitidos']}")
    print(f"  No publicados  : {len(total['no_publicados'])}")
    if total["no_publicados"]:
        print(f"      {', '.join(total['no_publicados'])}")
    print(f"  Fallidos       : {len(total['fallidos'])}")
    if total["fallidos"]:
        print(f"      {', '.join(total['fallidos'])}")
    print("=" * 60)

    return 1 if total["fallidos"] else 0


if __name__ == "__main__":
    sys.exit(main())
