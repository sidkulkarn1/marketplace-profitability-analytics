-- 1. Select one provisional store per sales tier

CREATE OR REPLACE TABLE candidate_five_stores AS
WITH ranked AS (
    SELECT
        STORE_ID,
        sales_tier,
        net_sales,
        baskets,
        active_days,
        active_skus,
        ROW_NUMBER() OVER (
            PARTITION BY sales_tier
            ORDER BY active_days DESC,
                     baskets DESC,
                     STORE_ID
        ) AS selection_rank
    FROM eligible_store_profiles
)
SELECT
    STORE_ID,
    sales_tier,
    net_sales,
    baskets,
    active_days,
    active_skus
FROM ranked
WHERE selection_rank = 1;


-- 2. Filter transactions to candidate stores

CREATE OR REPLACE VIEW candidate_transactions AS
SELECT t.*
FROM transactions t
JOIN candidate_five_stores s
    ON t.STORE_ID = s.STORE_ID;


-- 3. Calculate product sales across five stores

CREATE OR REPLACE VIEW candidate_sku_sales AS
SELECT
    PRODUCT_ID,
    ROUND(SUM(SALES_VALUE), 2) AS sku_sales,
    SUM(QUANTITY) AS units_sold,
    COUNT(DISTINCT STORE_ID) AS stores_selling,
    COUNT(*) AS transaction_lines
FROM candidate_transactions
GROUP BY PRODUCT_ID;


-- 4. Rank SKUs by sales contribution

CREATE OR REPLACE VIEW candidate_sku_rankings AS
SELECT
    *,
    ROW_NUMBER() OVER (
        ORDER BY sku_sales DESC, PRODUCT_ID
    ) AS sku_rank
FROM candidate_sku_sales;


-- 5. Export provisional stores

COPY (
    SELECT *
    FROM candidate_five_stores
    ORDER BY sales_tier DESC
) TO 'outputs/tables/01c_candidate_stores.csv'
(HEADER, DELIMITER ',');


-- 6. Export SKU rankings

COPY (
    SELECT *
    FROM candidate_sku_rankings
    ORDER BY sku_rank
) TO 'outputs/tables/01c_sku_rankings.csv'
(HEADER, DELIMITER ',');


-- 7. Test SKU coverage at three scope limits

COPY (
    WITH thresholds AS (
        SELECT UNNEST([300, 500, 800]) AS top_n
    )
    SELECT
        t.STORE_ID,
        th.top_n AS sku_scope,
        COUNT(DISTINCT t.PRODUCT_ID) AS total_active_skus,

        COUNT(DISTINCT CASE
            WHEN r.sku_rank <= th.top_n
            THEN t.PRODUCT_ID
        END) AS selected_active_skus,

        ROUND(SUM(t.SALES_VALUE), 2) AS total_sales,

        ROUND(SUM(CASE
            WHEN r.sku_rank <= th.top_n
            THEN t.SALES_VALUE
            ELSE 0
        END), 2) AS covered_sales,

        ROUND(
            100.0 * SUM(CASE
                WHEN r.sku_rank <= th.top_n
                THEN t.SALES_VALUE
                ELSE 0
            END) / NULLIF(SUM(t.SALES_VALUE), 0),
            2
        ) AS sales_coverage_pct

    FROM candidate_transactions t
    JOIN candidate_sku_rankings r
        ON t.PRODUCT_ID = r.PRODUCT_ID
    CROSS JOIN thresholds th

    GROUP BY t.STORE_ID, th.top_n
    ORDER BY th.top_n, t.STORE_ID

) TO 'outputs/tables/01c_sku_coverage.csv'
(HEADER, DELIMITER ',');
