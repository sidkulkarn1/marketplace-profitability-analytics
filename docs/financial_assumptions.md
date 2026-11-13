# Financial Assumptions & Modeling Methodology

**Project:** Marketplace Economics & Profitability Analytics
**Dataset:** Dunnhumby — The Complete Journey
**Primary Tools:** SQL (DuckDB), Microsoft Excel
**Model Type:** Retail unit economics, cost-to-serve, and contribution profitability

## 1. Project Scope

This project evaluates retail profitability using observed transaction data and simulated supply chain operating costs.

The analytical population consists of five selected stores and 800 retail SKUs, chosen through transaction coverage, store activity, and product revenue analysis.

| Metric | Value |
|---|---:|
| Selected Stores | 5 |
| Selected Retail SKUs | 800 |
| Transaction Lines | 44,595 |
| Observed Portfolio Revenue | $133,573.76 |
| Coverage of Eligible Retail Sales | 38.25% |
| Coverage of All Observed Five-Store Sales | 35.88% |

The modeled portfolio excludes the `KIOSK-GAS` and `MISC SALES TRAN` departments to better represent grocery and convenience retail economics.

**Scope limitation:** Dunnhumby contains transactions from participating households, not complete store-level financial records. Results describe the selected transaction sample and SKU portfolio rather than full-store profitability.

## 2. Revenue Assumptions

Observed revenue is calculated directly from the dataset's `SALES_VALUE` field.

**Revenue = SUM(SALES_VALUE)**

Transaction records with zero revenue are retained for reconciliation. Positive-quantity, zero-sales transactions may still incur modeled acquisition and operating costs.

Revenue figures are historical observations from the dataset and are not annualized or projected.

## 3. Cost of Goods Sold (COGS)

The dataset does not provide supplier purchase prices or actual product acquisition costs.

To estimate COGS, the model uses illustrative department-level cost ratios and reference unit selling prices derived from observed transactions.

| Department | Assumed COGS Ratio |
|---|---:|
| Grocery | 72% |
| Meat | 74% |
| Produce | 65% |
| Drug GM | 63% |
| Meat-Pckgd | 72% |
| Deli | 67% |
| Seafood | 74% |
| Seafood-Pckgd | 74% |
| Other Departments | 70% |

For each SKU, a reference unit price is estimated using the median positive observed sales value per recorded unit.

**Reference Unit Price = Median(SALES_VALUE / QUANTITY)**

For positive-quantity transactions with an available reference price:

**Modeled COGS = Quantity × Reference Unit Price × Department COGS Ratio**

For positive-sales transactions that do not meet the positive-quantity/reference-price condition, the model uses sales value multiplied by the assumed department COGS ratio.

These prices are proxies rather than supplier costs. Estimated COGS may therefore differ from applying a fixed ratio directly to total recorded revenue.

## 4. Operating Cost-to-Serve Assumptions

The model estimates four operating expense categories.

| Cost Component | Assumption | Calculation |
|---|---|---|
| Inbound Freight | $0.06 per recorded unit | MAX(Quantity, 0) × $0.06 |
| Picking | $0.12 per qualifying transaction line | Qualifying lines × $0.12 |
| Basket Handling | $0.60 per eligible basket | Allocated by eligible basket revenue share |
| Inventory Shrink | Department-specific | Modeled COGS × Shrink Rate |

Picking costs apply to transaction lines with positive quantity or positive sales.

Shared handling costs are allocated proportionally to eligible positive-revenue transaction lines within each basket, including the selected portfolio's appropriate share. This avoids assigning the full basket-handling cost to every SKU.

### Inventory Shrink Assumptions

| Department | Assumed Shrink Rate |
|---|---:|
| Produce | 4.00% |
| Meat | 2.50% |
| Meat-Pckgd | 2.00% |
| Seafood | 3.00% |
| Seafood-Pckgd | 2.50% |
| Deli | 3.00% |
| Grocery | 1.00% |
| Other Departments | 1.50% |

These rates are hypothetical model inputs, not observed losses or verified industry benchmarks.

## 5. Contribution Profitability Methodology

The financial model distinguishes gross profitability from contribution profitability.

**Modeled Gross Profit = Observed Revenue − Modeled COGS**

**Modeled Cost-to-Serve = Inbound Freight + Picking + Basket Handling + Inventory Shrink**

**Modeled Contribution Profit = Modeled Gross Profit − Modeled Cost-to-Serve**

**Contribution Margin = Modeled Contribution Profit / Observed Revenue**

### Validated Baseline Financial Results

| Financial Metric | Amount |
|---|---:|
| Observed Revenue | $133,573.76 |
| Modeled COGS | $93,541.83 |
| Modeled Gross Profit | $40,031.93 |
| Inbound Freight | $3,450.00 |
| Picking Costs | $5,332.80 |
| Basket Handling | $3,650.00 |
| Inventory Shrink | $1,630.30 |
| Total Modeled Cost-to-Serve | $14,063.10 |
| **Modeled Contribution Profit** | **$25,968.83** |
| **Modeled Contribution Margin** | **19.44%** |

The baseline reconciles across the SQL unit economics, cost-to-serve, and contribution profitability models.

## 6. Financial Scenario Assumptions

Four hypothetical intervention strategies are evaluated against the baseline.

| Strategy | Illustrative Intervention |
|---|---|
| Freight Consolidation | Reduce inbound freight expenses by 10% |
| Inventory Shrink Controls | Reduce shrink expenses by 15% |
| Fulfillment Efficiency | Reduce picking costs by 10% and basket handling by 5% |
| Combined Strategy | Apply all three interventions |

Scenario savings are calculated by applying the assumed reduction percentages to their corresponding baseline operating-cost components.

The scenarios assume unchanged transaction revenue, product mix, and COGS. Improvements are additive and do not incorporate interaction effects between interventions.

### Modeled Scenario Outcomes

| Scenario | Gross Savings | Contribution Profit |
|---|---:|---:|
| Baseline | $0.00 | $25,968.83 |
| Freight Consolidation | $345.00 | $26,313.83 |
| Shrink Reduction | $244.55 | $26,213.37 |
| Fulfillment Efficiency | $715.78 | $26,684.61 |
| Combined Strategy | $1,305.33 | $27,274.15 |

The combined strategy produces an illustrative contribution-margin increase from 19.44% to 20.42%, approximately **0.98 percentage points**.

These improvements are hypothetical scenario outputs, not realized or operationally validated savings.

## 7. Implementation Costs and Sensitivity Analysis

The Excel financial model includes editable implementation-cost inputs.

**Net Savings = Gross Savings − Implementation Costs**

**Scenario Contribution Profit = Baseline Contribution Profit + Net Savings**

Implementation costs are currently set to $0 in the reference model to preserve comparability with SQL07.

The sensitivity model evaluates the realization of combined gross savings under three hypothetical cases:

| Case | Assumed Savings Realization |
|---|---:|
| Conservative | 50% |
| Expected | 100% |
| Optimistic | 120% |

These represent illustrative outcomes, not statistical confidence intervals or probability-weighted forecasts.

Implementation costs would need to be estimated over a consistent operating period before evaluating investment returns or scaling decisions.

## 8. Financial Validation

The SQL pipeline includes reconciliation checks across the analytical stages.

Validation covers:

- Store, SKU, and transaction population consistency
- Revenue and modeled COGS reconciliation
- Gross profit and cost-to-serve reconciliation
- Contribution profit calculations
- Store-level financial aggregation
- Scenario savings calculations
- Combined versus individual intervention savings

Excel scenario calculations were also compared against SQL07 reference outputs, with minor rounding differences expected.

The earlier project conversation reported a successful financial audit. The reproducible check supplied in this repository is now `scripts/validate_08_exports.py`; it checks SQL08 against the current database. It does not independently audit the preserved Excel workbooks.

## 9. Modeling Limitations

The following limitations apply to the financial results:

- Retail transaction records represent sampled households rather than complete store sales.
- The 800-SKU portfolio captures only a portion of observed eligible retail revenue.
- Actual procurement, warehousing, and supplier cost records are unavailable.
- COGS, freight, labor, handling, and shrink expenses use illustrative assumptions.
- The model does not include last-mile delivery, payment processing, fixed facility costs, or corporate overhead.
- No operational pilot has validated the modeled cost improvements.
- Implementation costs and operational feasibility have not been independently established.
- Scenario results should not be interpreted as annual savings or actual DashMart profitability.

## 10. Intended Business Use

The model is designed to demonstrate how SQL and Excel can support structured supply chain profitability decisions.

It enables analysts to identify cost drivers, evaluate contribution margins, compare operating interventions, and quantify potential financial trade-offs.

The appropriate next business step would be to validate assumptions using actual operating data, pilot a targeted efficiency intervention, measure realized costs, and determine whether the results justify scaling.

---

**Disclaimer:** This is an independent academic and portfolio analysis using publicly available retail data. It is not affiliated with DoorDash or based on DoorDash's internal operating or financial records. All costs and profitability improvements are simulated.m

## SQL08 export assumptions

SQL08 mirrors the existing SQL05–07 financial calculations and adds three illustrative sensitivity cases. Its implementation cost is explicitly zero; it does not read editable Excel inputs. Workbook figures and inputs described above refer to the existing reference model and were not independently revalidated during the SQL08 update. Run `scripts/validate_08_exports.py` after each SQL08 refresh. Monetary values are rounded after aggregation, so displayed sums may differ by one cent.
