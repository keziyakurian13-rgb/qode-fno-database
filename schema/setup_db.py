"""
setup_db.py
-----------
Creates the DuckDB database file and runs DDL to create all 4 tables.

Run this script from your repo root:
    python3 schema/setup_db.py
"""

import duckdb
import os

# ── Paths ──────────────────────────────────────────────────────────────────
BASE_DIR  = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DDL_FILE  = os.path.join(BASE_DIR, "schema", "ddl.sql")
DB_FILE   = os.path.join(BASE_DIR, "fno_database.db")

# ── Connect (creates the .db file if it doesn't exist) ─────────────────────
print(f"📂 Creating database at: {DB_FILE}")
conn = duckdb.connect(DB_FILE)

# ── Read and run the DDL file ───────────────────────────────────────────────
print("📄 Reading ddl.sql ...")
with open(DDL_FILE, "r") as f:
    raw = f.read()

# Remove all comment lines first, then split by semicolon
lines = [l for l in raw.splitlines() if not l.strip().startswith("--")]
cleaned_ddl = "\n".join(lines)
statements = [s.strip() for s in cleaned_ddl.split(";") if s.strip()]

print("🔨 Creating tables ...\n")
for statement in statements:
    if "CREATE TABLE" in statement.upper():
        conn.execute(statement)
        table_name = statement.upper().split("CREATE TABLE")[1].split("(")[0].strip().lower()
        print(f"  ✅ Table '{table_name}' created")

# ── Verify all 4 tables exist ──────────────────────────────────────────────
print("\n📋 Tables in database:")
tables = conn.execute("SHOW TABLES").fetchall()
for t in tables:
    print(f"  → {t[0]}")

conn.close()
print("\n✅ Database setup complete! File saved as: fno_database.db")
