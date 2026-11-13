# Methodology and reproduction

## Scope and selection
Dunnhumby Complete Journey transaction data, obtained through Kaggle, represents participating households, not full-store financials. SQL01 profiles the source. SQL01b screens stores for at least 10,000 lines, 500 active days, first day <=30 and last day >=680, then assigns five revenue tiers. SQL01c selects one store per tier by active days, baskets, then store ID. SQL02 initially tests 800 SKUs; SQL02b reviews exceptions. SQL02c is the authoritative final scope: exclude null departments, KIOSK-GAS and MISC SALES TRAN, rank eligible SKU revenue across the five stores, then select the top 800 (product ID breaks ties).

The final portfolio contains 44,595 lines and $133,573.76 observed revenue: 38.25% of eligible retail sales and 35.88% of all observed five-store sales. Earlier 01/02 exports describe provisional populations and should not be substituted for SQL02c results.

## Financial pipeline
- SQL03: revenue, basket, store and department metrics.
- SQL04: median positive sales per positive unit by SKU; illustrative department COGS ratios; transaction gross profit. All scoped lines remain, including zero sales/quantity.
- SQL05: freight on nonnegative quantities, picking on positive-quantity or positive-sales lines, shrink on modeled COGS. Handling uses positive eligible revenue in the complete observed store/basket as its denominator, including products outside the 800-SKU portfolio.
- SQL06: contribution reconciliation, cost mix, store/department analysis and filtered SKU leakage.
- SQL07: baseline plus four interventions. Unrounded cost components drive savings; export rounding occurs after aggregation.
- SQL08: eight dashboard CSVs from the existing database, without changing persistent tables or views. Sensitivity adds 50%, 100% and 120% realization of combined gross savings, with zero implementation cost.

See [financial assumptions](financial_assumptions.md) for formulas and limitations and [data dictionary](data_dictionary.md) for grains and fields. Margins are revenue-weighted ratios of sums; never sum percentages or distinct SKU/basket counts across groups. Scenario revenue repeats for each scenario and must not be summed across scenarios.

## Run against the existing database
From the repository root, with the existing virtual environment:

```sh
.venv/bin/python scripts/run_sql.py sql/08_dashboard_exports.sql
.venv/bin/python scripts/validate_08_exports.py
```

The runner changes its working directory to the project root. SQL08 replaces only its own eight `outputs/tables/08_*.csv` files. Keep SQL01–07 unchanged when refreshing these exports.

## Rebuild from raw data (optional)
Python 3 and DuckDB are required. Create an environment with `python3 -m venv .venv`, then install DuckDB with `.venv/bin/python -m pip install duckdb`. Place `transaction_data.csv` and `product.csv` in `data/raw/`; raw data is intentionally excluded from Git. Create `outputs/tables/` if absent. Run the following scripts through `scripts/run_sql.py` in this exact order:

1. `01_data_profiling.sql`
2. `01b_store_selection.sql`
3. `01c_sku_coverage.sql`
4. `02_data_validation.sql`
5. `02b_product_scope_review.sql`
6. `02c_finalize_portfolio.sql`
7. `03_revenue_economics.sql`
8. `04_unit_economics.sql`
9. `05_cost_to_serve.sql`
10. `06_contribution_profitability.sql`
11. `07_scenario_analysis.sql`
12. `08_dashboard_exports.sql`

A full rebuild replaces database objects and earlier exports; back up meaningful local work first. Do not run scripts concurrently against the database.

## Validation
`validate_08_exports.py` opens the database read-only and checks file presence, nonempty results, unique keys, complete grouped populations, source revenue/line counts, product-key uniqueness, unresolved free units, financial identities, grouped financials, four cost components, scenario savings derived directly from baseline costs and assumptions, additive combined savings, sensitivity cases and the SQL06 leakage population. Monetary comparisons allow $0.021 for cent rounding. Counts and fixed sensitivity parameters are checked exactly where specified. Failures exit nonzero; successful completion prints `SQL08 DASHBOARD EXPORT CHECKS PASSED`.

This validates SQL exports against the current database; it does not prove the economic assumptions or independently audit Excel formulas. The three existing workbooks are preserved, not refreshed by SQL08.
