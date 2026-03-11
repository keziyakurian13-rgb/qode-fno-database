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
