#!/usr/bin/env python3
"""Benchmark: consultas directas sobre Parquet vs tabla materializada en DuckDB (Ejercicio 6).

Para cada escenario (cantidad de datos) y cada consulta:
  1. Estrategia "parquet": DuckDB en memoria con las vistas de sql/00_vistas.sql
     apuntando solo a los archivos del escenario.
  2. Estrategia "tabla":   base .duckdb temporal donde `viajes` y `zonas` son
     tablas construidas a partir de esos mismos archivos (scripts/build_duckdb.py).
El texto SQL ejecutado es identico en ambas estrategias.

Cada consulta se ejecuta 1 vez de calentamiento + N repeticiones; se reportan
la primera ejecucion y la mediana de las repeticiones. Las consultas se
ejecutan con fetchall() para incluir la materializacion completa del resultado.

Salidas (docs/benchmark/):
  resultados_benchmark.csv  una fila por ejecucion
  escenarios.csv            filas, tamanio Parquet, tamanio .duckdb y tiempo de carga
  resumen_benchmark.md      tablas resumen (mediana por consulta/escenario/estrategia)
  ../img/ej6_benchmark.png  grafica de tiempos por escenario

Uso:
    python scripts/benchmark.py                 # todos los escenarios, 5 repeticiones
    python scripts/benchmark.py --repeticiones 3 --escenarios 1_mes 2026
"""

import argparse
import csv
import gc
import os
import platform
import statistics
import sys
import time
from glob import glob
from pathlib import Path

import duckdb

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_duckdb import materializar  # noqa: E402
from lab_db import VISTAS, cargar_consultas  # noqa: E402

SALIDA = Path("docs/benchmark")
IMG = Path("docs/img")
BASE_TEMPORAL = Path("data/processed/benchmark_tmp.duckdb")

# Escenarios de tamanio creciente. Cada uno es un patron glob de nombres de archivo
# (relativo a data/raw/<tipo>/) que se expande con Python para yellow y green.
ESCENARIOS = {
    "1_mes":     "2026/*_2026-01.parquet",
    "3_meses":   "2026/*_2026-0[1-3].parquet",
    "2026":      "2026/*.parquet",
    "2024_2026": "*/*.parquet",
}

CONSULTAS_EDA = (
    "p1_viajes_por_mes",
    "p2_hora_dia_semana",
    "p3_caracteristicas_viaje",
    "p5b_top_zonas_origen",
    "p8a_propinas_por_metodo",
    "p9_composicion_total",
)


def archivos(patron: str, tipo: str) -> list[str]:
    return sorted(glob(f"data/raw/{tipo}/{patron}"))


def sql_vistas_para(patron: str) -> str:
    """00_vistas.sql con los globs sustituidos por la lista de archivos del escenario."""
    sql = VISTAS.read_text()
    for tipo in ("yellow", "green"):
        lista = archivos(patron, tipo)
        if not lista:
            raise SystemExit(f"No hay archivos {tipo} para el patron {patron!r}; ejecute download_data.py")
        literal = "[" + ", ".join(f"'{a}'" for a in lista) + "]"
        original = f"'data/raw/{tipo}/*/*.parquet'"
        assert original in sql, f"no se encontro {original} en {VISTAS}"
        sql = sql.replace(original, literal)
    return sql


def medir(con: duckdb.DuckDBPyConnection, sql: str) -> float:
    inicio = time.perf_counter()
    con.execute(sql).fetchall()
    return time.perf_counter() - inicio


def correr_consultas(con, consultas, repeticiones, escenario, estrategia, filas_csv):
    for nombre, sql in consultas.items():
        tiempos = [medir(con, sql) for _ in range(repeticiones + 1)]
        for i, t in enumerate(tiempos):
            filas_csv.append({"escenario": escenario, "estrategia": estrategia, "consulta": nombre,
                              "corrida": i, "segundos": round(t, 5)})
        print(f"    {estrategia:<7} {nombre:<26} primera {tiempos[0]:7.3f}s  "
              f"mediana {statistics.median(tiempos[1:]):7.3f}s")


def main() -> int:
    parser = argparse.ArgumentParser(description="Benchmark Parquet vs tabla DuckDB.")
    parser.add_argument("--repeticiones", type=int, default=5)
    parser.add_argument("--escenarios", nargs="+", choices=list(ESCENARIOS), default=list(ESCENARIOS))
    args = parser.parse_args()

    eda = cargar_consultas("02_analisis_exploratorio.sql")
    consultas = {**cargar_consultas("04_benchmark.sql"), **{n: eda[n] for n in CONSULTAS_EDA}}

    SALIDA.mkdir(parents=True, exist_ok=True)
    resultados, escenarios = [], []
    print(f"DuckDB {duckdb.__version__} | Python {platform.python_version()} | "
          f"{platform.system()} {platform.machine()} | {os.cpu_count()} CPUs")

    for escenario in args.escenarios:
        patron = ESCENARIOS[escenario]
        sql_vistas = sql_vistas_para(patron)
        lista = archivos(patron, "yellow") + archivos(patron, "green")
        bytes_parquet = sum(Path(a).stat().st_size for a in lista)
        print(f"\n=== Escenario {escenario}: {len(lista)} archivos, {bytes_parquet / 1024**2:,.0f} MiB Parquet ===")

        # Estrategia 1: Parquet directo
        con = duckdb.connect()
        con.execute(sql_vistas)
        filas = con.sql("SELECT count(*) FROM viajes").fetchone()[0]
        correr_consultas(con, consultas, args.repeticiones, escenario, "parquet", resultados)
        con.close()

        # Estrategia 2: tabla materializada
        BASE_TEMPORAL.unlink(missing_ok=True)
        con = duckdb.connect(str(BASE_TEMPORAL))
        inicio = time.perf_counter()
        materializar(con, sql_vistas)
        carga = time.perf_counter() - inicio
        con.close()
        bytes_duckdb = BASE_TEMPORAL.stat().st_size
        print(f"    tabla materializada en {carga:.1f}s ({bytes_duckdb / 1024**2:,.0f} MiB)")
        con = duckdb.connect(str(BASE_TEMPORAL))
        correr_consultas(con, consultas, args.repeticiones, escenario, "tabla", resultados)
        con.close()
        gc.collect()
        BASE_TEMPORAL.unlink(missing_ok=True)
        Path(str(BASE_TEMPORAL) + ".wal").unlink(missing_ok=True)

        escenarios.append({"escenario": escenario, "archivos": len(lista), "filas": filas,
                           "mib_parquet": round(bytes_parquet / 1024**2, 1),
                           "mib_duckdb": round(bytes_duckdb / 1024**2, 1),
                           "segundos_carga_tabla": round(carga, 2)})
        # Se guarda al terminar cada escenario para no perder lo medido si algo falla despues.
        guardar_csv(SALIDA / "resultados_benchmark.csv", resultados)
        guardar_csv(SALIDA / "escenarios.csv", escenarios)

    escribir_resumen(resultados, escenarios, args.repeticiones)
    print(f"\nResultados en {SALIDA}/")
    return 0


def guardar_csv(ruta: Path, filas: list[dict]) -> None:
    with open(ruta, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(filas[0]))
        w.writeheader()
        w.writerows(filas)


def escribir_resumen(resultados, escenarios, repeticiones):
    """Tablas markdown + grafica a partir de los resultados (usa DuckDB sobre las listas)."""
    import pandas as pd
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    df = pd.DataFrame(resultados)
    orden = list(ESCENARIOS)
    resumen = duckdb.sql("""
        SELECT escenario, consulta, estrategia,
               median(segundos) FILTER (WHERE corrida > 0) AS mediana,
               max(segundos)    FILTER (WHERE corrida = 0) AS primera
        FROM df GROUP BY ALL
    """).df()
    piv = resumen.pivot_table(index=["consulta", "escenario"], columns="estrategia",
                              values=["mediana", "primera"]).reset_index()
    piv.columns = ["consulta", "escenario", "med_parquet", "med_tabla", "pri_parquet", "pri_tabla"]
    piv["aceleracion"] = piv.med_parquet / piv.med_tabla
    piv["escenario"] = pd.Categorical(piv.escenario, orden, ordered=True)
    piv = piv.sort_values(["consulta", "escenario"])

    lineas = [
        "# Resultados del benchmark (generado por scripts/benchmark.py)",
        "",
        f"DuckDB {duckdb.__version__}, Python {platform.python_version()}, "
        f"{platform.system()} {platform.machine()}, {os.cpu_count()} CPUs. "
        f"Mediana de {repeticiones} repeticiones despues de 1 ejecucion de calentamiento.",
        "",
        "## Escenarios",
        "",
        "| escenario | archivos | filas | Parquet (MiB) | .duckdb (MiB) | carga de la tabla (s) |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for e in escenarios:
        lineas.append(f"| {e['escenario']} | {e['archivos']} | {e['filas']:,} | {e['mib_parquet']:,.1f} | "
                      f"{e['mib_duckdb']:,.1f} | {e['segundos_carga_tabla']:.1f} |")
    lineas += [
        "",
        "## Tiempos por consulta (segundos)",
        "",
        "`aceleracion` = mediana Parquet / mediana tabla (> 1: la tabla es mas rapida).",
        "",
        "| consulta | escenario | Parquet 1a | Parquet mediana | tabla 1a | tabla mediana | aceleracion |",
        "|---|---|---:|---:|---:|---:|---:|",
    ]
    for r in piv.itertuples():
        lineas.append(f"| {r.consulta} | {r.escenario} | {r.pri_parquet:.4f} | {r.med_parquet:.4f} | "
                      f"{r.pri_tabla:.4f} | {r.med_tabla:.4f} | {r.aceleracion:.1f}x |")

    totales = piv.groupby("escenario", observed=True)[["med_parquet", "med_tabla"]].sum()
    totales["aceleracion"] = totales.med_parquet / totales.med_tabla
    lineas += [
        "",
        "## Suma de medianas de todas las consultas por escenario",
        "",
        "| escenario | Parquet (s) | tabla (s) | aceleracion |",
        "|---|---:|---:|---:|",
    ]
    for esc, r in totales.iterrows():
        lineas.append(f"| {esc} | {r.med_parquet:.2f} | {r.med_tabla:.2f} | {r.aceleracion:.1f}x |")
    (SALIDA / "resumen_benchmark.md").write_text("\n".join(lineas) + "\n")

    # Grafica: una linea por consulta, tiempo mediano vs filas del escenario.
    filas = {e["escenario"]: e["filas"] for e in escenarios}
    piv["filas"] = piv.escenario.astype(str).map(filas)
    consultas = list(dict.fromkeys(piv.consulta))
    columnas = 3
    fig, ejes = plt.subplots(-(-len(consultas) // columnas), columnas, figsize=(13, 3 * -(-len(consultas) // columnas)))
    for eje, nombre in zip(ejes.flat, consultas):
        d = piv[piv.consulta == nombre]
        eje.plot(d.filas / 1e6, d.med_parquet, marker="o", label="Parquet")
        eje.plot(d.filas / 1e6, d.med_tabla, marker="s", label="tabla DuckDB")
        eje.set_title(nombre, fontsize=9); eje.set_xlabel("millones de filas", fontsize=8)
        eje.set_ylabel("s (mediana)", fontsize=8); eje.tick_params(labelsize=7)
    for eje in list(ejes.flat)[len(consultas):]:
        eje.axis("off")
    ejes.flat[0].legend(fontsize=8)
    fig.tight_layout()
    IMG.mkdir(parents=True, exist_ok=True)
    fig.savefig(IMG / "ej6_benchmark.png", dpi=110)


if __name__ == "__main__":
    sys.exit(main())
