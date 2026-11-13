"""Validate exported CSVs against the current database and financial identities."""
from pathlib import Path
import csv
import math
import duckdb

ROOT = Path(__file__).resolve().parents[1]

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def close(a, b, label, tolerance=0.021):
    require(math.isfinite(float(a)) and math.isfinite(float(b)) and
            abs(float(a)-float(b)) <= tolerance, f'{label}: {a} != {b}')

def main():
    db = ROOT / 'marketplace_profitability.duckdb'
    require(db.is_file(), f'Missing database: {db}')
    with duckdb.connect(str(db), read_only=True) as con:
        def scalar(q): return con.execute(q).fetchone()[0]
        data = {}
        keys = {'portfolio_kpis': None, 'store_profitability': ['STORE_ID'],
                'department_profitability': ['DEPARTMENT'], 'cost_breakdown': ['cost_component'],
                'scenario_comparison': ['scenario_id'], 'sensitivity_cases': ['case_name'],
                'sku_margin_leakage': ['PRODUCT_ID'],
                'store_department_profitability': ['STORE_ID', 'DEPARTMENT']}
        for name, key in keys.items():
            path = ROOT / 'outputs/tables' / f'08_{name}.csv'
            require(path.is_file(), f'Missing export: {path}')
            with path.open(newline='') as f: rows = list(csv.DictReader(f))
            require(bool(rows), f'Empty export: {name}')
            if key:
                require(len({tuple(r[k] for k in key) for r in rows}) == len(rows), f'Duplicate key: {name}')
            data[name] = rows
        p = data['portfolio_kpis'][0]
        require(len(data['portfolio_kpis']) == 1, 'Expected one KPI row')
        for field, expr in {'stores':'COUNT(DISTINCT STORE_ID)', 'skus':'COUNT(DISTINCT PRODUCT_ID)',
                            'transaction_lines':'COUNT(*)', 'revenue':'SUM(SALES_VALUE)',
                            'cogs':'SUM(modeled_cogs)', 'gross_profit':'SUM(modeled_gross_profit)',
                            'total_cost_to_serve':'SUM(modeled_cost_to_serve)',
                            'contribution_profit':'SUM(modeled_contribution_profit)'}.items():
            close(p[field], scalar(f'SELECT {expr} FROM cts_05_contribution'), field)
        close(p['revenue'], scalar('SELECT SUM(SALES_VALUE) FROM model_transactions'), 'source revenue')
        close(p['transaction_lines'], scalar('SELECT COUNT(*) FROM model_transactions'), 'source lines', 0)
        close(p['gross_profit'], float(p['revenue'])-float(p['cogs']), 'gross profit')
        close(p['contribution_profit'], float(p['gross_profit'])-float(p['total_cost_to_serve']), 'contribution')
        close(p['contribution_margin_pct'], 100*float(p['contribution_profit'])/float(p['revenue']), 'margin')
        require(scalar('SELECT SUM(unresolved_free_unit_line) FROM unit_04_line_financials') == 0, 'Unresolved free units')
        require(scalar('SELECT COUNT(*)-COUNT(DISTINCT PRODUCT_ID) FROM products') == 0, 'Duplicate product keys')
        # Independently reconcile each grouped row with unrounded transaction financials.
        for name, dimensions in [('store_profitability',['STORE_ID']), ('department_profitability',['DEPARTMENT']),
                                 ('store_department_profitability',['STORE_ID','DEPARTMENT'])]:
            expected = con.execute(f"SELECT {', '.join(dimensions)}, SUM(SALES_VALUE), SUM(modeled_cost_to_serve), SUM(modeled_contribution_profit) FROM cts_05_contribution GROUP BY {', '.join(dimensions)}").fetchall()
            lookup = {tuple(str(v) for v in row[:len(dimensions)]): row[len(dimensions):] for row in expected}
            require(len(data[name]) == len(lookup), f'Incomplete groups: {name}')
            for row in data[name]:
                values = lookup[tuple(row[k] for k in dimensions)]
                for col,val in zip(['revenue','cost_to_serve','contribution_profit'], values): close(row[col], val, f'{name}.{col}')
                close(row['contribution_margin_pct'], 100*values[2]/values[0], f'{name}.margin')
        components = {'Inbound Freight':'modeled_inbound_freight','Picking':'modeled_picking_cost',
                      'Basket Handling':'allocated_basket_handling','Shrink':'modeled_shrink_cost'}
        require({r['cost_component'] for r in data['cost_breakdown']} == set(components), 'Cost components')
        totals={k:scalar(f'SELECT SUM({v}) FROM cts_05_contribution') for k,v in components.items()}
        for row in data['cost_breakdown']:
            close(row['modeled_cost'], totals[row['cost_component']], 'component cost')
        close(sum(totals.values()), p['total_cost_to_serve'], 'component total')
        assumptions=con.execute('SELECT * FROM scenario_07_assumptions ORDER BY scenario_id').fetchall()
        scenarios={r['scenario_id']:r for r in data['scenario_comparison']}
        require(set(scenarios)=={r[0] for r in assumptions}, 'Scenario coverage')
        savings={}
        baseline=scalar('SELECT SUM(modeled_contribution_profit) FROM cts_05_contribution')
        revenue=scalar('SELECT SUM(SALES_VALUE) FROM model_transactions')
        for sid, name, freight, picking, handling, shrink in assumptions:
            s=sum(totals[k]*float(rate) for k,rate in zip(components,[freight,picking,handling,shrink]))
            savings[sid]=s
            row=scenarios[sid]
            close(row['total_savings'],s, f'{sid} savings')
            close(row['scenario_contribution_profit'],baseline+s,f'{sid} profit')
            close(row['scenario_cost_to_serve'],sum(totals.values())-s,f'{sid} costs')
            close(row['revenue'],revenue,f'{sid} revenue')
            close(row['scenario_margin_pct'],100*(baseline+s)/revenue,f'{sid} margin')
        close(savings['S04'],sum(savings[s] for s in ['S01','S02','S03']), 'additive savings')
        factors={'Conservative':0.5,'Expected':1.0,'Optimistic':1.2}
        require({r['case_name'] for r in data['sensitivity_cases']}==set(factors), 'Sensitivity coverage')
        for row in data['sensitivity_cases']:
            factor=factors[row['case_name']]
            close(row['realization_factor'],factor,'realization',0)
            close(row['implementation_cost'],0,'implementation',0)
            for col in ['gross_savings','net_savings']: close(row[col],savings['S04']*factor,col)
            close(row['contribution_profit'],baseline+savings['S04']*factor,'sensitivity profit')
        # SQL06's leakage population is deliberately filtered and limited.
        expected=con.execute('SELECT PRODUCT_ID, contribution_profit FROM profit_06_sku_profile WHERE transaction_lines >= 20 AND revenue >= 100 ORDER BY contribution_margin_pct, revenue DESC LIMIT 40').fetchall()
        require({r['PRODUCT_ID'] for r in data['sku_margin_leakage']}=={str(r[0]) for r in expected},'Leakage population')
        for pid,profit in expected:
            row=next(r for r in data['sku_margin_leakage'] if r['PRODUCT_ID']==str(pid))
            close(row['contribution_profit'],profit,'SKU profit')
        print('SQL08 DASHBOARD EXPORT CHECKS PASSED')
        print('Validated rows: '+', '.join(f'{k}={len(v)}' for k,v in data.items()))

if __name__ == '__main__':
    main()
