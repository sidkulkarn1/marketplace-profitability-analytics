-- 1. Load primary source tables

CREATE OR REPLACE TABLE transactions AS
SELECT *
FROM read_csv_auto('data/raw/transaction_data.csv');

CREATE OR REPLACE TABLE products AS
SELECT *
FROM read_csv_auto('data/raw/product.csv');


-- 2. Dataset overview

COPY (
    SELECT
        COUNT(*) AS transaction_lines,
        COUNT(DISTINCT BASKET_ID) AS baskets,
        COUNT(DISTINCT STORE_ID) AS stores,
        COUNT(DISTINCT PRODUCT_ID) AS transacted_skus,
        COUNT(DISTINCT household_key) AS households,
        MIN(DAY) AS first_day,
        MAX(DAY) AS last_day,
        ROUND(SUM(SALES_VALUE), 2) AS net_sales
    FROM transactions
) TO 'outputs/tables/01_dataset_summary.csv'
  (HEADER, DELIMITER ',');


-- 3. Data quality checks

COPY (
    SELECT
        COUNT(*) FILTER (
            WHERE SALES_VALUE = 0
        ) AS zero_sales_lines,

        COUNT(*) FILTER (
            WHERE QUANTITY = 0
        ) AS zero_quantity_lines,

        COUNT(*) FILTER (
            WHERE SALES_VALUE < 0
        ) AS negative_sales_lines,

        COUNT(*) FILTER (
            WHERE PRODUCT_ID IS NULL
               OR STORE_ID IS NULL
               OR BASKET_ID IS NULL
        ) AS missing_key_lines,

        (
            SELECT COUNT(*)
            FROM transactions t
            LEFT JOIN products p
                ON t.PRODUCT_ID = p.PRODUCT_ID
            WHERE p.PRODUCT_ID IS NULL
        ) AS unmatched_product_lines,

        (
            SELECT COUNT(*) - COUNT(DISTINCT PRODUCT_ID)
            FROM products
        ) AS duplicate_product_ids

    FROM transactions
) TO 'outputs/tables/01_data_quality.csv'
  (HEADER, DELIMITER ',');


-- 4. Store-level operating coverage

CREATE OR REPLACE VIEW store_coverage AS
SELECT
    STORE_ID,
    COUNT(*) AS transaction_lines,
    COUNT(DISTINCT BASKET_ID) AS baskets,
    COUNT(DISTINCT PRODUCT_ID) AS active_skus,
    COUNT(DISTINCT DAY) AS active_days,
    COUNT(DISTINCT household_key) AS households,
    MIN(DAY) AS first_day,
    MAX(DAY) AS last_day,
    ROUND(SUM(SALES_VALUE), 2) AS net_sales
FROM transactions
GROUP BY STORE_ID;

COPY (
    SELECT *
    FROM store_coverage
    ORDER BY transaction_lines DESC
) TO 'outputs/tables/01_store_coverage.csv'
  (HEADER, DELIMITER ',');


-- 5. Initial store candidate shortlist
-- Screening thresholds, not final selection.

COPY (
    SELECT *
    FROM store_coverage
    WHERE transaction_lines >= 10000
      AND active_days >= 500
    ORDER BY transaction_lines DESC
    LIMIT 50
) TO 'outputs/tables/01_store_candidates.csv'
  (HEADER, DELIMITER ',');
