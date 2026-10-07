#!/usr/bin/env python3
"""Materializa los datos Parquet en una base DuckDB (Ejercicio 6.2).

Crea data/processed/taxis.duckdb con:
  - viajes        TABLA con todos los anios descargados (esquema unificado de
                  sql/00_vistas.sql, yellow + green).
  - zonas         TABLA con el catalogo de zonas de taxi.
  - tipos_pago    vista (constantes).
  - viajes_limpios vista con las reglas de limpieza, ahora sobre la TABLA.

Se ejecuta el mismo sql/00_vistas.sql y luego cada vista de datos se sustituye
por una tabla con el mismo nombre. Asi las consultas de sql/ funcionan sin
cambios tanto sobre los Parquet como sobre la base materializada.

Uso:
    python scripts/build_duckdb.py                       # data/processed/taxis.duckdb
    python scripts/build_duckdb.py --output otra.duckdb
"""

import argparse
import sys
import time
from pathlib import Path

import duckdb

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lab_db import VISTAS  # noqa: E402

DESTINO_DEFAULT = Path("data/processed/taxis.duckdb")
# Vistas de 00_vistas.sql que se convierten en tablas.
A_MATERIALIZAR = ("viajes", "zonas")


def materializar(con: duckdb.DuckDBPyConnection, sql_vistas: str) -> dict[str, float]:
    """Crea las vistas y reemplaza A_MATERIALIZAR por tablas. Devuelve segundos por tabla."""
    con.execute(sql_vistas)
    tiempos = {}
    for nombre in A_MATERIALIZAR:
        inicio = time.perf_counter()
        con.execute(f"CREATE OR REPLACE TABLE {nombre}__tmp AS SELECT * FROM {nombre}")
        con.execute(f"DROP VIEW {nombre}")
        con.execute(f"ALTER TABLE {nombre}__tmp RENAME TO {nombre}")
        tiempos[nombre] = time.perf_counter() - inicio
    # Las vistas crudas leen Parquet directamente; en la base materializada no se usan.
    con.execute("DROP VIEW IF EXISTS yellow_raw; DROP VIEW IF EXISTS green_raw;")
    con.execute("CHECKPOINT")
    return tiempos


def main() -> int:
    parser = argparse.ArgumentParser(description="Materializa los Parquet en una base DuckDB.")
    parser.add_argument("--output", type=Path, default=DESTINO_DEFAULT,
                        help=f"archivo .duckdb de destino (por defecto: {DESTINO_DEFAULT})")
    args = parser.parse_args()

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.unlink(missing_ok=True)          # reconstruccion completa y reproducible
    with duckdb.connect(str(args.output)) as con:
        tiempos = materializar(con, VISTAS.read_text())
        resumen = con.sql("""
            SELECT tipo_taxi, anio, count(DISTINCT mes) AS meses, count(*) AS registros
            FROM viajes GROUP BY ALL ORDER BY ALL
        """).fetchall()

    print(f"Base creada: {args.output} ({args.output.stat().st_size / 1024**3:.2f} GiB)")
    for nombre, segundos in tiempos.items():
        print(f"  tabla {nombre:<8} {segundos:6.1f} s")
    for tipo, anio, meses, registros in resumen:
        print(f"  {tipo:<6} {anio}  {meses:>2} meses  {registros:>12,} registros")
    return 0


if __name__ == "__main__":
    sys.exit(main())
