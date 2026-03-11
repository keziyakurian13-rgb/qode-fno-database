-- ============================================================
-- optimization.sql
-- Index Creation + EXPLAIN ANALYZE Benchmarking
-- Author: Keziya Kurian | Qode Advisors Assignment
-- Database: DuckDB (fno_database.db)
-- ============================================================
-- Strategy:
--   1. Run a slow query BEFORE indexes (baseline)
--   2. Create indexes on high-frequency filter columns
--   3. Run the SAME query AFTER indexes (post-optimization)
--   4. Compare EXPLAIN ANALYZE output to prove speedup
-- ============================================================


-- ============================================================
-- STEP 1: EXPLAIN ANALYZE — BEFORE Optimization (Baseline)
-- ============================================================
-- Running Query 1 without any indexes.
-- DuckDB will do a full sequential scan of 2.5M rows.
-- ============================================================

EXPLAIN ANALYZE
SELECT
    i.symbol,
    SUM(t.chg_in_oi) AS total_oi_change
FROM trades t
JOIN instruments i ON t.instrument_id = i.instrument_id
GROUP BY i.symbol
ORDER BY ABS(SUM(t.chg_in_oi)) DESC
LIMIT 10;


-- ============================================================
-- STEP 2: Create Indexes
-- ============================================================
-- Index 1: timestamp — speeds up time-series range queries
-- Index 2: instrument_id in trades — speeds up JOINs
-- Index 3: symbol in instruments — speeds up symbol lookups
-- Index 4: exchange_id — speeds up cross-exchange filtering
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_trades_timestamp
    ON trades(timestamp);

CREATE INDEX IF NOT EXISTS idx_trades_instrument_id
    ON trades(instrument_id);

CREATE INDEX IF NOT EXISTS idx_trades_expiry_id
    ON trades(expiry_id);

CREATE INDEX IF NOT EXISTS idx_instruments_symbol
    ON instruments(symbol);

CREATE INDEX IF NOT EXISTS idx_instruments_exchange_id
    ON instruments(exchange_id);

-- ============================================================
-- STEP 3: EXPLAIN ANALYZE — AFTER Optimization
-- ============================================================
-- Same query as STEP 1 — now with indexes in place.
-- Compare the cost and execution plan to show improvement.
-- ============================================================

EXPLAIN ANALYZE
SELECT
    i.symbol,
    SUM(t.chg_in_oi) AS total_oi_change
FROM trades t
JOIN instruments i ON t.instrument_id = i.instrument_id
GROUP BY i.symbol
ORDER BY ABS(SUM(t.chg_in_oi)) DESC
LIMIT 10;


-- ============================================================
-- STEP 4: Verify Indexes Were Created
-- ============================================================

PRAGMA show_tables;


-- ============================================================
-- STEP 5: Partitioning Strategy
-- ============================================================
-- NOTE: DuckDB (.db single-file mode) does not support
-- PostgreSQL-style declarative table partitioning
-- (CREATE TABLE trades PARTITION BY RANGE(timestamp)).
--
-- DuckDB EQUIVALENT approaches used here:
--
-- A) Index-based partitioning (implemented above):
--    idx_trades_timestamp  → enables partition pruning on date ranges
--    idx_trades_expiry_id  → enables partition pruning on expiry
--
-- B) Parquet file partitioning (for bulk analytics at scale):
--    COPY trades TO 'partitioned/' (FORMAT PARQUET, PARTITION_BY (timestamp));
--    This splits trades into one file per timestamp — equivalent to
--    partitioning by date in PostgreSQL.
--
-- C) PostgreSQL equivalent (for reference):
--    If PostgreSQL were used instead of DuckDB, partitioning would be:
--
--    CREATE TABLE trades (
--        trade_id      INTEGER,
--        instrument_id INTEGER,
--        expiry_id     INTEGER,
--        timestamp     DATE NOT NULL,
--        ...
--    ) PARTITION BY RANGE (timestamp);
--
--    CREATE TABLE trades_aug2019 PARTITION OF trades
--        FOR VALUES FROM ('2019-08-01') TO ('2019-09-01');
--
--    CREATE TABLE trades_sep2019 PARTITION OF trades
--        FOR VALUES FROM ('2019-09-01') TO ('2019-10-01');
--
--    CREATE TABLE trades_oct2019 PARTITION OF trades
--        FOR VALUES FROM ('2019-10-01') TO ('2019-11-01');
--
-- For 10M+ rows at HFT scale, Parquet partitioning (option B)
-- is the recommended approach in production quant environments.
-- ============================================================

