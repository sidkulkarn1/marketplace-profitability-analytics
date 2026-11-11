-- 1. Measure product department diversity

CREATE OR REPLACE VIEW store_department_diversity AS
SELECT
    t.STORE_ID,
    COUNT(DISTINCT p.DEPARTMENT) AS departments
FROM transactions t
JOIN products p
    ON t.PRODUCT_ID = p.PRODUCT_ID
GROUP BY t.STORE_ID;


-- 2. Build eligible store profiles

CREATE OR REPLACE VIEW eligible_store_profiles AS
WITH eligible AS (
    SELECT
        s.STORE_ID,
        s.transaction_lines,
        s.baskets,
        s.active_skus,
        s.active_days,
        s.first_day,
        s.last_day,
        s.net_sales,
        d.departments,

        ROUND(
            s.net_sales / NULLIF(s.baskets, 0), 2
        ) AS sales_per_basket,

        ROUND(
            s.net_sales / NULLIF(s.active_days, 0), 2
        ) AS sales_per_active_day

    FROM store_coverage s
    LEFT JOIN store_department_diversity d
        ON s.STORE_ID = d.STORE_ID

    WHERE s.transaction_lines >= 10000
      AND s.active_days >= 500
      AND s.first_day <= 30
      AND s.last_day >= 680
)
SELECT
    *,
    NTILE(5) OVER (
        ORDER BY net_sales
    ) AS sales_tier
FROM eligible;


-- 3. Export all eligible stores

COPY (
    SELECT *
    FROM eligible_store_profiles
    ORDER BY net_sales DESC
) TO 'outputs/tables/01_store_selection_profile.csv'
(HEADER, DELIMITER ',');


-- 4. Shortlist three stores per sales tier

COPY (
    SELECT *
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY sales_tier
                ORDER BY active_days DESC, baskets DESC
            ) AS tier_rank
        FROM eligible_store_profiles
    ) ranked
    WHERE tier_rank <= 3
    ORDER BY sales_tier DESC, tier_rank
) TO 'outputs/tables/01_store_shortlist.csv'
(HEADER, DELIMITER ',');
