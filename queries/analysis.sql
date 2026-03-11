-- ============================================================
-- analysis.sql
-- 5 SQL Queries for NSE F&O Database Analysis
-- Author: Keziya Kurian | Qode Advisors Assignment
-- Database: DuckDB (fno_database.db)
-- ============================================================


-- ============================================================
-- QUERY 1: Top 10 Symbols by Open Interest (OI) Change
--          Across Exchanges
-- ============================================================
-- Purpose: Rank symbols by total change in open interest.
-- Shows which contracts had the biggest OI movement — a key
-- metric for understanding market activity and sentiment.
-- ============================================================

SELECT
    i.symbol,
    e.exchange_name,
    i.instrument_type,
    SUM(t.chg_in_oi)         AS total_oi_change,
    SUM(ABS(t.chg_in_oi))    AS absolute_oi_movement
FROM trades t
JOIN instruments i ON t.instrument_id = i.instrument_id
JOIN exchanges   e ON i.exchange_id   = e.exchange_id
GROUP BY i.symbol, e.exchange_name, i.instrument_type
ORDER BY ABS(SUM(t.chg_in_oi)) DESC
LIMIT 10;


-- ============================================================
-- QUERY 2: 7-Day Rolling Standard Deviation of Close Prices
--          for NIFTY Options (Volatility Analysis)
-- ============================================================
-- Purpose: Calculate rolling 7-day volatility for NIFTY.
-- Standard deviation of close prices shows how much prices
-- fluctuate — a core metric for options pricing and risk.
-- Uses window functions (ROWS BETWEEN) for rolling calculation.
-- ============================================================

SELECT
    t.timestamp,
    i.symbol,
    t.close,
    ROUND(
        STDDEV(t.close) OVER (
            PARTITION BY i.symbol
            ORDER BY t.timestamp
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ), 4
    ) AS rolling_7day_stddev
FROM trades t
JOIN instruments i ON t.instrument_id = i.instrument_id
WHERE i.symbol = 'NIFTY'
  AND i.instrument_type IN ('FUTIDX', 'OPTIDX')
ORDER BY t.timestamp
LIMIT 100;


-- ============================================================
-- QUERY 3: Cross-Exchange Comparison
--          Avg settle_pr: MCX instruments vs NSE Index Futures
-- ============================================================
-- Purpose: Compare average settlement prices across exchanges.
-- MCX instruments (HINDZINC, NATIONALUM — metal commodity proxies)
-- vs NSE equity index futures (NIFTY, BANKNIFTY, NIFTYIT).
-- Note: Dataset is NSE-only. Metal stocks tagged as MCX proxies
-- to demonstrate cross-exchange schema capability.
-- ============================================================

SELECT
    e.exchange_name,
    i.instrument_type,
    COUNT(DISTINCT i.symbol)      AS num_symbols,
    COUNT(t.trade_id)             AS num_trades,
    ROUND(AVG(t.settle_pr), 2)   AS avg_settle_price,
    ROUND(MIN(t.settle_pr), 2)   AS min_settle_price,
    ROUND(MAX(t.settle_pr), 2)   AS max_settle_price
FROM trades t
JOIN instruments i ON t.instrument_id = i.instrument_id
JOIN exchanges   e ON i.exchange_id   = e.exchange_id
WHERE e.exchange_name IN ('NSE', 'MCX')
  AND (
      (e.exchange_name = 'MCX')
      OR
      (e.exchange_name = 'NSE' AND i.instrument_type = 'FUTIDX')
  )
GROUP BY e.exchange_name, i.instrument_type
ORDER BY e.exchange_name;


-- ============================================================
-- QUERY 4: Option Chain Summary
--          Grouped by expiry_date and strike_price
--          for NIFTY — calculating implied volume
-- ============================================================
-- Purpose: Summarise the full option chain for NIFTY.
-- Groups CE and PE contracts by expiry and strike to show
-- total open interest, volume, and average pricing at each level.
-- This is the classic "option chain" view used by traders.
-- ============================================================

SELECT
    ex.expiry_date,
    ex.strike_price,
    ex.option_type,
    COUNT(t.trade_id)            AS trading_days,
    SUM(t.contracts)             AS total_volume,
    SUM(t.open_int)              AS total_open_interest,
    ROUND(AVG(t.close), 2)      AS avg_close_price,
    ROUND(AVG(t.settle_pr), 2)  AS avg_settle_price
FROM trades t
JOIN instruments i ON t.instrument_id = i.instrument_id
JOIN expiries   ex ON t.expiry_id     = ex.expiry_id
WHERE i.symbol      = 'NIFTY'
  AND ex.option_type IN ('CE', 'PE')
GROUP BY ex.expiry_date, ex.strike_price, ex.option_type
ORDER BY ex.expiry_date, ex.strike_price, ex.option_type
LIMIT 100;


-- ============================================================
-- QUERY 5: Max Contracts (Volume) in Rolling 30-Day Window
--          Using Window Functions / Index-Optimised
-- ============================================================
-- Purpose: Find the highest single-day contract volume seen
-- in the past 30 days for each symbol — a peak activity metric.
-- Uses a window function for the rolling max calculation.
-- Performance: Optimised by the idx_trades_timestamp index.
-- ============================================================

SELECT
    i.symbol,
    t.timestamp,
    t.contracts                              AS daily_volume,
    MAX(t.contracts) OVER (
        PARTITION BY i.instrument_id
        ORDER BY t.timestamp
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    )                                        AS max_volume_30days,
    ROUND(
        100.0 * t.contracts /
        NULLIF(MAX(t.contracts) OVER (
            PARTITION BY i.instrument_id
            ORDER BY t.timestamp
            ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
        ), 0), 2
    )                                        AS pct_of_30day_peak
FROM trades t
JOIN instruments i ON t.instrument_id = i.instrument_id
WHERE t.contracts IS NOT NULL
  AND t.contracts > 0
ORDER BY i.symbol, t.timestamp
LIMIT 200;
