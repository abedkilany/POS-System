# Ventio Project Map

This guide explains where responsibilities live and how to locate the implementation for a change. The searchable per-file catalog is in [FILE_INDEX.md](FILE_INDEX.md); the source code and tests remain authoritative.

## Start here

| Goal | First stop | Follow the path |
| --- | --- | --- |
| Understand the app and its durable rules | [README.md](../README.md) | Read only the relevant business or runtime section. |
| Route a coding task efficiently | [AGENTS.md](../AGENTS.md) | Use its task-to-code table and focused-context rules. |
| Find a particular source or test file | [FILE_INDEX.md](FILE_INDEX.md) | Search the exact filename or symbol, then open the source. |
| Find platform, config, or resource files | [PLATFORM_INDEX.md](PLATFORM_INDEX.md) | Search by filename; generated build output is omitted. |
| Trace a business workflow | `lib/features/` → `lib/data/` → `lib/core/services/` → repositories/SQLite | Follow the matching feature and its focused tests. |
| Trace a database change | `lib/core/storage/sqlite/` and `database/` | Client business SQLite lives under `lib`; `database/` contains VPS/control-plane SQL. |

## Runtime shape

1. Flutter screens and user actions live under `lib/features/`.
2. `AppStore` and its typed domain ports coordinate application state and workflows in `lib/data/`.
3. Business rules, reports, posting, backup, and transport operations live in `lib/core/services/` and the relevant repositories.
4. Local operational data is authoritative in SQLite, implemented under `lib/core/storage/sqlite/`. In-memory state is a cache, not a second business database.
5. Authorized Host and Client devices exchange business data over LAN or Direct peer synchronization. `server.js` and `server_api/` provide the VPS control plane; they do not store the store's operational business records.

For accounting, inventory, synchronization, backup, and assistant data-access rules, use the corresponding sections in the README. This map intentionally routes to those rules rather than copying them.

## Repository directory index

| Path | Responsibility |
| --- | --- |
| `lib/` | Flutter application, domain models, application state, services, persistence, and UI. |
| `lib/data/` | AppStore facade, domain state, typed ports, and workflow implementation parts. |
| `lib/core/services/` | Accounting, sales, purchases, inventory, backup, database, reporting, and sync workflows. |
| `lib/core/storage/sqlite/` | Drift database, schema, migrations, typed SQLite stores, and query implementations. |
| `lib/core/repositories/` | Domain persistence and reconciliation boundaries. |
| `lib/core/sync_unified/` | Shared event, snapshot, and payload synchronization contracts. |
| `lib/core/accounting/`, `lib/core/money/` | Accounting account-role rules and shared money/currency primitives. |
| `lib/core/security/`, `lib/core/snapshot/` | Audit integrity/security helpers and snapshot/recovery primitives. |
| `lib/core/localization/`, `lib/core/theme/`, `lib/core/utils/`, `lib/core/shortcuts/` | Localization, design system, shared helpers, and keyboard shortcut definitions. |
| `lib/features/` | Screens and UI workflows grouped by business area; see the feature map below. |
| `lib/models/` | Typed business and application data models. |
| `lib/widgets/` | Reusable UI components shared across feature screens. |
| `server.js`, `server_api/` | VPS API entry point and control-plane handlers for accounts, devices, pairing, signaling, health, and entitlements. |
| `database/` | SQL schemas and migrations used by the VPS/control plane, not the client's business SQLite database. |
| `test/` | Unit, widget, regression, structural-contract, and workflow tests. |
| `integration_test/` | End-to-end tests that navigate the running Flutter application. |
| `tool/` | Quality gates, focused verification utilities, test runners, and the source-index generator. |
| `scripts/` | Translation checks, platform-admin setup, and Windows installer build automation. |
| `assets/` | Translation JSON, fonts, UI sounds, and Ventio brand images. |
| `installer/` | Installer-specific distribution resources. |
| `android/`, `web/`, `windows/` | Current Android, Web, and Windows platform runners/configuration. |
| `ios/`, `linux/`, `macos/` | Flutter platform scaffolding retained for possible future targets; their presence does not mean those builds are part of the current release. |
| `.github/` | Repository automation and CI configuration. |

## Root configuration and shared resources

| File or path | Responsibility |
| --- | --- |
| `pubspec.yaml` | Flutter package identity, Dart dependencies, asset/font registration, and Flutter settings. |
| `pubspec.lock` | Exact resolved Dart/Flutter dependency versions for reproducible installs. |
| `analysis_options.yaml` | Dart analyzer and lint policy. |
| `dart_test.yaml` | Defaults for Dart/Flutter test execution. |
| `package.json`, `package-lock.json` | Node API package metadata/scripts and locked npm dependency versions. |
| `.gitignore` | Excludes build output, local secrets, caches, and machine-specific files from Git. |
| `.metadata` | Flutter project/platform migration metadata. |
| `.github/workflows/deploy-vps.yml` | GitHub Actions workflow for VPS deployment. |

### Brand, language, sound, and font assets

| Path | Responsibility |
| --- | --- |
| `assets/translations/ar.json`, `en.json`, `fr.json` | Arabic, English, and French UI translation keys. |
| `assets/sounds/beep.wav`, `error.wav` | Short UI success and error sounds. |
| `assets/fonts/Tahoma.ttf`, `Tahoma-Bold.ttf` | Tahoma family used for text rendering. |
| `assets/fonts/Roboto-Regular.ttf`, `Roboto-Medium.ttf` | Roboto regular and medium font faces. |
| `assets/fonts/DejaVuSans.ttf`, `DejaVuSans-Bold.ttf` | DejaVu Sans fallback faces. |
| `assets/branding/ventio_wordmark_transparent.png`, `ventio_wordmark_dark.png` | Transparent and dark-background Ventio wordmarks. |
| `assets/branding/ventio_symbol_transparent.png`, `ventio_app_icon_1024.png` | Standalone Ventio mark and high-resolution app icon source. |

### Platform entry points

| Path | Responsibility |
| --- | --- |
| `android/app/src/main/AndroidManifest.xml` | Android app identity, permissions, and main activity registration. |
| `android/app/src/main/kotlin/com/kilany/ventio/MainActivity.kt` | Android Flutter activity entry point. |
| `android/app/build.gradle.kts`, `android/settings.gradle.kts` | Android app and Gradle project build configuration. |
| `web/index.html`, `web/manifest.json` | Web document bootstrap and installable-web-app metadata. |
| `windows/runner/main.cpp`, `windows/runner/flutter_window.cpp` | Windows runner startup and Flutter window host. |
| `windows/CMakeLists.txt`, `windows/runner/CMakeLists.txt` | Windows native runner build configuration. |
| `ios/Runner/AppDelegate.swift`, `ios/Runner/Info.plist` | iOS Flutter bootstrap and bundle configuration; scaffold only for the current release. |
| `macos/Runner/AppDelegate.swift`, `macos/Runner/Info.plist` | macOS Flutter bootstrap and bundle configuration; scaffold only for the current release. |
| `linux/runner/main.cc`, `linux/runner/CMakeLists.txt` | Linux runner entry point and native build configuration; scaffold only for the current release. |

Other files under platform folders are Flutter-generated registrants, native resource catalogs, project/IDE settings, and runner support code. They follow the platform toolchain; change them only for a platform-specific task. Generated plugin metadata and build outputs are not application modules.

## Feature directory map

| Path | Main responsibility |
| --- | --- |
| `lib/features/account/` | Signed-in account/profile screen. |
| `lib/features/accounting/` | Financial reports, journals, accounting operations, and accounting screen support. |
| `lib/features/accounts/` | Chart-of-accounts and account-ledger UI. |
| `lib/features/admin/` | Administrative subscriber and account-management screens. |
| `lib/features/assistant/` | Provider settings, local assistant chat, consent, conversation history, and bounded read-only business tools. |
| `lib/features/barcode/` | Barcode scanning and lookup UI. |
| `lib/features/cash/` | Cash-box, drawer, and cash movement screens. |
| `lib/features/customers/`, `lib/features/suppliers/` | Customer and supplier records and related balances. |
| `lib/features/dashboard/` | Dashboard screens and snapshot composition. |
| `lib/features/database/` | Local database inspection and database-facing UI. |
| `lib/features/expenses/` | Expense entry, approval, posting, and expense lists. |
| `lib/features/inventory/` | Stock, warehouses, counts, and manufacturing UI. |
| `lib/features/maintenance/` | Recovery, migrations, integrity checks, and operational maintenance screens. |
| `lib/features/products/` | Product catalog and pricing UI. |
| `lib/features/purchases/` | Purchase workflows, receiving, returns, and purchase screens. |
| `lib/features/reports/` | Cross-feature report screens. |
| `lib/features/sales/` | Point of sale, invoices, returns, shifts, and sales UI. |
| `lib/features/security/` | Login gates and access-control UI. |
| `lib/features/settings/` | Application configuration, backup, device pairing, and sync setup/monitoring. |
| `lib/features/shared/` | Shared feature UI such as sync monitoring. |

## Reading split files

Large Dart libraries are divided into `part` files so each implementation unit stays reviewable. The main library file owns imports, declarations, and the `part` list; a `*_methods_NN.dart`, `*_split_NN.dart`, or feature-specific part is still part of that library, not an independent module. Read the parent file first, then the relevant part listed in [FILE_INDEX.md](FILE_INDEX.md).

Names such as `_widgets`, `_layout`, `_actions`, `_reports`, and `_persistence` describe the responsibility of a part. The index lists the methods or tests declared in each file to make these splits searchable.

## Persistence and API boundaries

- `lib/core/storage/sqlite/` owns the client SQLite schema and local persistence implementation.
- `lib/core/services/local_database_service.dart` is the app-facing database access boundary; business workflows should use typed service/repository APIs rather than write raw storage from UI code.
- `lib/data/app_store.dart` is a compatibility/session facade. Prefer its typed domain ports for new UI workflows.
- `server_api/` and `database/` serve the VPS control plane. Do not treat them as the client's operational business database.
- `test/` includes executable behavior checks as well as source-structure contract checks. Use the exact relevant test file from the index when changing one workflow.

## Keeping the map current

- Update this guide when a directory gains or loses a durable architectural responsibility.
- Regenerate the source index after adding, removing, renaming, or substantially splitting indexed code: `python tool/generate_project_file_index.py`.
- The generated catalogs cover every first-party source/test file under the source roots and every checked-in, non-ignored platform/resource file. Dependency caches, ignored local output, and build artifacts are excluded.
- Keep README sections for durable business/runtime rules. Keep this map for navigation and file ownership; avoid copying the same rules into both places.
- Do not document generated build output, dependency caches, or temporary task reports as application modules.
