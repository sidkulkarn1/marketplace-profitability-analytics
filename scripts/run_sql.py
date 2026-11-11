
from pathlib import Path
import os
import sys
import duckdb

# Always run from the project root.
ROOT = Path(__file__).resolve().parent.parent
os.chdir(ROOT)

if len(sys.argv) != 2:
    raise SystemExit(
        "Usage: python scripts/run_sql.py sql/01_data_profiling.sql"
    )

sql_file = ROOT / sys.argv[1]

if not sql_file.is_file():
    raise FileNotFoundError(sql_file)

connection = duckdb.connect(
    str(ROOT / "marketplace_profitability.duckdb")
)

try:
    connection.execute(sql_file.read_text())
    print(f"SUCCESS: {sql_file.name} executed")
finally:
    connection.close()
