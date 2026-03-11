# NSE Futures & Options — Relational Database
**Assignment: Senior Data Associate — Qode Advisors LLP**
**Author: Keziya Kurian**

---

## Overview

This project designs and implements a normalized relational database to store and analyze **2.5 million rows** of NSE Futures & Options (F&O) data from Kaggle. The schema supports multi-exchange analysis (NSE, BSE, MCX) and powers 5 advanced SQL queries for quant research use cases.

**Tech Stack:** Python · DuckDB · SQL · pandas

---

## Repository Structure

```
qode-fno-database/
├── 3mfanddo.csv                  # Raw Kaggle dataset (2.5M rows, 16 columns)
├── fno_database.db               # DuckDB database (all 4 tables populated)
│
├── diagrams/
│   └── er_diagram.png            # ER Diagram — entities, attributes, PK/FK, cardinality
│
├── schema/
│   ├── ddl.sql                   # CREATE TABLE statements (4 tables)
│   └── setup_db.py               # Python script to run DDL and create tables
│
├── notebooks/
│   └── ingest.py                 # CSV → DuckDB ingestion pipeline
│
└── queries/
    ├── analysis.sql              # 5 SQL analysis queries
    └── optimization.sql          # Indexes + EXPLAIN ANALYZE benchmarking
```

---

## Dataset

**Source:** [NSE Future and Options Dataset 3M — Kaggle](https://www.kaggle.com/datasets/sunnysai12345/nse-future-and-options-dataset-3m)

| Property | Value |
|---|---|
| Total rows | 2,533,210 |
| Columns | 16 |
| Date range | Aug–Oct 2019 |
| Exchange | NSE (equity F&O) |

**Columns:** `INSTRUMENT`, `SYMBOL`, `EXPIRY_DT`, `STRIKE_PR`, `OPTION_TYP`, `OPEN`, `HIGH`, `LOW`, `CLOSE`, `SETTLE_PR`, `CONTRACTS`, `VAL_INLAKH`, `OPEN_INT`, `CHG_IN_OI`, `TIMESTAMP`

---

## Schema Design

### Normalization (3NF)
The raw CSV is denormalized — repeating `SYMBOL`, `EXPIRY_DT`, `OPTION_TYP` across 2.5M rows. The schema breaks this into 4 normalized tables eliminating redundancy and enabling efficient querying.

### ER Diagram
![ER Diagram](diagrams/er_diagram.png)

### Tables

| Table | Rows | Purpose |
|---|---|---|
| `exchanges` | 3 | NSE, BSE, MCX — multi-exchange support |
| `instruments` | 328 | Unique SYMBOL + INSTRUMENT_TYPE combinations |
| `expiries` | 18,232 | Unique EXPIRY_DT + STRIKE_PR + OPTION_TYP |
| `trades` | 2,533,210 | Core fact table — daily OHLC, volume, OI |

### Key Relationships
- `exchanges` → `instruments`: **one-to-many** (one exchange has many instruments)
- `instruments` → `trades`: **one-to-many** (one instrument has many daily trade records)
- `expiries` → `trades`: **one-to-many** (one expiry contract has many trade records)

---

## Multi-Exchange Design

The dataset contains only NSE equity F&O data. The schema is designed to support BSE and MCX ingestion without any structural changes.

**MCX Proxy:** `HINDZINC` (Hindustan Zinc) and `NATIONALUM` (National Aluminium) are tagged under `exchange_id = 3 (MCX)` as the closest available commodity-adjacent proxies in the dataset. This enables a genuine cross-exchange SQL query demonstrating the schema's capability.

> Real MCX commodity futures (gold, silver, crude oil) can be ingested into the same schema without any DDL changes — simply set the correct `exchange_id` during ingestion.

---

## SQL Queries

All 5 queries are in [`queries/analysis.sql`](queries/analysis.sql).

| # | Query | Technique Used |
|---|---|---|
| 1 | Top 10 symbols by OI change across exchanges | GROUP BY, JOIN, ORDER BY ABS() |
| 2 | 7-day rolling std dev (NIFTY volatility) | Window function: STDDEV() OVER ROWS |
| 3 | Avg settle_pr: MCX vs NSE index futures | Cross-exchange JOIN + GROUP BY |
| 4 | Option chain by expiry_date and strike_price | Multi-column GROUP BY, SUM, AVG |
| 5 | Max volume in rolling 30-day window | Window function: MAX() OVER ROWS |

---

## Optimizations

See [`queries/optimization.sql`](queries/optimization.sql) for EXPLAIN ANALYZE output.

**Indexes created:**
```sql
CREATE INDEX idx_trades_timestamp      ON trades(timestamp);
CREATE INDEX idx_trades_instrument_id  ON trades(instrument_id);
CREATE INDEX idx_trades_expiry_id      ON trades(expiry_id);
CREATE INDEX idx_instruments_symbol    ON instruments(symbol);
CREATE INDEX idx_instruments_exchange_id ON instruments(exchange_id);
```

**Design rationale:**
- `timestamp` index: accelerates all time-series range queries
- `instrument_id` index: speeds up the most frequent JOIN (trades → instruments)
- `expiry_id` index: speeds up option chain queries that filter by expiry

---

## How to Reproduce

```bash
# 1. Install dependencies
pip install duckdb pandas

# 2. Create tables
python3 schema/setup_db.py

# 3. Load data
python3 notebooks/ingest.py

# 4. Run queries in DuckDB
python3 -c "
import duckdb
conn = duckdb.connect('fno_database.db')
with open('queries/analysis.sql') as f:
    print(conn.execute(f.read().split(';')[1]).df())
"
```

---

## Design Decisions

1. **DuckDB over PostgreSQL** — DuckDB is purpose-built for analytical workloads on local data. Ideal for 2.5M row time-series analysis without server overhead.
2. **Surrogate keys** — Auto-increment integer PKs used instead of natural keys (symbol strings) for faster joins and storage efficiency.
3. **Separate expiries table** — Decouples contract specifications (date + strike + type) from daily price data, avoiding repetition across 2.5M rows.
4. **Star schema pattern** — `trades` as the central fact table with `instruments` and `expiries` as dimension tables — standard quant data warehouse pattern.
5. **MCX proxy tagging** — Metal companies (HINDZINC, NATIONALUM) tagged as MCX exchange to demonstrate cross-exchange schema without requiring real MCX data.
