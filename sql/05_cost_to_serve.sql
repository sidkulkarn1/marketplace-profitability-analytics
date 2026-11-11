-- 1. Operating cost assumptions (USD)

CREATE OR REPLACE TABLE cts_05_parameters AS
SELECT
    0.06::DOUBLE AS inbound_freight_per_unit,
    0.12::DOUBLE AS picking_cost_per_line,
    0.60::DOUBLE AS shared_handling_per_basket;


-- 2. Department-level modeled shrink rates

CREATE OR REPLACE TABLE cts_05_shrink_rates AS
SELECT
    DEPARTMENT,
    CASE
        WHEN DEPARTMENT = 'PRODUCE' THEN 0.04
        WHEN DEPARTMENT = 'MEAT' THEN 0.025
        WHEN DEPARTMENT = 'MEAT-PCKGD' THEN 0.02
        WHEN DEPARTMENT = 'SEAFOOD' THEN 0.03
        WHEN DEPARTMENT = 'SEAFOOD-PCKGD' THEN 0.025
        WHEN DEPARTMENT = 'DELI' THEN 0.03
        WHEN DEPARTMENT = 'GROCERY' THEN 0.01
        ELSE 0.015
    END AS modeled_shrink_rate
FROM cogs_04_assumptions;


-- 3. Eligible retail revenue by complete observed basket
-- Use all eligible products, not just selected SKUs,
-- to allocate shared basket costs proportionally.

CREATE OR REPLACE VIEW cts_05_basket_sales AS
SELECT
    t.STORE_ID,
    t.BASKET_ID,
    SUM(GREATEST(t.SALES_VALUE, 0))
        AS eligible_basket_sales
FROM candidate_transactions t
JOIN products p
    ON t.PRODUCT_ID = p.PRODUCT_ID
WHERE p.DEPARTMENT IS NOT NULL
  AND p.DEPARTMENT NOT IN (
      'KIOSK-GAS',
      'MISC SALES TRAN'
  )
GROUP BY t.STORE_ID, t.BASKET_ID;


-- 4. Calculate cost-to-serve components per line

CREATE OR REPLACE VIEW cts_05_line_costs AS
SELECT
    u.*,

    GREATEST(u.QUANTITY, 0)
        * a.inbound_freight_per_unit
        AS modeled_inbound_freight,

    CASE
        WHEN u.QUANTITY > 0 OR u.SALES_VALUE > 0
        THEN a.picking_cost_per_line
        ELSE 0
    END AS modeled_picking_cost,

    CASE
        WHEN b.eligible_basket_sales > 0
         AND u.SALES_VALUE > 0
        THEN a.shared_handling_per_basket
             * u.SALES_VALUE
             / b.eligible_basket_sales
        ELSE 0
    END AS allocated_basket_handling,

    u.modeled_cogs * s.modeled_shrink_rate
        AS modeled_shrink_cost

FROM unit_04_line_financials u
JOIN cts_05_basket_sales b
    ON u.STORE_ID = b.STORE_ID
   AND u.BASKET_ID = b.BASKET_ID
JOIN cts_05_shrink_rates s
    ON u.DEPARTMENT = s.DEPARTMENT
CROSS JOIN cts_05_parameters a;


-- 5. Calculate total cost-to-serve and contribution

CREATE OR REPLACE VIEW cts_05_contribution AS
SELECT
    *,
    (
        modeled_inbound_freight
        + modeled_picking_cost
        + allocated_basket_handling
        + modeled_shrink_cost
    ) AS modeled_cost_to_serve,

    modeled_gross_profit
        - modeled_inbound_freight
        - modeled_picking_cost
        - allocated_basket_handling
        - modeled_shrink_cost
        AS modeled_contribution_profit
FROM cts_05_line_costs;


-- 6. Portfolio contribution summary

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
) TO 'outputs/tables/05_cost_to_serve_summary.csv'
(HEADER, DELIMITER ',');


-- 7. Store-level financial comparison

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
) TO 'outputs/tables/05_store_profitability.csv'
(HEADER, DELIMITER ',');


-- 8. Department-level cost and profitability

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
) TO 'outputs/tables/05_department_profitability.csv'
(HEADER, DELIMITER ',');


-- 9. Export cost assumptions for financial model

COPY (
    SELECT *
    FROM cts_05_parameters
) TO 'outputs/tables/05_cost_parameters.csv'
(HEADER, DELIMITER ',');

COPY (
    SELECT *
    FROM cts_05_shrink_rates
    ORDER BY DEPARTMENT
) TO 'outputs/tables/05_shrink_assumptions.csv'
(HEADER, DELIMITER ',');
