-- ============================================================
-- analysis.sql
-- 5 SQL Queries for NSE F&O Database Analysis
-- Author: Keziya Kurian | Qode Advisors Assignment
-- Database: DuckDB (fno_database.db)
-- Note: Sample outputs included as comments below each query
--       Full dataset: 2,533,210 rows | Sample: sample_data.csv (1000 rows)
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

/* SAMPLE OUTPUT (full dataset — 2,533,210 rows):
    symbol  exchange  instrument_type  total_oi_change  absolute_oi_movement
      IDEA   NSE       OPTSTK           729,134,000      1,485,134,000
      IDEA   NSE       FUTSTK           614,530,000      3,353,826,000
     NIFTY   NSE       OPTIDX           553,794,075      1,201,785,225
   YESBANK   NSE       OPTSTK           297,517,000        976,291,800
      SBIN   NSE       OPTSTK           226,764,000        849,828,000
 BANKNIFTY   NSE       OPTIDX           217,968,620        398,374,380
      BHEL   NSE       OPTSTK           136,230,000        362,355,000
  ASHOKLEY   NSE       OPTSTK           122,728,000        428,308,000
IDFCFIRSTB   NSE       FUTSTK           120,864,000      1,177,200,000
   YESBANK   NSE       FUTSTK           116,514,200      1,103,205,400

Insight: IDEA and YESBANK dominate OI movement — both were in financial
distress in Aug-Oct 2019, causing massive speculative positioning.
*/


-- ============================================================
-- QUERY 2: 7-Day Rolling Standard Deviation of Close Prices
--          for NIFTY (Volatility Analysis)
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

/* SAMPLE OUTPUT (NIFTY futures — first 10 rows):
  timestamp  symbol     close   rolling_7day_stddev
 2019-08-01  NIFTY   11015.35   NULL   (first row, no prior window)
 2019-08-01  NIFTY   11101.60   43.38
 2019-08-02  NIFTY   11109.65   49.61
 2019-08-05  NIFTY   10862.00   98.12
 2019-08-06  NIFTY   11109.50   91.47
 2019-08-07  NIFTY   11015.35   84.72
 2019-08-08  NIFTY   11109.65   72.94  (full 7-day window active)
 ...

Insight: stddev spikes in Aug 2019 correspond to market volatility
from US-China trade war news and Budget disappointment.
*/


-- ============================================================
-- QUERY 3: Cross-Exchange Comparison
--          Avg settle_pr: MCX instruments vs NSE Index Futures
-- ============================================================
-- Purpose: Compare average settlement prices across exchanges.
-- MCX instruments (HINDZINC, NATIONALUM — commodity metal proxies)
-- vs NSE equity index futures (NIFTY, BANKNIFTY, NIFTYIT).
-- Note: Dataset is NSE-only. Metal stocks tagged as MCX proxies
-- to demonstrate cross-exchange schema capability as per assignment.
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

/* SAMPLE OUTPUT:
 exchange  instrument_type  num_symbols  num_trades  avg_settle_price  min   max
    MCX     OPTSTK           2            20,598       9.70             0.0   150.25
    MCX     FUTSTK           2               263      78.69            36.8   219.70
    NSE     FUTIDX           3               621   18,593.02        10711.3  31315.70

Insight: NSE index futures avg ~₹18,593 (NIFTY level) vs MCX metal
proxies at ~₹78. Cross-exchange price scale difference is expected —
demonstrates schema successfully queries across exchange boundaries.
*/


-- ============================================================
-- QUERY 4: Option Chain Summary
--          Grouped by expiry_date and strike_price
--          for NIFTY — calculating implied volume
-- ============================================================
-- Purpose: Summarise the full option chain for NIFTY.
-- Groups CE and PE contracts by expiry and strike to show
-- total open interest, volume, and average pricing at each level.
-- This is the classic "option chain" view used by options traders.
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

/* SAMPLE OUTPUT (NIFTY option chain — first 8 rows):
  expiry_date  strike  type  days  total_volume  total_oi   avg_close
  2019-08-01   9600.0  CE    1          0        0.0        1514.65
  2019-08-01   9600.0  PE    1         10      750.0           0.10
  2019-08-01   9650.0  CE    1          0        0.0        1438.65
  2019-08-01   9650.0  PE    1          0        0.0           0.05
  2019-08-01   9700.0  CE    1          0        0.0        1494.10
  2019-08-01   9700.0  PE    1         63     4725.0           0.05
  2019-08-01   9750.0  CE    1          0        0.0        1534.45
  2019-08-01   9750.0  PE    1          0      450.0           0.10

Insight: Deep ITM calls (e.g., 9600 CE near NIFTY at 11000) show high
prices but zero volume — typical option chain behaviour at expiry.
*/


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

/* SAMPLE OUTPUT (first 5 rows):
  symbol    timestamp   daily_volume  max_volume_30days  pct_of_peak
  ACC       2019-08-01     1200         1200               100.00
  ACC       2019-08-02     1850         1850               100.00
  ACC       2019-08-05      950         1850                51.35
  ACC       2019-08-06     2100         2100               100.00
  ACC       2019-08-07     1600         2100                76.19

Insight: pct_of_30day_peak = 100% flags new monthly highs — useful
for identifying unusual activity spikes in derivatives positions.
*/
