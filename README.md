# NSE Futures & Options Relational Database

**Assignment: Qode Advisors LLP**  
**Database:** DuckDB | **Language:** Python + SQL

## Repository Structure

As per the assignment requirements, this public repository contains:

1. **`README.md`**: Design rationale (normalization choices, why star schema avoided, scalability for 10M+ rows HFT ingestion). *(This document)*
2. **`schema/ddl.sql` & `queries/optimization.sql`**: SQL DDL scripts (`CREATE TABLE`, `INDEX`, `PARTITION`).
3. **`queries/analysis.sql`**: Query `.sql` files with sample outputs on subset data.
4. **`notebooks/ingest_notebook.ipynb` & `notebooks/ingest.py`**: Jupyter notebook and script loading Kaggle CSV into DB (using DuckDB).

## Design Rationale

### 1. Normalization Choices (3NF)

The raw Kaggle dataset is a single denormalized CSV. I designed a **Third Normal Form (3NF)** relational schema dividing it into 4 tables: `exchanges`, `instruments`, `expiries`, and `trades`.

*   **Integrity:** Storing attributes like `symbol` or `strike_price` repeatedly in 2.5 million rows causes data anomalies. Normalizing extracts them into lookup tables, leaving the `trades` fact table with clean integer Foreign Keys.
*   **Storage Efficiency:** Replacing repeated strings (like 'BANKNIFTY') with 4 byte integers reduced the overall database footprint significantly.
*   **Extensibility:** Keeping an `exchanges` table allows the database to easily ingest BSE or MCX data in the future without altering the core `trades` schema.

### 2. Why Star Schema was Avoided

While a Star Schema is common in data warehousing for fast read heavy analytics (by denormalizing dimensions back into the fact table), I chose a 3NF relational model for this assignment for the following reasons:

*   **Write Performance (HFT Ingestion):** In a High Frequency Trading (HFT) or high volume environment, inserting millions of rows into a Star Schema requires writing heavy, redundant string data (dimensional attributes) on every tick. 3NF's integer only inserts are vastly lighter and faster.
*   **Data Integrity over Read Speed:** In quantitative finance, data correctness is paramount. A single update to an instrument's properties in 3NF requires updating one row. In a Star Schema, it requires updating every historical trade row.
*   **Columnar Engine Native Strengths:** Modern OLAP databases (like DuckDB) use columnar storage engines that natively optimize and vectorize JOINs on normalized integer keys. The traditional read speed penalty of 3NF is largely mitigated by the engine itself, making redundant denormalization unnecessary.

### 3. Scalability for 10M+ Rows HFT Ingestion

To ensure the system scales efficiently beyond the current 2.5 million rows to 10M+ rows in an HFT environment, several scalability measures were designed:

*   **B Tree Indexes:** Created heavily targeted indexes (`idx_trades_timestamp`, `idx_trades_instrument_id`) to ensure rapid querying without full table scans.
*   **Query Planners and Rewrites:** Demonstrated the ability to optimize complex aggregations (e.g., rewriting correlated subqueries into `GROUP BY` with Window `RANK()` functions) to drop execution times from 60+ seconds to ~0.06 seconds. 
*   **Partitioning Strategy:** 
    *   *DuckDB Implementation:* Implemented index based pruning. At true HFT scale, I documented the use of Parquet partitioning (`COPY trades TO 'partitioned/' (FORMAT PARQUET, PARTITION_BY (timestamp))`) which DuckDB reads with native automatic partition elimination.
    *   *PostgreSQL Equivalent:* Provided the standard PostgreSQL `PARTITION BY RANGE(timestamp)` DDL logic (in `queries/optimization.sql`) to demonstrate declarative partitioning knowledge.
