-- 1. Define the working modeling population

CREATE OR REPLACE TABLE model_stores AS
SELECT *
FROM candidate_five_stores;

CREATE OR REPLACE TABLE model_skus AS
SELECT
    PRODUCT_ID,
    sku_rank,
    sku_sales
FROM candidate_sku_rankings
WHERE sku_rank <= 800;

CREATE OR REPLACE VIEW model_transactions AS
SELECT t.*
FROM candidate_transactions t
JOIN model_skus s
    ON t.PRODUCT_ID = s.PRODUCT_ID;


-- 2. Reconcile modeled sales to five-store sales

COPY (
    WITH totals AS (
        SELECT SUM(SALES_VALUE) AS total_sales
        FROM candidate_transactions
    ),
    modeled AS (
        SELECT SUM(SALES_VALUE) AS modeled_sales
        FROM model_transactions
    )
    SELECT
        (SELECT COUNT(*) FROM model_stores)
            AS selected_stores,
        (SELECT COUNT(*) FROM model_skus)
            AS selected_skus,
        ROUND(t.total_sales, 2) AS total_sample_sales,
        ROUND(m.modeled_sales, 2) AS modeled_sales,
        ROUND(t.total_sales - m.modeled_sales, 2)
            AS excluded_sales,
        ROUND(
            100.0 * m.modeled_sales
            / NULLIF(t.total_sales, 0), 2
        ) AS coverage_pct
    FROM totals t
    CROSS JOIN modeled m
) TO 'outputs/tables/02_population_reconciliation.csv'
(HEADER, DELIMITER ',');


-- 3. Compare data quality across populations

COPY (
    WITH scoped AS (
        SELECT 'full_source' AS scope, *
        FROM transactions

        UNION ALL

        SELECT 'five_stores_all_skus' AS scope, *
        FROM candidate_transactions

        UNION ALL

        SELECT 'five_stores_top_800' AS scope, *
        FROM model_transactions
    )
    SELECT
        scope,
        COUNT(*) AS transaction_lines,
        COUNT(DISTINCT BASKET_ID) AS baskets,
        COUNT(DISTINCT PRODUCT_ID) AS active_skus,
        COUNT(*) FILTER (
            WHERE SALES_VALUE = 0
        ) AS zero_sales_lines,
        COUNT(*) FILTER (
            WHERE QUANTITY = 0
        ) AS zero_quantity_lines,
        COUNT(*) FILTER (
            WHERE QUANTITY < 0
        ) AS negative_quantity_lines,
        COUNT(*) FILTER (
            WHERE SALES_VALUE < 0
        ) AS negative_sales_lines,
        COUNT(*) FILTER (
            WHERE PRODUCT_ID IS NULL
               OR STORE_ID IS NULL
               OR BASKET_ID IS NULL
        ) AS missing_key_lines,
        ROUND(SUM(SALES_VALUE), 2) AS total_sales
    FROM scoped
    GROUP BY scope
    ORDER BY scope
) TO 'outputs/tables/02_quality_by_scope.csv'
(HEADER, DELIMITER ',');


-- 4. Assess department representation

COPY (
    SELECT
        p.DEPARTMENT,
        COUNT(DISTINCT t.PRODUCT_ID)
            AS total_active_skus,
        COUNT(DISTINCT CASE
            WHEN r.sku_rank <= 800
            THEN t.PRODUCT_ID
        END) AS selected_skus,

        ROUND(SUM(t.SALES_VALUE), 2)
            AS total_sales,

        ROUND(SUM(CASE
            WHEN r.sku_rank <= 800
            THEN t.SALES_VALUE
            ELSE 0
        END), 2) AS modeled_sales,

        ROUND(
            100.0 * SUM(CASE
                WHEN r.sku_rank <= 800
                THEN t.SALES_VALUE
                ELSE 0
            END)
            / NULLIF(SUM(t.SALES_VALUE), 0),
            2
        ) AS department_coverage_pct

    FROM candidate_transactions t
    JOIN products p
        ON t.PRODUCT_ID = p.PRODUCT_ID
    LEFT JOIN candidate_sku_rankings r
        ON t.PRODUCT_ID = r.PRODUCT_ID

    GROUP BY p.DEPARTMENT
    ORDER BY total_sales DESC
) TO 'outputs/tables/02_department_coverage.csv'
(HEADER, DELIMITER ',');
