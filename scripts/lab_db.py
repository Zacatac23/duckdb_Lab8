"""Utilidades compartidas por notebooks y scripts del laboratorio.

- conectar(): abre DuckDB (en memoria o sobre un archivo) y crea las vistas de
  sql/00_vistas.sql sobre los archivos Parquet.
- cargar_consultas(): lee un archivo .sql y devuelve sus consultas por nombre.
  Cada consulta del archivo va precedida de una linea `-- name: <nombre>`; asi la
  documentacion (el .sql) y la ejecucion (notebooks/scripts) usan el mismo texto.

Todas las rutas son relativas a la raiz del proyecto; los notebooks hacen
os.chdir() a la raiz antes de usar este modulo.
"""

import re
from pathlib import Path

import duckdb

RAIZ = Path(__file__).resolve().parent.parent
SQL_DIR = RAIZ / "sql"
VISTAS = SQL_DIR / "00_vistas.sql"


def conectar(base: str | Path = ":memory:", read_only: bool = False) -> duckdb.DuckDBPyConnection:
    """Conexion DuckDB con las vistas base creadas (si la base no es de solo lectura)."""
    con = duckdb.connect(str(base), read_only=read_only)
    if not read_only:
        con.execute(VISTAS.read_text())
    return con


def cargar_consultas(archivo: str | Path) -> dict[str, str]:
    """Devuelve {nombre: sql} para cada bloque `-- name: <nombre>` del archivo."""
    texto = Path(archivo).read_text() if Path(archivo).is_absolute() else (SQL_DIR / archivo).read_text()
    partes = re.split(r"^--\s*name:\s*(\S+)\s*$", texto, flags=re.MULTILINE)
    consultas = {}
    for nombre, cuerpo in zip(partes[1::2], partes[2::2]):
        sql = cuerpo.strip().rstrip(";").strip()
        consultas[nombre] = sql
    return consultas
