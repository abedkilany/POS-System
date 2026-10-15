# Source File Index

This searchable catalog is generated from first-party source declarations and test names.
It covers `lib/`, `test/`, `integration_test/`, `server_api/`, `scripts/`, `tool/`, `database/`, and the root `server.js` entry point.
Platform scaffolding, root build configuration, and bundled assets are cataloged in [PLATFORM_INDEX.md](PLATFORM_INDEX.md).

Use search to open the matching row; the source file remains authoritative for behavior. Regenerate both catalogs after adding, removing, or renaming indexed files with `python tool/generate_project_file_index.py`.

## `database/`

| File | Contents / responsibility clue |
| --- | --- |
| [`rebuild_snapshots_from_events.sql`](../database/rebuild_snapshots_from_events.sql) | Rebuilds entity snapshots from retained sync events, including stock movements. |
| [`sync_backfill_from_events.sql`](../database/sync_backfill_from_events.sql) | Backfills entity snapshots from previously uploaded restore-snapshot events. |
| [`sync_schema.sql`](../database/sync_schema.sql) | Schema/migration SQL for `store_host_heartbeats`, `idx_store_host_heartbeats_latest`, `store_devices`, `idx_store_devices_latest`. |
| [`sync_v2_pairing.sql`](../database/sync_v2_pairing.sql) | Schema/migration SQL for `device_pairing_codes`, `idx_device_pairing_codes_store`, `idx_store_devices_auth`. |

## `integration_test/`

| File | Contents / responsibility clue |
| --- | --- |
| [`app_shell_flow_test.dart`](../integration_test/app_shell_flow_test.dart) | Tests 4 cases in groups ‘App shell integration flows’; examples: `compact layout opens drawer and navigates to inventory`, `Arabic locale uses RTL directionality for the shell`, `wide layout navigates through core business sections`, … (1 more). |

## `lib/`

| File | Contents / responsibility clue |
| --- | --- |
| [`app.dart`](../lib/app.dart) | Library entry; declares shared library definitions and composes parts `app_split_01.dart`, `app_split_02.dart`, `app_split_03.dart`. |
| [`app_split_01.dart`](../lib/app_split_01.dart) | Implementation part of `app.dart`; contains `_AutoSnapshotProgressState`, `VentioApp`, `createState`, `GlobalKey`, `Function`, `initState`, … (19 more). |
| [`app_split_02.dart`](../lib/app_split_02.dart) | Implementation part of `app.dart`; contains `Function`, `_editSaleShortcut`, `_buildSalesShortcutStrip`, `_handleStoreChanged`, `initState`, `didUpdateWidget`, … (12 more). |
| [`app_split_03.dart`](../lib/app_split_03.dart) | Implementation part of `app.dart`; contains `_NoAccessPage`, `build`, `_TransportSnapshot`, `_ConnectionStatusSnapshot`, `HostConnectionIndicator`, `createState`, … (20 more). |
| [`main.dart`](../lib/main.dart) | Flutter application entry point; initializes app services and launches the UI. |

## `lib/core/accounting/`

| File | Contents / responsibility clue |
| --- | --- |
| [`accounting_account_role.dart`](../lib/core/accounting/accounting_account_role.dart) | Declares `AccountingAccountRole`. |

## `lib/core/`

| File | Contents / responsibility clue |
| --- | --- |
| [`app_brand.dart`](../lib/core/app_brand.dart) | Declares `AppBrand`. |

## `lib/core/localization/`

| File | Contents / responsibility clue |
| --- | --- |
| [`app_localizations.dart`](../lib/core/localization/app_localizations.dart) | Declares `AppLocalizations`, `_AppLocalizationsDelegate`, `localizeRuntimeMessage`. |
| [`localized_domain_exception.dart`](../lib/core/localization/localized_domain_exception.dart) | Declares `LocalizedDomainException`, `localizedErrorText`. |

## `lib/core/money/`

| File | Contents / responsibility clue |
| --- | --- |
| [`money_value.dart`](../lib/core/money/money_value.dart) | Declares `MoneyValue`. |

## `lib/core/repositories/`

| File | Contents / responsibility clue |
| --- | --- |
| [`auth_repository.dart`](../lib/core/repositories/auth_repository.dart) | Declares `AuthRepository`. |
| [`business_repositories.dart`](../lib/core/repositories/business_repositories.dart) | Declares `ProductRepository`, `CustomerRepository`, `SupplierRepository`, `SaleRepository`, `ExpenseRepository`, … (4 more). |
| [`business_session_context.dart`](../lib/core/repositories/business_session_context.dart) | Declares `BusinessSessionContext`. |
| [`inventory_reconciliation_repository.dart`](../lib/core/repositories/inventory_reconciliation_repository.dart) | Declares `InventoryReconciliationRepository`. |
| [`warehouse_inventory_repository.dart`](../lib/core/repositories/warehouse_inventory_repository.dart) | Declares `WarehouseInventoryRepository`. |

## `lib/core/security/`

| File | Contents / responsibility clue |
| --- | --- |
| [`audit_insert_guard.dart`](../lib/core/security/audit_insert_guard.dart) | Dart module for audit insert guard in `lib/core/security/`. |
| [`audit_integrity.dart`](../lib/core/security/audit_integrity.dart) | Declares `computeAuditRecordHash`, `computeAuditRecordHashFromRow`. |

## `lib/core/services/`

| File | Contents / responsibility clue |
| --- | --- |
| [`account_auth_service.dart`](../lib/core/services/account_auth_service.dart) | Declares `AccountAuthResult`, `AccountAuthCache`, `AdminSubscribersResult`, `AdminSubscriber`, `AccountAuthService`. |
| [`account_statement_pdf_service.dart`](../lib/core/services/account_statement_pdf_service.dart) | Declares `AccountStatementPdfService`, `_StatementRow`, `_StatementLabels`. |
| [`accounting_aging_service.dart`](../lib/core/services/accounting_aging_service.dart) | Declares `AccountingAgingService`, `_AgingDocument`, `_AgingTotals`. |
| [`accounting_production_integrity_service.dart`](../lib/core/services/accounting_production_integrity_service.dart) | Library entry; declares `AccountingIntegritySeverity`, `AccountingIntegrityIssue`, `AccountingProductionIntegrityReport`, `AccountingProductionIntegrityService` and composes parts `accounting_production_integrity_service_methods_01.dart`, `accounting_production_integrity_service_methods_02.dart`. |
| [`accounting_production_integrity_service_methods_01.dart`](../lib/core/services/accounting_production_integrity_service_methods_01.dart) | Implementation part of `accounting_production_integrity_service.dart`; contains `audit`, `_checkJournalStructure`, `_checkJournalReferences`, `_checkPostedEditFamilyUniqueness`, `_checkVoucherAndControlIntegrity`, `_checkPartyControlBalance`, … (2 more). |
| [`accounting_production_integrity_service_methods_02.dart`](../lib/core/services/accounting_production_integrity_service_methods_02.dart) | Implementation part of `accounting_production_integrity_service.dart`; contains `_checkManufacturingAndCounts`, `_checkStockReversalLinks`, `_checkCostingMethodHistory`, `_checkUnifiedBatchState`. |
| [`accounting_service.dart`](../lib/core/services/accounting_service.dart) | Declares `AccountingService`. |
| [`accounting_service_accounting_helpers.dart`](../lib/core/services/accounting_service_accounting_helpers.dart) | Implementation part of `accounting_service_impl.dart`; contains `_writeAuditLog`, `_FrozenAccountingTax`, `_TaxBreakdown`, `_writeAuditLogInTransaction`, `_CashLocationSnapshot`, `applyCashLocationDelta`, … (37 more). |
| [`accounting_service_accounts_settings.dart`](../lib/core/services/accounting_service_accounts_settings.dart) | Implementation part of `accounting_service_impl.dart`; contains `_writeAuditLog`, `_accountSnapshot`, `_assertAccountCanBeDeleted`, `_defaultVatRatePercent`, `listAccounts`, `createAccount`, … (18 more). |
| [`accounting_service_cash_drawers.dart`](../lib/core/services/accounting_service_cash_drawers.dart) | Implementation part of `accounting_service_impl.dart`; contains `_writeAuditLog`, `createPostedEntry`, `_moveCashLocationBalance`, `recordOpeningCashLocationBalance`, `openCashDrawer`, `closeCashDrawer`, … (3 more). |
| [`accounting_service_cash_operations.dart`](../lib/core/services/accounting_service_cash_operations.dart) | Implementation part of `accounting_service_impl.dart`; contains `_roundMoney`, `listPaymentAccounts`, `listActiveCashLocations`, `hasOpenCashDrawerForDevice`, `currentCashDrawerForDevice`, `hasOpenCashDrawer`, … (16 more). |
| [`accounting_service_cash_tax_reports.dart`](../lib/core/services/accounting_service_cash_tax_reports.dart) | Implementation part of `accounting_service_impl.dart`; contains `cashBalanceBefore`, `flushCurrentEntry`, `CashFlowStatementReport`, `sumAccount`, `TaxReport`, `cashFlowStatementReport`, … (2 more). |
| [`accounting_service_cash_transfers.dart`](../lib/core/services/accounting_service_cash_transfers.dart) | Implementation part of `accounting_service_impl.dart`; contains `_accountSnapshot`, `_writeAuditLog`, `ensureCashOutflowAllowed`, `persistTransfer`, `createCashLocation`, `linkCashDrawerToDevice`, … (6 more). |
| [`accounting_service_expense_posting.dart`](../lib/core/services/accounting_service_expense_posting.dart) | Implementation part of `accounting_service_impl.dart`; contains `insertMovement`, `applyCashLocationDelta`, `recordExpensesBulk`, `_upsertExpenseRowInExistingTransaction`, `_recordExpenseCompatibilityLedgerInExistingTransaction`, `_recordCreditExpenseCompatibilityLedgerInExistingTransaction`, … (2 more). |
| [`accounting_service_expenses.dart`](../lib/core/services/accounting_service_expenses.dart) | Implementation part of `accounting_service_impl.dart`; contains `_upsertExpenseRowInExistingTransaction`, `resolveAccountRole`, `expenseAccountRoleKeyForReport`, `_resolveExpenseAccountForDatabase`, `recordExpense`, `recordExpenseOnCredit`, … (4 more). |
| [`accounting_service_fixed_assets.dart`](../lib/core/services/accounting_service_fixed_assets.dart) | Implementation part of `accounting_service_impl.dart`; contains `_accountSnapshot`, `createFixedAsset`, `runDepreciationForAsset`, `runDepreciationForAllAssets`, `_runDepreciationForAssetRow`. |
| [`accounting_service_impl.dart`](../lib/core/services/accounting_service_impl.dart) | Library entry; declares shared library definitions and composes parts `accounting_service_inventory_setup.dart`, `accounting_service_accounts_settings.dart`, `accounting_service_sales_purchases.dart`, `accounting_service_expenses.dart`, `accounting_service_expense_posting.dart`, … (13 more). |
| [`accounting_service_internal_types.dart`](../lib/core/services/accounting_service_internal_types.dart) | Implementation part of `accounting_service_impl.dart`; contains `_InventoryAmount`, `_CashLocationSnapshot`, `_FrozenAccountingTax`, `_TaxBreakdown`. |
| [`accounting_service_inventory_mutations.dart`](../lib/core/services/accounting_service_inventory_mutations.dart) | Implementation part of `accounting_service_impl.dart`; contains `createPostedEntry`, `_assertDateNotInClosedPeriod`, `_writeAuditLogInTransaction`, `recordInventoryDeficitCostReconciliationInTransaction`, `recordInventoryDeficitCostVarianceInTransaction`, `recordInventoryBatchRevaluationInTransaction`, … (5 more). |
| [`accounting_service_inventory_reports.dart`](../lib/core/services/accounting_service_inventory_reports.dart) | Implementation part of `accounting_service_impl.dart`; contains `for`, `inventoryValuationReport`, `manufacturingOrderCostReport`, `manufacturingWasteReport`, `inventoryCountVarianceReport`, `cashBankMovementReport`. |
| [`accounting_service_inventory_setup.dart`](../lib/core/services/accounting_service_inventory_setup.dart) | Implementation part of `accounting_service_impl.dart`; contains `_inventoryRoleKeyForProduct`, `_resolveAccountRoleForDatabase`, `createPostedEntry`, `_clearDeferredBomInventoryReconciliation`, `setMutationListener`, `_notifyMutation`, … (13 more). |
| [`accounting_service_journal_reversals.dart`](../lib/core/services/accounting_service_journal_reversals.dart) | Implementation part of `accounting_service_impl.dart`; contains `sameNumber`, `mismatch`, `persistReversal`, `_requireSalePostedSnapshotMatches`, `_requirePurchasePostedSnapshotMatches`, `countPostedJournalEntriesForReferences`, … (5 more). |
| [`accounting_service_ledger_reports.dart`](../lib/core/services/accounting_service_ledger_reports.dart) | Implementation part of `accounting_service_impl.dart`; contains `flushCurrentAccount`, `_trialBalanceRows`, `creditNet`, `debitNet`, `accountCreditNet`, `accountDebitNet`, … (12 more). |
| [`accounting_service_manual_journals.dart`](../lib/core/services/accounting_service_manual_journals.dart) | Implementation part of `accounting_service_impl.dart`; contains `createPostedEntry`, `loadSelected`, `baseReference`, `createManualJournalEntry`, `editManualJournalEntry`. |
| [`accounting_service_models.dart`](../lib/core/services/accounting_service_models.dart) | Declares `InventoryCountVariance`, `JournalEntrySummaryReport`, `JournalEntryDetailsReport`, `JournalEntryDetailLineReport`, `AdvancedAccountingItem`, … (16 more). |
| [`accounting_service_sales_purchases.dart`](../lib/core/services/accounting_service_sales_purchases.dart) | Implementation part of `accounting_service_impl.dart`; contains `createPostedEntry`, `ensureCashOutflowAllowed`, `normalize`, `recordSale`, `recordSaleReturn`, `recordPurchase`, … (2 more). |
| [`accounting_service_voucher_posting.dart`](../lib/core/services/accounting_service_voucher_posting.dart) | Implementation part of `accounting_service_impl.dart`; contains `createPostedEntry`, `persistPayment`, `_assertDateNotInClosedPeriod`, `persistEntry`, `postVoucherPayment`, `recordAccountPayment`. |
| [`app_logging_service.dart`](../lib/core/services/app_logging_service.dart) | Library entry; declares shared library definitions and composes parts `app_logging_service_split_01.dart`, `app_logging_service_split_02.dart`. |
| [`app_logging_service_split_01.dart`](../lib/core/services/app_logging_service_split_01.dart) | Implementation part of `app_logging_service.dart`; contains `AppLogRecord`, `toJson`, `AuditLogRecord`, `AuditIntegrityResult`, `AppLogQuery`, `AuditLogQuery`, … (13 more). |
| [`app_logging_service_split_02.dart`](../lib/core/services/app_logging_service_split_02.dart) | Implementation part of `app_logging_service.dart`; contains `record`, `flushPending`, `_flushPendingInternal`, `fetch`, `cleanup`, `deleteAll`, … (9 more). |
| [`app_update_service.dart`](../lib/core/services/app_update_service.dart) | Dart module for app update service in `lib/core/services/`. |
| [`app_update_service_io.dart`](../lib/core/services/app_update_service_io.dart) | Declares `AppUpdateInfo`, `AppUpdateDownloadRecord`, `AppUpdateUiState`, `AppUpdateService`, `getAppUpdateService`, … (2 more). |
| [`app_update_service_stub.dart`](../lib/core/services/app_update_service_stub.dart) | Declares `AppUpdateInfo`, `AppUpdateUiState`, `AppUpdateService`, `getAppUpdateService`, `_compareSemanticVersion`, … (1 more). |
| [`authenticated_peer_session.dart`](../lib/core/services/authenticated_peer_session.dart) | Declares `AuthenticatedPeerSession`. |
| [`backup_download_service.dart`](../lib/core/services/backup_download_service.dart) | Declares `downloadTextFile`, `downloadBinaryFile`. |
| [`backup_download_service_stub.dart`](../lib/core/services/backup_download_service_stub.dart) | Declares `downloadTextFile`, `downloadBinaryFile`. |
| [`backup_download_service_web.dart`](../lib/core/services/backup_download_service_web.dart) | Declares `downloadTextFile`, `downloadBinaryFile`. |
| [`barcode_feedback_service.dart`](../lib/core/services/barcode_feedback_service.dart) | Declares `BarcodeFeedbackSettings`, `BarcodeFeedbackService`. |
| [`barcode_label_pdf_service.dart`](../lib/core/services/barcode_label_pdf_service.dart) | Declares `BarcodeLabelItem`, `BarcodeLabelPrintOptions`, `BarcodeLabelPdfService`. |
| [`batch_inventory_service.dart`](../lib/core/services/batch_inventory_service.dart) | Library entry; declares `UnifiedBatchCostPreview`, `BatchInventoryService` and composes parts `batch_inventory_service_methods_01.dart`, `batch_inventory_service_methods_02.dart`, `batch_inventory_service_methods_03.dart`, `batch_inventory_service_methods_04.dart`, `batch_inventory_service_methods_05.dart`. |
| [`batch_inventory_service_methods_01.dart`](../lib/core/services/batch_inventory_service_methods_01.dart) | Implementation part of `batch_inventory_service.dart`; contains `addStockInTransaction`, `adjustSpecificBatchInTransaction`, `setBatchStatusInTransaction`, `receiveInTransaction`, `allocateFefoInTransaction`, `restoreInTransaction`, … (1 more). |
| [`batch_inventory_service_methods_02.dart`](../lib/core/services/batch_inventory_service_methods_02.dart) | Implementation part of `batch_inventory_service.dart`; contains `addUnifiedBatchStockInTransaction`, `ensureUnifiedCutoverInTransaction`, `resolveReferenceUnitCostInTransaction`, `_provisionalDeficitUnitCostInTransaction`, `previewUnifiedAllocationInTransaction`, `requirePhysicalUnifiedStockInTransaction`, … (1 more). |
| [`batch_inventory_service_methods_03.dart`](../lib/core/services/batch_inventory_service_methods_03.dart) | Implementation part of `batch_inventory_service.dart`; contains `reverseUnifiedMovementEffectInTransaction`, `_ensureDeficitBatchAndRecordInTransaction`, `_settleOpenDeficitsWithIncomingBatchInTransaction`, `_restoreDeficitAllocationInTransaction`. |
| [`batch_inventory_service_methods_04.dart`](../lib/core/services/batch_inventory_service_methods_04.dart) | Implementation part of `batch_inventory_service.dart`; contains `applySyncedBatchMovementInTransaction`, `allocateUnifiedInTransaction`, `restoreUnifiedInTransaction`, `adjustUnifiedBatchInTransaction`, `transferUnifiedInTransaction`, `checkWarehouseBatchBalanceInTransaction`, … (1 more). |
| [`batch_inventory_service_methods_05.dart`](../lib/core/services/batch_inventory_service_methods_05.dart) | Implementation part of `batch_inventory_service.dart`; contains `_refreshBatchLifecycleStatusInTransaction`, `_validateUnifiedExpiryContract`, `_calendarDate`, `_calendarDateText`, `_sameCalendarDate`. |
| [`business_revision_service.dart`](../lib/core/services/business_revision_service.dart) | Declares `BusinessRevisionService`. |
| [`cash_balance_policy_service.dart`](../lib/core/services/cash_balance_policy_service.dart) | Declares `CashBalancePolicyService`. |
| [`cash_ledger_service.dart`](../lib/core/services/cash_ledger_service.dart) | Declares `CashLedgerService`, `CashLedgerSummary`, `CashLedgerDetails`, `CashLedgerAllocationReference`, `_CashLedgerFilterQuery`. |
| [`cash_operation_service.dart`](../lib/core/services/cash_operation_service.dart) | Declares `CashOperationService`, `CashOperationResult`. |
| [`cash_phase7_migration_service.dart`](../lib/core/services/cash_phase7_migration_service.dart) | Library entry; declares `CashPhase7Issue`, `CashPhase7Report`, `CashPhase7MigrationService` and composes parts `cash_phase7_migration_service_methods_01.dart`, `cash_phase7_migration_service_methods_02.dart`. |
| [`cash_phase7_migration_service_methods_01.dart`](../lib/core/services/cash_phase7_migration_service_methods_01.dart) | Implementation part of `cash_phase7_migration_service.dart`; contains `_id`, `run`, `_legacyPaymentRows`, `_remapLegacyPaymentJournals`, `_normalizeLegacyInvoiceAccounting`, `_invoiceNeedsPaymentSeparation`, … (3 more). |
| [`cash_phase7_migration_service_methods_02.dart`](../lib/core/services/cash_phase7_migration_service_methods_02.dart) | Implementation part of `cash_phase7_migration_service.dart`; contains `_runIntegrityChecks`, `_resolveCashLocation`, `_countJournalEntries`, `_countLedger`, `_persistIssues`, `_number`, … (1 more). |
| [`cash_receipt_pdf_service.dart`](../lib/core/services/cash_receipt_pdf_service.dart) | Declares `CashReceiptPdfService`. |
| [`cash_reversal_service.dart`](../lib/core/services/cash_reversal_service.dart) | Declares `CashReversalService`. |
| [`cash_shift_report_pdf_service.dart`](../lib/core/services/cash_shift_report_pdf_service.dart) | Declares `CashShiftReportPdfService`. |
| [`customer_receivables_pdf_service.dart`](../lib/core/services/customer_receivables_pdf_service.dart) | Declares `CustomerReceivableRow`, `CustomerReceivablesPdfService`. |
| [`database_sql_editor_service.dart`](../lib/core/services/database_sql_editor_service.dart) | Declares `SqlEditorResult`, `DatabaseSqlEditorService`. |
| [`direct_control_plane_service.dart`](../lib/core/services/direct_control_plane_service.dart) | Library entry; declares `VpsControlPlaneSettings`, `HostHeartbeatStatus`, `DirectRealtimeSignal`, `_DirectSnapshotRelayJob`, `_RealtimeChannelSession`, … (14 more) and composes parts `direct_control_plane_service_methods_01.dart`, `direct_control_plane_service_methods_02.dart`, `direct_control_plane_service_methods_03.dart`, `direct_control_plane_service_methods_04.dart`, `direct_control_plane_service_methods_05.dart`, … (1 more). |
| [`direct_control_plane_service_methods_01.dart`](../lib/core/services/direct_control_plane_service_methods_01.dart) | Implementation part of `direct_control_plane_service.dart`; contains `_clientDirectHostWorkNeedsDrain`, `_directClientNeedsDrainResult`, `_runDirectHostRelaySync`, `_runDirectClientRelayPush`, `_runDirectClientAuthoritativeSync`, `_drainClientPendingChangesBeforeRebuild`, … (23 more). |
| [`direct_control_plane_service_methods_02.dart`](../lib/core/services/direct_control_plane_service_methods_02.dart) | Implementation part of `direct_control_plane_service.dart`; contains `claimPairingCode`, `recoverExistingStoreFromDirect`, `recoverExistingStoreIdentityFromDirect`, `_shouldRequestFreshSnapshotForGeneration`, `_markFreshSnapshotRequestedForGeneration`, `_newDirectRebuildRequestId`, … (1 more). |
| [`direct_control_plane_service_methods_03.dart`](../lib/core/services/direct_control_plane_service_methods_03.dart) | Implementation part of `direct_control_plane_service.dart`; contains `rebuildFromDirectHostSnapshot`, `_waitForFreshDirectRebuildSnapshot`, `checkCurrentDeviceAccess`, `setDeviceSuspended`, `revokeDevice`, `deleteDeviceRecord`, … (11 more). |
| [`direct_control_plane_service_methods_04.dart`](../lib/core/services/direct_control_plane_service_methods_04.dart) | Implementation part of `direct_control_plane_service.dart`; contains `_handleRealtimePacket`, `_confirmDirectWipe`, `registerCurrentDevice`, `requestHostTransfer`, `approveHostTransfer`, `activateHostTransfer`, … (3 more). |
| [`direct_control_plane_service_methods_05.dart`](../lib/core/services/direct_control_plane_service_methods_05.dart) | Implementation part of `direct_control_plane_service.dart`; contains `testConnection`, `ensureHostRelayReady`, `validateSingleHost`, `sendHostHeartbeat`, `stopHost`, `waitForRealtimeSignal`, … (10 more). |
| [`direct_control_plane_service_methods_06.dart`](../lib/core/services/direct_control_plane_service_methods_06.dart) | Implementation part of `direct_control_plane_service.dart`; contains `_pullAuthoritativeChangesViaRelay`, `pushPendingForUnifiedEngine`, `pullAuthoritativeChangesForUnifiedEngine`, `syncNow`. |
| [`direct_device_identity.dart`](../lib/core/services/direct_device_identity.dart) | Declares `DirectDeviceIdentity`. |
| [`direct_peer_connection_service.dart`](../lib/core/services/direct_peer_connection_service.dart) | Library entry; declares shared library definitions and composes parts `direct_peer_connection_service_split_01.dart`, `direct_peer_connection_service_split_02.dart`, `direct_peer_connection_service_split_03.dart`. |
| [`direct_peer_connection_service_split_01.dart`](../lib/core/services/direct_peer_connection_service_split_01.dart) | Implementation part of `direct_peer_connection_service.dart`; contains `send`, `_bindDataChannel`, `_handleIncomingFragment`, `_readBufferedAmount`, `attachSignalSubscription`, `close`. |
| [`direct_peer_connection_service_split_02.dart`](../lib/core/services/direct_peer_connection_service_split_02.dart) | Implementation part of `direct_peer_connection_service.dart`; contains `connectAsHost`, `connectAsClient`, `acceptAsHost`, `_addCandidate`, `_waitForIceGatheringComplete`, `_logIcePath`, … (3 more). |
| [`direct_peer_connection_service_split_03.dart`](../lib/core/services/direct_peer_connection_service_split_03.dart) | Implementation part of `direct_peer_connection_service.dart`; contains `Function`, `start`, `_start`, `_handleSignal`, `_createPeer`, `_removePeer`, … (8 more). |
| [`direct_peer_handshake.dart`](../lib/core/services/direct_peer_handshake.dart) | Declares `DirectPeerHandshake`, `DirectPeerSessionMaterial`. |
| [`direct_peer_pairing_service.dart`](../lib/core/services/direct_peer_pairing_service.dart) | Declares `DirectPairingCodeResult`, `DirectPairingClaimResult`, `DirectPeerPairingService`. |
| [`direct_peer_protocol.dart`](../lib/core/services/direct_peer_protocol.dart) | Declares `DirectPeerRequestHandler`, `DirectPeerRequestSession`, `DirectPeerHostEndpoint`. |
| [`direct_peer_signaling_service.dart`](../lib/core/services/direct_peer_signaling_service.dart) | Declares `DirectPeerSignalingSettings`, `DirectPeerSignalingSession`, `DirectPeerSignalingService`, `DirectPeerIdentity`. |
| [`direct_sync_protocol_service.dart`](../lib/core/services/direct_sync_protocol_service.dart) | Declares `_DirectPullJob`, `DirectHostSyncEndpoint`, `DirectClientSyncService`. |
| [`direct_sync_settings.dart`](../lib/core/services/direct_sync_settings.dart) | Declares `DirectIceServer`, `DirectSyncSettings`. |
| [`expense_pdf_service.dart`](../lib/core/services/expense_pdf_service.dart) | Declares `ExpensePdfService`, `_ExpensePdfLabels`. |
| [`google_drive_backup_service.dart`](../lib/core/services/google_drive_backup_service.dart) | Library entry; declares shared library definitions and composes parts `google_drive_backup_service_split_01.dart`, `google_drive_backup_service_split_02.dart`, `google_drive_backup_service_split_03.dart`. |
| [`google_drive_backup_service_split_01.dart`](../lib/core/services/google_drive_backup_service_split_01.dart) | Implementation part of `google_drive_backup_service.dart`; contains `GoogleDriveBackupSettings`, `copyWith`, `GoogleDriveBackupStatus`, `GoogleDriveBackupFile`, `_formatSize`, `GoogleDriveAuthorizationChallenge`, … (1 more). |
| [`google_drive_backup_service_split_02.dart`](../lib/core/services/google_drive_backup_service_split_02.dart) | Implementation part of `google_drive_backup_service.dart`; contains `loadSettings`, `_readSecretWithLegacyMigration`, `lastSuccessAt`, `saveSettings`, `disconnect`, `startAuthorization`, … (32 more). |
| [`google_drive_backup_service_split_03.dart`](../lib/core/services/google_drive_backup_service_split_03.dart) | Implementation part of `google_drive_backup_service.dart`; contains `ZipEncoder`, `_buildZipBytesInIsolate`. |
| [`google_drive_browser_auth.dart`](../lib/core/services/google_drive_browser_auth.dart) | Dart module for google drive browser auth in `lib/core/services/`. |
| [`google_drive_browser_auth_io.dart`](../lib/core/services/google_drive_browser_auth_io.dart) | Declares `GoogleDriveBrowserAuth`. |
| [`google_drive_browser_auth_stub.dart`](../lib/core/services/google_drive_browser_auth_stub.dart) | Declares `GoogleDriveBrowserAuth`. |
| [`inventory_traceability_service.dart`](../lib/core/services/inventory_traceability_service.dart) | Declares `InventoryTraceabilityService`. |
| [`invoice_pdf_service.dart`](../lib/core/services/invoice_pdf_service.dart) | Library entry; declares `InvoicePdfService`, `_InvoicePdfServiceImplementation`, `_InvoicePdfLabels` and composes parts `invoice_pdf_service_impl_01.dart`, `invoice_pdf_service_impl_02.dart`, `invoice_pdf_service_impl_03.dart`. |
| [`invoice_pdf_service_impl_01.dart`](../lib/core/services/invoice_pdf_service_impl_01.dart) | Implementation part of `invoice_pdf_service.dart`; contains `buildInvoicePdf`, `printInvoice`, `shareInvoice`, `printSaleReturn`, `buildSaleReturnPdf`, `_isReceiptPageFormat`, … (8 more). |
| [`invoice_pdf_service_impl_02.dart`](../lib/core/services/invoice_pdf_service_impl_02.dart) | Implementation part of `invoice_pdf_service.dart`; contains `_buildReceiptFooter`, `_buildHeroHeader`, `_brandRule`, `_invoiceInfoBlock`, `_metaItem`, `_centerBrandBlock`, … (15 more). |
| [`invoice_pdf_service_impl_03.dart`](../lib/core/services/invoice_pdf_service_impl_03.dart) | Implementation part of `invoice_pdf_service.dart`; contains `_formatMoney`. |
| [`lan_sync_service.dart`](../lib/core/services/lan_sync_service.dart) | Dart module for lan sync service in `lib/core/services/`. |
| [`lan_sync_service_io.dart`](../lib/core/services/lan_sync_service_io.dart) | Library entry; declares `LanSyncProgressCallback`, `LanSyncDeviceMode`, `HostRegistryDevice`, `LanSyncSettings`, `LanSyncResult`, … (2 more) and composes parts `lan_sync_service_io_methods_01.dart`, `lan_sync_service_io_methods_02.dart`, `lan_sync_service_io_methods_03.dart`, `lan_sync_service_io_methods_04.dart`. |
| [`lan_sync_service_io_methods_01.dart`](../lib/core/services/lan_sync_service_io_methods_01.dart) | Implementation part of `lan_sync_service_io.dart`; contains `_attachStoreListener`, `_onStoreChanged`, `_isNetworkFailure`, `_failureMessage`, `_snapshotGenerationKey`, `_snapshotGenerationInProgressKey`, … (29 more). |
| [`lan_sync_service_io_methods_02.dart`](../lib/core/services/lan_sync_service_io_methods_02.dart) | Implementation part of `lan_sync_service_io.dart`; contains `_handleRequest`, `_handleRealtimeSocket`, `_closeRealtimeClient`, `_client`, `discoverHost`, `_attachToken`, … (4 more). |
| [`lan_sync_service_io_methods_03.dart`](../lib/core/services/lan_sync_service_io_methods_03.dart) | Implementation part of `lan_sync_service_io.dart`; contains `pullNow`, `_repairFromHostSnapshotImpl`, `_updateHostRegistryDeviceName`, `_decodeRejectedSyncRequests`, `_saveCursorAndRecordState`, `recordDeviceSyncState`, … (10 more). |
| [`lan_sync_service_io_methods_04.dart`](../lib/core/services/lan_sync_service_io_methods_04.dart) | Implementation part of `lan_sync_service_io.dart`; contains `syncNow`. |
| [`lan_sync_service_stub.dart`](../lib/core/services/lan_sync_service_stub.dart) | Declares `LanSyncProgressCallback`, `LanSyncDeviceMode`, `HostRegistryDevice`, `LanSyncSettings`, `LanSyncResult`, … (1 more). |
| [`local_auto_backup_service.dart`](../lib/core/services/local_auto_backup_service.dart) | Dart module for local auto backup service in `lib/core/services/`. |
| [`local_auto_backup_service_io.dart`](../lib/core/services/local_auto_backup_service_io.dart) | Declares `LocalAutoBackupSettings`, `LocalAutoBackupStatus`, `LocalAutoBackupService`, `_buildZipBytesInIsolate`. |
| [`local_auto_backup_service_stub.dart`](../lib/core/services/local_auto_backup_service_stub.dart) | Declares `LocalAutoBackupSettings`, `LocalAutoBackupStatus`, `LocalAutoBackupService`. |
| [`local_database_service.dart`](../lib/core/services/local_database_service.dart) | Library entry; declares `LocalDatabaseService`, `_LocalDatabaseServiceImplementation`, `_PendingBusinessEntityWrite` and composes parts `local_database_service_impl_01.dart`, `local_database_service_impl_02.dart`, `local_database_service_impl_03.dart`, `local_database_service_impl_04.dart`. |
| [`local_database_service_impl_01.dart`](../lib/core/services/local_database_service_impl_01.dart) | Implementation part of `local_database_service.dart`; contains `_intValue`, `_doubleValue`, `useInMemoryStoreForTesting`, `clearInMemoryStoreForTesting`, `useSqliteDatabaseForTesting`, `resetForTesting`, … (27 more). |
| [`local_database_service_impl_02.dart`](../lib/core/services/local_database_service_impl_02.dart) | Implementation part of `local_database_service.dart`; contains `replaceInventoryBatchRowsImmediate`, `getInventoryMigrationAdjustmentsFromSqlite`, `getPhase8AccountingSnapshotRows`, `replacePhase8AccountingSnapshotRowsImmediate`, `getPhase8AccountingDeltaRows`, `upsertPhase8AccountingSnapshotRowsImmediate`, … (49 more). |
| [`local_database_service_impl_03.dart`](../lib/core/services/local_database_service_impl_03.dart) | Implementation part of `local_database_service.dart`; contains `upsertBusinessEntityJson`, `upsertBusinessEntityJsons`, `upsertSyncChange`, `upsertSyncChanges`, `upsertSyncQueueItem`, `upsertSyncQueueItems`, … (15 more). |
| [`local_database_service_impl_04.dart`](../lib/core/services/local_database_service_impl_04.dart) | Implementation part of `local_database_service.dart`; contains `adminEntries`, `_syncDatabase`, `_memorySyncChanges`, `_memorySyncQueue`, `pendingSyncQueueCountForTarget`, `pendingSyncChangesCount`, … (1 more). |
| [`maintenance_storage_info.dart`](../lib/core/services/maintenance_storage_info.dart) | Declares `MaintenanceStorageInfo`, `getMaintenanceStorageInfo`. |
| [`maintenance_storage_info_io.dart`](../lib/core/services/maintenance_storage_info_io.dart) | Declares `getMaintenanceStorageInfoImpl`, `_findSqliteFiles`. |
| [`maintenance_storage_info_stub.dart`](../lib/core/services/maintenance_storage_info_stub.dart) | Declares `getMaintenanceStorageInfoImpl`. |
| [`manufacturing_pdf_service.dart`](../lib/core/services/manufacturing_pdf_service.dart) | Declares `ManufacturingPdfService`, `_Labels`. |
| [`page_timing_scope.dart`](../lib/core/services/page_timing_scope.dart) | Declares `PageTimingScope`, `_PageTimingScopeState`. |
| [`password_hashing.dart`](../lib/core/services/password_hashing.dart) | Declares `PasswordHashing`. |
| [`payment_voucher_service.dart`](../lib/core/services/payment_voucher_service.dart) | Library entry; declares `PaymentVoucherService`, `_AllocationTarget` and composes parts `payment_voucher_service_methods_01.dart`, `payment_voucher_service_methods_02.dart`, `payment_voucher_service_methods_03.dart`, `payment_voucher_service_methods_04.dart`, `payment_voucher_service_methods_05.dart`, … (3 more). |
| [`payment_voucher_service_methods_01.dart`](../lib/core/services/payment_voucher_service_methods_01.dart) | Implementation part of `payment_voucher_service.dart`; contains `_newId`, `_newVoucherNo`, `createReceipt`, `createPayment`, `editReceipt`. |
| [`payment_voucher_service_methods_02.dart`](../lib/core/services/payment_voucher_service_methods_02.dart) | Implementation part of `payment_voucher_service.dart`; contains `editPayment`, `_assertVoucherHasNoDownstreamRefunds`, `_ensureVoucherCashHistoryAvailable`, `_hasActiveVoucherCashMovement`, `_reverseActiveVoucherCashMovementsInTransaction`, `_reverseActiveAllocationsForEdit`, … (5 more). |
| [`payment_voucher_service_methods_03.dart`](../lib/core/services/payment_voucher_service_methods_03.dart) | Implementation part of `payment_voucher_service.dart`; contains `refundSaleCash`, `refundableCashForPurchase`, `unallocatedCashForPurchase`, `refundableCashForExpense`, `cashPaidForExpense`, `refundableCashForPurchaseReturn`, … (2 more). |
| [`payment_voucher_service_methods_04.dart`](../lib/core/services/payment_voucher_service_methods_04.dart) | Implementation part of `payment_voucher_service.dart`; contains `refundPurchaseCash`, `refundExpenseCash`, `reverseReceiptVoucher`, `reversePaymentVoucher`, `_reverseVoucher`, `_insertCompatibilityRefundMovement`. |
| [`payment_voucher_service_methods_05.dart`](../lib/core/services/payment_voucher_service_methods_05.dart) | Implementation part of `payment_voucher_service.dart`; contains `_insertCompatibilityAccountMovement`, `_reverseCompatibilityAccountMovements`, `syncPurchasePaymentCacheFromAllocations`, `_rebuildAllocationCache`, `_repairSplitCompatibilityAccountMovements`. |
| [`payment_voucher_service_methods_06.dart`](../lib/core/services/payment_voucher_service_methods_06.dart) | Implementation part of `payment_voucher_service.dart`; contains `backfillLegacyCashLedger`, `findReceiptById`, `findPaymentById`, `allocationsFor`, `listReceipts`, `listPayments`, … (7 more). |
| [`payment_voucher_service_methods_07.dart`](../lib/core/services/payment_voucher_service_methods_07.dart) | Implementation part of `payment_voucher_service.dart`; contains `_allocateRefundCoverage`, `_insertRefundCoverage`, `normalizeOverAllocatedVouchers`, `_reconcileVoucherUnallocatedAmount`, `_applyAllocationCaches`, `_appendVoucherCashMovement`, … (3 more). |
| [`payment_voucher_service_methods_08.dart`](../lib/core/services/payment_voucher_service_methods_08.dart) | Implementation part of `payment_voucher_service.dart`; contains `_receiptFromRow`, `_paymentFromRow`, `_allocationFromRow`, `_isCash`, `_currency`, `_money`, … (3 more). |
| [`pdf_font_loader.dart`](../lib/core/services/pdf_font_loader.dart) | Declares `PdfFontPair`, `PdfFontLoader`. |
| [`pdf_system_font_loader_io.dart`](../lib/core/services/pdf_system_font_loader_io.dart) | Declares `loadSystemPdfFontPairBytes`. |
| [`pdf_system_font_loader_stub.dart`](../lib/core/services/pdf_system_font_loader_stub.dart) | Declares `loadSystemPdfFontPairBytes`. |
| [`posted_document_edit_framework.dart`](../lib/core/services/posted_document_edit_framework.dart) | Declares `PostedDocumentEditPipeline`. |
| [`posted_document_snapshot_service.dart`](../lib/core/services/posted_document_snapshot_service.dart) | Declares `PostedDocumentSnapshotService`, `_FrozenTaxLine`. |
| [`price_list_pdf_service.dart`](../lib/core/services/price_list_pdf_service.dart) | Declares `PriceListPdfService`. |
| [`print_service.dart`](../lib/core/services/print_service.dart) | Declares `PrintSelection`, `PrintService`, `_PrintSelectionDialog`, `_PrintSelectionDialogState`. |
| [`professional_pdf_theme.dart`](../lib/core/services/professional_pdf_theme.dart) | Declares `ProfessionalPdfTheme`. |
| [`purchase_pdf_service.dart`](../lib/core/services/purchase_pdf_service.dart) | Declares `PurchasePdfService`, `_PurchasePdfLabels`. |
| [`secure_peer_session.dart`](../lib/core/services/secure_peer_session.dart) | Dart module for secure peer session in `lib/core/services/`. |
| [`simple_report_pdf_service.dart`](../lib/core/services/simple_report_pdf_service.dart) | Declares `SimpleReportPdfService`. |
| [`sql_result_download_service.dart`](../lib/core/services/sql_result_download_service.dart) | Declares `downloadSqlResultFile`. |
| [`sql_result_download_service_stub.dart`](../lib/core/services/sql_result_download_service_stub.dart) | Declares `downloadSqlResultFile`. |
| [`sql_result_download_service_web.dart`](../lib/core/services/sql_result_download_service_web.dart) | Declares `downloadSqlResultFile`. |
| [`sql_result_export_service.dart`](../lib/core/services/sql_result_export_service.dart) | Declares `SqlResultExportService`. |
| [`sqlite_sync_state_service.dart`](../lib/core/services/sqlite_sync_state_service.dart) | Library entry; declares `_StockOperationState`, `SqliteSyncStateService` and composes parts `sqlite_sync_state_service_methods_01.dart`, `sqlite_sync_state_service_methods_02.dart`, `sqlite_sync_state_service_methods_03.dart`, `sqlite_sync_state_service_methods_04.dart`. |
| [`sqlite_sync_state_service_methods_01.dart`](../lib/core/services/sqlite_sync_state_service_methods_01.dart) | Implementation part of `sqlite_sync_state_service.dart`; contains `_db`, `_memorySyncChanges`, `_memorySyncQueue`, `_saveMemorySyncChanges`, `_saveMemorySyncQueue`, `_syncMetaString`, … (26 more). |
| [`sqlite_sync_state_service_methods_02.dart`](../lib/core/services/sqlite_sync_state_service_methods_02.dart) | Implementation part of `sqlite_sync_state_service.dart`; contains `retryFailedSyncQueue`, `recoverStaleInProgressSyncQueue`, `recoverSubmittedSyncQueue`, `markSyncChangesSubmittedByIds`, `markSyncChangesSyncedByIds`, `markSyncChangesRejectedByIds`, … (5 more). |
| [`sqlite_sync_state_service_methods_03.dart`](../lib/core/services/sqlite_sync_state_service_methods_03.dart) | Implementation part of `sqlite_sync_state_service.dart`; contains `_applyRemoteSyncChanges`, `_applyCashAccountingDelta`, `_applyBusinessEntityChange`, `_materializePurchaseBatches`, `_applySupplierPriceChange`, `_applyInventoryBatchChange`, … (3 more). |
| [`sqlite_sync_state_service_methods_04.dart`](../lib/core/services/sqlite_sync_state_service_methods_04.dart) | Implementation part of `sqlite_sync_state_service.dart`; contains `_acquireStockOperation`, `_hasAppliedStockMovement`, `_applyWarehouseAwareMovement`, `_updateProductCompatibilityCacheFromWarehouseInventory`, `_markStockOperationCompleted`, `_markStockOperationFailed`, … (2 more). |
| [`startup_timing_service.dart`](../lib/core/services/startup_timing_service.dart) | Declares `StartupTimingRecord`, `PageTimingRecord`, `StartupTimingService`. |
| [`startup_timing_service_io.dart`](../lib/core/services/startup_timing_service_io.dart) | Declares `saveTextReport`. |
| [`startup_timing_service_stub.dart`](../lib/core/services/startup_timing_service_stub.dart) | Declares `saveTextReport`. |
| [`stock_transaction_service.dart`](../lib/core/services/stock_transaction_service.dart) | Library entry; declares `StockTransactionReceipt`, `StockIntegrityIssue`, `StockIntegrityReport`, `_StockOperationInProgressException`, `_OperationAcquisition`, … (3 more) and composes parts `stock_transaction_service_methods_01.dart`, `stock_transaction_service_methods_02.dart`. |
| [`stock_transaction_service_methods_01.dart`](../lib/core/services/stock_transaction_service_methods_01.dart) | Implementation part of `stock_transaction_service.dart`; contains `getBalance`, `listBalances`, `validateSufficientStock`, `applyDelta`, `recordMovementsAtomically`, `recordMovementsInTransaction`, … (4 more). |
| [`stock_transaction_service_methods_02.dart`](../lib/core/services/stock_transaction_service_methods_02.dart) | Implementation part of `stock_transaction_service.dart`; contains `_assertUnifiedBatchIdentityInTransaction`, `_applyMovementAtomically`, `_insertStockMovementAppendOnly`, `_acquireOperationRecord`, `_markOperationCompleted`, `_markOperationFailed`, … (11 more). |
| [`store_bootstrap_service.dart`](../lib/core/services/store_bootstrap_service.dart) | Declares `StoreBootstrapService`. |
| [`sync_diagnostics_log.dart`](../lib/core/services/sync_diagnostics_log.dart) | Declares `SyncDiagnosticsLog`, `DirectDiagnosticsSummary`. |
| [`unified_batch_phase4_closure_service.dart`](../lib/core/services/unified_batch_phase4_closure_service.dart) | Declares `UnifiedBatchPhase4ClosureResult`, `UnifiedBatchPhase4ClosureService`. |
| [`unified_sync_core_service.dart`](../lib/core/services/unified_sync_core_service.dart) | Declares `UnifiedSyncCoreService`, `HostClientAcceptancePlan`, `HostAcceptedChanges`, `UnifiedSyncPullMetadata`. |
| [`warehouse_inventory_pdf_service.dart`](../lib/core/services/warehouse_inventory_pdf_service.dart) | Declares `WarehouseInventoryPdfRow`, `WarehouseInventoryPdfService`, `_WarehouseInventoryPdfLabels`. |
| [`warehouse_transfer_pdf_service.dart`](../lib/core/services/warehouse_transfer_pdf_service.dart) | Declares `WarehouseTransferPdfService`, `_WarehouseTransferPdfLabels`. |
| [`web_indexed_store.dart`](../lib/core/services/web_indexed_store.dart) | Dart module for web indexed store in `lib/core/services/`. |
| [`web_indexed_store_stub.dart`](../lib/core/services/web_indexed_store_stub.dart) | Declares `WebIndexedStore`. |
| [`web_indexed_store_web.dart`](../lib/core/services/web_indexed_store_web.dart) | Declares `WebIndexedStore`. |
| [`windows_release_catalog.dart`](../lib/core/services/windows_release_catalog.dart) | Dart module for windows release catalog in `lib/core/services/`. |
| [`windows_release_catalog_stub.dart`](../lib/core/services/windows_release_catalog_stub.dart) | Declares `WindowsReleaseItem`, `WindowsReleaseCatalogService`. |
| [`windows_release_catalog_web.dart`](../lib/core/services/windows_release_catalog_web.dart) | Declares `WindowsReleaseItem`, `WindowsReleaseCatalogService`. |

## `lib/core/shortcuts/`

| File | Contents / responsibility clue |
| --- | --- |
| [`app_shortcuts.dart`](../lib/core/shortcuts/app_shortcuts.dart) | Declares `ShortcutPage`, `ShortcutPageInfo`, `SaleShortcutAction`, `SaleShortcutActionInfo`, `SalePaymentShortcutAction`, … (6 more). |

## `lib/core/snapshot/`

| File | Contents / responsibility clue |
| --- | --- |
| [`unified_snapshot.dart`](../lib/core/snapshot/unified_snapshot.dart) | Declares `UnifiedSnapshotSection`, `UnifiedSnapshotManifest`, `UnifiedSnapshotCatalog`. |
| [`unified_snapshot_progress.dart`](../lib/core/snapshot/unified_snapshot_progress.dart) | Declares `UnifiedSnapshotProgressView`. |
| [`unified_snapshot_transfer.dart`](../lib/core/snapshot/unified_snapshot_transfer.dart) | Declares `UnifiedSnapshotTransferProgress`, `UnifiedSnapshotChunkResponse`, `UnifiedSnapshotManifestResponse`, `UnifiedSnapshotChunkPullTransport`, `UnifiedSnapshotTransferService`, … (2 more). |

## `lib/core/storage/sqlite/`

| File | Contents / responsibility clue |
| --- | --- |
| [`business_sqlite_store.dart`](../lib/core/storage/sqlite/business_sqlite_store.dart) | Declares `BusinessSqliteStore`. |
| [`business_sqlite_store_domain_upserts.dart`](../lib/core/storage/sqlite/business_sqlite_store_domain_upserts.dart) | Implementation part of `business_sqlite_store_impl.dart`; contains `_upsertTypedEntityRow`, `_insertSaleLikeItems`, `_upsertSearchIndex`, `_insertPurchaseItems`, `_upsertInventoryCountPayload`, `_insertInventoryCountLines`, … (14 more). |
| [`business_sqlite_store_entity_readers.dart`](../lib/core/storage/sqlite/business_sqlite_store_entity_readers.dart) | Implementation part of `business_sqlite_store_impl.dart`; contains `readAccountTransactions`, `readCustomers`, `readSuppliers`, `readExpenseById`, `readExpenses`, `readWarehouses`, … (15 more). |
| [`business_sqlite_store_entity_reads.dart`](../lib/core/storage/sqlite/business_sqlite_store_entity_reads.dart) | Implementation part of `business_sqlite_store_impl.dart`; contains `_setMeta`, `_migrateComplexTables`, `_metaValue`, `jsonEncode`, `migrateFromLegacyJsonIfNeeded`, `markFreshInstallValidated`, … (7 more). |
| [`business_sqlite_store_entity_upserts.dart`](../lib/core/storage/sqlite/business_sqlite_store_entity_upserts.dart) | Implementation part of `business_sqlite_store_impl.dart`; contains `_upsertSearchIndex`, `_upsertTypedEntityRow`, `_insertProductUnits`, `_upsertStockMovementPayload`, `_upsertAccountTransactionPayload`, `_upsertProductPayload`, … (1 more). |
| [`business_sqlite_store_impl.dart`](../lib/core/storage/sqlite/business_sqlite_store_impl.dart) | Library entry; declares shared library definitions and composes parts `business_sqlite_store_queries.dart`, `business_sqlite_store_summary_and_migrations.dart`, `business_sqlite_store_entity_reads.dart`, `business_sqlite_store_stock_movements.dart`, `business_sqlite_store_entity_readers.dart`, … (8 more). |
| [`business_sqlite_store_internal_types.dart`](../lib/core/storage/sqlite/business_sqlite_store_internal_types.dart) | Implementation part of `business_sqlite_store_impl.dart`; contains `_SqlFilter`, `_AccountBalanceSummary`. |
| [`business_sqlite_store_migration_validation.dart`](../lib/core/storage/sqlite/business_sqlite_store_migration_validation.dart) | Implementation part of `business_sqlite_store_impl.dart`; contains `_insertSaleLikeItems`, `_insertPurchaseItems`, `_insertInventoryCountLines`, `_insertBillOfMaterialsLines`, `_payloadMapList`, `_migrateComplexTables`. |
| [`business_sqlite_store_models.dart`](../lib/core/storage/sqlite/business_sqlite_store_models.dart) | Declares `BusinessSqliteValidationResult`, `BusinessQueryPage`. |
| [`business_sqlite_store_payload_batches.dart`](../lib/core/storage/sqlite/business_sqlite_store_payload_batches.dart) | Implementation part of `business_sqlite_store_impl.dart`; contains `upsertEntityPayloads`. |
| [`business_sqlite_store_purchase_reports.dart`](../lib/core/storage/sqlite/business_sqlite_store_purchase_reports.dart) | Implementation part of `business_sqlite_store_impl.dart`; contains `_readPurchasesByIds`, `for`, `_SqlFilter`, `BusinessQueryPage`, `_saveLocalMirrorValue`, `upsertEntityPayloads`, … (13 more). |
| [`business_sqlite_store_queries.dart`](../lib/core/storage/sqlite/business_sqlite_store_queries.dart) | Implementation part of `business_sqlite_store_impl.dart`; contains `BusinessQueryPage`, `_SqlFilter`, `isBusinessKey`, `isTypedEntityKey`, `_safeLimit`, `_safeOffset`, … (13 more). |
| [`business_sqlite_store_sales_reads.dart`](../lib/core/storage/sqlite/business_sqlite_store_sales_reads.dart) | Implementation part of `business_sqlite_store_impl.dart`; contains `_readSalesByIds`, `for`, `_SqlFilter`, `BusinessQueryPage`, `readSales`, `readSalesByIds`, … (6 more). |
| [`business_sqlite_store_sql_helpers.dart`](../lib/core/storage/sqlite/business_sqlite_store_sql_helpers.dart) | Implementation part of `business_sqlite_store_impl.dart`; contains `_setMeta`, `BusinessSqliteValidationResult`, `StockMovement`, `AccountTransaction`, `_doubleValue`, `_intValue`, … (22 more). |
| [`business_sqlite_store_stock_movements.dart`](../lib/core/storage/sqlite/business_sqlite_store_stock_movements.dart) | Implementation part of `business_sqlite_store_impl.dart`; contains `BusinessQueryPage`, `readStockMovements`, `queryStockMovements`, `assistantStockBalances`, `assistantStockMovementSummary`, `queryWasteLossMovements`, … (2 more). |
| [`business_sqlite_store_summary_and_migrations.dart`](../lib/core/storage/sqlite/business_sqlite_store_summary_and_migrations.dart) | Implementation part of `business_sqlite_store_impl.dart`; contains `_labelValueRows`, `_keyValueRows`, `_AccountBalanceSummary`, `_intScalar`, `refreshSummaryTables`, `refreshDailyMetrics`, … (23 more). |
| [`sqlite_database_connection.dart`](../lib/core/storage/sqlite/sqlite_database_connection.dart) | Dart module for sqlite database connection in `lib/core/storage/sqlite/`. |
| [`sqlite_database_connection_io.dart`](../lib/core/storage/sqlite/sqlite_database_connection_io.dart) | Declares `openVentioSqliteConnection`, `getVentioSqliteDirectoryPath`. |
| [`sqlite_database_connection_stub.dart`](../lib/core/storage/sqlite/sqlite_database_connection_stub.dart) | Declares `openVentioSqliteConnection`. |
| [`sqlite_migration_manager.dart`](../lib/core/storage/sqlite/sqlite_migration_manager.dart) | Declares `SqliteMigrationStatus`, `SqliteMigrationManager`. |
| [`sync_sqlite_store.dart`](../lib/core/storage/sqlite/sync_sqlite_store.dart) | Declares `SyncSqliteStore`. |
| [`ventio_drift_database.dart`](../lib/core/storage/sqlite/ventio_drift_database.dart) | Library entry; declares `VentioDriftDatabase` and composes parts `ventio_drift_database_methods_01.dart`, `ventio_drift_database_methods_02.dart`, `ventio_drift_database_methods_03.dart`, `ventio_drift_database_methods_04.dart`, `ventio_drift_database_methods_05.dart`, … (3 more). |
| [`ventio_drift_database_methods_01.dart`](../lib/core/storage/sqlite/ventio_drift_database_methods_01.dart) | Implementation part of `ventio_drift_database.dart`; contains `_applyFoundationSchema`, `_sealLegacyAuditRows`, `_ensureColumn`, `_rebuildVoucherTablesForDiscountOnlySettlements`, `_tableHasColumn`, `_tableColumns`, … (20 more). |
| [`ventio_drift_database_methods_02.dart`](../lib/core/storage/sqlite/ventio_drift_database_methods_02.dart) | Implementation part of `ventio_drift_database.dart`; contains `dropLegacyProductStockColumn`, `_ensureProductColumns`, `_ensureProductUnitTables`, `_ensureSaleColumns`, `_ensureSaleItemTables`, `_ensureSaleQuotationColumns`, … (18 more). |
| [`ventio_drift_database_methods_03.dart`](../lib/core/storage/sqlite/ventio_drift_database_methods_03.dart) | Implementation part of `ventio_drift_database.dart`; contains `_ensureWarehouseInventoryColumns`, `_ensureInventoryBatchTables`, `_ensureStockOperationsTable`, `_ensureStockOperationsColumns`, `_ensureInventoryReconciliationsTable`, `_ensureInventoryMigrationAdjustmentsTable`, … (12 more). |
| [`ventio_drift_database_methods_04.dart`](../lib/core/storage/sqlite/ventio_drift_database_methods_04.dart) | Implementation part of `ventio_drift_database.dart`; contains `_backfillSimpleBusinessColumnsIfNeeded`, `_metaValue`, `_setMeta`. |
| [`ventio_drift_database_methods_05.dart`](../lib/core/storage/sqlite/ventio_drift_database_methods_05.dart) | Implementation part of `ventio_drift_database.dart`; contains `_createAccountingFoundation`. |
| [`ventio_drift_database_methods_06.dart`](../lib/core/storage/sqlite/ventio_drift_database_methods_06.dart) | Implementation part of `ventio_drift_database.dart`; contains `_addColumnIfMissing`. |
| [`ventio_drift_database_methods_07.dart`](../lib/core/storage/sqlite/ventio_drift_database_methods_07.dart) | Implementation part of `ventio_drift_database.dart`; contains `_seedDefaultChartOfAccounts`. |
| [`ventio_drift_database_methods_08.dart`](../lib/core/storage/sqlite/ventio_drift_database_methods_08.dart) | Implementation part of `ventio_drift_database.dart`; contains `_seedAdvancedAccountingDefaults`, `_migrateDefaultAccountingArabicLabels`, `_ensureWarehouseTransferOrderColumns`, `_ensureAssistantChatHistorySchema`, `_createBusinessEntityTable`. |

## `lib/core/sync_unified/`

| File | Contents / responsibility clue |
| --- | --- |
| [`direct_sync_transport_adapter.dart`](../lib/core/sync_unified/direct_sync_transport_adapter.dart) | Declares `DirectSyncTransportAdapter`. |
| [`lan_sync_transport_adapter.dart`](../lib/core/sync_unified/lan_sync_transport_adapter.dart) | Declares `LanSyncTransportAdapter`. |
| [`sync_contracts.dart`](../lib/core/sync_unified/sync_contracts.dart) | Declares `UnifiedSyncErrorCode`, `UnifiedSyncErrorCodeWire`, `UnifiedSyncError`, `UnifiedSyncEnvelope`, `UnifiedCursorEnvelope`, … (6 more). |
| [`sync_device_state.dart`](../lib/core/sync_unified/sync_device_state.dart) | Declares `SyncDeviceState`, `HostPeerSyncState`, `SyncPeerLiveStatus`, `SyncPeerLiveEvent`, `SyncDeviceStateStore`, … (3 more). |
| [`sync_transport_adapter.dart`](../lib/core/sync_unified/sync_transport_adapter.dart) | Declares `UnifiedSyncTransportKind`, `UnifiedSyncResult`, `UnifiedSyncResultSemantics`, `UnifiedSyncResultRepairDecision`, `UnifiedSyncResultFactory`, … (7 more). |
| [`sync_unified.dart`](../lib/core/sync_unified/sync_unified.dart) | Dart module for sync unified in `lib/core/sync_unified/`. |
| [`unified_auto_sync_controller.dart`](../lib/core/sync_unified/unified_auto_sync_controller.dart) | Declares `AutoSnapshotProgressPresenter`, `_SignalLoopWaitResult`, `UnifiedSyncFactory`, `UnifiedAutoLanSyncController`, `UnifiedAutoDirectSyncController`, … (3 more). |
| [`unified_direct_snapshot_retry_flow.dart`](../lib/core/sync_unified/unified_direct_snapshot_retry_flow.dart) | Declares `UnifiedDirectSnapshotRetryResult`, `UnifiedDirectSnapshotRetryFlow`. |
| [`unified_pairing_lifecycle.dart`](../lib/core/sync_unified/unified_pairing_lifecycle.dart) | Declares `UnifiedPairingClaimPayload`, `UnifiedPairingLifecycle`. |
| [`unified_pairing_snapshot_flow.dart`](../lib/core/sync_unified/unified_pairing_snapshot_flow.dart) | Declares `UnifiedPairingSnapshotSuccess`, `UnifiedPairingSnapshotFlow`. |
| [`unified_snapshot_lifecycle.dart`](../lib/core/sync_unified/unified_snapshot_lifecycle.dart) | Declares `UnifiedSnapshotApplyResult`, `UnifiedSnapshotLifecycle`. |
| [`unified_sync_engine.dart`](../lib/core/sync_unified/unified_sync_engine.dart) | Declares `UnifiedSyncEngine`. |
| [`unified_sync_orchestration.dart`](../lib/core/sync_unified/unified_sync_orchestration.dart) | Declares `UnifiedSyncPushInvoker`, `UnifiedSyncPullInvoker`, `UnifiedSnapshotRepairInvoker`, `runUnifiedSyncOrchestration`. |
| [`unified_sync_policy.dart`](../lib/core/sync_unified/unified_sync_policy.dart) | Declares `UnifiedSyncPolicy`. |
| [`unified_sync_transport_helpers.dart`](../lib/core/sync_unified/unified_sync_transport_helpers.dart) | Declares `UnifiedSyncTransportHelpers`. |

## `lib/core/theme/`

| File | Contents / responsibility clue |
| --- | --- |
| [`app_theme.dart`](../lib/core/theme/app_theme.dart) | Declares `AppTheme`. |

## `lib/core/utils/`

| File | Contents / responsibility clue |
| --- | --- |
| [`currency_utils.dart`](../lib/core/utils/currency_utils.dart) | Declares `_roundToDecimals`, `roundCashAmount`, `roundLbpAmount`, `currencyDefinition`, `accountingDecimalsForCurrency`, … (14 more). |
| [`responsive.dart`](../lib/core/utils/responsive.dart) | Declares `VentioScreenSize`, `VentioResponsive`, `ResponsivePage`, `ResponsiveDialogBox`, `ResponsiveActionRow`, … (1 more). |
| [`revision_cache.dart`](../lib/core/utils/revision_cache.dart) | Declares `RevisionValueCache`, `RevisionKeyCache`. |

## `lib/data/`

| File | Contents / responsibility clue |
| --- | --- |
| [`app_store.dart`](../lib/data/app_store.dart) | Library entry; declares `_ManufacturingCostResolution`, `DataConflict`, `BusinessDataIntegrityResult`, `BusinessDataIntegrityRepairResult`, `PurchasesOverview`, … (11 more) and composes parts `app_store_backup.dart`, `app_store_purchase_insights.dart`, `app_store_catalog_read.dart`, `app_store_party_read.dart`, `app_store_core_loading.dart`, … (70 more). |
| [`app_store_access_auth.dart`](../lib/data/app_store_access_auth.dart) | Implementation part of `app_store.dart`; contains `SensitiveActionAuthRequiredException`, `toString`, `authorizeSensitiveAction`, `clearSensitiveActionAuthorization`, `requireSensitiveActionAuthorization`, `canAccessPage`, … (13 more). |
| [`app_store_backup.dart`](../lib/data/app_store_backup.dart) | Implementation part of `app_store.dart`; contains `BackupSummary`, `BackupImportSection`, `BackupImportPlan`, `BackupValidationResult`, `exportEncryptedBackupJson`, `inspectBackupJson`, … (7 more). |
| [`app_store_backup_recovery.dart`](../lib/data/app_store_backup_recovery.dart) | Implementation part of `app_store.dart`; contains `_businessBackupJson`, `rebuildProductStockCache`, `rebuildAllProductStockCaches`, `_applyProductStockCompatibilityDeltas`, `_refreshProductStockCompatibilityCache`, `_backupSafeLocalDatabaseEntries`, … (9 more). |
| [`app_store_backup_recovery_split_02.dart`](../lib/data/app_store_backup_recovery_split_02.dart) | Implementation part of `app_store.dart`; contains `exportDirectBootstrapSnapshotChunks`, `exportRecoveryFileJson`, `parseRecoveryFileJson`, `_recoveryChecksum`, `exportBackupJson`, `currentHostSnapshotGeneration`, … (14 more). |
| [`app_store_backup_recovery_split_03.dart`](../lib/data/app_store_backup_recovery_split_03.dart) | Implementation part of `app_store.dart`; contains `importBackupJson`, `_shouldPreserveLiveHostConnectionKey`, `_isHostRebuildRuntimeKeyForAnotherImport`, `_readVersion`, `_readUpdatedAt`, `_dedupeUsersByUsername`. |
| [`app_store_backup_recovery_split_04.dart`](../lib/data/app_store_backup_recovery_split_04.dart) | Implementation part of `app_store.dart`; contains `_replaceUsersWithoutDuplicates`, `_mergeUsersWithoutUsernameDuplicates`, `_mergeByUpdatedAt`, `_mergeSyncChanges`, `mergeBackupJson`. |
| [`app_store_catalog_parties_expenses.dart`](../lib/data/app_store_catalog_parties_expenses.dart) | Implementation part of `app_store.dart`; contains `_indexProductAt`, `_unindexProduct`, `_indexCustomerAt`, `_indexSupplierAt`, `addOrUpdateProduct`, `addOrUpdateProductsBulk`, … (5 more). |
| [`app_store_catalog_parties_expenses_split_02.dart`](../lib/data/app_store_catalog_parties_expenses_split_02.dart) | Implementation part of `app_store.dart`; contains `addOrUpdateCustomersBulk`, `deleteCustomer`, `addOrUpdateSupplier`, `addOrUpdateSuppliersBulk`, `deleteSupplier`, `addOrUpdateCategory`, … (9 more). |
| [`app_store_catalog_parties_expenses_split_03.dart`](../lib/data/app_store_catalog_parties_expenses_split_03.dart) | Implementation part of `app_store.dart`; contains `editPostedExpense`, `_reverseExpenseCompatibilityForEditInTransaction`, `addOrUpdateExpense`, `postExpense`, `createAndPostExpensesBulk`, `deleteDraftExpense`, … (1 more). |
| [`app_store_catalog_parties_expenses_split_04.dart`](../lib/data/app_store_catalog_parties_expenses_split_04.dart) | Implementation part of `app_store.dart`; contains `permanentlyDeleteCancelledExpense`. |
| [`app_store_catalog_read.dart`](../lib/data/app_store_catalog_read.dart) | Implementation part of `app_store.dart`; contains `_productByIdReadImpl`, `_findProductByCodeReadImpl`, `_ensureProductsCacheReadImpl`, `_ensureStockTrackedProductsCacheReadImpl`, `_ensurePriceListsCacheReadImpl`, `_ensureProductPricesCacheReadImpl`, … (11 more). |
| [`app_store_core_loading.dart`](../lib/data/app_store_core_loading.dart) | Implementation part of `app_store.dart`; contains `_emitTrace`, `_traceAsync`, `_traceSync`, `_traceSyncResult`, `warmDeferredPageCaches`, `_requestLedgerDataLoad`, … (27 more). |
| [`app_store_core_loading_split_02.dart`](../lib/data/app_store_core_loading_split_02.dart) | Implementation part of `app_store.dart`; contains `_ensureSaleQuotationsCache`, `_ensureDeliveryNotesCache`, `_ensureDeliveryNoteLookupCache`, `_ensureBillsOfMaterialsCache`, `_ensureManufacturingOrdersCache`, `_rebuildInventoryCostLayerLookupCache`, … (22 more). |
| [`app_store_domains.dart`](../lib/data/app_store_domains.dart) | Implementation part of `app_store.dart`; contains `productById`, `ensureLoaded`, `ensureSalesLoaded`, `ensurePurchasesLoaded`, `accountBalance`, `transactionsForAccount`, … (14 more). |
| [`app_store_forwarding_api.dart`](../lib/data/app_store_forwarding_api.dart) | Implementation part of `app_store.dart`; contains `_traceAsync`, `_traceSync`, `_traceSyncResult`, `warmDeferredPageCaches`, `_requestSyncDataLoad`, `_loadDeferredGroup`, … (93 more). |
| [`app_store_forwarding_api_split_02.dart`](../lib/data/app_store_forwarding_api_split_02.dart) | Implementation part of `app_store.dart`; contains `_isReplayOrDuplicateSyncEvent`, `validateClientDraftForHostAcceptance`, `clearPendingSyncQueue`, `_loadInvoiceCounter`, `_runDataMigrationsIfNeeded`, `_safeUsdCost`, … (100 more). |
| [`app_store_forwarding_api_split_03.dart`](../lib/data/app_store_forwarding_api_split_03.dart) | Implementation part of `app_store.dart`; contains `_reconcileUnsyncedChangesWithQueue`, `_saleSyncMetaPreview`, `_purchaseSyncMetaPreview`, `_expenseSyncMetaPreview`, `_withSyncMeta`, `_persistAccountTransactionInExistingTransaction`, … (74 more). |
| [`app_store_forwarding_api_split_04.dart`](../lib/data/app_store_forwarding_api_split_04.dart) | Implementation part of `app_store.dart`; contains `settleAccountPayment`, `editReceiptVoucher`, `editPaymentVoucher`, `settleSalePayment`, `_settleSalePaymentInternal`, `settlePurchasePayment`, … (46 more). |
| [`app_store_forwarding_api_split_05.dart`](../lib/data/app_store_forwarding_api_split_05.dart) | Implementation part of `app_store.dart`; contains `editCompletedManufacturingOrder`, `reverseManufacturingOrder`, `createSaleQuotation`, `convertSaleQuotationToSale`, `deleteSaleQuotation`, `deliveryNoteForSale`, … (60 more). |
| [`app_store_identity_users.dart`](../lib/data/app_store_identity_users.dart) | Implementation part of `app_store.dart`; contains `_detectPlatform`, `_loadOrCreateAppIdentity`, `_detectInitialDeviceName`, `updateDeviceName`, `recoverExistingStoreIdentity`, `_identityForLanSnapshotImport`, … (21 more). |
| [`app_store_identity_users_split_02.dart`](../lib/data/app_store_identity_users_split_02.dart) | Implementation part of `app_store.dart`; contains `_restoreActiveUser`, `_isLoginTemporarilyBlocked`, `_registerLoginFailure`, `login`, `logout`, `applySessionUser`, … (13 more). |
| [`app_store_identity_users_split_03.dart`](../lib/data/app_store_identity_users_split_03.dart) | Implementation part of `app_store.dart`; contains `applyStoreOwnerCredentials`, `addOrUpdateUser`, `deleteUser`, `_hashPasswordAsync`, `_hashPasswordWithSalt`, `_hashLegacyLocalCredentialWithSalt`, … (17 more). |
| [`app_store_inventory.dart`](../lib/data/app_store_inventory.dart) | Implementation part of `app_store.dart`; contains `_stockAt`, `movementCountAfterInventoryLine`, `createInventoryCountSession`, `countInventoryLine`, `resetInventoryCountLine`, `approveInventoryCount`. |
| [`app_store_inventory_split_02.dart`](../lib/data/app_store_inventory_split_02.dart) | Implementation part of `app_store.dart`; contains `reverseInventoryCount`, `cancelInventoryCount`, `reviewAutoCorrection`, `setExpiryBatchStatus`, `_recordInventoryBatchSyncChanges`, `adjustExpiryBatchStock`. |
| [`app_store_inventory_split_03.dart`](../lib/data/app_store_inventory_split_03.dart) | Implementation part of `app_store.dart`; contains `reverseExpiryBatchAdjustment`, `manualStockAdjustmentVersion`. |
| [`app_store_inventory_split_04.dart`](../lib/data/app_store_inventory_split_04.dart) | Implementation part of `app_store.dart`; contains `editStockAdjustment`. |
| [`app_store_inventory_split_05.dart`](../lib/data/app_store_inventory_split_05.dart) | Implementation part of `app_store.dart`; contains `adjustStock`, `recordWasteLoss`, `reverseWasteLossGroup`. |
| [`app_store_inventory_split_06.dart`](../lib/data/app_store_inventory_split_06.dart) | Implementation part of `app_store.dart`; contains `deleteWasteLoss`, `_applyPurchaseStock`, `_addStockMovement`, `_reconcileInventoryAccountsAfterBomChange`. |
| [`app_store_manufacturing.dart`](../lib/data/app_store_manufacturing.dart) | Implementation part of `app_store.dart`; contains `estimatedUnifiedBatchUnitCostForProduct`, `_estimatedUnifiedBatchUnitCostForProduct`, `_repairZeroCostManufacturingInputBatchesInTransaction`, `estimateBillOfMaterialsSnapshot`, `estimateBillOfMaterialsUnitCost`, `createBillOfMaterials`, … (4 more). |
| [`app_store_manufacturing_split_02.dart`](../lib/data/app_store_manufacturing_split_02.dart) | Implementation part of `app_store.dart`; contains `updateManufacturingOrder`, `startManufacturingOrder`, `finishManufacturingOrder`. |
| [`app_store_manufacturing_split_03.dart`](../lib/data/app_store_manufacturing_split_03.dart) | Implementation part of `app_store.dart`; contains `completeManufacturingOrder`. |
| [`app_store_manufacturing_split_04.dart`](../lib/data/app_store_manufacturing_split_04.dart) | Implementation part of `app_store.dart`; contains `editCompletedManufacturingOrder`. |
| [`app_store_manufacturing_split_05.dart`](../lib/data/app_store_manufacturing_split_05.dart) | Implementation part of `app_store.dart`; contains `reverseManufacturingOrder`. |
| [`app_store_orchestration.dart`](../lib/data/app_store_orchestration.dart) | Implementation part of `app_store.dart`; contains `ensureSyncDataLoaded`, `ensureProductsLoaded`, `ensureCustomersLoaded`, `ensureSalesLoaded`, `ensureSaleQuotationsLoaded`, `ensureDeliveryNotesLoaded`, … (72 more). |
| [`app_store_party_read.dart`](../lib/data/app_store_party_read.dart) | Implementation part of `app_store.dart`; contains `_resolveCustomerNameReadImpl`, `_sanitizeSelectedCustomerIdReadImpl`, `_ensureSuppliersCacheReadImpl`, `_ensureSupplierProductPricesCacheReadImpl`. |
| [`app_store_persistence_sync_core.dart`](../lib/data/app_store_persistence_sync_core.dart) | Implementation part of `app_store.dart`; contains `_rebuildPurchaseIndexes`, `_saleByIdFromSqlite`, `_purchaseByIdFromSqlite`, `reloadPurchaseFromSqlite`, `_expenseByIdFromSqlite`, `_putStockMovementAtIndex`, … (18 more). |
| [`app_store_persistence_sync_core_split_02.dart`](../lib/data/app_store_persistence_sync_core_split_02.dart) | Implementation part of `app_store.dart`; contains `_saveDirty`, `_saveDirtySqliteHotPath`, `_resetBusinessDataInMemory`, `resetBusinessData`, `clearLocalDeviceBusinessData`, `clearLocalOnlyPendingSyncChanges`. |
| [`app_store_persistence_sync_core_split_03.dart`](../lib/data/app_store_persistence_sync_core_split_03.dart) | Implementation part of `app_store.dart`; contains `factoryResetLocalDevice`, `_hasPendingSyncFor`, `cleanupSoftDeletedRecords`, `verifyLocalBusinessDataIntegrity`, `repairMissingProductReferences`, `updateStoreProfile`, … (5 more). |
| [`app_store_persistence_sync_core_split_04.dart`](../lib/data/app_store_persistence_sync_core_split_04.dart) | Implementation part of `app_store.dart`; contains `_sqliteKeyForEntityType`, `_rememberSqliteDirtyBusinessRow`, `_forgetSqliteDirtyBusinessRow`, `_businessPayloadWithoutSyncEnvelope`, `_rememberRemoteSqliteBusinessRows`, `_recordSyncChange`, … (12 more). |
| [`app_store_persistence_sync_core_split_05.dart`](../lib/data/app_store_persistence_sync_core_split_05.dart) | Implementation part of `app_store.dart`; contains `addOrUpdateAccountTransaction`, `deleteAccountTransaction`, `_upsertAccountTransactionInternal`, `_recordPurchaseLedger`, `_recordPurchaseCancelLedger`, `_recordSaleLedger`, … (2 more). |
| [`app_store_pricing_costing.dart`](../lib/data/app_store_pricing_costing.dart) | Implementation part of `app_store.dart`; contains `_ensureDefaultPriceLists`, `_rebuildProductPriceLookupCache`, `_rebuildProductCostLookupCache`, `_rebuildProductPricingLookupCaches`, `_ensureProductPricingLookupCaches`, `_removeProductPricingLookupEntries`, … (11 more). |
| [`app_store_pricing_costing_split_02.dart`](../lib/data/app_store_pricing_costing_split_02.dart) | Implementation part of `app_store.dart`; contains `productCostSnapshotsForProducts`, `productCostSnapshotForProduct`, `_ensureProductCostEntries`, `_runtimeInventoryCostingMethod`, `_ensureCostingMethodHistory`, `_currentOpenFifoEffectiveFrom`, … (8 more). |
| [`app_store_pricing_costing_split_03.dart`](../lib/data/app_store_pricing_costing_split_03.dart) | Implementation part of `app_store.dart`; contains `_resolveCostForSaleItem`, `_resolveCostForSaleItemInTransaction`, `_restoreInventoryCostLayersFromSaleItemsInTransaction`, `_closeInventoryCostLayersForPurchaseInTransaction`, `_consumeManufacturingCostInTransaction`, `_restoreInventoryCostLayersFromSaleItem`, … (1 more). |
| [`app_store_purchase_insights.dart`](../lib/data/app_store_purchase_insights.dart) | Implementation part of `app_store.dart`; contains `_ensurePurchaseInsightsCacheImpl`, `_purchasePriceHistoryForProductImpl`, `_supplierPriceComparisonForProductImpl`, `_lastPurchasePriceForImpl`, `_lastPurchasePriceForProductImpl`, `_lastPurchaseItemForImpl`, … (2 more). |
| [`app_store_purchases.dart`](../lib/data/app_store_purchases.dart) | Implementation part of `app_store.dart`; contains `_stablePurchaseLineId`, `_unifiedOpeningCostForProductInTransaction`, `_ensureUnifiedBatchCutoverForProductInTransaction`, `_assertUnifiedBatchMovementBalancesInTransaction`, `_purchaseInventoryUnitCostPerBase`, `_receivedPurchasePaymentStatus`, … (4 more). |
| [`app_store_purchases_split_02.dart`](../lib/data/app_store_purchases_split_02.dart) | Implementation part of `app_store.dart`; contains `createPurchase`. |
| [`app_store_purchases_split_03.dart`](../lib/data/app_store_purchases_split_03.dart) | Implementation part of `app_store.dart`; contains `updatePurchaseDraft`. |
| [`app_store_purchases_split_04.dart`](../lib/data/app_store_purchases_split_04.dart) | Implementation part of `app_store.dart`; contains `receivePurchase`, `deleteDraftPurchase`, `permanentlyDeleteCancelledPurchase`, `_activePostedJournalCountInTransaction`, `_requirePostedJournalInTransaction`, `_requireNoActiveJournalInTransaction`, … (1 more). |
| [`app_store_purchases_split_05.dart`](../lib/data/app_store_purchases_split_05.dart) | Implementation part of `app_store.dart`; contains `editPurchaseReturn`. |
| [`app_store_purchases_split_06.dart`](../lib/data/app_store_purchases_split_06.dart) | Implementation part of `app_store.dart`; contains `createPurchaseReturn`. |
| [`app_store_purchases_split_07.dart`](../lib/data/app_store_purchases_split_07.dart) | Implementation part of `app_store.dart`; contains `returnPurchase`, `cancelPurchase`. |
| [`app_store_recovery.dart`](../lib/data/app_store_recovery.dart) | Implementation part of `app_store.dart`; contains `AppStoreRecoveryService`. |
| [`app_store_recovery_methods_01.dart`](../lib/data/app_store_recovery_methods_01.dart) | Implementation part of `app_store.dart`; contains `importBackupJson`, `mergeBackupJson`, `importSyncSnapshotJson`. |
| [`app_store_recovery_methods_02.dart`](../lib/data/app_store_recovery_methods_02.dart) | Implementation part of `app_store.dart`; contains `replaceFromSnapshotPayloadDirectToSqlite`, `replaceFromBackupMap`, `_snapshotListMaps`, `_snapshotScalarString`, `_identityForLanSnapshotImport`, `_shouldPreserveLiveHostConnectionKey`, … (10 more). |
| [`app_store_sales_returns.dart`](../lib/data/app_store_sales_returns.dart) | Implementation part of `app_store.dart`; contains `createSaleQuotation`, `convertSaleQuotationToSale`, `deleteSaleQuotation`, `deliveryNoteForSale`, `createDeliveryNoteFromSale`, `markDeliveryNoteDelivered`, … (1 more). |
| [`app_store_sales_returns_split_02.dart`](../lib/data/app_store_sales_returns_split_02.dart) | Implementation part of `app_store.dart`; contains `createSale`. |
| [`app_store_sales_returns_split_03.dart`](../lib/data/app_store_sales_returns_split_03.dart) | Implementation part of `app_store.dart`; contains `editPostedSale`. |
| [`app_store_sales_returns_split_04.dart`](../lib/data/app_store_sales_returns_split_04.dart) | Implementation part of `app_store.dart`; contains `_saleOperationalVersion`, `_saleStockMovementId`, `_saleStockMovementIdempotencyKey`, `_saleMovementGroupId`, `_returnedSaleQuantitiesByProduct`, `_remainingReversibleStockQuantityInTransaction`, … (2 more). |
| [`app_store_sales_returns_split_05.dart`](../lib/data/app_store_sales_returns_split_05.dart) | Implementation part of `app_store.dart`; contains `returnSale`. |
| [`app_store_sales_returns_split_06.dart`](../lib/data/app_store_sales_returns_split_06.dart) | Implementation part of `app_store.dart`; contains `editSaleReturn`. |
| [`app_store_sales_returns_split_07.dart`](../lib/data/app_store_sales_returns_split_07.dart) | Implementation part of `app_store.dart`; contains `cancelSaleReturn`. |
| [`app_store_sales_returns_split_08.dart`](../lib/data/app_store_sales_returns_split_08.dart) | Implementation part of `app_store.dart`; contains `cancelSale`, `deleteSale`, `estimateProfit`. |
| [`app_store_startup_migrations.dart`](../lib/data/app_store_startup_migrations.dart) | Implementation part of `app_store.dart`; contains `initialize`, `_loadEntityListJsonForStartup`, `_loadEntityListJsonBatchesForStartup`, `_decodeDeferredList`, `_loadTypedEntityList`, `_loadStockMovementsForStartup`, … (3 more). |
| [`app_store_startup_migrations_split_02.dart`](../lib/data/app_store_startup_migrations_split_02.dart) | Implementation part of `app_store.dart`; contains `_loadDeferredStartupData`, `_loadLedgerDeferredStartupData`, `_loadSyncDeferredStartupData`, `refreshAccountTransactionsFromSqlite`, `refreshSalesProductData`, `refreshAfterDatabaseChange`, … (4 more). |
| [`app_store_startup_migrations_split_03.dart`](../lib/data/app_store_startup_migrations_split_03.dart) | Implementation part of `app_store.dart`; contains `_ensureCatalogDefaults`, `_seedCatalogFromProducts`, `_loadSyncChanges`, `_loadSyncSequence`, `_nextSyncSequence`, `_newSyncEnvelopeId`, … (13 more). |
| [`app_store_state.dart`](../lib/data/app_store_state.dart) | Implementation part of `app_store.dart`; contains `_cachedProducts`, `_cachedProductsGeneration`, `_cachedStockTrackedProducts`, `_cachedStockTrackedProductsGeneration`, `_cachedSupplierProductPrices`, `_cachedPriceLists`, … (75 more). |
| [`app_store_supplier_insights.dart`](../lib/data/app_store_supplier_insights.dart) | Implementation part of `app_store.dart`; contains `_seedSupplierProductPricesFromPurchaseHistory`, `_seedSupplierProductPricesFromLegacyProductSuppliers`, `_markSingleSupplierPerProductAsPreferred`, `_supplierProductPriceId`, `supplierCountForProduct`, `supplierProductPricesForProduct`, … (7 more). |
| [`app_store_sync_apply.dart`](../lib/data/app_store_sync_apply.dart) | Implementation part of `app_store.dart`; contains `markAllSyncChangesSynced`, `importSyncSnapshotJson`, `_replaceFromBackupMap`, `_syncHistoryCompactionResult`, `_syncHistoryCompactionLogLine`, `compactSyncedSyncHistoryForDiagnostics`, … (4 more). |
| [`app_store_sync_apply_split_02.dart`](../lib/data/app_store_sync_apply_split_02.dart) | Implementation part of `app_store.dart`; contains `applyRemoteSyncChanges`, `_addDuplicateConflicts`, `_detectDataConflicts`, `_remoteWins`, `_upsertByUpdatedAt`, `_applySupplierProductPriceFromSync`. |
| [`app_store_sync_apply_split_03.dart`](../lib/data/app_store_sync_apply_split_03.dart) | Implementation part of `app_store.dart`; contains `_applySyncChangePayload`, `_remoteSyncChangeApplyProblem`, `assertRemoteSyncChangesApplied`, `markSyncChangesSubmittedByIds`, `markSyncChangesSyncedByIds`, `settleLegacyLanHostQueue`, … (1 more). |
| [`app_store_sync_apply_split_04.dart`](../lib/data/app_store_sync_apply_split_04.dart) | Implementation part of `app_store.dart`; contains `markSyncQueueChangesInProgress`, `markSyncChangesRejectedByIds`, `_quarantineRejectedLocalCreates`, `markSyncQueueChangesFailed`, `retryFailedSyncQueue`, `recoverStaleInProgressSyncQueue`, … (3 more). |
| [`app_store_warehouse_cash.dart`](../lib/data/app_store_warehouse_cash.dart) | Implementation part of `app_store.dart`; contains `_loadPurchaseCounter`, `createWarehouse`, `recentWarehouseTransferOrders`, `createWarehouseTransferOrder`. |
| [`app_store_warehouse_cash_split_02.dart`](../lib/data/app_store_warehouse_cash_split_02.dart) | Implementation part of `app_store.dart`; contains `editWarehouseTransferOrder`. |
| [`app_store_warehouse_cash_split_03.dart`](../lib/data/app_store_warehouse_cash_split_03.dart) | Implementation part of `app_store.dart`; contains `transferStock`, `_openCashVoucherContext`, `_saleReturnEntitlementFromSqlite`, `refundableSaleCashAmount`, `normalizeRefundAllocations`, `refundablePurchaseCashAmount`, … (4 more). |
| [`app_store_warehouse_cash_split_04.dart`](../lib/data/app_store_warehouse_cash_split_04.dart) | Implementation part of `app_store.dart`; contains `refundableExpenseCashAmount`, `refundExpenseCash`, `settleAccountPayment`, `editReceiptVoucher`, `editPaymentVoucher`, `settleSalePayment`, … (3 more). |
| [`backup_inventory_normalizer.dart`](../lib/data/backup_inventory_normalizer.dart) | Declares `normalizeBackupInventoryForStore`. |
| [`mock_data.dart`](../lib/data/mock_data.dart) | Declares `MockData`. |

## `lib/features/account/`

| File | Contents / responsibility clue |
| --- | --- |
| [`store_account_dashboard_page.dart`](../lib/features/account/store_account_dashboard_page.dart) | Declares `StoreAccountDashboardPage`, `_StoreAccountDashboardPageState`, `_AccountNavigation`, `_MetricCard`, `_InfoRow`, … (1 more). |

## `lib/features/accounting/`

| File | Contents / responsibility clue |
| --- | --- |
| [`accounting_page.dart`](../lib/features/accounting/accounting_page.dart) | Library entry; declares `AccountingPage`, `_AccountingPageState` and composes parts `accounting_page_chart_of_accounts.dart`, `accounting_page_report_navigation.dart`, `accounting_page_subledgers.dart`, `accounting_page_cash.dart`, `accounting_page_transactions.dart`, … (13 more). |
| [`accounting_page_advanced.dart`](../lib/features/accounting/accounting_page_advanced.dart) | Implementation part of `accounting_page.dart`; contains `_AdvancedAccountingTab`, `createState`, `initState`, `_load`, `_refresh`, `dispose`, … (4 more). |
| [`accounting_page_advanced_assets.dart`](../lib/features/accounting/accounting_page_advanced_assets.dart) | Implementation part of `accounting_page.dart`; contains `_runDepreciationForAllDialog`, `_runDepreciationForAssetDialog`, `_createFixedAssetDialog`. |
| [`accounting_page_advanced_cash.dart`](../lib/features/accounting/accounting_page_advanced_cash.dart) | Implementation part of `accounting_page.dart`; contains `_createCashLocationDialog`, `_showCashTransferJournalHint`, `_openingBalancesDialog`. |
| [`accounting_page_advanced_journal.dart`](../lib/features/accounting/accounting_page_advanced_journal.dart) | Implementation part of `accounting_page.dart`; contains `_manualJournalDialog`. |
| [`accounting_page_advanced_operations.dart`](../lib/features/accounting/accounting_page_advanced_operations.dart) | Implementation part of `accounting_page.dart`; contains `_createPaymentAccountDialog`, `_createChequeDialog`, `_createMasterDataDialog`, `_settleCheque`, `_bounceChequeDialog`, `_closePeriod`, … (1 more). |
| [`accounting_page_cash.dart`](../lib/features/accounting/accounting_page_cash.dart) | Implementation part of `accounting_page.dart`; contains `_CashLedgerTransactionsTab`, `createState`, `initState`, `didUpdateWidget`, `dispose`, `_handleStoreChanged`, … (12 more). |
| [`accounting_page_cash_tax_reports.dart`](../lib/features/accounting/accounting_page_cash_tax_reports.dart) | Implementation part of `accounting_page.dart`; contains `_CashBankReportTab`, `build`, `_CashFlowStatementTab`, `_CashFlowSection`, `_StatementLine`, `_TaxReportTab`, … (1 more). |
| [`accounting_page_chart_of_accounts.dart`](../lib/features/accounting/accounting_page_chart_of_accounts.dart) | Implementation part of `accounting_page.dart`; contains `_ChartOfAccountsTab`, `createState`, `initState`, `_reload`, `_refresh`, `_createAccountDialog`, … (6 more). |
| [`accounting_page_financial_statements.dart`](../lib/features/accounting/accounting_page_financial_statements.dart) | Implementation part of `accounting_page.dart`; contains `_TrialBalanceTab`, `build`, `_IncomeStatementTab`, `_InventoryManufacturingReportBundle`, `load`, `_InventoryManufacturingReportsTab`, … (1 more). |
| [`accounting_page_general_ledger.dart`](../lib/features/accounting/accounting_page_general_ledger.dart) | Implementation part of `accounting_page.dart`; contains `_GeneralLedgerTab`, `createState`, `initState`, `_loadFilterData`, `_pickRange`, `build`, … (3 more). |
| [`accounting_page_journal_entries.dart`](../lib/features/accounting/accounting_page_journal_entries.dart) | Implementation part of `accounting_page.dart`; contains `_JournalEntriesTab`, `createState`, `initState`, `_pickRange`, `_editManualJournal`, `build`, … (7 more). |
| [`accounting_page_report_navigation.dart`](../lib/features/accounting/accounting_page_report_navigation.dart) | Implementation part of `accounting_page.dart`; contains `_AccountingReportRange`, `_ReportsAccountingGroup`, `createState`, `initState`, `_loadAccountingPeriods`, `_startOfDay`, … (18 more). |
| [`accounting_page_report_widgets.dart`](../lib/features/accounting/accounting_page_report_widgets.dart) | Implementation part of `accounting_page.dart`; contains `_AccountSelector`, `build`, `_FinancialReportTitle`, `_ReportBalanceBanner`, `_FinancialBreakdownSection`, `_FinancialStatementLine`, … (17 more). |
| [`accounting_page_roles.dart`](../lib/features/accounting/accounting_page_roles.dart) | Implementation part of `accounting_page.dart`; contains `_AccountingRolesTab`, `createState`, `initState`, `didUpdateWidget`, `_load`, `_loadCached`, … (7 more). |
| [`accounting_page_settings.dart`](../lib/features/accounting/accounting_page_settings.dart) | Implementation part of `accounting_page.dart`; contains `_AccountingSettingsTab`, `createState`, `initState`, `didUpdateWidget`, `_load`, `_updateVatRate`, … (11 more). |
| [`accounting_page_shell_widgets.dart`](../lib/features/accounting/accounting_page_shell_widgets.dart) | Implementation part of `accounting_page.dart`; contains `_AccessDeniedScaffold`, `build`, `_AccountingHeader`, `_CachedFuturePanel`, `Function`, `createState`, … (14 more). |
| [`accounting_page_subledgers.dart`](../lib/features/accounting/accounting_page_subledgers.dart) | Implementation part of `accounting_page.dart`; contains `_AccountsTab`, `_rowsFromSqlite`, `build`, `_AccountsTabMemory`, `_AccountsRowsView`, `_AccountRowData`, … (11 more). |
| [`accounting_page_transactions.dart`](../lib/features/accounting/accounting_page_transactions.dart) | Implementation part of `accounting_page.dart`; contains `_TransactionsTab`, `build`, `_isCashTxn`, `_TransactionTableHeader`, `_TransactionRow`, `_iconForType`, … (3 more). |
| [`accounting_snapshot_service.dart`](../lib/features/accounting/accounting_snapshot_service.dart) | Declares `AccountingSnapshotService`, `_computeSnapshotFromStore`. |

## `lib/features/accounts/`

| File | Contents / responsibility clue |
| --- | --- |
| [`account_ledger_widgets.dart`](../lib/features/accounts/account_ledger_widgets.dart) | Declares `_AccountLedgerSheet`, `_TransactionTile`, `_PaymentDraft`, `_PaymentDialog`, `_PaymentDialogState`, … (4 more). |
| [`account_statement_actions.dart`](../lib/features/accounts/account_statement_actions.dart) | Declares `_ExpenseAccountSelection`, `_ExpenseAccountFilterDialog`, `_ExpenseAccountFilterDialogState`, `pickAccountStatementDateRange`, `printAccountStatementForAccount`, … (8 more). |

## `lib/features/admin/`

| File | Contents / responsibility clue |
| --- | --- |
| [`admin_subscribers_page.dart`](../lib/features/admin/admin_subscribers_page.dart) | Library entry; declares shared library definitions and composes parts `admin_subscribers_page_split_01.dart`, `admin_subscribers_page_split_02.dart`. |
| [`admin_subscribers_page_split_01.dart`](../lib/features/admin/admin_subscribers_page_split_01.dart) | Implementation part of `admin_subscribers_page.dart`; contains `AdminSubscribersPage`, `createState`, `initState`, `dispose`, `_platformAccessToken`, `_load`, … (11 more). |
| [`admin_subscribers_page_split_02.dart`](../lib/features/admin/admin_subscribers_page_split_02.dart) | Implementation part of `admin_subscribers_page.dart`; contains `_SubscribersToolbar`, `build`, `_SubscriberIdentity`, `_StoreCell`, `_PlanBadge`, `_StatusBadge`, … (5 more). |

## `lib/features/assistant/`

| File | Contents / responsibility clue |
| --- | --- |
| [`assistant_attachment_service.dart`](../lib/features/assistant/assistant_attachment_service.dart) | Declares `AssistantAttachment`, `AssistantAttachmentService`. |
| [`assistant_business_analysis_service.dart`](../lib/features/assistant/assistant_business_analysis_service.dart) | Declares `AssistantBusinessAnalysisService`, `AssistantBusinessAnalysisException`. |
| [`assistant_chat_history_dialog.dart`](../lib/features/assistant/assistant_chat_history_dialog.dart) | Declares `AssistantChatHistoryDialog`, `_AssistantChatHistoryDialogState`. |
| [`assistant_chat_history_store.dart`](../lib/features/assistant/assistant_chat_history_store.dart) | Declares `AssistantSavedConversation`, `AssistantSavedExchange`, `AssistantPendingExchange`, `AssistantChatHistoryStore`. |
| [`assistant_chat_page.dart`](../lib/features/assistant/assistant_chat_page.dart) | Library entry; declares shared library definitions and composes parts `assistant_chat_page_split_01.dart`, `assistant_chat_page_split_02.dart`, `assistant_chat_page_split_03.dart`. |
| [`assistant_chat_page_split_01.dart`](../lib/features/assistant/assistant_chat_page_split_01.dart) | Implementation part of `assistant_chat_page.dart`; contains `AssistantChatPage`, `createState`. |
| [`assistant_chat_page_split_02.dart`](../lib/features/assistant/assistant_chat_page_split_02.dart) | Implementation part of `assistant_chat_page.dart`; contains `initState`, `dispose`, `_loadConfiguration`, `_restoreMostRecentConversation`, `_loadSavedConversation`, `_startNewChat`, … (13 more). |
| [`assistant_chat_page_split_03.dart`](../lib/features/assistant/assistant_chat_page_split_03.dart) | Implementation part of `assistant_chat_page.dart`; contains `_AssistantMessageBubble`, `build`, `_AssistantAnswerContent`, `_inlineSpans`, `_tableCells`, `_AssistantTypingIndicator`. |
| [`assistant_conversation_service.dart`](../lib/features/assistant/assistant_conversation_service.dart) | Declares `AssistantConversationService`, `_AssistantScope`. |
| [`assistant_database_explorer_service.dart`](../lib/features/assistant/assistant_database_explorer_service.dart) | Library entry; declares `AssistantDatabaseExplorerService`, `AssistantDatabaseExplorerException`, `_Domain`, `_DimensionSpec`, `_MeasureSpec`, … (2 more) and composes parts `assistant_database_explorer_specs_01.dart`, `assistant_database_explorer_specs_02.dart`, `assistant_database_explorer_specs_03.dart`, `assistant_database_explorer_specs_04.dart`. |
| [`assistant_database_explorer_specs_01.dart`](../lib/features/assistant/assistant_database_explorer_specs_01.dart) | Implementation part of `assistant_database_explorer_service.dart`; contains supporting declarations. |
| [`assistant_database_explorer_specs_02.dart`](../lib/features/assistant/assistant_database_explorer_specs_02.dart) | Implementation part of `assistant_database_explorer_service.dart`; contains supporting declarations. |
| [`assistant_database_explorer_specs_03.dart`](../lib/features/assistant/assistant_database_explorer_specs_03.dart) | Implementation part of `assistant_database_explorer_service.dart`; contains supporting declarations. |
| [`assistant_database_explorer_specs_04.dart`](../lib/features/assistant/assistant_database_explorer_specs_04.dart) | Implementation part of `assistant_database_explorer_service.dart`; contains supporting declarations. |
| [`assistant_how_to_knowledge_service.dart`](../lib/features/assistant/assistant_how_to_knowledge_service.dart) | Declares `AssistantHowToKnowledgeService`, `_Guide`. |
| [`assistant_provider.dart`](../lib/features/assistant/assistant_provider.dart) | Declares `AssistantJsonMap`, `AssistantProvider`, `AssistantThinkingLevel`, `AssistantChatRole`, `AssistantMessageRole`, … (6 more). |
| [`assistant_provider_settings_page.dart`](../lib/features/assistant/assistant_provider_settings_page.dart) | Declares `AssistantProviderSettingsPage`, `_AssistantProviderSettingsPageState`. |
| [`assistant_provider_settings_service.dart`](../lib/features/assistant/assistant_provider_settings_service.dart) | Declares `AssistantProviderSettingsService`. |
| [`assistant_provider_transport.dart`](../lib/features/assistant/assistant_provider_transport.dart) | Declares `AssistantProviderTransport`. |
| [`assistant_read_tool_service.dart`](../lib/features/assistant/assistant_read_tool_service.dart) | Library entry; declares `AssistantReadToolException`, `AssistantReadToolService`, `_AssistantReadToolServiceImplementation`, `_AssistantDatePeriod`, `_AssistantParty`, … (1 more) and composes parts `assistant_read_tool_service_impl_01.dart`, `assistant_read_tool_service_impl_02.dart`, `assistant_read_tool_service_impl_03.dart`, `assistant_read_tool_service_impl_04.dart`. |
| [`assistant_read_tool_service_impl_01.dart`](../lib/features/assistant/assistant_read_tool_service_impl_01.dart) | Implementation part of `assistant_read_tool_service.dart`; contains `definitionsFor`. |
| [`assistant_read_tool_service_impl_02.dart`](../lib/features/assistant/assistant_read_tool_service_impl_02.dart) | Implementation part of `assistant_read_tool_service.dart`; contains `execute`. |
| [`assistant_read_tool_service_impl_03.dart`](../lib/features/assistant/assistant_read_tool_service_impl_03.dart) | Implementation part of `assistant_read_tool_service.dart`; contains `_readPartyAccountStatement`, `_readInvoiceDetails`, `_saleInvoiceData`, `_purchaseInvoiceData`, `_readPartyPaymentHistory`, `_receiptVoucherData`, … (5 more). |
| [`assistant_read_tool_service_impl_04.dart`](../lib/features/assistant/assistant_read_tool_service_impl_04.dart) | Implementation part of `assistant_read_tool_service.dart`; contains `_requiredPartyType`, `_requirePartyLedgerPermission`, `_invoiceMatches`, `_invoiceNumberIsExact`, `_dateMatches`, `_localDateOnly`, … (19 more). |
| [`assistant_report_export_service.dart`](../lib/features/assistant/assistant_report_export_service.dart) | Declares `AssistantReportExportService`. |

## `lib/features/barcode/`

| File | Contents / responsibility clue |
| --- | --- |
| [`barcode_labels_page.dart`](../lib/features/barcode/barcode_labels_page.dart) | Declares `BarcodeLabelsPage`, `_BarcodeLabelsPageState`, `_BarcodeTarget`, `_BarcodePrintOptionsDialog`, `_BarcodePrintOptionsDialogState`, … (1 more). |
| [`barcode_scanner_page.dart`](../lib/features/barcode/barcode_scanner_page.dart) | Declares `BarcodeScannerPage`, `_BarcodeScannerPageState`, `_ScannerErrorView`. |

## `lib/features/cash/`

| File | Contents / responsibility clue |
| --- | --- |
| [`cash_history_panel.dart`](../lib/features/cash/cash_history_panel.dart) | Declares `CashHistoryPanel`, `_CashHistoryPanelState`, `_CashHistorySnapshot`. |
| [`cash_page.dart`](../lib/features/cash/cash_page.dart) | Library entry; declares `_ExpenseSettlementSelection`, `CashPage`, `_CashPageState` and composes parts `cash_page_methods_01.dart`, `cash_page_methods_02.dart`, `cash_page_methods_03.dart`, `cash_page_methods_04.dart`. |
| [`cash_page_methods_01.dart`](../lib/features/cash/cash_page_methods_01.dart) | Implementation part of `cash_page.dart`; contains `_refresh`, `_cashPurchasesSnapshot`, `_settleSaleInvoiceDialog`, `_settlePurchaseInvoiceDialog`, `_l`, `_refundPurchaseReturnDialog`. |
| [`cash_page_methods_02.dart`](../lib/features/cash/cash_page_methods_02.dart) | Implementation part of `cash_page.dart`; contains `_refundDialog`, `_settleExpenseDialog`. |
| [`cash_page_methods_03.dart`](../lib/features/cash/cash_page_methods_03.dart) | Implementation part of `cash_page.dart`; contains `_cashOperationDialog`, `_cashTransferDialog`, `_openDrawerDialog`, `_closeDrawerDialog`, `_loadAllShiftMovements`. |
| [`cash_page_methods_04.dart`](../lib/features/cash/cash_page_methods_04.dart) | Implementation part of `cash_page.dart`; contains `_showShiftReportsDialog`, `_pageHeader`, `_dashboardMetric`, `_quickActionsCard`, `_shiftSummaryCard`, `_shiftLine`. |

## `lib/features/customers/`

| File | Contents / responsibility clue |
| --- | --- |
| [`customers_page.dart`](../lib/features/customers/customers_page.dart) | Declares `CustomersPage`, `_CustomersPageState`, `_CustomerQueryResult`, `_AccessDeniedScaffold`, `_CustomerDialog`, … (1 more). |

## `lib/features/dashboard/`

| File | Contents / responsibility clue |
| --- | --- |
| [`dashboard_page.dart`](../lib/features/dashboard/dashboard_page.dart) | Library entry; declares shared library definitions and composes parts `dashboard_page_split_01.dart`, `dashboard_page_split_02.dart`, `dashboard_page_split_03.dart`. |
| [`dashboard_page_split_01.dart`](../lib/features/dashboard/dashboard_page_split_01.dart) | Implementation part of `dashboard_page.dart`; contains `DashboardPage`, `createState`, `initState`, `didUpdateWidget`, `dispose`, `_handleStoreChanged`, … (20 more). |
| [`dashboard_page_split_02.dart`](../lib/features/dashboard/dashboard_page_split_02.dart) | Implementation part of `dashboard_page.dart`; contains `_QuickActionsPanel`, `build`, `_QuickActionTile`, `createState`, `_MainChartPanel`, `Function`, … (10 more). |
| [`dashboard_page_split_03.dart`](../lib/features/dashboard/dashboard_page_split_03.dart) | Implementation part of `dashboard_page.dart`; contains `_LineChartPainter`, `paint`, `shouldRepaint`, `BoxShadow`, `_softShadow`. |
| [`dashboard_service.dart`](../lib/features/dashboard/dashboard_service.dart) | Declares `DashboardStatusLevel`, `DashboardOperationType`, `DashboardMetric`, `DashboardOperationItem`, `DashboardHealthSnapshot`, … (7 more). |
| [`dashboard_snapshot_service.dart`](../lib/features/dashboard/dashboard_snapshot_service.dart) | Library entry; declares `DashboardSnapshotService`, `DashboardSnapshotCache` and composes parts `dashboard_snapshot_service_methods_01.dart`, `dashboard_snapshot_service_methods_02.dart`. |
| [`dashboard_snapshot_service_methods_01.dart`](../lib/features/dashboard/dashboard_snapshot_service_methods_01.dart) | Implementation part of `dashboard_snapshot_service.dart`; contains `_summaryFutureKey`, `loadCachedSummary`, `_saveCachedSummary`, `buildState`, `prewarmSummary`, `buildStateFromCachedSummary`, … (8 more). |
| [`dashboard_snapshot_service_methods_02.dart`](../lib/features/dashboard/dashboard_snapshot_service_methods_02.dart) | Implementation part of `dashboard_snapshot_service.dart`; contains `_computeSnapshotFromStore`. |

## `lib/features/database/`

| File | Contents / responsibility clue |
| --- | --- |
| [`database_page.dart`](../lib/features/database/database_page.dart) | Library entry; declares `DatabasePage`, `_DatabasePageState`, `_AccessDeniedScaffold` and composes parts `database_page_methods_01.dart`, `database_page_methods_02.dart`, `database_page_methods_03.dart`. |
| [`database_page_methods_01.dart`](../lib/features/database/database_page_methods_01.dart) | Implementation part of `database_page.dart`; contains `_t`, `_tf`, `_displayKey`, `_reload`, `_deleteSelectedRows`, `_buildLockedView`, … (8 more). |
| [`database_page_methods_02.dart`](../lib/features/database/database_page_methods_02.dart) | Implementation part of `database_page.dart`; contains `_buildSqlEditorView`, `_buildSqlResults`, `_buildSqlResultTable`, `_latestExportableSqlResultIndex`, `_buildSqlExportButton`, `_buildSqlExportFormatButton`, … (14 more). |
| [`database_page_methods_03.dart`](../lib/features/database/database_page_methods_03.dart) | Implementation part of `database_page.dart`; contains `_sortedRows`, `_compareValues`, `_sortByColumn`, `_openCellEditor`, `_openRowEditor`, `_isLargeField`, … (5 more). |

## `lib/features/expenses/`

| File | Contents / responsibility clue |
| --- | --- |
| [`expenses_page.dart`](../lib/features/expenses/expenses_page.dart) | Library entry; declares shared library definitions and composes parts `expenses_page_split_01.dart`, `expenses_page_split_02.dart`, `expenses_page_split_03.dart`. |
| [`expenses_page_split_01.dart`](../lib/features/expenses/expenses_page_split_01.dart) | Implementation part of `expenses_page.dart`; contains `ExpensesPage`, `createState`, `_handleStoreChanged`, `initState`, `dispose`, `didUpdateWidget`, … (12 more). |
| [`expenses_page_split_02.dart`](../lib/features/expenses/expenses_page_split_02.dart) | Implementation part of `expenses_page.dart`; contains `_ExpenseQueryResult`, `_ExpensePostingSelection`, `_AccessDeniedScaffold`, `build`, `_ExpenseCard`, `_ExpenseCatalogItem`, … (5 more). |
| [`expenses_page_split_03.dart`](../lib/features/expenses/expenses_page_split_03.dart) | Implementation part of `expenses_page.dart`; contains `initState`, `dispose`, `_loadCatalog`, `_decodeItemList`, `_decodeTypesMap`, `_mergeLegacyExpensesIntoCatalog`, … (12 more). |

## `lib/features/inventory/`

| File | Contents / responsibility clue |
| --- | --- |
| [`batch_allocation_dialog.dart`](../lib/features/inventory/batch_allocation_dialog.dart) | Declares `_BatchDraft`, `showBatchAllocationDialog`. |
| [`inventory_page.dart`](../lib/features/inventory/inventory_page.dart) | Library entry; declares shared library definitions and composes parts `inventory_page_split_01.dart`, `inventory_page_split_02.dart`, `inventory_page_split_03.dart`, `inventory_page_split_04.dart`, `inventory_page_split_05.dart`, … (1 more). |
| [`inventory_page_split_01.dart`](../lib/features/inventory/inventory_page_split_01.dart) | Implementation part of `inventory_page.dart`; contains `InventoryPage`, `createState`, `_InventoryOverviewMetrics`, `_InventoryBatchesTab`, `_changeStatus`, `_adjustBatch`, … (4 more). |
| [`inventory_page_split_02.dart`](../lib/features/inventory/inventory_page_split_02.dart) | Implementation part of `inventory_page.dart`; contains `_warehouseStock`, `_handleStoreChanged`, `initState`, `dispose`, `didUpdateWidget`, `_scanInventorySearchBarcode`, … (13 more). |
| [`inventory_page_split_03.dart`](../lib/features/inventory/inventory_page_split_03.dart) | Implementation part of `inventory_page.dart`; contains `didUpdateWidget`, `_loadStockRowsByWarehouse`, `_stockRowsByWarehouseFuture`, `_createWarehouse`, `_transferStock`, `_printWarehouseInventory`, … (4 more). |
| [`inventory_page_split_04.dart`](../lib/features/inventory/inventory_page_split_04.dart) | Implementation part of `inventory_page.dart`; contains `_movementTypeOptions`, `_warehouseOptions`, `_resetMovementFilters`, `didUpdateWidget`, `dispose`, `_queryMovementsFromSqlite`, … (10 more). |
| [`inventory_page_split_05.dart`](../lib/features/inventory/inventory_page_split_05.dart) | Implementation part of `inventory_page.dart`; contains `didUpdateWidget`, `_queryCorrectionsFromSqlite`, `_queryPendingCorrectionsCount`, `_queryAllCorrectionsCount`, `_loadMoreCorrections`, `build`, … (13 more). |
| [`inventory_page_split_06.dart`](../lib/features/inventory/inventory_page_split_06.dart) | Implementation part of `inventory_page.dart`; contains `_StockCountProductTile`, `build`, `_resetCount`, `_enterCount`, `showDialog`, `Function`, … (14 more). |
| [`manufacturing_page.dart`](../lib/features/inventory/manufacturing_page.dart) | Library entry; declares `ManufacturingPage`, `_ManufacturingPageState`, `_AccessDeniedScaffold`, `_SummaryCard` and composes parts `manufacturing_page_methods_01.dart`, `manufacturing_page_methods_02.dart`, `manufacturing_page_methods_03.dart`. |
| [`manufacturing_page_methods_01.dart`](../lib/features/inventory/manufacturing_page_methods_01.dart) | Implementation part of `manufacturing_page.dart`; contains `_t`, `_tf`, `_buildRecipesTab`, `_buildOrdersTab`, `_localizedText`, `_manufacturingStatusLabel`, … (3 more). |
| [`manufacturing_page_methods_02.dart`](../lib/features/inventory/manufacturing_page_methods_02.dart) | Implementation part of `manufacturing_page.dart`; contains `_showBomDialog`, `_confirmDeleteBom`, `_showCompleteOrderDialog`, `_confirmDeleteManufacturingOrder`, `_showOrderDetails`. |
| [`manufacturing_page_methods_03.dart`](../lib/features/inventory/manufacturing_page_methods_03.dart) | Implementation part of `manufacturing_page.dart`; contains `_reverseManufacturingOrder`, `_orderDetailRow`, `_formatOrderDate`, `_showEditOrderDialog`, `_showFinishOrderDialog`. |
| [`warehouse_transfer_page.dart`](../lib/features/inventory/warehouse_transfer_page.dart) | Declares `WarehouseTransferPage`, `_WarehouseTransferPageState`, `_TransferDraftItem`. |

## `lib/features/maintenance/`

| File | Contents / responsibility clue |
| --- | --- |
| [`diagnostics_page.dart`](../lib/features/maintenance/diagnostics_page.dart) | Declares `DiagnosticsPage`, `_DiagnosticsPageState`, `_LogsList`, `_AppLogTile`, `_AuditLogTile`. |
| [`disaster_recovery_service.dart`](../lib/features/maintenance/disaster_recovery_service.dart) | Dart module for disaster recovery service in `lib/features/maintenance/`. |
| [`disaster_recovery_service_io.dart`](../lib/features/maintenance/disaster_recovery_service_io.dart) | Declares `DisasterRecoveryVerificationResult`, `DisasterRecoveryReadiness`, `DisasterRecoveryService`. |
| [`disaster_recovery_service_stub.dart`](../lib/features/maintenance/disaster_recovery_service_stub.dart) | Declares `DisasterRecoveryVerificationResult`, `DisasterRecoveryReadiness`, `DisasterRecoveryService`. |
| [`maintenance_models.dart`](../lib/features/maintenance/maintenance_models.dart) | Declares `MaintenanceSeverity`, `MaintenanceRepairAction`, `MaintenanceIssue`, `MaintenanceSummary`, `MaintenanceRepairResult`. |
| [`maintenance_page.dart`](../lib/features/maintenance/maintenance_page.dart) | Library entry; declares shared library definitions and composes parts `maintenance_page_split_01.dart`, `maintenance_page_split_02.dart`, `maintenance_page_split_03.dart`. |
| [`maintenance_page_split_01.dart`](../lib/features/maintenance/maintenance_page_split_01.dart) | Implementation part of `maintenance_page.dart`; contains `MaintenancePage`, `createState`. |
| [`maintenance_page_split_02.dart`](../lib/features/maintenance/maintenance_page_split_02.dart) | Implementation part of `maintenance_page.dart`; contains `initState`, `_refresh`, `_createRecoveryCheckpoint`, `_verifyLatestRecoveryBackup`, `_repairProductCosts`, `_showCostRepairError`, … (12 more). |
| [`maintenance_page_split_03.dart`](../lib/features/maintenance/maintenance_page_split_03.dart) | Implementation part of `maintenance_page.dart`; contains `_AccessDeniedScaffold`, `build`, `_MaintenanceDashboard`, `_highestSeverity`, `_headlineFor`, `_formatCompactBytes`, … (18 more). |
| [`maintenance_service.dart`](../lib/features/maintenance/maintenance_service.dart) | Declares `MaintenanceService`, `_BackupSnapshot`. |
| [`phase10_health_service.dart`](../lib/features/maintenance/phase10_health_service.dart) | Declares `Phase10HealthLevel`, `Phase10HealthCheck`, `Phase10HealthReport`, `Phase10HealthService`. |
| [`product_cost_repair_service.dart`](../lib/features/maintenance/product_cost_repair_service.dart) | Declares `ProductCostRepairResult`, `ProductCostRepairService`. |

## `lib/features/products/`

| File | Contents / responsibility clue |
| --- | --- |
| [`products_page.dart`](../lib/features/products/products_page.dart) | Library entry; declares shared library definitions and composes parts `products_page_methods_01.dart`, `products_page_methods_02.dart`, `products_page_methods_03.dart`, `products_page_components_01.dart`, `products_page_components_02.dart`, … (2 more). |
| [`products_page_components_01.dart`](../lib/features/products/products_page_components_01.dart) | Implementation part of `products_page.dart`; contains `ProductsPage`, `createState`, `initState`, `dispose`, `didUpdateWidget`, `build`, … (10 more). |
| [`products_page_components_02.dart`](../lib/features/products/products_page_components_02.dart) | Implementation part of `products_page.dart`; contains `initState`, `dispose`, `build`, `_CurrencyPriceOverrideDraft`, `copyWith`. |
| [`products_page_components_03.dart`](../lib/features/products/products_page_components_03.dart) | Implementation part of `products_page.dart`; contains `_CurrencyPriceOverridesEditor`, `build`, `_addOverride`, `_update`, `_remove`, `_SupplierPricesEditor`, … (10 more). |
| [`products_page_components_04.dart`](../lib/features/products/products_page_components_04.dart) | Implementation part of `products_page.dart`; contains `_SaleUnitsEditor`, `_generateUnitBarcode`, `_scanUnitBarcode`, `build`, `_ProductFormSection`, `_MoneyField`, … (14 more). |
| [`products_page_methods_01.dart`](../lib/features/products/products_page_methods_01.dart) | Implementation part of `products_page.dart`; contains `_handleStoreChanged`, `_refreshPricingData`, `_invalidateProductViewCaches`, `_resetProductReveal`, `_syncProductReveal`, `_scanProductSearchBarcode`, … (9 more). |
| [`products_page_methods_02.dart`](../lib/features/products/products_page_methods_02.dart) | Implementation part of `products_page.dart`; contains `_openProductPriceHistory`, `_openPriceList`, `_priceListTitle`, `_productFieldSummary`, `_priceAmountLabel`, `_priceAmountValue`, … (11 more). |
| [`products_page_methods_03.dart`](../lib/features/products/products_page_methods_03.dart) | Implementation part of `products_page.dart`; contains `_loadSupplierOptions`, `_costUsd`, `_setControllerNumber`, `_syncMarginFromPrice`, `_syncPriceFromMargin`, `_syncAllMargins`, … (17 more). |

## `lib/features/purchases/`

| File | Contents / responsibility clue |
| --- | --- |
| [`purchase_workstation_page.dart`](../lib/features/purchases/purchase_workstation_page.dart) | Declares `PurchaseWorkstationPage`, `_PurchaseWorkstationPageState`, `_DraftPurchaseLine`. |
| [`purchases_page.dart`](../lib/features/purchases/purchases_page.dart) | Library entry; declares `PurchasesPage`, `_PurchasesPageState`, `_PurchaseDialogSession`, `_AccessDeniedScaffold`, `_MetricCard`, … (3 more) and composes parts `purchases_page_dialog_actions_01.dart`, `purchases_page_dialog_actions_02.dart`, `purchases_page_dialog_ui.dart`, `purchases_page_methods_01.dart`, `purchases_page_methods_02.dart`. |
| [`purchases_page_dialog_actions_01.dart`](../lib/features/purchases/purchases_page_dialog_actions_01.dart) | Implementation part of `purchases_page.dart`; contains `selectedSupplierPriceFor`, `suggestedPurchaseItem`, `suggestedBaseCost`, `applySuggestedSupplierPrice`, `priceHintForSelectedProduct`, `unitConversionSummary`, … (6 more). |
| [`purchases_page_dialog_actions_02.dart`](../lib/features/purchases/purchases_page_dialog_actions_02.dart) | Implementation part of `purchases_page.dart`; contains `updateSupplierPricesFromItemsIfNeeded`, `addPurchaseLine`, `resetProductEntryAfterAdd`, `addSelectedPurchaseLine`, `choosePurchaseProduct`, `collectRequiredBatchAllocations`, … (4 more). |
| [`purchases_page_dialog_ui.dart`](../lib/features/purchases/purchases_page_dialog_ui.dart) | Implementation part of `purchases_page.dart`; contains `showPurchaseDialog`. |
| [`purchases_page_methods_01.dart`](../lib/features/purchases/purchases_page_methods_01.dart) | Implementation part of `purchases_page.dart`; contains `_handleStoreChanged`, `_formatQuantity`, `_resetPurchaseReveal`, `_syncPurchaseReveal`, `_formatShortDate`, `_purchaseProductMatchesSearch`, … (16 more). |
| [`purchases_page_methods_02.dart`](../lib/features/purchases/purchases_page_methods_02.dart) | Implementation part of `purchases_page.dart`; contains `_deleteDraftPurchase`, `_returnPurchase`, `_openPurchaseReturnDialog`, `_showPurchaseDetails`, `_printPurchase`, `_openPurchaseDialog`. |

## `lib/features/reports/`

| File | Contents / responsibility clue |
| --- | --- |
| [`reports_page.dart`](../lib/features/reports/reports_page.dart) | Declares `ReportsPage`, `_ReportsPageData`, `_ReportProductAlert`, `_ReportMovementItem`, `_AccessDeniedScaffold`, … (7 more). |
| [`reports_snapshot_service.dart`](../lib/features/reports/reports_snapshot_service.dart) | Declares `ReportsSnapshotService`, `_computeSnapshotFromStore`. |

## `lib/features/sales/`

| File | Contents / responsibility clue |
| --- | --- |
| [`delivery_notes_page.dart`](../lib/features/sales/delivery_notes_page.dart) | Declares `DeliveryNotesPage`, `_DeliveryNotesPageState`, `_AccessDeniedScaffold`. |
| [`quotations_page.dart`](../lib/features/sales/quotations_page.dart) | Declares `QuotationsPage`, `_QuotationsPageState`, `_AccessDeniedScaffold`, `_QuotationDraft`, `_QuotationDialog`, … (2 more). |
| [`sales_page.dart`](../lib/features/sales/sales_page.dart) | Library entry; declares `_BarcodeAddResult`, `_SalesExitChoice`, `SalesPage`, `_SalesPageState`, `_formatMoneyInput`, … (1 more) and composes parts `sales_page_cart_panel.dart`, `sales_page_credit_notes_returns.dart`, `sales_page_customer_shift.dart`, `sales_page_desktop_layout.dart`, `sales_page_held_carts_scanner.dart`, … (12 more). |
| [`sales_page_cart_panel.dart`](../lib/features/sales/sales_page_cart_panel.dart) | Implementation part of `sales_page.dart`; contains `_buildCart`. |
| [`sales_page_credit_notes_returns.dart`](../lib/features/sales/sales_page_credit_notes_returns.dart) | Implementation part of `sales_page.dart`; contains `_creditNoteMatches`, `_invoiceEntryDate`, `_buildCreditNoteTile`, `_editCreditNote`, `_cancelSaleReturn`, `_invoiceSearchIndex`, … (2 more). |
| [`sales_page_customer_shift.dart`](../lib/features/sales/sales_page_customer_shift.dart) | Implementation part of `sales_page.dart`; contains `_salePriceFor`, `_setSalePriceType`, `_buildSalePriceTypeSelector`, `_selectedCustomer`, `_walkInCustomerLabel`, `_customerSearchText`, … (11 more). |
| [`sales_page_desktop_layout.dart`](../lib/features/sales/sales_page_desktop_layout.dart) | Implementation part of `sales_page.dart`; contains `_buildDesktopSalesLayout`, `_buildCurrentSalePanel`, `_buildQuickProductGridPanel`. |
| [`sales_page_held_carts_scanner.dart`](../lib/features/sales/sales_page_held_carts_scanner.dart) | Implementation part of `sales_page.dart`; contains `_toggleManualBarcodeInput`, `_restoreScannerMode`, `_loadHeldSaleCarts`, `_saveHeldSaleCarts`, `_defaultHeldCartName`, `_confirmSalesExit`, … (10 more). |
| [`sales_page_invoice_workflows.dart`](../lib/features/sales/sales_page_invoice_workflows.dart) | Implementation part of `sales_page.dart`; contains `_totalLine`, `_openSaleReturnDialog`, `_showInvoicesSheet`, `_queryInvoicesFromSqlite`, `_buildInvoicesPanelFromSales`, `_buildInvoicesPanelFromSummaries`, … (1 more). |
| [`sales_page_mobile_layout.dart`](../lib/features/sales/sales_page_mobile_layout.dart) | Implementation part of `sales_page.dart`; contains `_buildMobileSalesLayout`, `_buildMobileSaleControls`, `_buildMobileInvoiceSummary`, `_buildSaleTotalBar`. |
| [`sales_page_models.dart`](../lib/features/sales/sales_page_models.dart) | Implementation part of `sales_page.dart`; contains `_SaleShiftStatus`, `_BarcodeProductMatch`, `_SalesQueryResult`, `_QuickProductSlot`, `toJson`, `_HeldSaleCart`, … (3 more). |
| [`sales_page_posted_sale_edit.dart`](../lib/features/sales/sales_page_posted_sale_edit.dart) | Implementation part of `sales_page.dart`; contains `_saleReturnLabel`, `_editPostedSale`, `_latestActiveCreditNoteForSale`. |
| [`sales_page_product_data.dart`](../lib/features/sales/sales_page_product_data.dart) | Implementation part of `sales_page.dart`; contains `_handleStoreChanged`, `_currentStoreUiRevision`, `_refreshProductData`, `_syncDiscountPercentFromAmount`, `_syncDiscountAmountFromPercent`, `_refreshInvoiceBatchCostPreview`, … (10 more). |
| [`sales_page_product_dialogs.dart`](../lib/features/sales/sales_page_product_dialogs.dart) | Implementation part of `sales_page.dart`; contains `_cartLineTotalText`, `_showQuickProductsSheet`, `_scanCodeWithCameraOnce`, `_showProductSearchSheet`. |
| [`sales_page_quick_products.dart`](../lib/features/sales/sales_page_quick_products.dart) | Implementation part of `sales_page.dart`; contains `_buildQuickProductTile`, `_quickVisibleSlotIndexes`, `_cloneQuickPages`, `_startQuickGridEditing`, `_saveQuickGridEditing`, `_cancelQuickGridEditing`, … (18 more). |
| [`sales_page_sale_payment.dart`](../lib/features/sales/sales_page_sale_payment.dart) | Implementation part of `sales_page.dart`; contains `_saleSaveFailureMessage`, `_showTemporarySaleDebugDialog`, `_createDeliveryNote`, `_addProduct`, `_barcodeMatchFromSqlite`, `_addByCode`, … (2 more). |
| [`sales_page_sale_return_save.dart`](../lib/features/sales/sales_page_sale_return_save.dart) | Implementation part of `sales_page.dart`; contains `_editLatestSaleReturn`, `_returnSale`, `_confirmInvoicePrintAfterSave`, `_saveCurrentInvoice`, `_handleInvoiceAction`. |
| [`sales_page_shift_dialogs.dart`](../lib/features/sales/sales_page_shift_dialogs.dart) | Implementation part of `sales_page.dart`; contains `_openSaleDrawerDialog`, `_closeSaleDrawerDialog`. |
| [`sales_page_shortcuts_cart.dart`](../lib/features/sales/sales_page_shortcuts_cart.dart) | Implementation part of `sales_page.dart`; contains `_handleSaleHardwareShortcutKey`, `_productSearchDigitIndex`, `_handleSaleShortcutKey`, `_handleCartArrowKey`, `_canHandleCartArrowKeys`, `_normalizedSelectedCartIndex`, … (12 more). |
| [`sales_page_widgets.dart`](../lib/features/sales/sales_page_widgets.dart) | Implementation part of `sales_page.dart`; contains `_EmbeddedScannerError`, `build`, `_MobileSaleAction`, `_AccessDeniedScaffold`. |

## `lib/features/security/`

| File | Contents / responsibility clue |
| --- | --- |
| [`login_gate_page.dart`](../lib/features/security/login_gate_page.dart) | Library entry; declares `LoginGatePage`, `_LoginGatePageState`, `_PasswordResetDraft`, `_InitialAdminSetupCard`, `_InitialAdminSetupCardState`, … (1 more) and composes parts `login_gate_page_methods_01.dart`, `login_gate_page_methods_02.dart`. |
| [`login_gate_page_methods_01.dart`](../lib/features/security/login_gate_page_methods_01.dart) | Implementation part of `login_gate_page.dart`; contains `_handleStoreChanged`, `_normalizeLoginPart`, `_isValidLoginPart`, `_showAuthMessage`, `_setAuthCache`, `_persistRecoveredStoreAuthCache`, … (6 more). |
| [`login_gate_page_methods_02.dart`](../lib/features/security/login_gate_page_methods_02.dart) | Implementation part of `login_gate_page.dart`; contains `_openSupportPasswordReset`, `_completeInitialSetup`, `_formatBytes`, `_formatDateTime`, `_releaseSubtitle`, `_showWindowsInstallerReleases`. |
| [`sensitive_action_guard.dart`](../lib/features/security/sensitive_action_guard.dart) | Declares `requestSensitiveActionAuthorization`, `_authorize`. |

## `lib/features/settings/`

| File | Contents / responsibility clue |
| --- | --- |
| [`settings_currency.dart`](../lib/features/settings/settings_currency.dart) | Implementation part of `settings_page.dart`; contains `_organizedCurrencyCards`. |
| [`settings_devices.dart`](../lib/features/settings/settings_devices.dart) | Implementation part of `settings_page.dart`; contains `_deviceCards`. |
| [`settings_general.dart`](../lib/features/settings/settings_general.dart) | Implementation part of `settings_page.dart`; contains `_organizedGeneralCards`, `_organizedBranchCards`. |
| [`settings_page.dart`](../lib/features/settings/settings_page.dart) | Library entry; declares `SettingsPage` and composes parts `settings_page_backup.dart`, `settings_page_backup_helpers.dart`, `settings_page_sync_shared.dart`, `settings_general.dart`, `settings_currency.dart`, … (23 more). |
| [`settings_page_backup.dart`](../lib/features/settings/settings_page_backup.dart) | Implementation part of `settings_page.dart`; contains `downloadBackupFile`, `importBackupFile`, `downloadRecoveryFile`, `recoverExistingStore`, `recoverStoreIdentity`, `recoverStoreData`, … (4 more). |
| [`settings_page_backup_helpers.dart`](../lib/features/settings/settings_page_backup_helpers.dart) | Implementation part of `settings_page.dart`; contains `_looksLikeZip`, `_requestBackupPassword`, `_publishImportedSnapshotToDirectIfNeeded`. |
| [`settings_page_backup_widgets.dart`](../lib/features/settings/settings_page_backup_widgets.dart) | Implementation part of `settings_page.dart`; contains `_ScannerFeedbackSettingsCard`, `createState`, `initState`, `_save`, `build`, `_AutoLocalBackupSettingsCard`, … (20 more). |
| [`settings_page_cash_widgets.dart`](../lib/features/settings/settings_page_cash_widgets.dart) | Implementation part of `settings_page.dart`; contains `_SaleWarehouseSettingsCard`, `createState`, `initState`, `_load`, `_save`, `build`, … (3 more). |
| [`settings_page_data_actions.dart`](../lib/features/settings/settings_page_data_actions.dart) | Implementation part of `settings_page.dart`; contains `_downloadBackupFile`, `_importBackupFile`, `_downloadRecoveryFile`, `_recoverExistingStore`, `_clearLocalData`, `_rebuildFromHost`, … (1 more). |
| [`settings_page_financial_actions.dart`](../lib/features/settings/settings_page_financial_actions.dart) | Implementation part of `settings_page.dart`; contains `_priceDisplayModeLabel`, `_editFinancialSettings`, `_editCurrency`, `_editExchangeRate`, `_editDocumentNumbering`. |
| [`settings_page_info_widgets.dart`](../lib/features/settings/settings_page_info_widgets.dart) | Implementation part of `settings_page.dart`; contains `_SectionCard`, `build`, `_InfoTile`, `_InfoGridItem`, `_InfoGrid`, `_Line`, … (1 more). |
| [`settings_page_navigation_widgets.dart`](../lib/features/settings/settings_page_navigation_widgets.dart) | Implementation part of `settings_page.dart`; contains `_SettingsNavData`, `_SettingsSection`, `_DeferredSettingsPage`, `build`, `_SettingsSideNav`, `_SettingsNavItem`, … (1 more). |
| [`settings_page_organization_actions.dart`](../lib/features/settings/settings_page_organization_actions.dart) | Implementation part of `settings_page.dart`; contains `_editBranch`, `_editOrganizationGeneral`, `_editOrganizationLegal`, `_editOrganizationBranding`, `_saveOrganizationProfile`. |
| [`settings_page_sections.dart`](../lib/features/settings/settings_page_sections.dart) | Implementation part of `settings_page.dart`; contains `_settingsList`, `_generalCards`, `_aboutCards`, `_documentCards`, `_branchCards`, `_taxCards`, … (8 more). |
| [`settings_page_shortcuts_identity_widgets.dart`](../lib/features/settings/settings_page_shortcuts_identity_widgets.dart) | Implementation part of `settings_page.dart`; contains `_KeyboardShortcutsSettingsCard`, `createState`, `initState`, `_handleShortcutSettingsChanged`, `dispose`, `_keyLabel`, … (14 more). |
| [`settings_page_sync.dart`](../lib/features/settings/settings_page_sync.dart) | Implementation part of `settings_page.dart`; contains `_UnifiedSyncSettingsCard`, `Function`, `createState`, `initState`, `dispose`, `build`. |
| [`settings_page_sync_channels.dart`](../lib/features/settings/settings_page_sync_channels.dart) | Implementation part of `settings_page.dart`; contains `_syncChannelsCard`, `_activeTransportSelector`, `_syncMethodExpansionTile`, `_readOnlyTransportLine`, `_advancedSyncCard`, `_plainSyncPanel`, … (4 more). |
| [`settings_page_sync_configuration.dart`](../lib/features/settings/settings_page_sync_configuration.dart) | Implementation part of `settings_page.dart`; contains `_runtimeClientTransport`, `_refreshDirectSyncPlanAccess`, `_onSyncDraftChanged`, `_scheduleHostSyncAutoSave`, `_resetSyncDraft`, `_testCurrentConnection`, … (7 more). |
| [`settings_page_sync_connect_dialog.dart`](../lib/features/settings/settings_page_sync_connect_dialog.dart) | Implementation part of `settings_page.dart`; contains `_openConnectToStoreDialog`. |
| [`settings_page_sync_dashboard.dart`](../lib/features/settings/settings_page_sync_dashboard.dart) | Implementation part of `settings_page.dart`; contains `_clientSuspendedWarningCard`, `_syncHeroHeader`, `_syncOverviewCard`, `_thisDeviceCard`, `_addDeviceCard`, `_isLanClientConfigured`, … (2 more). |
| [`settings_page_sync_monitoring.dart`](../lib/features/settings/settings_page_sync_monitoring.dart) | Implementation part of `settings_page.dart`; contains `_AdvancedSyncDebugCard`, `createState`, `_controlPlaneService`, `initState`, `_refreshDirectDevices`, `_loadAndAdoptDirectDevices`, … (17 more). |
| [`settings_page_sync_operations.dart`](../lib/features/settings/settings_page_sync_operations.dart) | Implementation part of `settings_page.dart`; contains `_syncNow`, `_shortDeviceLabel`, `_formatShortDateTime`, `_peerSyncStatus`, `_testPairedClientConnections`, `_testDirectConnection`, … (1 more). |
| [`settings_page_sync_pairing_actions.dart`](../lib/features/settings/settings_page_sync_pairing_actions.dart) | Implementation part of `settings_page.dart`; contains `_refreshHostIpAddresses`, `_generateLanToken`, `_loadActivePairingCodes`, `_startPairingCountdownTimer`, `_refreshLanPairingConsumedState`, `_expireLanPairingCode`, … (20 more). |
| [`settings_page_sync_pairing_views.dart`](../lib/features/settings/settings_page_sync_pairing_views.dart) | Implementation part of `settings_page.dart`; contains `_pairingContent`, `_miniLine`, `_softNotice`, `_humanStatus`, `_hostChangedNotificationCard`, `_transferHostCard`, … (11 more). |
| [`settings_page_sync_shared.dart`](../lib/features/settings/settings_page_sync_shared.dart) | Implementation part of `settings_page.dart`; contains `_OperationProgress`, `_ScannedPairingPayload`, `_DirectMonitoringSnapshot`, `DirectDeviceLimitStatus`, `_SyncStatusView`, `_StatusChip`, … (13 more). |
| [`settings_page_update_widgets.dart`](../lib/features/settings/settings_page_update_widgets.dart) | Implementation part of `settings_page.dart`; contains `_WindowsUpdateStatusCard`, `createState`, `initState`, `dispose`, `_lastCheckedText`, `_check`, … (5 more). |
| [`settings_printer.dart`](../lib/features/settings/settings_printer.dart) | Implementation part of `settings_page.dart`; contains `_printerCards`, `_printSettingsCard`, `_detectPrintPrinters`, `_editPrintSettings`, `_buildDocumentPrintSetting`, `_formatsForDocument`, … (2 more). |
| [`settings_security.dart`](../lib/features/settings/settings_security.dart) | Implementation part of `settings_page.dart`; contains `_securityCards`. |
| [`settings_sync.dart`](../lib/features/settings/settings_sync.dart) | Implementation part of `settings_page.dart`; contains `_organizedSyncCards`, `_SettingsSectionIntro`, `build`. |
| [`sync_setup_page.dart`](../lib/features/settings/sync_setup_page.dart) | Library entry; declares `_ConnectMode`, `_SetupStatus`, `_ClientPairingState`, `SyncSetupPage`, `_SyncSetupPageState` and composes parts `sync_setup_page_connection_state.dart`, `sync_setup_page_pairing.dart`, `sync_setup_page_status_widgets.dart`, `sync_setup_page_form_widgets.dart`. |
| [`sync_setup_page_connection_state.dart`](../lib/features/settings/sync_setup_page_connection_state.dart) | Implementation part of `sync_setup_page.dart`; contains `_startQrCountdownTimer`, `_syncQrStatusFromInput`, `_markQrFailed`, `_setStatus`, `_setSnapshotProgress`, `_clearStatus`, … (4 more). |
| [`sync_setup_page_form_widgets.dart`](../lib/features/settings/sync_setup_page_form_widgets.dart) | Implementation part of `sync_setup_page.dart`; contains `_buildModeSelector`, `_buildHeader`, `_buildSectionTitle`, `_qrStatusBadge`, `_qrBorderColor`, `_buildConnectionStateCard`, … (3 more). |
| [`sync_setup_page_pairing.dart`](../lib/features/settings/sync_setup_page_pairing.dart) | Implementation part of `sync_setup_page.dart`; contains `_scanQr`, `_applyScannedPayload`, `_connectLan`, `_connectDirect`, `_connect`. |
| [`sync_setup_page_status_widgets.dart`](../lib/features/settings/sync_setup_page_status_widgets.dart) | Implementation part of `sync_setup_page.dart`; contains `_buildConnectionLogCard`, `_buildDirectSummary`, `_buildStatusBanner`. |
| [`users_permissions_page.dart`](../lib/features/settings/users_permissions_page.dart) | Declares `UsersPermissionsPage`, `_UsersPermissionsPageState`, `_PermissionGroup`, `_UserEditResult`, `_SectionHeader`, … (2 more). |

## `lib/features/shared/`

| File | Contents / responsibility clue |
| --- | --- |
| [`sync_monitoring_section.dart`](../lib/features/shared/sync_monitoring_section.dart) | Library entry; declares shared library definitions and composes parts `sync_monitoring_section_split_01.dart`, `sync_monitoring_section_split_02.dart`. |
| [`sync_monitoring_section_split_01.dart`](../lib/features/shared/sync_monitoring_section_split_01.dart) | Implementation part of `sync_monitoring_section.dart`; contains `SyncMonitoringSection`, `createState`, `initState`, `dispose`, `didUpdateWidget`, `_refreshDirectDevices`, … (27 more). |
| [`sync_monitoring_section_split_02.dart`](../lib/features/shared/sync_monitoring_section_split_02.dart) | Implementation part of `sync_monitoring_section.dart`; contains `_SyncStatusView`, `_HostSyncMonitoringTable`, `Function`, `createState`, `dispose`, `build`, … (8 more). |

## `lib/features/suppliers/`

| File | Contents / responsibility clue |
| --- | --- |
| [`suppliers_page.dart`](../lib/features/suppliers/suppliers_page.dart) | Declares `SuppliersPage`, `_SuppliersPageState`, `_SupplierQueryResult`, `_AccessDeniedScaffold`, `_SupplierDialog`, … (1 more). |

## `lib/models/`

| File | Contents / responsibility clue |
| --- | --- |
| [`account_transaction.dart`](../lib/models/account_transaction.dart) | Declares `AccountTransaction`. |
| [`accounting_account.dart`](../lib/models/accounting_account.dart) | Declares `AccountingAccount`. |
| [`aging_report.dart`](../lib/models/aging_report.dart) | Declares `AgingBucket`, `AgingReportRow`, `AgingOpenDocument`, `AgingReportResult`. |
| [`app_identity.dart`](../lib/models/app_identity.dart) | Declares `AppPlatformType`, `DeviceRole`, `AppRole`, `SyncMode`, `AppIdentity`. |
| [`app_user.dart`](../lib/models/app_user.dart) | Declares `AppUser`. |
| [`cash_ledger_transaction.dart`](../lib/models/cash_ledger_transaction.dart) | Declares `CashLedgerTransaction`. |
| [`catalog_item.dart`](../lib/models/catalog_item.dart) | Declares `CatalogItem`. |
| [`credit_note.dart`](../lib/models/credit_note.dart) | Declares `CreditNote`. |
| [`customer.dart`](../lib/models/customer.dart) | Declares `Customer`. |
| [`delivery_note.dart`](../lib/models/delivery_note.dart) | Declares `DeliveryNote`. |
| [`expense.dart`](../lib/models/expense.dart) | Declares `Expense`. |
| [`inventory_batch.dart`](../lib/models/inventory_batch.dart) | Declares `InventoryBatchStatus`, `InventoryBatchStatusJson`, `InventoryBatch`, `InventoryBatchBalance`, `BatchAllocation`, … (1 more). |
| [`inventory_cost_layer.dart`](../lib/models/inventory_cost_layer.dart) | Declares `InventoryCostLayerConsumption`, `InventoryCostLayer`, `InventoryCostResult`. |
| [`inventory_count.dart`](../lib/models/inventory_count.dart) | Declares `InventoryCountSession`, `InventoryCountLine`. |
| [`inventory_reconciliation.dart`](../lib/models/inventory_reconciliation.dart) | Declares `InventoryReconciliation`. |
| [`journal_entry.dart`](../lib/models/journal_entry.dart) | Declares `JournalLineDraft`, `JournalEntryDraft`. |
| [`manufacturing.dart`](../lib/models/manufacturing.dart) | Declares `BillOfMaterialsLine`, `BillOfMaterials`, `ManufacturingMaterialCost`, `ManufacturingWasteLine`, `ManufacturingOrder`. |
| [`payment_allocation.dart`](../lib/models/payment_allocation.dart) | Declares `PaymentAllocation`, `PaymentAllocationDraft`. |
| [`payment_voucher.dart`](../lib/models/payment_voucher.dart) | Declares `PaymentVoucher`. |
| [`posted_document_snapshot.dart`](../lib/models/posted_document_snapshot.dart) | Declares `PostedDocumentSnapshot`, `PostedStoreProfileSnapshot`, `PostedPartySnapshot`, `PostedCurrencySnapshot`, `PostedDocumentLineSnapshot`, … (2 more). |
| [`print_settings.dart`](../lib/models/print_settings.dart) | Declares `PrintPaperFormats`, `PrintDocumentKeys`, `PrintPrinterProfile`, `PrintDocumentSettings`, `PrintSettings`. |
| [`product.dart`](../lib/models/product.dart) | Declares `ProductQuantityType`, `ProductQuantityTypeJson`, `ProductSaleUnit`, `Product`. |
| [`product_costing.dart`](../lib/models/product_costing.dart) | Declares `InventoryCostingMethod`, `InventoryCostingMethodJson`, `ProductCost`, `CostingMethodHistory`. |
| [`product_pricing.dart`](../lib/models/product_pricing.dart) | Declares `ProductPriceOverrideMode`, `ProductPriceOverrideModeJson`, `PriceList`, `ProductPrice`, `ProductPriceOverride`, … (2 more). |
| [`purchase.dart`](../lib/models/purchase.dart) | Declares `Purchase`. |
| [`purchase_item.dart`](../lib/models/purchase_item.dart) | Declares `PurchaseItem`. |
| [`receipt_voucher.dart`](../lib/models/receipt_voucher.dart) | Declares `ReceiptVoucher`. |
| [`sale.dart`](../lib/models/sale.dart) | Declares `Sale`. |
| [`sale_item.dart`](../lib/models/sale_item.dart) | Declares `SaleItem`. |
| [`sale_quotation.dart`](../lib/models/sale_quotation.dart) | Declares `SaleQuotation`. |
| [`sale_summary.dart`](../lib/models/sale_summary.dart) | Declares `SaleSummary`. |
| [`stock_movement.dart`](../lib/models/stock_movement.dart) | Declares `StockMovement`. |
| [`store_profile.dart`](../lib/models/store_profile.dart) | Library entry; declares shared library definitions and composes parts `store_profile_split_01.dart`, `store_profile_split_02.dart`. |
| [`store_profile_split_01.dart`](../lib/models/store_profile_split_01.dart) | Implementation part of `store_profile.dart`; contains `FinancialCurrency`, `copyWith`, `toJson`, `CurrencyExchangeRate`, `DocumentNumberingSettings`, `OrganizationBranch`, … (1 more). |
| [`store_profile_split_02.dart`](../lib/models/store_profile_split_02.dart) | Implementation part of `store_profile.dart`; contains `StoreProfile`, `currencyByCode`, `exchangeRateForDate`, `latestExchangeRate`, `taxProfileById`, `copyWith`, … (4 more). |
| [`supplier.dart`](../lib/models/supplier.dart) | Declares `Supplier`. |
| [`supplier_product_price.dart`](../lib/models/supplier_product_price.dart) | Declares `SupplierProductPriceHistoryEntry`, `SupplierProductPrice`. |
| [`supplier_purchase_price.dart`](../lib/models/supplier_purchase_price.dart) | Declares `SupplierPurchasePrice`. |
| [`sync_change.dart`](../lib/models/sync_change.dart) | Declares `SyncChange`. |
| [`sync_queue_item.dart`](../lib/models/sync_queue_item.dart) | Declares `SyncQueueItem`. |
| [`tax_profile.dart`](../lib/models/tax_profile.dart) | Declares `TaxTreatment`, `TaxTreatmentCode`, `TaxProfile`, `TaxAmountBreakdown`, `TaxCalculator`. |
| [`user_role.dart`](../lib/models/user_role.dart) | Declares `AppPermissionPage`, `AppPermission`, `UserRole`. |
| [`warehouse.dart`](../lib/models/warehouse.dart) | Declares `Warehouse`. |
| [`warehouse_inventory.dart`](../lib/models/warehouse_inventory.dart) | Declares `WarehouseInventory`. |
| [`warehouse_transfer_order.dart`](../lib/models/warehouse_transfer_order.dart) | Declares `WarehouseTransferOrderItem`, `WarehouseTransferOrder`. |

## `lib/widgets/`

| File | Contents / responsibility clue |
| --- | --- |
| [`app_section_header.dart`](../lib/widgets/app_section_header.dart) | Declares `AppSectionHeader`. |
| [`empty_state_card.dart`](../lib/widgets/empty_state_card.dart) | Declares `EmptyStateCard`. |
| [`page_data_load_indicator.dart`](../lib/widgets/page_data_load_indicator.dart) | Declares `PageDataLoadIndicator`. |
| [`report_card.dart`](../lib/widgets/report_card.dart) | Declares `ReportCard`. |
| [`shortcut_key_picker.dart`](../lib/widgets/shortcut_key_picker.dart) | Declares `ShortcutGuideChip`, `showShortcutKeyPicker`. |
| [`summary_card.dart`](../lib/widgets/summary_card.dart) | Declares `SummaryCard`. |

## `scripts/`

| File | Contents / responsibility clue |
| --- | --- |
| [`build_windows_installer.ps1`](../scripts/build_windows_installer.ps1) | PowerShell script; see its filename for the workflow. |
| [`check_translations.mjs`](../scripts/check_translations.mjs) | defines helpers/handlers `walk`. |
| [`create_platform_admin.mjs`](../scripts/create_platform_admin.mjs) | defines helpers/handlers `hashPassword`. |

## `./`

| File | Contents / responsibility clue |
| --- | --- |
| [`server.js`](../server.js) | defines helpers/handlers `parseQuery`, `attachResponseHelpers`, `readBody`. |

## `server_api/`

| File | Contents / responsibility clue |
| --- | --- |
| [`_db.js`](../server_api/_db.js) | defines helpers/handlers `requiredSecret`, `accountSigningSecret`, `adminSigningSecret`, `ensureAuthSessionsTable`, `hashRefreshToken`, `signToken`, … (21 more). |
| [`deploy-health.js`](../server_api/deploy-health.js) | API endpoint handler for deploy health. |
| [`health.js`](../server_api/health.js) | API endpoint handler for health. |
| [`router.js`](../server_api/router.js) | defines helpers/handlers `normalizePath`, `allowedOrigins`, `applyCors`. |

## `server_api/account/`

| File | Contents / responsibility clue |
| --- | --- |
| [`change-password.js`](../server_api/account/change-password.js) | defines helpers/handlers `sendError`, `verifyPassword`, `hashPassword`. |
| [`owner-profile.js`](../server_api/account/owner-profile.js) | defines helpers/handlers `sendError`, `normalizePart`, `isValidUsername`, `hashPassword`, `ensureTables`. |

## `server_api/admin/`

| File | Contents / responsibility clue |
| --- | --- |
| [`password-reset.js`](../server_api/admin/password-reset.js) | defines helpers/handlers `bodyOf`, `verifyAdminToken`, `requireAdmin`, `hashCode`, `resetCode`, `hashPassword`, … (1 more). |
| [`subscribers.js`](../server_api/admin/subscribers.js) | defines helpers/handlers `verifyAdminToken`, `assertAdmin`, `bodyOf`, `cleanSlug`, `cleanSimple`, `requireText`, … (4 more). |

## `server_api/auth/`

| File | Contents / responsibility clue |
| --- | --- |
| [`login.js`](../server_api/auth/login.js) | defines helpers/handlers `normalizePart`, `parseLoginName`, `verifyPassword`, `ensureTables`. |
| [`logout.js`](../server_api/auth/logout.js) | API endpoint handler for auth logout. |
| [`password-reset.js`](../server_api/auth/password-reset.js) | defines helpers/handlers `bodyOf`, `hashCode`, `hashPassword`, `parseLoginName`. |
| [`register.js`](../server_api/auth/register.js) | defines helpers/handlers `normalizePart`, `randomId`, `ventioId`, `hashPassword`, `isValidSlug`, `ensureTables`. |
| [`session.js`](../server_api/auth/session.js) | defines helpers/handlers `sendError`. |

## `server_api/google-drive/`

| File | Contents / responsibility clue |
| --- | --- |
| [`auth-start.js`](../server_api/google-drive/auth-start.js) | defines helpers/handlers `ensureTable`, `apiBaseUrl`, `page`. |
| [`callback.js`](../server_api/google-drive/callback.js) | defines helpers/handlers `ensureTable`, `apiBaseUrl`, `page`. |
| [`refresh.js`](../server_api/google-drive/refresh.js) | API endpoint handler for google drive refresh. |
| [`status.js`](../server_api/google-drive/status.js) | defines helpers/handlers `ensureTable`. |

## `server_api/sync/`

| File | Contents / responsibility clue |
| --- | --- |
| [`device-access.js`](../server_api/sync/device-access.js) | API endpoint handler for sync device access. |
| [`device-key.js`](../server_api/sync/device-key.js) | defines helpers/handlers `ensureDeviceKeyColumn`, `cleanKey`. |
| [`device-revoke.js`](../server_api/sync/device-revoke.js) | API endpoint handler for sync device revoke. |
| [`device-suspend.js`](../server_api/sync/device-suspend.js) | API endpoint handler for sync device suspend. |
| [`device-wipe-ack.js`](../server_api/sync/device-wipe-ack.js) | API endpoint handler for sync device wipe ack. |
| [`devices.js`](../server_api/sync/devices.js) | defines helpers/handlers `asIso`, `normalizeTransport`, `asNullableDate`, `ensureDeviceTable`, `rowToDevice`. |
| [`entitlement.js`](../server_api/sync/entitlement.js) | API endpoint handler for sync entitlement. |
| [`host-heartbeat.js`](../server_api/sync/host-heartbeat.js) | defines helpers/handlers `asIso`, `ensureHeartbeatTable`. |
| [`ice-config.js`](../server_api/sync/ice-config.js) | defines helpers/handlers `urls`. |
| [`realtime.js`](../server_api/sync/realtime.js) | defines helpers/handlers `scopeKey`, `shortId`, `oppositeRole`, `addClient`, `removeClient`, `send`, … (11 more). |
| [`signal.js`](../server_api/sync/signal.js) | API endpoint handler for sync signal. |
| [`stun.js`](../server_api/sync/stun.js) | defines helpers/handlers `bindingResponse`, `attachStunServer`. |

## `server_api/sync/pairing/`

| File | Contents / responsibility clue |
| --- | --- |
| [`claim.js`](../server_api/sync/pairing/claim.js) | defines helpers/handlers `ensurePairingTable`, `ensureDeviceTable`, `makeDeviceToken`. |
| [`create.js`](../server_api/sync/pairing/create.js) | defines helpers/handlers `ensurePairingTable`, `normalizeRecoveryKey`, `hashRecoveryKey`, `ensureRecoveryTable`, `ensureStoreDevicesTable`, `authorizeLocalHostOrAccount`, … (1 more). |
| [`status.js`](../server_api/sync/pairing/status.js) | defines helpers/handlers `ensurePairingTable`. |

## `server_api/sync/recovery/`

| File | Contents / responsibility clue |
| --- | --- |
| [`claim.js`](../server_api/sync/recovery/claim.js) | defines helpers/handlers `normalize`, `makeDeviceToken`, `ensureDeviceTable`. |

## `test/`

| File | Contents / responsibility clue |
| --- | --- |
| [`account_transaction_sqlite_first_contract_test.dart`](../test/account_transaction_sqlite_first_contract_test.dart) | Test suite with 2 cases; examples: `account transaction writers are SQLite-first and awaited`, `voucher payment compatibility ledger is owned by PaymentVoucherService transaction`. |
| [`accounting_chart_phase1_test.dart`](../test/accounting_chart_phase1_test.dart) | Test suite with 4 cases; examples: `Phase 1 seeds the complete chart idempotently`, `user account supports hierarchy and duplicate-code protection`, `non-postable grouping account cannot receive a new journal line`, … (1 more). |
| [`accounting_closure_phase1_atomicity_contract_test.dart`](../test/accounting_closure_phase1_atomicity_contract_test.dart) | Test suite with 5 cases; examples: `sale FIFO consumption is owned by the SQLite sale transaction`, `sale return and cancel restore FIFO layers inside their transactions`, `purchase return and cancel close layers transactionally and block consumed layers`, … (2 more). |
| [`accounting_phase2_account_roles_test.dart`](../test/accounting_phase2_account_roles_test.dart) | Test suite with 6 cases; examples: `inventory count variance report prepares against the current schema`, `Phase 2 seeds every semantic account role idempotently`, `one-to-one role update stays synchronized with legacy default`, … (3 more). |
| [`accounting_phase2_cash_reconciliation_contract_test.dart`](../test/accounting_phase2_cash_reconciliation_contract_test.dart) | Test suite with 3 cases; examples: `returned purchases are not treated as missing active purchase journals`, `voucher reconciliation subtracts refunds before allocation balance`, `party control reconciliation includes reversed journal pairs`. |
| [`accounting_phase2_production_closure_contract_test.dart`](../test/accounting_phase2_production_closure_contract_test.dart) | Test suite with 5 cases; examples: `expiry adjustment requires accounting journal before commit`, `expiry and waste reversal are owned by outer SQLite transaction`, `waste and inventory count cannot commit material change without journal`, … (2 more). |
| [`accounting_phase4_operational_posting_test.dart`](../test/accounting_phase4_operational_posting_test.dart) | Test suite with 6 cases; examples: `Phase 4 sale and purchase use semantic posting roles`, `sale return posts to sales returns and reduces reported revenue`, `sale discount posts to contra-revenue and nets VAT after discount`, … (3 more). |
| [`accounting_phase5_manufacturing_test.dart`](../test/accounting_phase5_manufacturing_test.dart) | Test suite with 1 cases; examples: `actual manufacturing cost flows Raw to WIP to Finished with waste`. |
| [`accounting_phase6_reversal_test.dart`](../test/accounting_phase6_reversal_test.dart) | Test suite with 1 cases; examples: `manufacturing reversal restores stock, reverses journal, and is idempotent`. |
| [`accounting_phase7_reports_test.dart`](../test/accounting_phase7_reports_test.dart) | Test suite with 1 cases; examples: `final reports use posted journal lines and expose contra revenue`. |
| [`accounting_phase8_completion_regression_test.dart`](../test/accounting_phase8_completion_regression_test.dart) | Test suite with 7 cases; examples: `purchase and sale route inventory through semantic product classes`, `inventory valuation uses Unified Batch carrying value instead of product cost cache`, `BOM create update and delete reclassify existing Unified Batch inventory`, … (4 more). |
| [`accounting_phase8_integrity_test.dart`](../test/accounting_phase8_integrity_test.dart) | Test suite with 3 cases; examples: `received purchase commits stock, Unified Batch, and journal together`, `failed manufacturing journal rolls back stock, order, and movements`, `schema 33+ preserves manufacturing and reversal audit indexes`. |
| [`accounting_production_integrity_service_test.dart`](../test/accounting_production_integrity_service_test.dart) | Test suite with 3 cases; examples: `production integrity gate detects an unbalanced posted journal`, `production integrity detects semantic inventory account misclassification`, `Unified Batch gate detects warehouse quantity that no longer matches batches`. |
| [`accounting_ui_alignment_group1_contract_test.dart`](../test/accounting_ui_alignment_group1_contract_test.dart) | Test suite with 5 cases; examples: `cash movement UI is sourced from Cash Ledger`, `accounting summary cash totals are sourced from cash ledger`, `subledger transaction UI uses debit and credit semantics`, … (2 more). |
| [`accounting_ui_alignment_group2_contract_test.dart`](../test/accounting_ui_alignment_group2_contract_test.dart) | Test suite with 5 cases; examples: `general ledger exposes real accounting filters and opening balance`, `trial balance separates debit and credit balances and checks equality`, `income statement has account-level financial breakdowns`, … (2 more). |
| [`accounting_ui_alignment_group3_contract_test.dart`](../test/accounting_ui_alignment_group3_contract_test.dart) | Test suite with 5 cases; examples: `accounting navigation separates operations from subledgers`, `journal entries are first-class UI with filters and drill-down`, `cash movement has unified direction type and date filters`, … (2 more). |
| [`accounting_ui_alignment_group4_contract_test.dart`](../test/accounting_ui_alignment_group4_contract_test.dart) | Test suite with 12 cases; examples: `closure preserves Group 1 cash and account-role contracts`, `closure preserves Group 2 financial-reporting contracts`, `closure preserves Group 3 UX and journal drill-down contracts`, … (9 more). |
| [`accounting_ui_alignment_group4_reconciliation_test.dart`](../test/accounting_ui_alignment_group4_reconciliation_test.dart) | Test suite with 3 cases; examples: `closure gate detects cash-location vs GL mismatch`, `closure gate detects customer subledger vs control-account mismatch`, `closure gate detects supplier subledger vs control-account mismatch`. |
| [`app_store_workflow_test.dart`](../test/app_store_workflow_test.dart) | Test suite entry point; composes `app_store_workflow_test_split_01.dart`, `app_store_workflow_test_split_02.dart`, `app_store_workflow_test_split_03.dart`, `app_store_workflow_test_split_04.dart`, `app_store_workflow_test_split_05.dart` and delegates test cases to those parts. |
| [`app_store_workflow_test_split_01.dart`](../test/app_store_workflow_test_split_01.dart) | Test implementation part of `app_store_workflow_test.dart`; covers groups ‘AppStore initialization and persisted state’; ‘AppStore product, customer, supplier, catalog, and expense workflows’; cases: `initializes defaults, identity, walk-in customer, admin user, and catalog defaults`, `re-hydrates products, customers, sales counters, roles, and profile from local db`, `imports legacy sales without warehouse fields as main warehouse`, … (7 more). |
| [`app_store_workflow_test_split_02.dart`](../test/app_store_workflow_test_split_02.dart) | Test implementation part of `app_store_workflow_test.dart`; cases: `creates sales, rejects insufficient stock without auto correction, restores stock on cancel, and tracks profit`, `phase 6 cancellation never auto-refunds cash; refund is explicit`, `returns a sale, restores stock, and records a sale return movement`, … (4 more). |
| [`app_store_workflow_test_split_03.dart`](../test/app_store_workflow_test_split_03.dart) | Test implementation part of `app_store_workflow_test.dart`; cases: `sale cancel is blocked after a partial return`, `zero-price sale return still reverses COGS journal atomically`, `draft purchase receive rolls back stock, FIFO layer, document and journal when accounting fails`, … (6 more). |
| [`app_store_workflow_test_split_04.dart`](../test/app_store_workflow_test_split_04.dart) | Test implementation part of `app_store_workflow_test.dart`; covers groups ‘AppStore sales, purchases, stock, and reports’; cases: `received purchase edit recalculates payment status from allocations`, `handles purchase draft, receive, cancel, and manual stock adjustment`, `SQLite-first purchase ledger is durable immediately after create`, … (5 more). |
| [`app_store_workflow_test_split_05.dart`](../test/app_store_workflow_test_split_05.dart) | Test implementation part of `app_store_workflow_test.dart`; covers groups ‘AppStore backup, restore, encryption, merge, and conflicts’; ‘AppStore sync queue and permissions’; cases: `exports, validates, encrypts, decrypts, imports, and summarizes backups`, `round-trips SQLite-first inventory tables without double applying restore`, `merge backup prefers latest data and reports duplicate data conflicts`, … (6 more). |
| [`assistant_provider_transport_test.dart`](../test/assistant_provider_transport_test.dart) | Tests 7 cases in groups ‘AssistantProviderTransport’; examples: `rejects empty models and API keys before making a request`, `sends private OpenAI Responses requests and parses tool calls`, `sends Gemini Interactions requests and parses tool calls`, … (4 more). |
| [`assistant_services_test.dart`](../test/assistant_services_test.dart) | Tests 6 cases in groups ‘Assistant provider settings and conversation safety’; ‘AssistantHowToKnowledgeService’; examples: `stores provider credentials in secure storage and deletes them`, `keeps business-data consent specific to provider and revocable`, `requires consent before reading a key or contacting a provider`, … (3 more). |
| [`audit_recovered_startup_test.dart`](../test/audit_recovered_startup_test.dart) | Test suite with 1 cases; examples: `recovered copy completes real database and AppStore startup twice`. |
| [`audit_recovery_regression_test.dart`](../test/audit_recovery_regression_test.dart) | Test suite with 5 cases; examples: `concurrent callers wait for durable, sequential audit records`, `database rejects unsigned, stale, replacement and mutable writes`, `recovery preserves signed prefix and unsigned evidence, then reopens`, … (2 more). |
| [`authenticated_peer_session_test.dart`](../test/authenticated_peer_session_test.dart) | Test suite with 4 cases; examples: `wraps outgoing messages in authenticated frames`, `rejects tampered and replayed frames`, `does not send after session expiry`, … (1 more). |
| [`backup_validation_test.dart`](../test/backup_validation_test.dart) | Tests 5 cases in groups ‘Backup validation contract’; examples: `accepts a structurally complete backup and reports counts`, `rejects non-object, malformed, and incomplete backups safely`, `uses a safe default store name when profile name is absent`, … (2 more). |
| [`batch_allocation_dialog_test.dart`](../test/batch_allocation_dialog_test.dart) | Test suite with 1 cases; examples: `batch allocation dialog lets the user split one quantity`. |
| [`batch_expiry_workflow_test.dart`](../test/batch_expiry_workflow_test.dart) | Test suite with 4 cases; examples: `receives multiple expiry batches and allocates them using FEFO`, `allows an unallocated negative batch remainder when enabled`, `rejects an expired batch at receipt`, … (1 more). |
| [`cash_history_phase4_test.dart`](../test/cash_history_phase4_test.dart) | Test suite with 4 cases; examples: `phase 4 history supports SQL filters, search, paging summary and invoice search`, `phase 4 details resolve drawer, shift, allocations and journal reference`, `current shift range starts at session opened_at instead of start of today`, … (1 more). |
| [`cash_ledger_phase1_test.dart`](../test/cash_ledger_phase1_test.dart) | Test suite with 6 cases; examples: `foundation creates phase 1 cash ledger schema and indexes`, `append writes immutable ledger row linked to open drawer session`, `idempotency key returns original row instead of duplicating money`, … (3 more). |
| [`cash_operations_phase5_test.dart`](../test/cash_operations_phase5_test.dart) | Test suite with 14 cases; examples: `store-wide negative cash policy is the only outflow authority`, `foundation creates Phase 5 cash operations schema`, `deposit writes operation, journal, ledger and balance exactly once`, … (11 more). |
| [`cash_phase6_test.dart`](../test/cash_phase6_test.dart) | Test suite entry point; composes `cash_phase6_test_registration_01.dart`, `cash_phase6_test_registration_02.dart` and delegates test cases to those parts. |
| [`cash_phase6_test_registration_01.dart`](../test/cash_phase6_test_registration_01.dart) | Test implementation part of `cash_phase6_test.dart`; cases: `expected cash is opening balance plus current-session Cash Ledger only`, `shortage close writes immutable ledger, journal and reconciles balance`, `overage close writes cash-in ledger and counted balance`, … (5 more). |
| [`cash_phase6_test_registration_02.dart`](../test/cash_phase6_test_registration_02.dart) | Test implementation part of `cash_phase6_test.dart`; cases: `normalization repairs stale purchase paid amount when allocations already match total`, `purchase refund preflight sync repairs stale paid cache from allocations`, `supplier cash refund posts cash-in ledger and is idempotent`, … (6 more). |
| [`cash_phase7_migration_test.dart`](../test/cash_phase7_migration_test.dart) | Test suite with 5 cases; examples: `phase 7 schema is created by the foundation`, `legacy receipt becomes voucher + journal + ledger without moving cash twice`, `legacy supplier cash payment becomes payment voucher without moving cash twice`, … (2 more). |
| [`cash_phase8_integration_contract_test.dart`](../test/cash_phase8_integration_contract_test.dart) | Test suite with 10 cases; examples: `phase 8 snapshot catalog includes authoritative cash/accounting data`, `cash box permissions expose separate view and manage capabilities`, `cash operation emits Phase 8 mutation only after successful commit`, … (7 more). |
| [`costing_method_transition_contract_test.dart`](../test/costing_method_transition_contract_test.dart) | Test suite with 3 cases; examples: `Phase 4 locks production costing to Unified Batch`, `legacy costing codes remain readable for historical documents`, `legacy cost layers are historical evidence, not valuation truth`. |
| [`dashboard_service_test.dart`](../test/dashboard_service_test.dart) | Tests 1 cases in groups ‘DashboardService’; examples: `builds a dashboard snapshot without widget-side calculations`. |
| [`dashboard_snapshot_service_test.dart`](../test/dashboard_snapshot_service_test.dart) | Tests 1 cases in groups ‘DashboardSnapshotService’; examples: `computes sales totals from line items when computed fields are absent`. |
| [`db_first_contract_test.dart`](../test/db_first_contract_test.dart) | Test suite with 1 cases; examples: `pure db-first contract is documented and startup is db-first`. |
| [`delivery_note_model_test.dart`](../test/delivery_note_model_test.dart) | Test suite with 1 cases; examples: `DeliveryNote serializes and restores status/items`. |
| [`direct_peer_protocol_realtime_test.dart`](../test/direct_peer_protocol_realtime_test.dart) | Test suite with 2 cases; examples: `forwards Direct realtime events without treating them as responses`, `closes the realtime event stream when the peer connection closes`. |
| [`direct_snapshot_historical_integrity_regression_test.dart`](../test/direct_snapshot_historical_integrity_regression_test.dart) | Test suite with 1 cases; examples: `Direct bootstrap uses the same snapshot acceptance policy as LAN`. |
| [`direct_transport_foundation_test.dart`](../test/direct_transport_foundation_test.dart) | Test suite with 6 cases; examples: `recognizes direct as a supported unified transport kind`, `preserves direct as the selected device transport`, `keeps Direct bootstrap provisional until the initial snapshot completes`, … (3 more). |
| [`enterprise_stress_test.dart`](../test/enterprise_stress_test.dart) | Tests 2 cases in groups ‘Enterprise stress and recovery tests’; examples: `handles realistic catalog and sales volume without corrupting inventory`, `backup restore survives a populated store round trip`. |
| [`fake_database_test.dart`](../test/fake_database_test.dart) | Tests 4 cases in groups ‘FakeLocalDatabase contract’; examples: `starts empty and records writes`, `can be seeded for repository and store tests`, `records deletes and removes values`, … (1 more). |
| [`fixed_asset_cash_purchase_contract_test.dart`](../test/fixed_asset_cash_purchase_contract_test.dart) | Test suite with 2 cases; examples: `cash fixed-asset purchase is atomic with the asset transaction`, `fixed-asset dialog defaults to real cash drawer payment`. |
| [`golden_smoke_test.dart`](../test/golden_smoke_test.dart) | Tests 1 cases in groups ‘Golden visual regression smoke tests’; examples: `core dashboard cards keep their visual contract`. |
| [`inventory_movement_links_test.dart`](../test/inventory_movement_links_test.dart) | Test suite with 1 cases; examples: `inventory movement references link purchases and sales`. |
| [`invoice_generation_test.dart`](../test/invoice_generation_test.dart) | Tests 2 cases in groups ‘Invoice PDF generation’; examples: `builds a non-empty PDF document with a valid header`, `supports custom currency prefixes without throwing`. |
| [`lan_sync_transport_adapter_test.dart`](../test/lan_sync_transport_adapter_test.dart) | Tests 1 cases in groups ‘LanSyncTransportAdapter’; examples: `does not rebuild when the Host is offline`. |
| [`legacy_json_api_regression_test.dart`](../test/legacy_json_api_regression_test.dart) | Test suite with 1 cases; examples: `legacy JSON data APIs stay out of runtime lib sources`. |
| [`manufacturing_model_test.dart`](../test/manufacturing_model_test.dart) | Test suite with 2 cases; examples: `BillOfMaterials serializes and calculates unit cost`, `ManufacturingOrder serializes`. |
| [`model_business_logic_test.dart`](../test/model_business_logic_test.dart) | Tests 19 cases in groups ‘Product calculations and stock flags’; ‘Sale and sale item calculations’; examples: `calculates profit, margin, and inventory values`, `uses zero margin when price is zero`, `detects low stock only when stock tracking is enabled`, … (16 more). |
| [`model_serialization_test.dart`](../test/model_serialization_test.dart) | Tests 18 cases in groups ‘JSON round trips’; ‘Defensive JSON defaults’; examples: `Product round trip excludes derived inventory stock from product payloads`, `Sale round trip preserves nested items and totals`, `Purchase round trip preserves nested items and totals`, … (15 more). |
| [`negative_stock_policy_test.dart`](../test/negative_stock_policy_test.dart) | Test suite with 3 cases; examples: `DENY keeps Unified Batch strict and rolls shortage back`, `ALLOW consumes real batches then creates a tracked deficit`, `incoming stock settles deficit before becoming physical availability`. |
| [`offline_online_test.dart`](../test/offline_online_test.dart) | Tests 2 cases in groups ‘Offline/online behavior’; examples: `offline connection returns a failed result instead of throwing`, `online connection can recover after an offline result`. |
| [`page_smoke_test.dart`](../test/page_smoke_test.dart) | Tests 1 cases in groups ‘Feature page smoke tests’; examples: `${entry.key} page builds`. |
| [`payment_routing_phase3_contract_test.dart`](../test/payment_routing_phase3_contract_test.dart) | Test suite with 5 cases; examples: `phase 3 routes operational cash settlement through voucher methods`, `phase 3 separates invoice accounting from voucher payment posting`, `invoice editing is no longer part of the sale store`, … (2 more). |
| [`payment_voucher_phase2_test.dart`](../test/payment_voucher_phase2_test.dart) | Test suite entry point; composes `payment_voucher_phase2_test_split_01.dart`, `payment_voucher_phase2_test_split_02.dart` and delegates test cases to those parts. |
| [`payment_voucher_phase2_test_split_01.dart`](../test/payment_voucher_phase2_test_split_01.dart) | Test implementation part of `payment_voucher_phase2_test.dart`; declares `_openDb`, `_seedDrawer`, `_seedSale`, `_seedPurchase`. |
| [`payment_voucher_phase2_test_split_02.dart`](../test/payment_voucher_phase2_test_split_02.dart) | Test implementation part of `payment_voucher_phase2_test.dart`; cases: `foundation creates Phase 2 voucher and allocation schema`, `cash receipt supports multi-invoice allocation and unallocated credit`, `discounted customer receipt posts cash, discount, and full receivable`, … (13 more). |
| [`performance_smoke_test.dart`](../test/performance_smoke_test.dart) | Tests 4 cases in groups ‘Performance smoke tests’; examples: `calculates totals for a large invoice within a small budget`, `filters low stock products at realistic catalog scale`, `builds and searches a product index at large catalog scale`, … (1 more). |
| [`phase2_snapshot_behavior_test.dart`](../test/phase2_snapshot_behavior_test.dart) | Tests 3 cases in groups ‘Phase 2 snapshot behavior’; examples: `imports authoritative snapshots without double applying inventory`, `snapshot validation uses the incoming Store policy for negative inventory`, `legacy snapshots remain compatible without warehouse-aware tables`. |
| [`phase2_sync_payload_test.dart`](../test/phase2_sync_payload_test.dart) | Test suite with 3 cases; examples: `warehouse_inventory schema exposes the expected uniqueness guard`, `StockMovement round trip preserves warehouse-aware replay fields`, `unified snapshot inventory section includes warehouse-aware tables`. |
| [`phase2_tax_profiles_vat_test.dart`](../test/phase2_tax_profiles_vat_test.dart) | Test suite with 10 cases; examples: `tax calculator extracts inclusive VAT and preserves zero/exempt modes`, `mixed sale freezes line VAT after proportional document discount`, `discount allocation stays exact at currency precision`, … (7 more). |
| [`phase3_permission_enforcement_contract_test.dart`](../test/phase3_permission_enforcement_contract_test.dart) | Tests 9 cases in groups ‘Phase 3 permission enforcement contracts’; examples: `inventory mutations use inventory permissions, not product edit`, `purchase lifecycle separates manage and cancel permissions`, `supplier money operations require payment permission`, … (6 more). |
| [`phase4_5_6_security_contract_test.dart`](../test/phase4_5_6_security_contract_test.dart) | Tests 11 cases in groups ‘Phase 4 encrypted backup and secret protection contracts’; ‘Phase 5 authentication and sensitive action contracts’; examples: `manual and automatic backups use encrypted export paths`, `device-bound auth and cloud secrets use secure storage`, `backup payload excludes device secrets from scalar snapshot`, … (8 more). |
| [`phase5_manufacturing_transfer_test.dart`](../test/phase5_manufacturing_transfer_test.dart) | Tests 9 cases in groups ‘Phase 5 manufacturing and warehouse transfers’; examples: `manufacturing consumes raw stock and produces into target warehouse`, `manufacturing uses physical batches then a costed deficit when negative stock is allowed`, `manufacturing repairs an untouched zero-cost inventory-count batch before consumption`, … (6 more). |
| [`phase6_multi_warehouse_e2e_test.dart`](../test/phase6_multi_warehouse_e2e_test.dart) | Tests 1 cases in groups ‘Phase 6 end-to-end warehouse scenario’; examples: `covers purchase, transfer, sale, return, manufacturing, count, backup and replay`. |
| [`phase9_expense_atomicity_test.dart`](../test/phase9_expense_atomicity_test.dart) | Test suite with 4 cases; examples: `expense post commits document, accounting, cash and compatibility ledger together`, `partial cash expense posts the remainder to accounts payable`, `expense post rolls back every side effect when compatibility ledger insert fails`, … (1 more). |
| [`phase9_financial_atomicity_phase2_contract_test.dart`](../test/phase9_financial_atomicity_phase2_contract_test.dart) | Tests 5 cases in groups ‘Phase 9 financial atomicity - phase 2 contracts’; examples: `expense posting commits expense row and compatibility ledger with accounting`, `expense cancellation finalizes status and compatibility reversals inside reversal transaction`, `supplier refunds expose a stable refund key and key journal/ledger reference by it`, … (2 more). |
| [`phase9_invoice_atomicity_contract_test.dart`](../test/phase9_invoice_atomicity_contract_test.dart) | Test suite with 5 cases; examples: `purchase create commits invoice accounting and supplier ledger in SQLite transaction`, `purchase return/cancel commit accounting reversal and supplier ledger with document`, `sale create commits invoice accounting and customer ledger with stock/document`, … (2 more). |
| [`phase9_post_commit_financial_write_cleanup_contract_test.dart`](../test/phase9_post_commit_financial_write_cleanup_contract_test.dart) | Test suite with 1 cases; examples: `Phase 1/2 authoritative workflows do not re-write financial ledgers after commit`. |
| [`posted_document_edit_framework_contract_test.dart`](../test/posted_document_edit_framework_contract_test.dart) | Test suite with 1 cases; examples: `posted document edit framework executes the safety contract in order`. |
| [`posted_document_snapshot_test.dart`](../test/posted_document_snapshot_test.dart) | Test suite with 5 cases; examples: `posted sale view keeps historical store and line values`, `posted purchase view keeps historical document number and line values`, `snapshot JSON round-trip preserves legacy and tax-ready fields`, … (2 more). |
| [`posted_edit_batch_phase2_contract_test.dart`](../test/posted_edit_batch_phase2_contract_test.dart) | Test suite with 8 cases; examples: `receipt and payment edits keep append-only allocation history`, `posted expense edit is versioned and cancel remains family-aware`, `completed warehouse transfer edit reverses and rebuilds batch movements`, … (5 more). |
| [`posted_edit_final_integrity_contract_test.dart`](../test/posted_edit_final_integrity_contract_test.dart) | Test suite with 4 cases; examples: `production integrity recognizes versioned posted-edit families`, `phase7 cash integrity accepts edited vouchers and sales`, `manufacturing traceability ignores reversed historical edit movements`, … (1 more). |
| [`posted_snapshot_backfill_sql_contract_test.dart`](../test/posted_snapshot_backfill_sql_contract_test.dart) | Test suite with 1 cases; examples: `posted snapshot backfill writes only typed snapshot columns`. |
| [`print_settings_test.dart`](../test/print_settings_test.dart) | Test suite with 3 cases; examples: `document defaults use standard, narrow, and shipping formats`, `print settings round-trip preserves printers and document defaults`, `invalid persisted formats fall back to the document default`. |
| [`product_derived_flush_lifecycle_contract_test.dart`](../test/product_derived_flush_lifecycle_contract_test.dart) | Test suite with 2 cases; examples: `product-derived flush drains in-flight SQLite work before dirty exit`, `shutdown prevents timer rescheduling and performs a deterministic drain`. |
| [`production_phase10_health_disaster_recovery_contract_test.dart`](../test/production_phase10_health_disaster_recovery_contract_test.dart) | Test suite with 3 cases; examples: `Phase 10 composes all production integrity gates`, `Phase 10 recovery checkpoint performs a non-destructive restore drill`, `backup restore runs Phase 10 post-restore validation`. |
| [`production_phase12_structural_refactor_contract_test.dart`](../test/production_phase12_structural_refactor_contract_test.dart) | Test suite with 3 cases; examples: `Phase 12 keeps AppStore as a thin facade with domain state ownership`, `Phase 12 domain ports are consumed by production UI paths`, `Phase 12 preserves compatibility API and production schema contract`. |
| [`production_phase7_transaction_integrity_contract_test.dart`](../test/production_phase7_transaction_integrity_contract_test.dart) | Test suite with 6 cases; examples: `production sqlite commits use FULL durability`, `journal posting owns duplicate check and persistence post-condition`, `account transaction row and accounting effects share one transaction`, … (3 more). |
| [`production_phase8_golden_financial_scenario_test.dart`](../test/production_phase8_golden_financial_scenario_test.dart) | Test suite with 2 cases; examples: `production Phase 8 golden financial scenario closes to known balances`, `golden scenario uses application write paths and read-only SQL evidence`. |
| [`production_phase9_multi_warehouse_manufacturing_traceability_test.dart`](../test/production_phase9_multi_warehouse_manufacturing_traceability_test.dart) | Test suite with 1 cases; examples: `production Phase 9 preserves FEFO batch identity across transfer, manufacturing and trace graph`. |
| [`production_phase9_traceability_contract_test.dart`](../test/production_phase9_traceability_contract_test.dart) | Test suite with 1 cases; examples: `Phase 9 traceability service covers production invariants`. |
| [`purchase_edit_journal_repost_contract_test.dart`](../test/purchase_edit_journal_repost_contract_test.dart) | Test suite with 4 cases; examples: `received purchase edit is guarded by downstream Unified Batch usage`, `purchase accounting rejects stale posted snapshots before posting`, `receivePurchase can suppress normal accounting queue for edit repost`, … (1 more). |
| [`purchases_sqlite_overview_test.dart`](../test/purchases_sqlite_overview_test.dart) | Test suite with 1 cases; examples: `builds purchase overview from sqlite without throwing`. |
| [`sale_edit_journal_repost_contract_test.dart`](../test/sale_edit_journal_repost_contract_test.dart) | Test suite with 5 cases; examples: `posted sale edit follows the shared safe edit pipeline`, `sale edit protects returns, delivery notes, payments and version races`, `sale edit stock movement identity remains valid across edit and cancel`, … (2 more). |
| [`sqlite_accounting_metrics_test.dart`](../test/sqlite_accounting_metrics_test.dart) | Tests 1 cases in groups ‘SQLite accounting metrics’; examples: `builds accounting metrics from SQLite aggregates`. |
| [`sqlite_business_query_test.dart`](../test/sqlite_business_query_test.dart) | Tests 4 cases in groups ‘SQLite business query layer’; examples: `queries products with search, category, and pagination`, `queries customers and suppliers without loading full tables`, `queries expenses by status and text`, … (1 more). |
| [`sqlite_migration_regression_test.dart`](../test/sqlite_migration_regression_test.dart) | Test suite with 2 cases; examples: `initializeFoundation repairs legacy products tables missing track_stock`, `schema 25 removes the retired products.stock column`. |
| [`sqlite_operational_columns_test.dart`](../test/sqlite_operational_columns_test.dart) | Test suite with 9 cases; examples: `stock movements are written and read from typed SQLite columns`, `account transactions are written and read from typed SQLite columns`, `customers are written and read from typed SQLite columns`, … (6 more). |
| [`sqlite_snapshot_summary_test.dart`](../test/sqlite_snapshot_summary_test.dart) | Tests 2 cases in groups ‘SQLite snapshot summaries’; examples: `builds dashboard summary from SQLite aggregates`, `builds reports summary from SQLite aggregates`. |
| [`stock_transaction_phase0_test.dart`](../test/stock_transaction_phase0_test.dart) | Test suite with 17 cases; examples: `creates a warehouse balance and reads it back`, `rejects negative balance when policy is disabled`, `allows negative balance when policy is enabled`, … (14 more). |
| [`sync_and_permissions_test.dart`](../test/sync_and_permissions_test.dart) | Tests 23 cases in groups ‘AppStore sync queue recovery’; ‘SyncQueueItem state machine’; examples: `recovers submitted host rows to pending without duplicating work`, `pending item is ready when no retry date exists`, `failed item is pending but waits until retry date`, … (20 more). |
| [`sync_crash_recovery_test.dart`](../test/sync_crash_recovery_test.dart) | Tests 2 cases in groups ‘Sync crash and recovery’; examples: `recovers an in-progress push after reopening the app`, `does not lose a submitted Client draft after a crash before Host confirmation`. |
| [`sync_stage5_contract_test.dart`](../test/sync_stage5_contract_test.dart) | Tests 4 cases in groups ‘Stage 5 Host-authoritative sync contract’; examples: `Client may store both configs but exposes one active transport`, `Direct Client relay ACK state is submitted, not confirmed`, `Host authoritative event has a different eventId and sourceCommandId`, … (1 more). |
| [`unified_batch_phase1_test.dart`](../test/unified_batch_phase1_test.dart) | Test suite with 11 cases; examples: `phase 1 schema stores batch cost, source line and receipt date`, `non-expiry product uses batches and allocates oldest receipt first`, `expiry contract is controlled by product data`, … (8 more). |
| [`unified_batch_phase2_test.dart`](../test/unified_batch_phase2_test.dart) | Test suite with 11 cases; examples: `phase 2 schema carries cutover, draft expiry and sale batch cost`, `non-expiry cutover creates one idempotent opening batch`, `legacy negative warehouse cutover creates a tracked deficit`, … (8 more). |
| [`unified_batch_phase3_test.dart`](../test/unified_batch_phase3_test.dart) | Test suite with 5 cases; examples: `warehouse transfer preserves exact batch identity and cost`, `unified batch adjustment never allows a negative balance`, `manufacturing primitives retain exact consumed cost and output cost`, … (2 more). |
| [`unified_batch_phase4_test.dart`](../test/unified_batch_phase4_test.dart) | Test suite with 8 cases; examples: `phase 4 closes non-expiry inventory into Unified Batch idempotently`, `phase 4 repairs duplicate post-cutover costing rows idempotently`, `phase 4 converts allowed negative warehouse stock into a tracked deficit`, … (5 more). |
| [`unified_pairing_lifecycle_test.dart`](../test/unified_pairing_lifecycle_test.dart) | Tests 2 cases in groups ‘UnifiedPairingLifecycle’; examples: `validates same-store pairing claims consistently`, `builds a normalized client identity for claimed pairing`. |
| [`unified_snapshot_transfer_test.dart`](../test/unified_snapshot_transfer_test.dart) | Test suite with 3 cases; examples: `shared snapshot transfer validates and ACKs every chunk`, `shared snapshot transfer rejects an empty manifest`, `shared snapshot transfer rejects inconsistent chunk totals`. |
| [`unified_sync_engine_test.dart`](../test/unified_sync_engine_test.dart) | Tests 3 cases in groups ‘UnifiedSyncEngine’; examples: `does not rebuild when pull fails because the Host is offline`, `still rebuilds when the pull reports a missing snapshot`, `forwards transport lifecycle helpers through the unified engine`. |
| [`unified_sync_policy_test.dart`](../test/unified_sync_policy_test.dart) | Tests 3 cases in groups ‘UnifiedSyncPolicy’; examples: `allows LAN only for a configured Host or the active LAN client`, `allows Direct for a Host or the active Direct client`, `gates Direct and LAN roles through shared policy`. |
| [`unified_sync_queue_target_test.dart`](../test/unified_sync_queue_target_test.dart) | Test suite with 1 cases; examples: `LAN and Direct use the stable Host-facing queue target`. |
| [`unified_sync_transport_helpers_test.dart`](../test/unified_sync_transport_helpers_test.dart) | Tests 2 cases in groups ‘UnifiedSyncTransportHelpers’; examples: `classifies unsupported messages the same way for every transport`, `classifies authorization and conflict errors consistently`. |
| [`warehouse_inventory_phase1_test.dart`](../test/warehouse_inventory_phase1_test.dart) | Test suite with 4 cases; examples: `backfill migrates legacy balances into warehouse_inventory`, `backfill skips an already-applied migration adjustment on rerun`, `backfill handles a deleted product with movements in multiple warehouses`, … (1 more). |
| [`warehouse_model_test.dart`](../test/warehouse_model_test.dart) | Test suite with 1 cases; examples: `warehouse serializes and stock movements keep warehouse identity`. |
| [`widget_smoke_test.dart`](../test/widget_smoke_test.dart) | Tests 4 cases in groups ‘Reusable widget smoke tests’; examples: `AppSectionHeader renders title and subtitle`, `EmptyStateCard renders icon, title, and message`, `SummaryCard renders label and value`, … (1 more). |
| [`widget_test.dart`](../test/widget_test.dart) | Test suite with 1 cases; examples: `VentioApp builds without crashing`. |

## `test/fakes/`

| File | Contents / responsibility clue |
| --- | --- |
| [`fake_local_database.dart`](../test/fakes/fake_local_database.dart) | Test fakes module; provides `getString`, `setString`, `containsKey`, `deleteString`, `_ensureOnline`, `FakeLocalDatabase`. |

## `test/fixtures/`

| File | Contents / responsibility clue |
| --- | --- |
| [`production_phase8_golden_financial_expected.json`](../test/fixtures/production_phase8_golden_financial_expected.json) | Project configuration/data file (json). |

## `test/goldens/`

| File | Contents / responsibility clue |
| --- | --- |
| [`core_cards.png`](../test/goldens/core_cards.png) | Project source/resource file (.png). |

## `test/helpers/`

| File | Contents / responsibility clue |
| --- | --- |
| [`accounting_page_source.dart`](../test/helpers/accounting_page_source.dart) | Test helpers module; provides `readAccountingPageImplementationSource`. |
| [`accounting_service_source.dart`](../test/helpers/accounting_service_source.dart) | Test helpers module; provides `readAccountingServiceSource`, `readAccountingServiceImplementationSource`. |
| [`app_store_source.dart`](../test/helpers/app_store_source.dart) | Test helpers module; provides `readAppStoreImplementationSource`. |
| [`app_store_test_accessors.dart`](../test/helpers/app_store_test_accessors.dart) | Test helpers module; provides `_decodeEntityList`, `_decodeCachedEntityList`, `_sortProducts`, `_CachedEntityList`, `Function`, `AppStoreTestAccessors`. |
| [`business_sqlite_store_source.dart`](../test/helpers/business_sqlite_store_source.dart) | Test helpers module; provides `readBusinessSqliteStoreSource`, `readBusinessSqliteStoreImplementationSource`. |
| [`dart_library_source.dart`](../test/helpers/dart_library_source.dart) | Test helpers module; provides `readDartLibrarySource`. |
| [`sales_page_source.dart`](../test/helpers/sales_page_source.dart) | Test helpers module; provides `readSalesPageImplementationSource`. |
| [`schema_version_contract.dart`](../test/helpers/schema_version_contract.dart) | Test helpers module; provides `expectSchemaVersionAtLeast`. |
| [`settings_page_source.dart`](../test/helpers/settings_page_source.dart) | Test helpers module; provides `readSettingsPageImplementationSource`. |

## `test/support/`

| File | Contents / responsibility clue |
| --- | --- |
| [`test_business_session_context.dart`](../test/support/test_business_session_context.dart) | Test support module; provides `hasPermission`, `requirePermission`, `refreshAfterDatabaseChange`, `TestBusinessSessionContext`. |

## `tool/`

| File | Contents / responsibility clue |
| --- | --- |
| [`accounting_closure_audit.py`](../tool/accounting_closure_audit.py) | Defines `AuditIssue`, `AuditMetric`, `_number`, `_round`, `_table_exists`, `_setting_account`, … (6 more). |
| [`check_coverage.dart`](../tool/check_coverage.dart) | Declares `_Options`, `main`, `_normalizePath`, `_normalizeSourcePath`, `_matchesAny`, … (1 more). |
| [`check_coverage.ps1`](../tool/check_coverage.ps1) | PowerShell script; see its filename for the workflow. |
| [`check_coverage.sh`](../tool/check_coverage.sh) | Project source/resource file (.sh). |
| [`generate_project_file_index.py`](../tool/generate_project_file_index.py) | Defines `unique`, `short_list`, `readable_module_name`, `dart_declared_names`, `dart_summary`, `source_summary`, … (3 more). |
| [`quality_gate_config.json`](../tool/quality_gate_config.json) | Project configuration/data file (json). |
| [`recover_audit_tail.dart`](../tool/recover_audit_tail.dart) | Declares `auditRows`, `digest`, `validateRecoverableTail`, `recoverTail`, `main`. |
| [`run_full_quality_gate.ps1`](../tool/run_full_quality_gate.ps1) | PowerShell script; see its filename for the workflow. |
| [`run_full_quality_gate.sh`](../tool/run_full_quality_gate.sh) | Project source/resource file (.sh). |
| [`run_phase0_baseline.dart`](../tool/run_phase0_baseline.dart) | Declares `_RunResult`, `main`, `_pubspecVersion`, `_testInventory`, `_staticVersionInventory`, … (4 more). |
| [`run_phase0_baseline.ps1`](../tool/run_phase0_baseline.ps1) | PowerShell script; see its filename for the workflow. |
| [`run_phase0_baseline.sh`](../tool/run_phase0_baseline.sh) | Project source/resource file (.sh). |
| [`run_tests_windows.ps1`](../tool/run_tests_windows.ps1) | PowerShell script; see its filename for the workflow. |
| [`verify_cost_source_unification.py`](../tool/verify_cost_source_unification.py) | Defines `read`, `check`. |
| [`verify_phase10_health_disaster_recovery.py`](../tool/verify_phase10_health_disaster_recovery.py) | Defines `add`. |
| [`verify_phase12_structural_refactor.py`](../tool/verify_phase12_structural_refactor.py) | Defines `check`. |
| [`verify_phase7_transaction_integrity.py`](../tool/verify_phase7_transaction_integrity.py) | Defines `check`. |
| [`verify_phase8_golden_financial.py`](../tool/verify_phase8_golden_financial.py) | Defines `check`. |
| [`verify_phase9_traceability.py`](../tool/verify_phase9_traceability.py) | Defines `check`. |
| [`verify_unified_batch_negative_stock_hardening.py`](../tool/verify_unified_batch_negative_stock_hardening.py) | Defines `read`, `check`. |
