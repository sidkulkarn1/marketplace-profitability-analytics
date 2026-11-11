-- 1. Define illustrative department-level cost ratios

CREATE OR REPLACE TABLE cogs_04_assumptions AS
SELECT DISTINCT
    p.DEPARTMENT,
    CASE
        WHEN p.DEPARTMENT = 'GROCERY' THEN 0.72
        WHEN p.DEPARTMENT = 'MEAT' THEN 0.74
        WHEN p.DEPARTMENT = 'PRODUCE' THEN 0.65
        WHEN p.DEPARTMENT = 'DRUG GM' THEN 0.63
        WHEN p.DEPARTMENT = 'MEAT-PCKGD' THEN 0.72
        WHEN p.DEPARTMENT = 'DELI' THEN 0.67
        WHEN p.DEPARTMENT = 'SEAFOOD' THEN 0.74
        WHEN p.DEPARTMENT = 'SEAFOOD-PCKGD' THEN 0.74
        ELSE 0.70
    END AS modeled_cogs_ratio
FROM model_skus s
JOIN products p
    ON s.PRODUCT_ID = p.PRODUCT_ID;


-- 2. Estimate a reference unit price for each SKU
-- Median observed net selling price per unit.
-- This is a proxy, not an actual list price.

CREATE OR REPLACE VIEW unit_04_reference_prices AS
SELECT
    PRODUCT_ID,
    MEDIAN(
        SALES_VALUE / NULLIF(QUANTITY, 0)
    ) AS reference_unit_price
FROM model_transactions
WHERE SALES_VALUE > 0
  AND QUANTITY > 0
GROUP BY PRODUCT_ID;


-- 3. Build modeled transaction-level financials

CREATE OR REPLACE VIEW unit_04_line_financials AS
WITH base AS (
    SELECT
        t.STORE_ID,
        t.BASKET_ID,
        t.PRODUCT_ID,
        t.DAY,
        t.QUANTITY,
        t.SALES_VALUE,
        p.DEPARTMENT,
        a.modeled_cogs_ratio,
        r.reference_unit_price,

        CASE
            WHEN t.QUANTITY > 0
                 AND r.reference_unit_price IS NOT NULL
            THEN t.QUANTITY
                 * r.reference_unit_price
                 * a.modeled_cogs_ratio

            WHEN t.SALES_VALUE > 0
            THEN t.SALES_VALUE
                 * a.modeled_cogs_ratio

            ELSE 0.0
        END AS modeled_cogs,

        CASE
            WHEN t.QUANTITY > 0
                 AND t.SALES_VALUE = 0
                 AND r.reference_unit_price IS NULL
            THEN 1
            ELSE 0
        END AS unresolved_free_unit_line

    FROM model_transactions t
    JOIN products p
        ON t.PRODUCT_ID = p.PRODUCT_ID
    JOIN cogs_04_assumptions a
        ON p.DEPARTMENT = a.DEPARTMENT
    LEFT JOIN unit_04_reference_prices r
        ON t.PRODUCT_ID = r.PRODUCT_ID
)
SELECT
    *,
    SALES_VALUE - modeled_cogs
        AS modeled_gross_profit
FROM base;


-- 4. Portfolio financial reconciliation

COPY (
    SELECT
        COUNT(DISTINCT STORE_ID) AS stores,
        COUNT(DISTINCT PRODUCT_ID) AS skus,
        COUNT(*) AS transaction_lines,

        ROUND(SUM(SALES_VALUE), 2)
            AS observed_revenue,

        ROUND(SUM(modeled_cogs), 2)
            AS modeled_cogs,

        ROUND(SUM(modeled_gross_profit), 2)
            AS modeled_gross_profit,

        ROUND(
            100.0 * SUM(modeled_gross_profit)
            / NULLIF(SUM(SALES_VALUE), 0), 2
        ) AS modeled_gross_margin_pct,

        ROUND(
            SUM(SALES_VALUE)
            - SUM(modeled_cogs)
            - SUM(modeled_gross_profit), 6
        ) AS reconciliation_gap,

        SUM(unresolved_free_unit_line)
            AS unresolved_free_unit_lines

    FROM unit_04_line_financials
) TO 'outputs/tables/04_unit_economics_summary.csv'
(HEADER, DELIMITER ',');


-- 5. Department-level financial performance

COPY (
    SELECT
        DEPARTMENT,
        COUNT(DISTINCT PRODUCT_ID) AS active_skus,
        ROUND(MAX(modeled_cogs_ratio), 4)
            AS assumed_cogs_ratio,

        ROUND(SUM(SALES_VALUE), 2) AS revenue,
        ROUND(SUM(modeled_cogs), 2) AS modeled_cogs,
        ROUND(SUM(modeled_gross_profit), 2)
            AS modeled_gross_profit,

        ROUND(
            100.0 * SUM(modeled_gross_profit)
            / NULLIF(SUM(SALES_VALUE), 0), 2
        ) AS modeled_gross_margin_pct

    FROM unit_04_line_financials
    GROUP BY DEPARTMENT
    ORDER BY modeled_gross_profit DESC
) TO 'outputs/tables/04_department_unit_economics.csv'
(HEADER, DELIMITER ',');


-- 6. Store-level financial performance

COPY (
    SELECT
        STORE_ID,
        COUNT(DISTINCT PRODUCT_ID) AS active_skus,
        ROUND(SUM(SALES_VALUE), 2) AS revenue,
        ROUND(SUM(modeled_cogs), 2) AS modeled_cogs,
        ROUND(SUM(modeled_gross_profit), 2)
            AS modeled_gross_profit,

        ROUND(
            100.0 * SUM(modeled_gross_profit)
            / NULLIF(SUM(SALES_VALUE), 0), 2
        ) AS modeled_gross_margin_pct

    FROM unit_04_line_financials
    GROUP BY STORE_ID
    ORDER BY modeled_gross_profit DESC
) TO 'outputs/tables/04_store_unit_economics.csv'
(HEADER, DELIMITER ',');


-- 7. Export assumed department cost ratios

COPY (
    SELECT *
    FROM cogs_04_assumptions
    ORDER BY DEPARTMENT
) TO 'outputs/tables/04_cogs_assumptions.csv'
(HEADER, DELIMITER ',');
