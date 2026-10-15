# Ventio Agent Guide

Use this file to route work to relevant code. `README.md` remains the source for durable architecture and business rules. [`docs/PROJECT_MAP.md`](docs/PROJECT_MAP.md) explains directory ownership, [`docs/FILE_INDEX.md`](docs/FILE_INDEX.md) is a searchable source/test index, and [`docs/PLATFORM_INDEX.md`](docs/PLATFORM_INDEX.md) catalogs platform scaffolding and bundled resources.

## Context rules

- Start from the requested screen, behavior, or symbol. Search exact names with `rg`; read only matching code, its direct dependencies, the database schema when relevant, and focused tests.
- Use the project map for ownership and the relevant file index to locate a path or declaration. Search the index for the relevant row; do not read the entire catalog as task context. The indexes are navigational and source files remain authoritative.
- Do not read all of `lib/`, `test/`, or `README.md` by default. Open only the README section needed for the task.
- For large files, search for the relevant class/method first and inspect only its line range. Avoid opening an entire screen, service, or storage file unless the task truly spans it.
- Inspect only the requested platform. Do not scan iOS, macOS, or Linux scaffolds for a Windows/Web/Android task.
- Treat SQLite schema and migrations as authoritative for table and column names. Verify columns before changing SQL.
- Keep changes within the requested feature. Prefer the smallest relevant test; run the full suite or build an app only when requested or necessary for a broad change.
- Ignore generated/local output: `.dart_tool/`, `build/`, `coverage/`, `node_modules/`, and platform build artifacts.
- Keep tool output small: request test summaries and failing excerpts, not full startup/debug logs. Do not paste whole files into the response.

## Architecture anchors

- `lib/features/`: UI by feature.
- `lib/data/app_store.dart` and `lib/data/app_store_*.dart`: application state and workflow facade/splits. Prefer typed domain ports where available.
- `lib/core/services/`: business workflows and reports.
- `lib/core/storage/sqlite/`: SQLite schema, migrations, and typed persistence. SQLite is authoritative for business data; preferences are not a business datastore.
- `lib/core/accounting/`, `lib/core/repositories/`, `lib/models/`: accounting rules, repository boundaries, and domain models.
- `server_api/` and root `server.js`: VPS API. It is a control plane, not the store for business records.

## Task-to-code map

| Task | Start here | Focused tests |
| --- | --- | --- |
| Accounting and financial reports | `lib/features/accounting/`, `lib/core/services/accounting_service.dart`, `lib/core/services/accounting_production_integrity_service.dart` | `test/accounting_*.dart`, `test/production_*.dart` |
| Inventory, warehouses, manufacturing | `lib/features/inventory/`, `lib/data/app_store_inventory.dart`, `lib/data/app_store_warehouse_cash.dart`, `lib/data/app_store_manufacturing.dart`, relevant services | `test/*inventory*`, `test/*warehouse*`, `test/*manufacturing*` |
| SQLite schema, migrations, queries | `lib/core/storage/sqlite/` | `test/sqlite_*.dart`, migration and persistence tests |
| UI navigation and shared shell | `lib/features/<area>/`, `integration_test/app_shell_flow_test.dart` | matching feature tests and `integration_test/` |
| AI assistant and providers | `lib/features/assistant/` | `test/assistant_*.dart` |
| Sync and VPS/API | `lib/core/sync_unified/`, `lib/core/services/`, `server_api/`, `server.js` | search for the specific transport/API feature before selecting tests |
| Windows packaging | `windows/`, `installer/`, `scripts/build_windows_installer.ps1` | build/package checks only when requested or required |

## Change checks

- For a database query, verify its table definition/migration and exercise it against the current SQLite schema in a test.
- For an accounting or stock mutation, trace the workflow through its service and transaction boundary; preserve atomicity and reversal history.
- Do not infer that disabled, generated, or platform-specific files are active code. Check their references and the task's target platform first.
- Keep detailed explanations in `README.md` only when they describe durable behavior; do not add temporary task reports.
- Update `docs/PROJECT_MAP.md` when directory ownership or durable architecture changes. Regenerate `docs/FILE_INDEX.md` after source/test paths or declarations change with `python tool/generate_project_file_index.py`.

## Compact task brief

When a request needs clarification, structure the task around these fields:

```text
Goal:
Area or screen:
Expected result:
Constraints:
Verification:
```
