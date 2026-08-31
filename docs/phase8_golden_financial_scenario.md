# Production Phase 8 — Golden Financial Scenario

Status: implemented on top of the P0–P7 production baseline.

> This production-roadmap Phase 8 is separate from older internal test/file names
> such as `accounting_phase8_*` and `cash_phase8_*` already present in Ventio.

## Goal

Ventio now has one deterministic financial reference scenario whose expected
ending balances are known before the test runs. The purpose is not merely to
prove that individual functions return successfully; it is to prove that the
whole accounting + cash + VAT + inventory chain closes to the same numbers.

The canonical expected values are stored in:

`test/fixtures/production_phase8_golden_financial_expected.json`

The executable scenario is:

`test/production_phase8_golden_financial_scenario_test.dart`

## Canonical scenario

The fixture uses USD and a 10% tax-inclusive standard VAT profile plus an exempt
profile. It performs all business mutations through production application
paths; direct SQL is read-only evidence after the business actions.

1. Record $200 opening cash with an owner-capital journal basis.
2. Open the production cash drawer at $200.
3. Receive the main credit purchase:
   - 10 standard-VAT units at $11 gross = $110 gross / $100 inventory / $10 input VAT.
   - 10 exempt units at $5 = $50 inventory.
   - Main purchase total = $160; inventory GL = $150; input VAT = $10.
4. Receive and fully return a second VAT purchase before any downstream batch
   movement. Its purchase and reversal must net to zero.
5. Pay $60 to the supplier in cash.
6. Create a credit sale:
   - 4 standard-VAT units at $22 = $88 gross.
   - 2 exempt units at $10 = $20 gross.
   - Gross subtotal = $108.
   - Gross document discount = $10.80.
   - Net sales before discount = $100.
   - Net sales discount = $10.
   - Output VAT after discount = $7.20.
   - Customer receivable = $97.20.
   - COGS = $50.
7. Collect $40 from the customer in cash.
8. Return one standard-VAT sale unit:
   - Customer credit = $19.80.
   - Sales return net = $18.
   - Output VAT reversal = $1.80.
   - COGS reversal = $10.
9. Post a $12 cash rent expense.

## Golden ending balances

| Measure | Expected |
| --- | ---: |
| Cash | $168.00 |
| Accounts receivable | $37.40 |
| Accounts payable | $100.00 credit |
| Inventory | $110.00 |
| Input VAT | $10.00 debit |
| Output VAT | $5.40 credit |
| Standard product quantity | 7 |
| Exempt product quantity | 8 |
| Standard inventory unit cost | $10.00 |
| Exempt inventory unit cost | $5.00 |
| Net sales | $72.00 |
| Net COGS | $40.00 |
| Gross profit | $32.00 |
| Operating expense | $12.00 |
| Net income | $20.00 |
| Total assets | $325.40 |
| Liabilities | $105.40 |
| Equity | $200.00 |
| Retained earnings | $20.00 |
| Balance sheet difference | $0.00 |

The scenario also requires total posted journal debits to equal total posted
journal credits and requires the Unified Batch inventory subledger value to
reconcile to the inventory GL balance at $110.

## VAT inventory-cost closure discovered by the golden scenario

Phase 8 review exposed a material mismatch in the purchase path: the purchase
journal correctly debited inventory at the tax-exclusive taxable base and input
VAT separately, while Unified Batch/product cost preview still used the gross
VAT-inclusive purchase cost.

That meant a recoverable VAT amount could enter batch cost and later COGS even
though the same VAT had already been recorded as an input-tax asset.

`app_store_purchases.dart` now derives the inventory cost per base unit from the
same tax treatment used by the posted document:

- standard recoverable VAT -> inventory receives the taxable base only;
- zero-rated/exempt -> inventory receives the complete line amount;
- legacy tax configuration -> the historical default VAT fallback is honored.

The normalized cost is used for both product-cost previews and every Unified
Batch purchase receipt/repost path. The golden test explicitly asserts that an
$11 VAT-inclusive standard purchase creates a $10 batch unit cost.

## Acceptance contract

Phase 8 is accepted only when the deferred final test stage eventually runs the
executable golden scenario successfully. A passing result means all of the
following agree simultaneously:

- posted-document frozen VAT facts;
- purchase and sales journals;
- payment vouchers and cash balance;
- customer/supplier control accounts;
- sale-return accounting;
- expense posting;
- warehouse quantities;
- Unified Batch quantities and costs;
- inventory subledger valuation;
- trial-balance debit/credit equality;
- profit math;
- the production income-statement report;
- the production balance-sheet report and zero balance-sheet difference.

## Validation policy for this build

Per the project decision, full `flutter analyze` and the full Flutter test suite
remain deferred until the final testing stage. Phase 8 adds an executable golden
scenario plus a lightweight static verifier. The static verifier proves that the
contract and fixture are present; it does not replace executing the Flutter test.
