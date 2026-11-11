
-- PROJECT 4: MARKETPLACE ECONOMICS & PROFITABILITY
-- SQL03: REVENUE ECONOMICS
-- Final population: 5 stores, 800 eligible retail SKUs

-- 1. Portfolio revenue overview

COPY (
    SELECT
        COUNT(DISTINCT STORE_ID) AS stores,
        COUNT(DISTINCT PRODUCT_ID) AS active_skus,
        COUNT(*) AS transaction_lines,
        COUNT(DISTINCT BASKET_ID) AS contributing_baskets,
        ROUND(SUM(SALES_VALUE), 2) AS observed_sales,
        ROUND(
            SUM(SALES_VALUE) /
            NULLIF(COUNT(DISTINCT BASKET_ID), 0), 2
        ) AS sales_per_contributing_basket,
        MIN(DAY) AS first_day,
        MAX(DAY) AS last_day
    FROM model_transactions
) TO 'outputs/tables/03_revenue_overview.csv'
(HEADER, DELIMITER ',');


-- 2. Store revenue performance

CREATE OR REPLACE VIEW revenue_03_store_metrics AS
SELECT
    STORE_ID,
    COUNT(*) AS transaction_lines,
    COUNT(DISTINCT BASKET_ID) AS contributing_baskets,
    COUNT(DISTINCT PRODUCT_ID) AS active_skus,
    COUNT(DISTINCT DAY) AS active_days,
    ROUND(SUM(SALES_VALUE), 2) AS observed_sales,
    ROUND(
        SUM(SALES_VALUE) /
        NULLIF(COUNT(DISTINCT BASKET_ID), 0), 2
    ) AS sales_per_contributing_basket,
    ROUND(
        SUM(SALES_VALUE) /
        NULLIF(COUNT(DISTINCT DAY), 0), 2
    ) AS sales_per_active_day
FROM model_transactions
GROUP BY STORE_ID;

COPY (
    SELECT *
    FROM revenue_03_store_metrics
    ORDER BY observed_sales DESC
) TO 'outputs/tables/03_store_revenue.csv'
(HEADER, DELIMITER ',');


-- 3. Department revenue contribution

COPY (
    SELECT
        p.DEPARTMENT,
        COUNT(DISTINCT t.PRODUCT_ID) AS active_skus,
        COUNT(DISTINCT t.BASKET_ID) AS contributing_baskets,
        ROUND(SUM(t.SALES_VALUE), 2) AS observed_sales,
        ROUND(
            100.0 * SUM(t.SALES_VALUE) /
            NULLIF(
                (SELECT SUM(SALES_VALUE)
                 FROM model_transactions), 0
            ), 2
        ) AS revenue_share_pct
    FROM model_transactions t
    JOIN products p
        ON t.PRODUCT_ID = p.PRODUCT_ID
    GROUP BY p.DEPARTMENT
    ORDER BY observed_sales DESC
) TO 'outputs/tables/03_department_revenue.csv'
(HEADER, DELIMITER ',');


-- 4. Selected-portfolio basket economics

CREATE OR REPLACE VIEW revenue_03_basket_metrics AS
SELECT
    STORE_ID,
    BASKET_ID,
    COUNT(*) AS portfolio_lines,
    COUNT(DISTINCT PRODUCT_ID) AS portfolio_unique_skus,
    SUM(QUANTITY) AS recorded_units,
    ROUND(SUM(SALES_VALUE), 2) AS portfolio_basket_sales
FROM model_transactions
GROUP BY STORE_ID, BASKET_ID;

COPY (
    SELECT *
    FROM revenue_03_basket_metrics
    ORDER BY portfolio_basket_sales DESC
) TO 'outputs/tables/03_basket_economics.csv'
(HEADER, DELIMITER ',');
