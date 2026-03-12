# NSE Futures & Options Relational Database Design

**Assignment: Qode Advisors LLP**
**Database:** DuckDB | **Language:** Python + SQL

Designing a successful SQL database involves structure, performance, and scalability. This document outlines the key steps taken to design the 2.53 million row High-Frequency Trading (HFT) database for this assignment.

## Step 1: Purpose and Requirements
The core purpose of this database is to organize and analyze 3 months of historical stock market data (specifically, Futures & Options) from the National Stock Exchange (NSE). The dataset contains 2.53 million rows.

The main goal was to make sure the database is incredibly fast at reading data for complex analysis, while also being highly efficient at saving new live data so it can easily handle 10 million or more rows in a real-world trading environment.

## Step 2: Identify Entities and Attributes
Instead of putting all 2.5 million rows into one massive, messy spreadsheet, the data was grouped into logical categories. Doing this early ensures the database is future-proof and easy to manage:

*   **Exchanges:** Identifying the stock exchange (like the NSE). This allows us to easily add data from other exchanges like BSE or MCX later without having to redesign anything.
*   **Instruments:** Unique trading assets, like the `NIFTY` index or a specific stock.
*   **Expiries:** The specific details of an options contract (the date it expires, the strike price, and whether it is a Call or Put). Because we store the exact calendar date rather than a rule like "last Thursday," the database perfectly handles real-world shifts—such as when the NSE moves an expiry to a Wednesday due to a market holiday (e.g., August 14th, 2019) or changes the weekly expiry day entirely (like the recent shift of BankNifty to Wednesdays).
*   **Trades:** The actual daily records showing the price and volume for each asset.

While those four entities map the Kaggle dataset perfectly, to make this database **truly future-proof for a live automated trading system**, two critical additions are required:

*   **Contract Specifications (Lot Sizes):** In real F&O trading, a single contract isn't just "1 unit." Options are traded in lots. For example, 1 lot of NIFTY currently is 25 units, while BANKNIFTY is 15 units. Lot sizes actively change over time based on exchange rules (NSE changes them frequently when price values get too high). If you don't track lot size, you cannot calculate actual Rupee Profit & Loss (P&L)!
    *   *Entity:* `contract_specifications`
    *   *Attributes:* `instrument_id`, `effective_date`, `lot_size`
*   **Corporate Actions:** This is the bane of every data engineer's existence. When a company announces a stock split (e.g., HDFC Bank splits 2-for-1) or a massive special dividend, the stock price crashes by 50% overnight intentionally. Because stock options are derived from the stock price, the exchange also legally alters the strike prices of all existing Options contracts overnight. If your database doesn't have a table tracking these splits/dividends, your backtesting model will look at the price drop, assume the company collapsed, and execute thousands of false trades.
    *   *Entity:* `corporate_actions`
    *   *Attributes:* `instrument_id`, `action_date`, `action_type`, `adjustment_ratio`

## Step 3: Choose the Right Data Types
Each piece of information in the database must have the correct format (known as a data type). Getting this right improves performance and ensures the data is reliable.

For instance, we used whole numbers (`INTEGER`) for IDs and calendar dates (`DATE`) for timestamps. Most importantly, we used exact decimals (`DECIMAL`) for prices instead of standard floating-point numbers. Choosing the exact decimal format is a simple yet powerful way to make sure the financial calculations are perfectly accurate without any rounding errors.

## Step 4: Define Primary and Foreign Keys
Think of primary keys as a unique ID tag for a specific record. Foreign keys are simply links that connect those ID tags across different tables so the database knows how they relate.

In our design, the main `trades` table uses these simple ID links to connect to the instrument and expiry details. This prevents us from having to type out long text (like the bank's symbol name) millions of times, which saves an enormous amount of storage space.

## Step 5: Normalize the SQL Database
Normalization is the process of organizing data to reduce clutter and improve accuracy. By applying these rules, the massive 2.5 million row file was divided into a heavily organized structure known as **Third Normal Form (3NF)**. A well-normalized SQL database runs faster, uses less space, and avoids duplicate information. 

Often, data teams use a different design called a "Star Schema." However, a Star Schema requires copying the same text over and over again, which slows down the system when saving millions of rows per second. By using the 3NF approach instead, the database only ever saves a piece of information once. For example, if a contract's details change, we only have to update a single row rather than fixing 2.5 million duplicated rows. This makes the database incredibly fast at saving new live market data while keeping the information perfectly accurate.

## Step 6: Build Relationships and Indexes
Defining how tables connect to each other is a vital part of SQL database design. This database relies on simple, clean connections (where one instrument can relate to many trade records).

Indexes in SQL are like the index at the back of a textbook—they help speed up searches so the computer doesn't have to read every single page. We heavily indexed the dates and instrument IDs because they are searched the most. To make sure searches stay lightning-fast as the database grows past 10 million rows, we also documented advanced indexing strategies (like BRIN) that allow the database to skip over huge chunks of irrelevant dates instantly.

## Step 7: Ensure Security and Backup
Security is critical for every SQL database. While this specific assignment focuses on building the analytics engine locally using DuckDB, in a real-world production environment using a server database like PostgreSQL, we would set up strict user permissions. For example, data analysts would only be allowed to read the data, while automated data pipelines would be the only ones allowed to insert new records.

Protecting sensitive financial data using automated database rules and setting up regular backups prevents data loss during system crashes. A secure and well-maintained SQL database builds trust and ensures long-term reliability.

## Addendum: Data Quality & Structural Loopholes
Building the database is only half the battle; ensuring the data is clean is just as critical. A deep dive into this 2.53 million row dataset revealed some major real-world flaws that this design successfully accounts for. Here is the proof of work showing how these loopholes were found using SQL:

*   **Zero vs. NULL Pricing (The 82.9% Loopholes):** In this dataset, if an asset doesn't trade on a given day, its price is listed as a `0` instead of a blank space (`NULL`). This affects roughly 2.1 million rows (nearly 83% of the data).
    ```sql
    SELECT COUNT(*) 
    FROM trades 
    WHERE open = 0 OR close = 0;
    -- Result: 2,100,676 rows
    ```
    In financial algorithms, treating a missing price as exactly zero dollars causes system-breaking errors or shows a false 100% loss. This database is explicitly designed to accept blank (`NULL`) values so data engineers can clean up these dangerous zeros safely.

*   **Impossible Close Prices:** An automated check revealed over 2.1 million rows where the final `Close` price is mathematically outside the bounds of the daily `High` and `Low`.
    ```sql
    SELECT COUNT(*) 
    FROM trades 
    WHERE close > high OR close < low;
    -- Result: 2,100,775 rows
    ```
    This happens when the exchange carries forward yesterday's settlement price for assets that haven't traded today. A naive database would pull this bad data and ruin trading models, but our deep investigation flagged this for the ingestion layer.

*   **Impossible Open Interest Drops:** The dataset contains 117 records where no trading volume occurred, yet the total number of open contracts changed.
    ```sql
    SELECT COUNT(*) 
    FROM trades 
    WHERE contracts = 0 AND chg_in_oi != 0;
    -- Result: 117 rows
    ```
    Statistically, this is impossible without real trading activity, indicating manual spreadsheet adjustments upstream that require custom handling.

*   **Missing Calendar Days:** Real-world stock market data naturally skips weekends and holidays. Our SQL queries strictly use rows (`ROWS BETWEEN 6 PRECEDING`) instead of calendar dates to calculate 7-day rolling averages, ensuring the math isn't corrupted by a missing weekend.

## Conclusion
A successful SQL database design combines structure, performance, and security. By following these key steps, a strong foundation was created for analyzing massive stock market datasets.

This optimized SQL database isn't just fast today—it processes all 2.5 million rows in a fraction of a second—but it remains scalable and dependable for years to come. Investing time in this clean, organized design now ensures smooth, professional-grade performance in the future.

---

### Repository Files
*   **`schema/ddl.sql`**: Contains the exact `CREATE TABLE` logic for all 4 tables (exchanges, instruments, expiries, trades) with strict Primary Key and Foreign Key constraints.
*   **`queries/optimization.sql`**: Contains the `CREATE INDEX` SQL code. Furthermore, it explicitly documents the Partitioning strategy in "STEP 5", explaining how Parquet files partition data in DuckDB, and provides the exact equivalent `CREATE TABLE ... PARTITION BY RANGE` code for PostgreSQL.
*   **`queries/analysis.sql`**: Contains all 7 advanced queries (like the Put-Call Ratio and 7-Day Rolling Volatility). More importantly, directly beneath every single query is a `/* SAMPLE OUTPUT */` comment block showing the real mathematical output from the data, along with a short "Insight" on what that data proves about the market.
*   **`notebooks/ingest.py` & `notebooks/ingest_notebook.ipynb`**: The Python scripts used to cleanly load the messy 2.53 million row Kaggle CSV into our normalized database.
