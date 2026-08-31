# Production Phase 9 — Multi-Warehouse + Manufacturing + Traceability

Status: implemented on top of the P0–P8 production baseline.

## Goal

Phase 9 closes the physical inventory chain so that Ventio can answer, from the
same authoritative SQLite data that drives stock and accounting:

- where every batch currently exists;
- where that batch came from;
- which warehouses it crossed;
- which manufacturing order consumed it;
- which finished batches were produced from it;
- which raw batches produced a finished batch;
- which later sales/transfers/manufacturing movements used the batch;
- whether warehouse aggregate quantity still equals the sum of batch balances.

The implementation deliberately **does not create a second mutable lineage
ledger**. Traceability is derived from the existing authoritative records:

- `inventory_batches` — immutable batch/source identity and actual batch cost;
- `inventory_batch_balances` — current batch quantity by warehouse;
- `warehouse_inventory` — authoritative aggregate quantity by warehouse;
- `stock_movements` — batch-addressed physical movement history;
- `manufacturing_orders` — production document and frozen production costs.

This avoids a second graph that could drift away from the actual inventory
ledger.

## New production traceability service

`lib/core/services/inventory_traceability_service.dart`

### Batch trace graph

`traceBatch(...)` starts from one batch and returns:

- batch metadata and current balances in every warehouse;
- every stock movement for that batch;
- purchase/manufacturing origin references;
- warehouse-transfer references;
- sale references;
- upstream raw batches for a manufactured output;
- downstream finished batches when the batch is consumed by manufacturing;
- recursive manufacturing lineage with a bounded depth.

Manufacturing edges are derived from the shared manufacturing-order reference:
input `manufacturing_consume` movements point to their consumed batch, while
output batches use `source_type = manufacturing_output` and the same order id.

Public AppStore entry points were added:

- `traceInventoryBatch(...)`
- `verifyInventoryTraceabilityIntegrity()`

Both require inventory-movement view permission and authoritative SQLite.

## Transaction-time transfer closure

Every production warehouse transfer already keeps the exact same batch id when
moving quantity from source warehouse to destination warehouse. Phase 9 adds an
additional transaction-time invariant after the movement rows are persisted:

- each transferred batch has one source and one destination warehouse;
- transfer-out quantity exactly offsets transfer-in quantity;
- transfer-out carrying value exactly equals transfer-in carrying value;
- batch identity is present on every new post-cutover transfer slice.

If this invariant fails, the surrounding SQLite transaction throws and rolls
back instead of committing an untraceable transfer.

This protection is applied to both:

- single-product `transferStock(...)`;
- multi-product `createWarehouseTransferOrder(...)`.

## Transaction-time manufacturing closure

Manufacturing was already Unified-Batch based and used FEFO for expiry-tracked
materials / oldest received batch first for non-expiry materials. Phase 9 keeps
those allocation contracts as explicit acceptance requirements and adds a final
traceability/cost-conservation assertion before manufacturing commit.

For every completed manufacturing order it verifies:

- consumed material movements carry valid batch ids;
- output movements carry valid batch ids;
- movement batch product identity matches `inventory_batches`;
- consumed batch value equals the order's frozen material cost;
- output movement quantity equals actual production quantity;
- output movement value equals eligible production cost;
- `material cost - waste cost = eligible output cost`;
- output batches exist with `source_type = manufacturing_output`;
- output batch initial quantity and value reconcile to the manufacturing order.

A failure rolls back stock, batches, manufacturing order and accounting journal
through the Phase 7 transaction boundary.

## Integrity audit for P10/P11

`verifyInventoryTraceabilityIntegrity()` provides a read-only report designed to
feed the Phase 10 Health Dashboard and the Phase 11 Final Production Gate. It
checks:

1. `warehouse_inventory` quantity equals summed batch balances per
   store/warehouse/product.
2. Batch balances are not orphaned, negative or over-reserved.
3. Batch product/store identity matches its balance rows.
4. Product expiry policy matches current positive-stock batch expiry data.
   Ventio also blocks switching expiry tracking on or off while positive stock
   still exists under the previous policy.
5. Batch-addressed stock movements reference a real batch of the same product.
6. Post-Unified-Batch transfers cannot lose batch identity.
7. Transfer quantity and carrying value are conserved per batch.
8. Unified-Batch-era completed manufacturing orders reconcile their material
   cost, waste, output quantity, output value and output batches.

Legacy pre-cutover transfer history is not falsely classified as a Phase 9
failure merely because it predates Unified Batch identity.

## Trace query indexes

SQLite schema version is now `31` and adds indexes for the two dominant lineage
queries:

- `idx_stock_movements_reference_type_batch`
- `idx_inventory_batches_source_trace`

These support manufacturing ancestor/descendant tracing without scanning the
entire movement history.

## Deferred executable acceptance test

The final test stage now includes:

`test/production_phase9_multi_warehouse_manufacturing_traceability_test.dart`

Its scenario creates two expiry raw batches, verifies FEFO identity through a
warehouse transfer, manufactures a finished batch from the earlier raw batch,
transfers the finished batch to retail, traces the finished batch back to its
raw ancestor, and requires the Phase 9 integrity report to be healthy.

A lightweight static contract test is also present:

`test/production_phase9_traceability_contract_test.dart`

Per project policy, the full Flutter test suite and `flutter analyze` remain
deferred until the final release-test stage.

## Backup / restore / sync continuity

Phase 9 deliberately derives lineage from data that Ventio already treats as authoritative and portable. Unified snapshots/backups carry `stockMovements`, `inventoryBatches`, `inventoryBatchBalances`, and `manufacturingOrders`; restore reconstructs those same collections. Direct synchronization likewise applies `stock_movement`, `inventory_batch`, and `manufacturing_order` entities. Therefore traceability is not a local-only feature and does not depend on a second lineage store that could be omitted from backup or drift on a client device.

