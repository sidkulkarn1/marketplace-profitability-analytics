-- 1. Consolidated portfolio financial baseline

CREATE OR REPLACE VIEW profit_06_baseline AS
SELECT
    COUNT(DISTINCT STORE_ID) AS stores,
    COUNT(DISTINCT PRODUCT_ID) AS skus,
    COUNT(*) AS transaction_lines,
    ROUND(SUM(SALES_VALUE), 2) AS revenue,
    ROUND(SUM(modeled_cogs), 2) AS cogs,
    ROUND(SUM(modeled_gross_profit), 2) AS gross_profit,
    ROUND(SUM(modeled_cost_to_serve), 2) AS cost_to_serve,
    ROUND(SUM(modeled_contribution_profit), 2)
        AS contribution_profit,
    ROUND(
        100.0 * SUM(modeled_contribution_profit)
        / NULLIF(SUM(SALES_VALUE), 0), 2
    ) AS contribution_margin_pct,
    ROUND(
        SUM(modeled_gross_profit)
        - SUM(modeled_cost_to_serve)
        - SUM(modeled_contribution_profit), 6
    ) AS reconciliation_gap
FROM cts_05_contribution;

COPY (
    SELECT *
    FROM profit_06_baseline
) TO 'outputs/tables/06_baseline_reconciliation.csv'
(HEADER, DELIMITER ',');


-- 2. Rank store contribution profitability

CREATE OR REPLACE VIEW profit_06_store_ranking AS
WITH store_metrics AS (
    SELECT
        STORE_ID,
        COUNT(DISTINCT PRODUCT_ID) AS active_skus,
        ROUND(SUM(SALES_VALUE), 2) AS revenue,
        ROUND(SUM(modeled_cogs), 2) AS cogs,
        ROUND(SUM(modeled_cost_to_serve), 2)
            AS cost_to_serve,
        ROUND(SUM(modeled_contribution_profit), 2)
            AS contribution_profit,
        ROUND(
            100.0 * SUM(modeled_contribution_profit)
            / NULLIF(SUM(SALES_VALUE), 0), 2
        ) AS contribution_margin_pct
    FROM cts_05_contribution
    GROUP BY STORE_ID
)
SELECT
    *,
    ROUND(
        contribution_margin_pct -
        (SELECT contribution_margin_pct
         FROM profit_06_baseline), 2
    ) AS margin_vs_portfolio_pp,
    ROW_NUMBER() OVER (
        ORDER BY contribution_margin_pct DESC, STORE_ID
    ) AS margin_rank
FROM store_metrics;

COPY (
    SELECT *
    FROM profit_06_store_ranking
    ORDER BY margin_rank
) TO 'outputs/tables/06_store_profitability_ranking.csv'
(HEADER, DELIMITER ',');


-- 3. Department-level cost drivers

COPY (
    SELECT
        DEPARTMENT,
        COUNT(DISTINCT PRODUCT_ID) AS active_skus,
        ROUND(SUM(SALES_VALUE), 2) AS revenue,
        ROUND(SUM(modeled_cogs), 2) AS cogs,
        ROUND(SUM(modeled_gross_profit), 2) AS gross_profit,

        ROUND(SUM(modeled_inbound_freight), 2)
            AS inbound_freight,
        ROUND(SUM(modeled_picking_cost), 2)
            AS picking_cost,
        ROUND(SUM(allocated_basket_handling), 2)
            AS basket_handling,
        ROUND(SUM(modeled_shrink_cost), 2)
            AS shrink_cost,

        ROUND(SUM(modeled_cost_to_serve), 2)
            AS total_cost_to_serve,
        ROUND(SUM(modeled_contribution_profit), 2)
            AS contribution_profit,

        ROUND(
            100.0 * SUM(modeled_cost_to_serve)
            / NULLIF(SUM(SALES_VALUE), 0), 2
        ) AS cost_to_serve_pct_revenue,

        ROUND(
            100.0 * SUM(modeled_contribution_profit)
            / NULLIF(SUM(SALES_VALUE), 0), 2
        ) AS contribution_margin_pct

    FROM cts_05_contribution
    GROUP BY DEPARTMENT
    ORDER BY total_cost_to_serve DESC

) TO 'outputs/tables/06_department_cost_drivers.csv'
(HEADER, DELIMITER ',');


-- 4. Identify low-margin and loss-making SKUs

CREATE OR REPLACE VIEW profit_06_sku_profile AS
SELECT
    t.PRODUCT_ID,
    p.DEPARTMENT,
    p.COMMODITY_DESC,
    COUNT(*) AS transaction_lines,
    ROUND(SUM(t.SALES_VALUE), 2) AS revenue,
    ROUND(SUM(t.modeled_cogs), 2) AS cogs,
    ROUND(SUM(t.modeled_cost_to_serve), 2)
        AS cost_to_serve,
    ROUND(SUM(t.modeled_contribution_profit), 2)
        AS contribution_profit,
    ROUND(
        100.0 * SUM(t.modeled_contribution_profit)
        / NULLIF(SUM(t.SALES_VALUE), 0), 2
    ) AS contribution_margin_pct
FROM cts_05_contribution t
JOIN products p
    ON t.PRODUCT_ID = p.PRODUCT_ID
GROUP BY
    t.PRODUCT_ID,
    p.DEPARTMENT,
    p.COMMODITY_DESC;

-- Minimum volume filters avoid ranking
-- extremely small, noisy product observations.

COPY (
    SELECT
        *,
        CASE
            WHEN contribution_profit < 0
                THEN 'Negative Contribution'
            WHEN contribution_margin_pct < 10
                THEN 'Low Margin'
            ELSE 'Other'
        END AS margin_flag
    FROM profit_06_sku_profile
    WHERE transaction_lines >= 20
      AND revenue >= 100
    ORDER BY contribution_margin_pct ASC, revenue DESC
    LIMIT 40

) TO 'outputs/tables/06_sku_margin_leakage.csv'
(HEADER, DELIMITER ',');


-- 5. Store-by-department profitability

COPY (
    SELECT
        STORE_ID,
        DEPARTMENT,
        COUNT(DISTINCT PRODUCT_ID) AS active_skus,
        ROUND(SUM(SALES_VALUE), 2) AS revenue,
        ROUND(SUM(modeled_cost_to_serve), 2)
            AS cost_to_serve,
        ROUND(SUM(modeled_contribution_profit), 2)
            AS contribution_profit,
        ROUND(
            100.0 * SUM(modeled_contribution_profit)
            / NULLIF(SUM(SALES_VALUE), 0), 2
        ) AS contribution_margin_pct

    FROM cts_05_contribution
    GROUP BY STORE_ID, DEPARTMENT
    ORDER BY STORE_ID, contribution_profit DESC

) TO 'outputs/tables/06_store_department_profitability.csv'
(HEADER, DELIMITER ',');


-- 6. Portfolio cost-component breakdown

COPY (
    WITH components AS (
        SELECT 'Inbound Freight' AS cost_component,
            SUM(modeled_inbound_freight) AS modeled_cost
        FROM cts_05_contribution

        UNION ALL

        SELECT 'Picking',
            SUM(modeled_picking_cost)
        FROM cts_05_contribution

        UNION ALL

        SELECT 'Basket Handling',
            SUM(allocated_basket_handling)
        FROM cts_05_contribution

        UNION ALL

        SELECT 'Shrink',
            SUM(modeled_shrink_cost)
        FROM cts_05_contribution
    )
    SELECT
        cost_component,
        ROUND(modeled_cost, 2) AS modeled_cost,
        ROUND(
            100.0 * modeled_cost /
            NULLIF(
                (SELECT SUM(modeled_cost_to_serve)
                 FROM cts_05_contribution), 0
            ), 2
        ) AS cost_share_pct,
        ROUND(
            100.0 * modeled_cost /
            NULLIF(
                (SELECT SUM(SALES_VALUE)
                 FROM cts_05_contribution), 0
            ), 2
        ) AS cost_pct_revenue
    FROM components
    ORDER BY modeled_cost DESC

) TO 'outputs/tables/06_cost_component_breakdown.csv'
(HEADER, DELIMITER ',');
