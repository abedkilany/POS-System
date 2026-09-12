#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def read(rel):
    return (ROOT / rel).read_text(encoding='utf-8')

checks = []

def check(name, condition):
    checks.append((name, bool(condition)))
    print(('PASS' if condition else 'FAIL'), name)

pricing = read('lib/data/app_store_pricing_costing.dart')
purchases = read('lib/data/app_store_purchases.dart')
manufacturing = read('lib/data/app_store_manufacturing.dart')
products = read('lib/features/products/products_page.dart')
sales = read('lib/features/sales/sales_page.dart')
dashboard_store = read('lib/core/storage/sqlite/business_sqlite_store.dart')
sync_apply = read('lib/data/app_store_sync_apply.dart')

check('product cost snapshot API exists', 'ProductCostSnapshot' in read('lib/data/app_store.dart'))
check('current inventory cost is weighted from remaining batches',
      'SUM(bb.quantity * b.unit_cost)' in pricing and 'carryingValue) / quantity' in pricing)
check('virtual deficit batches excluded from current cost',
      "b.source_type <> 'inventory_deficit'" in pricing and "b.id NOT LIKE 'deficit:%'" in pricing)
check('last purchase cost comes from effective purchase receipt',
      "b.source_type = 'purchase'" in pricing and "sm.movement_type = 'purchase_receive'" in pricing)
check('purchase receipt does not overwrite product reference cost',
      'Product.cost/originalCost/usdCost are the user-maintained reference cost.' in purchases)
check('manufacturing output keeps reference cost independent',
      'Keep the product reference cost user-maintained and independent.' in manufacturing)
check('manufacturing estimator uses unified batch balances',
      'previewUnifiedAllocationInTransaction' in manufacturing and 'inventory_batch_balances' in manufacturing)
check('products UI shows current, last purchase and reference cost',
      "tr.text('current_inventory_cost')" in products and
      "tr.text('last_purchase_cost_label')" in products and
      "tr.text('reference_cost')" in products)
check('sales profit preview resolves expected unified batch cost',
      '_refreshInvoiceBatchCostPreview' in sales and 'estimatedUnifiedBatchUnitCostForProduct' in sales)
check('dashboard valuation uses batch carrying value',
      'SUM(bb.quantity * b.unit_cost)' in dashboard_store and "b.source_type <> 'inventory_deficit'" in dashboard_store)
check('remote purchase movement does not overwrite reference cost',
      'reference cost. Inventory valuation is carried by batches.' in sync_apply)

failed = [name for name, ok in checks if not ok]
print(f'\nRESULT: {len(checks)-len(failed)}/{len(checks)} checks passed')
if failed:
    raise SystemExit(1)
