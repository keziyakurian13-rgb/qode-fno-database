# Reasoning Document
## NSE Futures & Options — Relational Database Design
**Author: Keziya Kurian | Qode Advisors LLP Assignment**

---

## 1. Understanding the Assignment

When I first read the assignment, I had two immediate questions: *What exactly is a relational database?* and *Why can't I just use the CSV directly?*

The CSV file (`3mfanddo.csv`) has 2,533,210 rows and 16 columns. Every single row has values like `BANKNIFTY`, `FUTIDX`, `29-Aug-2019` repeated over and over. The word `BANKNIFTY` alone appears tens of thousands of times as a full string. This is what databases call a **flat file** — all information crammed into one table with massive repetition.

The assignment asked me to design a **relational database**, which means reorganizing this flat data into multiple linked tables so that each piece of information is stored exactly once. The benefits are immediately obvious: less storage, faster queries, no inconsistency, and the ability to extend the schema to support other exchanges (BSE, MCX) without breaking anything.

---

## 2. Setting Up — Installing Kaggle and Downloading the Dataset

Before touching any data, I had to get it. The dataset was hosted on Kaggle, so the first step was setting up the Kaggle CLI.

```bash
pip install kaggle
```

Then I needed an API key. I went to [kaggle.com/settings](https://www.kaggle.com/settings), created a new API token named `Qode_Assignment`, and configured my credentials:

```bash
mkdir -p ~/.kaggle
echo '{"username":"christykurian","key":"<api_key>"}' > ~/.kaggle/kaggle.json
chmod 600 ~/.kaggle/kaggle.json
```

Then downloaded the dataset directly into the repo folder:

```bash
kaggle datasets download -d sunnysai12345/nse-future-and-options-dataset-3m \
    --path ~/Desktop/qode-fno-database --force
```

After downloading, I unzipped it:

```bash
unzip nse-future-and-options-dataset-3m.zip
```

This produced a single file: **`3mfanddo.csv`** — that was the original filename from Kaggle, not renamed by me. The file was ~34MB compressed and contained 2,533,210 rows.

---

## 3. Exploring the Dataset

The first thing I did was load the CSV and inspect it:

```python
import pandas as pd
df = pd.read_csv('3mfanddo.csv')
print(df.columns.tolist())   # check all 16 columns
print(df.shape)              # (2533210, 16)
print(df.head())             # first 5 rows
```

**What I found:**
- 16 columns total (including an `Unnamed: 0` index column I had to drop)
- 4 instrument types: `FUTIDX`, `FUTSTK`, `OPTIDX`, `OPTSTK`
- Only 3 index instruments: `NIFTY`, `BANKNIFTY`, `NIFTYIT`
- 164 total unique symbols
- 328 unique (SYMBOL + INSTRUMENT_TYPE) combinations
- 18,232 unique (EXPIRY_DT + STRIKE_PR + OPTION_TYP) combinations

**My key question at this point** was: *The assignment mentions gold futures (MCX), but does the dataset have gold?* After searching every symbol, the answer was no — this dataset is 100% NSE equity F&O from Aug–Oct 2019. The assignment says "assume ingestion of similar structured data," so I designed the schema to support MCX and tagged metal companies (`HINDZINC`, `NATIONALUM`) as MCX proxies to demonstrate the cross-exchange query.

---

## 4. Deciding the Schema — Why 4 Tables?

My next challenge was: *which columns go into which table?*

I started by asking: **what are the distinct "things" (entities) in this data?**

- An **exchange** is a real-world entity (NSE, BSE, MCX) — exists independently
- An **instrument** (NIFTY, BANKNIFTY) is a real entity — has its own identity
- An **expiry** (date + strike + option type) is a real entity — defines a contract
- A **trade** is the actual daily price event — this is the core fact

This maps perfectly to the 4 tables the assignment asked for. Each table stores one entity, and they connect through foreign keys.

**Why not fewer tables?** If I merged `instruments` into `trades`, I'd repeat `BANKNIFTY` millions of times. If I merged `expiries` into `trades`, I'd repeat `29-Aug-2019, 11000, CE` thousands of times. Redundancy = worse performance + risk of inconsistency.

**Why not more tables?** Splitting `OPEN`, `HIGH`, `LOW`, `CLOSE` into their own table would be over-engineering — they describe the same event (one day's trade) and always belong together.

---

## 5. Why 3NF Over Star Schema?

The assignment specifically asked me to explain normalization choices and why star schema was avoided. Here is my reasoning:

A **star schema** denormalizes dimension data back into the fact table (trades). For example, instead of `instrument_id = 2`, you'd store `symbol = 'BANKNIFTY'`, `exchange = 'NSE'` directly in every trades row. This avoids joins, making reads faster.

**I chose 3NF instead because:**

1. **DuckDB is columnar** — it performs aggregations natively on normalized data. Joins are cheap. The performance advantage of a star schema is minimal in DuckDB.
2. **Data integrity** — F&O research requires correctness above all. If I stored symbol names in every row and a symbol was renamed, I'd have to update 2.5M rows.
3. **HFT write efficiency** — at 10M+ rows, writing denormalized strings on every insert is expensive. Writing integer IDs is 3–5× faster.
4. **Multi-exchange extensibility** — adding MCX data to a 3NF schema requires no structural changes. A star schema would need new columns or flag columns.

---

## 6. Writing the DDL

Once the design was clear, I wrote the CREATE TABLE statements in `schema/ddl.sql`. The order matters: you must create referenced tables before referencing tables.

**Order:** `exchanges` → `instruments` → `expiries` → `trades`

Key decisions:
- Used **surrogate integer PKs** (not natural keys like symbol strings). Integer joins are 3–5× faster than string joins, and integers never change even if a symbol name changes.
- Used `DECIMAL` for prices (not `FLOAT`) — FLOAT has rounding errors unacceptable in financial data.
- Used `NOT NULL` on all foreign keys and critical columns to enforce data integrity at the database level.

I then wrote `schema/setup_db.py` to connect to DuckDB, read the SQL file, strip comment lines (an important bug I had to fix — the parser accidentally skipped CREATE TABLE statements that had comment blocks before them), and execute each statement. After fixing the comment-stripping logic, all 4 tables were created:

```
✅ Table 'exchanges' created
✅ Table 'instruments' created
✅ Table 'expiries' created
✅ Table 'trades' created
```

---

## 7. Data Ingestion — The Hard Part

Ingestion is where theory meets reality. The challenge: the CSV is one flat table, but the database needs 4 linked tables with integer IDs that don't exist in the CSV.

**My approach in `notebooks/ingest.py`:**

**Step 1 — Exchanges (manual insert):** The CSV has no exchange column. All data is NSE. So I manually inserted 3 rows: NSE (1), BSE (2), MCX (3). This establishes the multi-exchange schema even without real BSE/MCX data.

**Step 2 — Instruments (from CSV, unique combos only):** I extracted unique (SYMBOL, INSTRUMENT) combinations using `drop_duplicates()`. This gave 328 rows — not 2.5 million. Each gets an auto-assigned ID. I also applied MCX tagging here: any symbol in `{'HINDZINC', 'NATIONALUM'}` gets `exchange_id = 3`.

**Step 3 — Expiries (from CSV, unique combos only):** I extracted unique (EXPIRY_DT, STRIKE_PR, OPTION_TYP) combinations — 18,232 rows. An important detail: dates in the CSV were formatted `DD-Mon-YYYY` (e.g., `29-Aug-2019`), not standard `YYYY-MM-DD`. I converted them using `pd.to_datetime(format='%d-%b-%Y').dt.strftime('%Y-%m-%d')`.

**Step 4 — Trades (all 2.5M rows):** For each trade row, I needed to look up the correct `instrument_id` and `expiry_id`. I built Python dictionaries (hash maps) from the lookup tables so each row's IDs could be found in O(1) time. Then I used DuckDB's bulk insert `conn.execute("INSERT INTO trades SELECT * FROM trades_df")` which is dramatically faster than row-by-row insertion.

**Final row counts:**
```
exchanges    →          3 rows
instruments  →        328 rows
expiries     →     18,232 rows
trades       →  2,533,210 rows
```

---

## 8. SQL Queries — What I Wrote and Why

All 5 queries are in `queries/analysis.sql`.

**Query 1 — Top 10 by OI Change:** Uses `SUM(chg_in_oi)` grouped by symbol and exchange, ordered by `ABS()` to catch both large positive and negative movements. Result: IDEA and NIFTY topped the list — consistent with the high-volatility Aug 2019 market.

**Query 2 — 7-Day Rolling Std Dev:** Uses `STDDEV() OVER (PARTITION BY symbol ORDER BY timestamp ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)` — a window function that calculates rolling volatility without needing a self-join. This is a standard technique in quant research for measuring realized volatility.

**Query 3 — Cross-Exchange Comparison:** Compares average `settle_pr` for MCX-tagged instruments (HINDZINC, NATIONALUM, ~₹78) vs NSE index futures (NIFTY/BANKNIFTY, ~₹18,593). This query demonstrates the cross-exchange schema design even with proxy data.

**Query 4 — Option Chain Summary:** Groups by `expiry_date + strike_price + option_type` — the standard view used by options traders to see all CE/PE prices at each strike across expiries. Uses `SUM(contracts)` as implied volume.

**Query 5 — Max Volume in 30-Day Window:** Uses `MAX(contracts) OVER (ROWS BETWEEN 29 PRECEDING AND CURRENT ROW)` — calculates the rolling peak trading activity per symbol. Also computes `pct_of_30day_peak` to show how today's volume compares to the recent high.

---

## 9. Optimization — Indexes and Partitioning

I created 5 indexes targeting the most frequent query patterns:

```sql
idx_trades_timestamp        → accelerates time-series date range filters
idx_trades_instrument_id    → accelerates most frequent JOIN (trades → instruments)
idx_trades_expiry_id        → accelerates option chain queries
idx_instruments_symbol      → accelerates symbol name lookups
idx_instruments_exchange_id → accelerates cross-exchange filters
```

After creating indexes, I ran `EXPLAIN ANALYZE` on Query 1. The result: **0.0677 seconds** on 2,533,210 rows. The query plan showed a `HASH_JOIN` between trades and instruments — DuckDB's optimizer chose a hash join, which is efficient for this scale.

**On partitioning:** I hit an important limitation. DuckDB in single-file `.db` mode does not support PostgreSQL-style declarative partitioning (`PARTITION BY RANGE`). However, my `idx_trades_timestamp` index achieves **index-based partition pruning** — where the query planner skips date ranges that don't match the filter, similar in effect to physical partitioning.

For 10M+ rows at HFT scale, the correct approach is **Parquet file partitioning**:
```sql
COPY trades TO 'partitioned/' (FORMAT PARQUET, PARTITION_BY (timestamp));
```
DuckDB reads partitioned Parquet natively with automatic partition elimination. Full PostgreSQL `PARTITION BY RANGE` equivalent DDL is also documented in `queries/optimization.sql` for reference.

---

## 10. Results Summary

| Component | Outcome |
|---|---|
| Schema | 3NF, 4 tables, PKs + FKs, multi-exchange ready |
| Ingestion | 2,533,210 rows loaded in DuckDB in ~2 minutes |
| Queries | All 5 queries working with real results |
| Optimization | 5 indexes, EXPLAIN ANALYZE captured (0.0677s on 2.5M rows) |
| Partitioning | Index-based pruning implemented; Parquet and PostgreSQL alternatives documented |
| GitHub | Public repo with all files, README, ER diagram, DDL, SQL, ingestion script |

The schema is production-ready for multi-exchange F&O ingestion and can scale to 10M+ rows without structural changes — only the ingestion script and partitioning strategy would need adjustment.
