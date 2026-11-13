-- Dashboard exports from the existing SQL01-07 database. Run from project root.
-- SELECT/COPY only: no persistent tables or views are changed.
-- Monetary values: USD, rounded only after aggregation; *_pct: 0-100.
-- Sensitivity inputs are illustrative, with zero implementation cost.
-- SKU leakage is a filtered top-40 diagnostic, not an additive portfolio total.

-- portfolio_kpis
COPY (
SELECT
        COUNT(DISTINCT STORE_ID) AS stores,
        COUNT(DISTINCT PRODUCT_ID) AS skus,
        COUNT(*) AS transaction_lines,

        ROUND(SUM(SALES_VALUE), 2) AS revenue,
        ROUND(SUM(modeled_cogs), 2) AS cogs,
        ROUND(SUM(modeled_gross_profit), 2)
            AS gross_profit,

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
            100.0 * SUM(modeled_contribution_profit)
            / NULLIF(SUM(SALES_VALUE), 0), 2
        ) AS contribution_margin_pct,

        ROUND(
            SUM(modeled_gross_profit)
            - SUM(modeled_cost_to_serve)
            - SUM(modeled_contribution_profit), 6
        ) AS reconciliation_gap

    FROM cts_05_contribution
) TO 'outputs/tables/08_portfolio_kpis.csv' (HEADER, DELIMITER ',');

-- store_profitability
COPY (
SELECT
        STORE_ID,
        ROUND(SUM(SALES_VALUE), 2) AS revenue,
        ROUND(SUM(modeled_cogs), 2) AS cogs,
        ROUND(SUM(modeled_gross_profit), 2)
            AS gross_profit,
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
    ORDER BY contribution_profit DESC
) TO 'outputs/tables/08_store_profitability.csv' (HEADER, DELIMITER ',');

-- department_profitability
COPY (
SELECT
        DEPARTMENT,
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
    GROUP BY DEPARTMENT
    ORDER BY contribution_profit DESC
) TO 'outputs/tables/08_department_profitability.csv' (HEADER, DELIMITER ',');

-- cost_breakdown
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
) TO 'outputs/tables/08_cost_breakdown.csv' (HEADER, DELIMITER ',');

-- scenario_comparison
COPY (
WITH totals AS (
        SELECT
            scenario_id,
            scenario_name,
            SUM(revenue) AS revenue,
            SUM(gross_profit) AS gross_profit,
            SUM(baseline_cost_to_serve) AS baseline_cost,
            SUM(total_savings) AS savings,
            SUM(baseline_contribution_profit) AS baseline_profit,
            SUM(scenario_contribution_profit) AS scenario_profit
        FROM scenario_07_financials
        GROUP BY scenario_id, scenario_name
    )
    SELECT
        scenario_id,
        scenario_name,
        ROUND(revenue, 2) AS revenue,
        ROUND(gross_profit, 2) AS gross_profit,
        ROUND(baseline_cost, 2) AS baseline_cost_to_serve,
        ROUND(savings, 2) AS total_savings,
        ROUND(baseline_cost - savings, 2)
            AS scenario_cost_to_serve,
        ROUND(baseline_profit, 2)
            AS baseline_contribution_profit,
        ROUND(scenario_profit, 2)
            AS scenario_contribution_profit,

        ROUND(
            100.0 * scenario_profit /
            NULLIF(revenue, 0), 2
        ) AS scenario_margin_pct,

        ROUND(
            100.0 * savings /
            NULLIF(revenue, 0), 2
        ) AS margin_improvement_pp

    FROM totals
    ORDER BY scenario_id
) TO 'outputs/tables/08_scenario_comparison.csv' (HEADER, DELIMITER ',');

-- sku_margin_leakage
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
) TO 'outputs/tables/08_sku_margin_leakage.csv' (HEADER, DELIMITER ',');

-- store_department_profitability
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
) TO 'outputs/tables/08_store_department_profitability.csv' (HEADER, DELIMITER ',');

-- sensitivity_cases
COPY (
WITH combined AS (
 SELECT SUM(total_savings) AS gross_savings,
 SUM(baseline_contribution_profit) AS baseline_profit, SUM(revenue) AS revenue
 FROM scenario_07_financials WHERE scenario_id = 'S04'
), cases AS (
 SELECT * FROM (VALUES ('Conservative',0.50),('Expected',1.00),('Optimistic',1.20))
 AS v(case_name, realization_factor)
)
SELECT case_name, realization_factor,
 ROUND(revenue,2) AS revenue,
 ROUND(gross_savings * realization_factor,2) AS gross_savings,
 0.00 AS implementation_cost,
 ROUND(gross_savings * realization_factor,2) AS net_savings,
 ROUND(baseline_profit + gross_savings * realization_factor,2) AS contribution_profit,
 ROUND(100.0 * (baseline_profit + gross_savings * realization_factor) / NULLIF(revenue,0),2) AS contribution_margin_pct
FROM combined CROSS JOIN cases ORDER BY realization_factor
) TO 'outputs/tables/08_sensitivity_cases.csv' (HEADER, DELIMITER ',');
