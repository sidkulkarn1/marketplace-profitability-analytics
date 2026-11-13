# Data dictionary

## Source and grain
Dunnhumby Complete Journey CSVs supplied locally through Kaggle. The exact Kaggle download URL/version was not recorded in the repository; confirm it before public publication. Only `transaction_data.csv` and `product.csv` are loaded by SQL01; other raw files are preserved. A transaction row is a source line, not a guaranteed unique basket/SKU pair. Monetary fields are interpreted as USD; dates remain relative dataset days.

### `transactions` — `data/raw/transaction_data.csv`

| Field | DuckDB type | Meaning / use |
|---|---|---|
| household_key | BIGINT | Participating household identifier; not used as a profitability grouping. |
| BASKET_ID | BIGINT | Observed basket identifier; handling joins on STORE_ID plus BASKET_ID. |
| DAY | BIGINT | Relative dataset day, not a calendar date. |
| PRODUCT_ID | BIGINT | SKU join key to products; expected unique in products, repeated in transactions. |
| QUANTITY | BIGINT | Recorded units; do not assume comparable physical size across SKUs. |
| SALES_VALUE | DOUBLE | Observed revenue used directly; discounts are not subtracted again. |
| STORE_ID | BIGINT | Store identifier; numeric code, not a measured quantity. |
| RETAIL_DISC | DOUBLE | Source retail discount field; retained, not separately modeled. |
| TRANS_TIME | VARCHAR | Source transaction time stored as text; not used in cost models. |
| WEEK_NO | BIGINT | Relative dataset week. |
| COUPON_DISC | DOUBLE | Source coupon discount; retained, not separately modeled. |
| COUPON_MATCH_DISC | DOUBLE | Source coupon-match discount; retained, not separately modeled. |

### `products` — `data/raw/product.csv`

| Field | DuckDB type | Meaning / use |
|---|---|---|
| PRODUCT_ID | BIGINT | SKU join key to products; expected unique in products, repeated in transactions. |
| MANUFACTURER | BIGINT | Source manufacturer identifier. |
| DEPARTMENT | VARCHAR | Department used for portfolio eligibility and cost assumptions. |
| BRAND | VARCHAR | Source brand classification. |
| COMMODITY_DESC | VARCHAR | Commodity description used in SKU diagnostics. |
| SUB_COMMODITY_DESC | VARCHAR | More detailed commodity classification. |
| CURR_SIZE_OF_PRODUCT | VARCHAR | Source product size text; not converted to standardized units. |

## Relationships and lineage
`transactions.PRODUCT_ID → products.PRODUCT_ID` is many-to-one. SQL01 profiles unmatched and duplicate keys. `model_stores` identifies the five selected stores; `model_skus` contains 800 distinct eligible products after SQL02c. `model_transactions` filters source lines to these stores and products. `unit_04_line_financials` attaches department ratios and SKU reference prices; `cts_05_contribution` adds operating costs and contribution. `scenario_07_financials` has store × department × scenario grain. Never join it to baseline lines without filtering/aggregating a scenario first.

## Dashboard exports
All paths below are in `outputs/tables/`, with prefix `08_` and suffix `.csv`.

| Export | Grain / key | Source and use |
|---|---|---|
| portfolio_kpis | One row | SQL05 contribution totals, distinct stores/SKUs, lines and reconciliation gap |
| store_profitability | STORE_ID | SQL05 revenue, COGS, gross profit, cost-to-serve, contribution and margin |
| department_profitability | DEPARTMENT | SQL05 revenue, COGS, cost-to-serve, contribution and margin |
| cost_breakdown | cost_component | SQL06 four components, cost share and percent of revenue |
| scenario_comparison | scenario_id | SQL07 five scenarios with savings, baseline and scenario costs/profit/margins |
| sensitivity_cases | case_name | Combined SQL07 savings at 0.5, 1.0 and 1.2 realization; zero implementation cost |
| sku_margin_leakage | PRODUCT_ID | SQL06: >=20 lines, >=$100 revenue, lowest-margin 40; not the entire portfolio |
| store_department_profitability | STORE_ID + DEPARTMENT | SQL06 active SKUs, revenue, cost-to-serve, contribution and margin |

## Derived field conventions
- `revenue` / `observed_revenue`: sum of SALES_VALUE; `cogs` / `modeled_cogs`: assumed acquisition cost; `gross_profit`: revenue minus COGS.
- `inbound_freight`, `picking_cost`, `basket_handling`, `shrink_cost`: modeled operating components; `cost_to_serve` / `total_cost_to_serve`: their sum.
- `contribution_profit`: gross profit minus cost-to-serve; `*_margin_pct`: profit / revenue ×100. A zero denominator yields null, not zero.
- `stores`, `skus`, `active_skus`: distinct counts in the row's scope; `transaction_lines`: source line count. Distinct counts are not additive.
- `reconciliation_gap`: gross profit minus operating costs minus contribution profit; expected zero within numerical tolerance.
- `modeled_cost`, `cost_share_pct`, `cost_pct_revenue`: component dollars, share of total operating cost, and component / revenue ×100.
- `total_savings`: gross savings before implementation; `scenario_cost_to_serve`: baseline cost less savings; `scenario_contribution_profit`: baseline profit plus savings; `margin_improvement_pp`: savings / revenue ×100 percentage points.
- `realization_factor`: decimal multiplier; `gross_savings`: combined savings × realization; `implementation_cost`: 0 in SQL08; `net_savings`: gross less implementation cost.
- `margin_flag`: Negative Contribution if profit <0, Low Margin if margin <10%, otherwise Other. The filtered bottom-40 can include Other.

Amounts are rounded to cents after aggregation; percent values use a 0–100 scale. Calculate aggregate margins from dollars, not averages of row margins. Summing rounded grouped amounts can differ slightly from a rounded portfolio total. Sensitivity cases and scenarios repeat the same baseline population and must not be added together.
