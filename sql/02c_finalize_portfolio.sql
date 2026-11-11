-- 1. Define eligible retail products

CREATE OR REPLACE VIEW eligible_sku_sales AS
SELECT
    t.PRODUCT_ID,
    p.DEPARTMENT,
    SUM(t.SALES_VALUE) AS sku_sales
FROM candidate_transactions t
JOIN products p
    ON t.PRODUCT_ID = p.PRODUCT_ID
WHERE p.DEPARTMENT IS NOT NULL
  AND p.DEPARTMENT NOT IN (
      'KIOSK-GAS',
      'MISC SALES TRAN'
  )
GROUP BY
    t.PRODUCT_ID,
    p.DEPARTMENT;


-- 2. Re-rank and select 800 eligible SKUs

CREATE OR REPLACE TABLE model_skus AS
WITH ranked AS (
    SELECT
        PRODUCT_ID,
        sku_sales,
        ROW_NUMBER() OVER (
            ORDER BY sku_sales DESC, PRODUCT_ID
        ) AS sku_rank
    FROM eligible_sku_sales
)
SELECT
    PRODUCT_ID,
    sku_rank,
    ROUND(sku_sales, 2) AS sku_sales
FROM ranked
WHERE sku_rank <= 800;


-- 3. Rebuild final transaction population

CREATE OR REPLACE VIEW model_transactions AS
SELECT t.*
FROM candidate_transactions t
JOIN model_skus s
    ON t.PRODUCT_ID = s.PRODUCT_ID;


-- 4. Separate valid unit-pricing transactions

CREATE OR REPLACE VIEW model_unit_valid_transactions AS
SELECT *
FROM model_transactions
WHERE SALES_VALUE > 0
  AND QUANTITY > 0;


-- 5. Reconcile final population

COPY (
    WITH source AS (
        SELECT SUM(SALES_VALUE) AS all_sales
        FROM candidate_transactions
    ),
    eligible AS (
        SELECT SUM(sku_sales) AS eligible_sales
        FROM eligible_sku_sales
    ),
    modeled AS (
        SELECT
            COUNT(*) AS transaction_lines,
            SUM(SALES_VALUE) AS modeled_sales,
            COUNT(DISTINCT STORE_ID) AS stores
        FROM model_transactions
    )
    SELECT
        m.stores,
        (SELECT COUNT(*) FROM model_skus)
            AS selected_skus,
        m.transaction_lines,
        ROUND(s.all_sales, 2)
            AS five_store_sales,
        ROUND(e.eligible_sales, 2)
            AS eligible_retail_sales,
        ROUND(m.modeled_sales, 2)
            AS portfolio_sales,
        ROUND(
            100.0 * m.modeled_sales /
            NULLIF(s.all_sales, 0), 2
        ) AS coverage_all_sales_pct,
        ROUND(
            100.0 * m.modeled_sales /
            NULLIF(e.eligible_sales, 0), 2
        ) AS coverage_eligible_sales_pct,
        (
            SELECT COUNT(*)
            FROM model_skus ms
            JOIN products p
                ON ms.PRODUCT_ID = p.PRODUCT_ID
            WHERE p.DEPARTMENT IN (
                'KIOSK-GAS', 'MISC SALES TRAN'
            )
        ) AS excluded_department_skus_remaining
    FROM modeled m
    CROSS JOIN source s
    CROSS JOIN eligible e
) TO 'outputs/tables/02c_final_reconciliation.csv'
(HEADER, DELIMITER ',');


-- 6. Final department composition

COPY (
    SELECT
        p.DEPARTMENT,
        COUNT(DISTINCT t.PRODUCT_ID) AS active_skus,
        COUNT(*) AS transaction_lines,
        ROUND(SUM(t.SALES_VALUE), 2)
            AS portfolio_sales
    FROM model_transactions t
    JOIN products p
        ON t.PRODUCT_ID = p.PRODUCT_ID
    GROUP BY p.DEPARTMENT
    ORDER BY portfolio_sales DESC
) TO 'outputs/tables/02c_final_department_mix.csv'
(HEADER, DELIMITER ',');


-- 7. Quantify excluded categories

COPY (
    SELECT
        p.DEPARTMENT,
        COUNT(DISTINCT t.PRODUCT_ID) AS excluded_skus,
        COUNT(*) AS transaction_lines,
        ROUND(SUM(t.SALES_VALUE), 2)
            AS excluded_sales
    FROM candidate_transactions t
    JOIN products p
        ON t.PRODUCT_ID = p.PRODUCT_ID
    WHERE p.DEPARTMENT IN (
        'KIOSK-GAS',
        'MISC SALES TRAN'
    )
    GROUP BY p.DEPARTMENT
    ORDER BY excluded_sales DESC
) TO 'outputs/tables/02c_excluded_categories.csv'
(HEADER, DELIMITER ',');
