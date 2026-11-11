-- 1. Department revenue composition

COPY (
    SELECT
        p.DEPARTMENT,
        COUNT(DISTINCT t.PRODUCT_ID) AS selected_skus,
        COUNT(*) AS transaction_lines,
        ROUND(SUM(t.SALES_VALUE), 2) AS observed_sales,
        ROUND(
            100.0 * SUM(t.SALES_VALUE) /
            NULLIF(
                (SELECT SUM(SALES_VALUE)
                 FROM model_transactions), 0
            ), 2
        ) AS portfolio_sales_share_pct
    FROM model_transactions t
    JOIN products p
        ON t.PRODUCT_ID = p.PRODUCT_ID
    GROUP BY p.DEPARTMENT
    ORDER BY observed_sales DESC
) TO 'outputs/tables/02b_department_mix.csv'
(HEADER, DELIMITER ',');


-- 2. Top 30 products by observed revenue

COPY (
    SELECT
        t.PRODUCT_ID,
        p.DEPARTMENT,
        p.COMMODITY_DESC,
        p.SUB_COMMODITY_DESC,
        p.BRAND,
        COUNT(*) AS transaction_lines,
        SUM(t.QUANTITY) AS units_sold,
        ROUND(SUM(t.SALES_VALUE), 2) AS observed_sales
    FROM model_transactions t
    JOIN products p
        ON t.PRODUCT_ID = p.PRODUCT_ID
    GROUP BY
        t.PRODUCT_ID,
        p.DEPARTMENT,
        p.COMMODITY_DESC,
        p.SUB_COMMODITY_DESC,
        p.BRAND
    ORDER BY observed_sales DESC
    LIMIT 30
) TO 'outputs/tables/02b_top_products.csv'
(HEADER, DELIMITER ',');


-- 3. Classify transaction exceptions

COPY (
    SELECT
        CASE
            WHEN SALES_VALUE = 0 AND QUANTITY = 0
                THEN 'both_zero'
            WHEN SALES_VALUE = 0 AND QUANTITY > 0
                THEN 'zero_sales_positive_quantity'
            WHEN SALES_VALUE > 0 AND QUANTITY = 0
                THEN 'positive_sales_zero_quantity'
            WHEN SALES_VALUE > 0 AND QUANTITY > 0
                THEN 'normal_positive_line'
            ELSE 'other_or_missing'
        END AS line_classification,
        COUNT(*) AS transaction_lines,
        COUNT(DISTINCT PRODUCT_ID) AS affected_skus,
        ROUND(SUM(SALES_VALUE), 2) AS observed_sales
    FROM model_transactions
    GROUP BY 1
    ORDER BY transaction_lines DESC
) TO 'outputs/tables/02b_transaction_exceptions.csv'
(HEADER, DELIMITER ',');


-- 4. Examine questionable product departments

COPY (
    SELECT
        t.PRODUCT_ID,
        p.DEPARTMENT,
        p.COMMODITY_DESC,
        p.SUB_COMMODITY_DESC,
        COUNT(*) AS transaction_lines,
        ROUND(SUM(t.SALES_VALUE), 2) AS observed_sales
    FROM model_transactions t
    JOIN products p
        ON t.PRODUCT_ID = p.PRODUCT_ID
    WHERE p.DEPARTMENT IN (
        'KIOSK-GAS',
        'MISC SALES TRAN',
        'COSMETICS'
    )
    GROUP BY
        t.PRODUCT_ID,
        p.DEPARTMENT,
        p.COMMODITY_DESC,
        p.SUB_COMMODITY_DESC
    ORDER BY observed_sales DESC
) TO 'outputs/tables/02b_category_review.csv'
(HEADER, DELIMITER ',');
