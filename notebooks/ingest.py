"""
ingest.py
---------
Loads 3mfanddo.csv into the 4 normalized DuckDB tables:
  1. exchanges   → 3 rows (NSE, BSE, MCX) — manually inserted
  2. instruments → unique SYMBOL + INSTRUMENT_TYPE (328 rows)
  3. expiries    → unique EXPIRY_DT + STRIKE_PR + OPTION_TYP (18,232 rows)
  4. trades      → all 2.5M rows with proper IDs

MCX tagging: HINDZINC and NATIONALUM tagged as exchange_id=3 (MCX)
as commodity metal proxies for cross-exchange query demonstration.

Run from repo root:
    python3 notebooks/ingest.py
"""

import duckdb
import pandas as pd
import os

# ── Paths ──────────────────────────────────────────────────────────────────
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV_FILE = os.path.join(BASE_DIR, "3mfanddo.csv")
DB_FILE  = os.path.join(BASE_DIR, "fno_database.db")

# ── Connect to database ────────────────────────────────────────────────────
print("📂 Connecting to database...")
conn = duckdb.connect(DB_FILE)

# ── Load CSV ───────────────────────────────────────────────────────────────
print("📄 Loading CSV...")
df = pd.read_csv(CSV_FILE)
df.columns = df.columns.str.strip()          # clean column names
print(f"   → {len(df):,} rows loaded\n")

# ══════════════════════════════════════════════════════════════════════════
# STEP 1: Insert exchanges (manually — CSV has no exchange column)
# ══════════════════════════════════════════════════════════════════════════
print("🔄 Step 1: Inserting exchanges...")
conn.execute("DELETE FROM exchanges")        # clear if re-running
conn.execute("""
    INSERT INTO exchanges (exchange_id, exchange_name) VALUES
    (1, 'NSE'),
    (2, 'BSE'),
    (3, 'MCX')
""")
count = conn.execute("SELECT COUNT(*) FROM exchanges").fetchone()[0]
print(f"   ✅ {count} exchanges inserted (NSE, BSE, MCX)\n")

# ══════════════════════════════════════════════════════════════════════════
# STEP 2: Insert instruments (unique SYMBOL + INSTRUMENT_TYPE combos)
# MCX tagging: HINDZINC and NATIONALUM → exchange_id = 3 (MCX proxy)
# All others  → exchange_id = 1 (NSE)
# ══════════════════════════════════════════════════════════════════════════
print("🔄 Step 2: Inserting instruments...")
conn.execute("DELETE FROM instruments")

# MCX-tagged commodity metal proxies
MCX_SYMBOLS = {'HINDZINC', 'NATIONALUM'}

unique_instruments = (
    df[['INSTRUMENT', 'SYMBOL']]
    .drop_duplicates()
    .reset_index(drop=True)
)
unique_instruments['instrument_id'] = unique_instruments.index + 1
unique_instruments['exchange_id'] = unique_instruments['SYMBOL'].apply(
    lambda s: 3 if s in MCX_SYMBOLS else 1
)

conn.executemany(
    "INSERT INTO instruments (instrument_id, symbol, instrument_type, exchange_id) VALUES (?, ?, ?, ?)",
    unique_instruments[['instrument_id', 'SYMBOL', 'INSTRUMENT', 'exchange_id']].values.tolist()
)
count = conn.execute("SELECT COUNT(*) FROM instruments").fetchone()[0]
print(f"   ✅ {count} instruments inserted")
mcx_count = conn.execute("SELECT COUNT(*) FROM instruments WHERE exchange_id = 3").fetchone()[0]
print(f"   → {mcx_count} tagged as MCX (HINDZINC, NATIONALUM)\n")

# ══════════════════════════════════════════════════════════════════════════
# STEP 3: Insert expiries (unique EXPIRY_DT + STRIKE_PR + OPTION_TYP)
# ══════════════════════════════════════════════════════════════════════════
print("🔄 Step 3: Inserting expiries...")
conn.execute("DELETE FROM expiries")

unique_expiries = (
    df[['EXPIRY_DT', 'STRIKE_PR', 'OPTION_TYP']]
    .drop_duplicates()
    .reset_index(drop=True)
)
unique_expiries['expiry_id'] = unique_expiries.index + 1

# Parse expiry dates to standard format (DD-Mon-YYYY → YYYY-MM-DD)
unique_expiries['EXPIRY_DT'] = pd.to_datetime(
    unique_expiries['EXPIRY_DT'], format='%d-%b-%Y'
).dt.strftime('%Y-%m-%d')

conn.executemany(
    "INSERT INTO expiries (expiry_id, expiry_date, strike_price, option_type) VALUES (?, ?, ?, ?)",
    unique_expiries[['expiry_id', 'EXPIRY_DT', 'STRIKE_PR', 'OPTION_TYP']].values.tolist()
)
count = conn.execute("SELECT COUNT(*) FROM expiries").fetchone()[0]
print(f"   ✅ {count:,} expiries inserted\n")

# ══════════════════════════════════════════════════════════════════════════
# STEP 4: Insert trades (all 2.5M rows with proper IDs)
# ══════════════════════════════════════════════════════════════════════════
print("🔄 Step 4: Inserting trades (2.5M rows — this may take a minute)...")
conn.execute("DELETE FROM trades")

# Build lookup maps: name → id
instrument_map = dict(
    zip(
        zip(unique_instruments['SYMBOL'], unique_instruments['INSTRUMENT']),
        unique_instruments['instrument_id']
    )
)
expiry_map = dict(
    zip(
        zip(unique_expiries['EXPIRY_DT'], unique_expiries['STRIKE_PR'], unique_expiries['OPTION_TYP']),
        unique_expiries['expiry_id']
    )
)

# Map IDs onto trades dataframe
df['EXPIRY_DT_PARSED'] = pd.to_datetime(
    df['EXPIRY_DT'], format='%d-%b-%Y'
).dt.strftime('%Y-%m-%d')

df['instrument_id'] = df.apply(
    lambda r: instrument_map.get((r['SYMBOL'], r['INSTRUMENT'])), axis=1
)
df['expiry_id'] = df.apply(
    lambda r: expiry_map.get((r['EXPIRY_DT_PARSED'], r['STRIKE_PR'], r['OPTION_TYP'])), axis=1
)
df['trade_id'] = range(1, len(df) + 1)

# Select and rename columns for trades table
trades_df = df[[
    'trade_id', 'instrument_id', 'expiry_id',
    'OPEN', 'HIGH', 'LOW', 'CLOSE', 'SETTLE_PR',
    'CONTRACTS', 'VAL_INLAKH', 'OPEN_INT', 'CHG_IN_OI',
    'TIMESTAMP'
]].copy()
trades_df.columns = [
    'trade_id', 'instrument_id', 'expiry_id',
    'open', 'high', 'low', 'close', 'settle_pr',
    'contracts', 'val_inlakh', 'open_int', 'chg_in_oi',
    'timestamp'
]

# Parse timestamp to date format
trades_df['timestamp'] = pd.to_datetime(
    trades_df['timestamp'], format='%d-%b-%Y'
).dt.strftime('%Y-%m-%d')

# Insert using DuckDB's fast bulk method
conn.execute("INSERT INTO trades SELECT * FROM trades_df")

count = conn.execute("SELECT COUNT(*) FROM trades").fetchone()[0]
print(f"   ✅ {count:,} trade rows inserted\n")

# ── Final summary ──────────────────────────────────────────────────────────
print("=" * 50)
print("📊 INGESTION COMPLETE — Table Row Counts:")
for table in ['exchanges', 'instruments', 'expiries', 'trades']:
    n = conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
    print(f"   {table:15} → {n:>10,} rows")

conn.close()
print("\n✅ All done! fno_database.db is ready for queries.")
