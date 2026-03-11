-- ============================================================
-- DDL: NSE Futures & Options Database
-- Author: Keziya Kurian
-- Assignment: Senior Data Associate — Qode Advisors LLP
-- Database: DuckDB
-- ============================================================


-- ============================================================
-- TABLE 1: exchanges
-- Stores the exchange where instruments are traded.
-- Supports multi-exchange design: NSE, BSE, MCX
-- ============================================================
CREATE TABLE exchanges (
    exchange_id   INTEGER PRIMARY KEY,
    exchange_name VARCHAR NOT NULL UNIQUE   -- 'NSE', 'BSE', 'MCX'
);


-- ============================================================
-- TABLE 2: instruments
-- Stores unique trading symbols and their type.
-- Each instrument belongs to one exchange (FK → exchanges).
-- Relationship: one exchange → many instruments (one-to-many)
-- ============================================================
CREATE TABLE instruments (
    instrument_id   INTEGER PRIMARY KEY,
    symbol          VARCHAR NOT NULL,        -- e.g., NIFTY, BANKNIFTY, GOLD
    instrument_type VARCHAR NOT NULL,        -- FUTIDX, FUTSTK, OPTIDX, OPTSTK
    exchange_id     INTEGER NOT NULL REFERENCES exchanges(exchange_id)
);


-- ============================================================
-- TABLE 3: expiries
-- Stores expiry date, strike price, and option type.
-- Separating this avoids repeating expiry info in every trade.
-- ============================================================
CREATE TABLE expiries (
    expiry_id    INTEGER PRIMARY KEY,
    expiry_date  DATE    NOT NULL,           -- e.g., 2019-08-29
    strike_price DECIMAL NOT NULL,           -- 0 for futures, actual value for options
    option_type  VARCHAR NOT NULL            -- 'CE', 'PE', or 'XX' (futures)
);


-- ============================================================
-- TABLE 4: trades
-- Core fact table — stores daily OHLC and volume data.
-- References instruments and expiries via foreign keys.
-- Relationship: one instrument → many trades (one-to-many)
-- Relationship: one expiry → many trades (one-to-many)
-- ============================================================
CREATE TABLE trades (
    trade_id      INTEGER PRIMARY KEY,
    instrument_id INTEGER NOT NULL REFERENCES instruments(instrument_id),
    expiry_id     INTEGER NOT NULL REFERENCES expiries(expiry_id),
    open          DECIMAL,                   -- Opening price
    high          DECIMAL,                   -- Highest price of the day
    low           DECIMAL,                   -- Lowest price of the day
    close         DECIMAL,                   -- Closing price
    settle_pr     DECIMAL,                   -- Settlement price
    contracts     INTEGER,                   -- Number of contracts traded
    val_inlakh    DECIMAL,                   -- Turnover in lakhs
    open_int      INTEGER,                   -- Open interest
    chg_in_oi     INTEGER,                   -- Change in open interest
    timestamp     DATE NOT NULL              -- Date of the trade record
);
