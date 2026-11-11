-- 1. Define scenario assumptions

CREATE OR REPLACE TABLE scenario_07_assumptions AS
SELECT *
FROM (VALUES
    ('BASE', 'Baseline', 0.00, 0.00, 0.00, 0.00),
    ('S01', 'Freight Consolidation', 0.10, 0.00, 0.00, 0.00),
    ('S02', 'Shrink Reduction', 0.00, 0.00, 0.00, 0.15),
    ('S03', 'Fulfillment Efficiency', 0.00, 0.10, 0.05, 0.00),
    ('S04', 'Combined Strategy', 0.10, 0.10, 0.05, 0.15)
) AS v(
    scenario_id,
    scenario_name,
    freight_reduction,
    picking_reduction,
    handling_reduction,
    shrink_reduction
);


-- 2. Aggregate current financial baseline
-- Preserve unrounded values for accurate modeling.

CREATE OR REPLACE VIEW scenario_07_base AS
SELECT
    STORE_ID,
    DEPARTMENT,
    SUM(SALES_VALUE) AS revenue,
    SUM(modeled_gross_profit) AS gross_profit,
    SUM(modeled_inbound_freight) AS freight_cost,
    SUM(modeled_picking_cost) AS picking_cost,
    SUM(allocated_basket_handling) AS handling_cost,
    SUM(modeled_shrink_cost) AS shrink_cost
FROM cts_05_contribution
GROUP BY STORE_ID, DEPARTMENT;


-- 3. Calculate savings by operating intervention

CREATE OR REPLACE VIEW scenario_07_savings AS
SELECT
    b.*,
    s.scenario_id,
    s.scenario_name,

    b.freight_cost * s.freight_reduction
        AS freight_savings,

    b.picking_cost * s.picking_reduction
        AS picking_savings,

    b.handling_cost * s.handling_reduction
        AS handling_savings,

    b.shrink_cost * s.shrink_reduction
        AS shrink_savings

FROM scenario_07_base b
CROSS JOIN scenario_07_assumptions s;


-- 4. Build scenario financial results

CREATE OR REPLACE VIEW scenario_07_financials AS
SELECT
    *,
    (
        freight_savings
        + picking_savings
        + handling_savings
        + shrink_savings
    ) AS total_savings,

    (
        freight_cost
        + picking_cost
        + handling_cost
        + shrink_cost
    ) AS baseline_cost_to_serve,

    gross_profit - (
        freight_cost
        + picking_cost
        + handling_cost
        + shrink_cost
    ) AS baseline_contribution_profit,

    gross_profit - (
        freight_cost
        + picking_cost
        + handling_cost
        + shrink_cost
    ) + (
        freight_savings
        + picking_savings
        + handling_savings
        + shrink_savings
    ) AS scenario_contribution_profit

FROM scenario_07_savings;


-- 5. Export editable scenario assumptions

COPY (
    SELECT *
    FROM scenario_07_assumptions
    ORDER BY scenario_id
) TO 'outputs/tables/07_scenario_assumptions.csv'
(HEADER, DELIMITER ',');


-- 6. Compare baseline and improvement scenarios

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
) TO 'outputs/tables/07_scenario_comparison.csv'
(HEADER, DELIMITER ',');


-- 7. Store-level scenario impact

COPY (
    SELECT
        scenario_id,
        scenario_name,
        STORE_ID,
        ROUND(SUM(revenue), 2) AS revenue,
        ROUND(SUM(total_savings), 2) AS savings,
        ROUND(SUM(baseline_contribution_profit), 2)
            AS baseline_profit,
        ROUND(SUM(scenario_contribution_profit), 2)
            AS scenario_profit,
        ROUND(
            100.0 * SUM(scenario_contribution_profit)
            / NULLIF(SUM(revenue), 0), 2
        ) AS scenario_margin_pct
    FROM scenario_07_financials
    GROUP BY scenario_id, scenario_name, STORE_ID
    ORDER BY scenario_id, STORE_ID
) TO 'outputs/tables/07_store_scenario_impact.csv'
(HEADER, DELIMITER ',');


-- 8. Savings by operating cost category

COPY (
    WITH components AS (
        SELECT
            scenario_id,
            'Inbound Freight' AS cost_component,
            SUM(freight_savings) AS savings
        FROM scenario_07_financials
        GROUP BY scenario_id

        UNION ALL

        SELECT
            scenario_id, 'Picking',
            SUM(picking_savings)
        FROM scenario_07_financials
        GROUP BY scenario_id

        UNION ALL

        SELECT
            scenario_id, 'Basket Handling',
            SUM(handling_savings)
        FROM scenario_07_financials
        GROUP BY scenario_id

        UNION ALL

        SELECT
            scenario_id, 'Shrink',
            SUM(shrink_savings)
        FROM scenario_07_financials
        GROUP BY scenario_id
    )
    SELECT
        scenario_id,
        cost_component,
        ROUND(savings, 2) AS modeled_savings
    FROM components
    ORDER BY scenario_id, cost_component
) TO 'outputs/tables/07_cost_savings_bridge.csv'
(HEADER, DELIMITER ',');


-- 9. Department-level scenario impact

COPY (
    SELECT
        scenario_id,
        scenario_name,
        DEPARTMENT,
        ROUND(SUM(revenue), 2) AS revenue,
        ROUND(SUM(total_savings), 2) AS savings,
        ROUND(SUM(scenario_contribution_profit), 2)
            AS scenario_profit,
        ROUND(
            100.0 * SUM(scenario_contribution_profit)
            / NULLIF(SUM(revenue), 0), 2
        ) AS scenario_margin_pct
    FROM scenario_07_financials
    GROUP BY scenario_id, scenario_name, DEPARTMENT
    ORDER BY scenario_id, savings DESC
) TO 'outputs/tables/07_department_scenario_impact.csv'
(HEADER, DELIMITER ',');
