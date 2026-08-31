#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PURCHASES = (ROOT / 'lib/data/app_store_purchases.dart').read_text(encoding='utf-8')
TEST = (ROOT / 'test/production_phase8_golden_financial_scenario_test.dart').read_text(encoding='utf-8')
FIXTURE_PATH = ROOT / 'test/fixtures/production_phase8_golden_financial_expected.json'
DOC = (ROOT / 'docs/phase8_golden_financial_scenario.md').read_text(encoding='utf-8')
FIXTURE = json.loads(FIXTURE_PATH.read_text(encoding='utf-8'))

scenario_start = TEST.find("test('production Phase 8 golden financial scenario closes to known balances'")
scenario_end = TEST.find("test('golden scenario uses application write paths and read-only SQL evidence'", scenario_start)
scenario_source = TEST[scenario_start:scenario_end] if scenario_start >= 0 and scenario_end > scenario_start else ''
forbidden_sql_writes = ('.customInsert(', '.customUpdate(', '.customDelete(', '.customStatement(', 'INSERT INTO ', 'UPDATE ', 'DELETE FROM ')

checks: list[tuple[str, bool]] = []

def check(name: str, condition: bool) -> None:
    checks.append((name, bool(condition)))

check('fixture schema is v1', FIXTURE.get('schemaVersion') == 1)
check('golden ending cash is 168', FIXTURE.get('endingCash') == 168.0)
check('golden ending AR is 37.4', FIXTURE.get('endingAccountsReceivable') == 37.4)
check('golden ending AP is 100', FIXTURE.get('endingAccountsPayable') == 100.0)
check('golden ending inventory is 110', FIXTURE.get('endingInventory') == 110.0)
check('golden net income is 20', FIXTURE.get('netIncome') == 20.0)
check('golden balance sheet closes to zero', FIXTURE.get('balanceSheetDifference') == 0.0)
check('golden assets are 325.4', FIXTURE.get('endingAssets') == 325.4)

calculated_cash = FIXTURE['openingCash'] - FIXTURE['supplierPayment'] + FIXTURE['customerReceipt'] - FIXTURE['cashExpense']
calculated_ar = FIXTURE['saleReceivable'] - FIXTURE['customerReceipt'] - FIXTURE['saleReturnGross']
calculated_inventory = FIXTURE['mainPurchaseInventoryNet'] - FIXTURE['saleCogsBeforeReturn'] + FIXTURE['saleReturnCogs']
calculated_net_sales = FIXTURE['saleRevenueBeforeDiscountNet'] - FIXTURE['saleDiscountNet'] - FIXTURE['saleReturnNet']
calculated_net_cogs = FIXTURE['saleCogsBeforeReturn'] - FIXTURE['saleReturnCogs']
calculated_net_income = calculated_net_sales - calculated_net_cogs - FIXTURE['operatingExpense']
check('golden arithmetic closes', all(abs(a-b) < 1e-9 for a,b in [
    (calculated_cash, FIXTURE['endingCash']),
    (calculated_ar, FIXTURE['endingAccountsReceivable']),
    (calculated_inventory, FIXTURE['endingInventory']),
    (calculated_net_sales, FIXTURE['netSales']),
    (calculated_net_cogs, FIXTURE['netCogs']),
    (calculated_net_income, FIXTURE['netIncome']),
]))
check('scenario contains a bounded source block', bool(scenario_source))
check('golden scenario SQL is read-only', bool(scenario_source) and not any(token in scenario_source for token in forbidden_sql_writes))
check('scenario creates and returns purchases', 'store.createPurchase(' in scenario_source and 'store.returnPurchase(' in scenario_source)
check('scenario settles supplier payment', 'store.settlePurchasePayment(' in scenario_source)
check('scenario creates sale with settlement and return', all(x in scenario_source for x in ['store.createSale(', 'store.settleSalePayment(', 'store.returnSale(']))
check('scenario posts cash expense', 'store.addOrUpdateExpense(' in scenario_source and 'store.postExpense(' in scenario_source)
check('opening cash has GL basis', 'AccountingService.recordOpeningCashLocationBalance(' in scenario_source)
check('scenario verifies drawer expected cash', 'calculateCashDrawerExpectedCash(' in scenario_source)
check('scenario reconciles batch subledger', 'inventory_batch_balances' in TEST and '_inventorySubledgerValue(' in scenario_source)
check('scenario verifies trial balance', 'SUM(jl.debit)' in scenario_source and 'SUM(jl.credit)' in scenario_source)
check('scenario verifies production financial reports', 'AccountingService.incomeStatementReport()' in scenario_source and 'AccountingService.balanceSheetReport()' in scenario_source)
check('purchase inventory cost uses tax-exclusive taxable base', 'return tax.taxableBase / item.baseQuantity;' in PURCHASES)
check('batch receipt accepts normalized inventory unit cost', 'required double inventoryUnitCost' in PURCHASES and 'unitCost: inventoryUnitCost' in PURCHASES)
check('all three purchase receipt/repost call sites pass normalized cost', PURCHASES.count('inventoryUnitCost: _purchaseInventoryUnitCostPerBase(') == 3)
check('product cost previews use normalized VAT cost', PURCHASES.count('final unitCost = _purchaseInventoryUnitCostPerBase(') == 2)
check('documentation records VAT/COGS closure', 'VAT inventory-cost closure discovered by the golden scenario' in DOC)
check('documentation records net income 20', '| Net income | $20.00 |' in DOC)

passed = sum(ok for _, ok in checks)
for name, ok in checks:
    print(f"{'PASS' if ok else 'FAIL'}  {name}")
print(f'\nPhase 8 static verification: {passed}/{len(checks)} PASS')
raise SystemExit(0 if passed == len(checks) else 1)
