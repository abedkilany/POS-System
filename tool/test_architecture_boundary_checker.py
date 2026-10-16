import importlib.util
import tempfile
import unittest
from collections import Counter
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "architecture_boundary_checker", ROOT / "tool" / "check_architecture_boundaries.py"
)
CHECKER = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(CHECKER)


class ArchitectureBoundaryCheckerTest(unittest.TestCase):
    def test_shared_library_growth_fails_even_when_no_individual_file_is_large(self):
        baseline = {
            "appStorePublicMembers": [], "appStoreMentions": {},
            "crossFeatureImports": {}, "appStoreSelectors": {},
            "appStoreLibraryLines": 100,
        }
        current = {**baseline, "appStoreLibraryLines": 101}
        with patch.object(CHECKER, "domain_adapter_app_store_calls", return_value=Counter()):
            errors = CHECKER.validate_against_baseline(current, baseline)
        self.assertEqual(len(errors), 1)
        self.assertIn("shared library grew", errors[0])

    def test_wrapped_members_and_root_class_cannot_bypass_facade_policy(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            data = root / "lib" / "data"
            data.mkdir(parents=True)
            api = data / "app_store_forwarding_api.dart"
            api.write_text(
                "mixin _Forwarding {\n"
                "  Future<List<Map<String, dynamic>>>\n"
                "      exportSnapshot() async => [];\n"
                "  List<Map<String, dynamic>>\n"
                "      get records => [];\n}\n", encoding="utf-8",
            )
            (data / "app_store.dart").write_text(
                "class AppStore extends ChangeNotifier\n"
                "    implements ApplicationSession {\n"
                "  late final SyncDomainPort sync = _SyncDomain(this);\n"
                "  static void setTraceSink(Object value) {}\n"
                "  void dispose() {}\n"
                "  int unguardedCounter = 0;\n"
                "  Future<void> bypass() async {}\n}\n", encoding="utf-8",
            )
            original_root, original_api = CHECKER.ROOT, CHECKER.APP_STORE_API_FILES
            try:
                CHECKER.ROOT, CHECKER.APP_STORE_API_FILES = root, [api]
                members = CHECKER.public_app_store_members()
            finally:
                CHECKER.ROOT, CHECKER.APP_STORE_API_FILES = original_root, original_api
            self.assertEqual(members, {"exportSnapshot", "records", "bypass", "unguardedCounter"})

    def test_counts_appstore_selectors_in_library_parts(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            app = root / "lib" / "app.dart"
            part = root / "lib" / "app_part.dart"
            api = root / "lib" / "data" / "app_store_forwarding_api.dart"
            app.parent.mkdir(parents=True)
            api.parent.mkdir(parents=True)
            app.write_text(
                "part 'app_part.dart';\nfinal AppStore store = AppStore();\n",
                encoding="utf-8",
            )
            part.write_text(
                "part of 'app.dart';\nvoid start() { store.initialize(); }\n",
                encoding="utf-8",
            )
            api.write_text(
                "part of 'app_store.dart';\n"
                "mixin _ForwardingApi {\n"
                "  Future<void> initialize() async {}\n"
                "}\n",
                encoding="utf-8",
            )

            original_root = CHECKER.ROOT
            original_api_files = CHECKER.APP_STORE_API_FILES
            try:
                CHECKER.ROOT = root
                CHECKER.APP_STORE_API_FILES = [api]
                selectors = CHECKER.app_store_selectors(
                    CHECKER.public_app_store_members()
                )
            finally:
                CHECKER.ROOT = original_root
                CHECKER.APP_STORE_API_FILES = original_api_files

            self.assertEqual(selectors, {"lib/app_part.dart": Counter({"initialize": 1})})

    def test_does_not_count_typed_domain_selectors_as_compatibility(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            app = root / "lib" / "app.dart"
            part = root / "lib" / "app_part.dart"
            api = root / "lib" / "data" / "app_store_forwarding_api.dart"
            app.parent.mkdir(parents=True)
            api.parent.mkdir(parents=True)
            app.write_text(
                "part 'app_part.dart';\nfinal AppStore store = AppStore();\n",
                encoding="utf-8",
            )
            part.write_text(
                "part of 'app.dart';\nvoid start() { store.runtime.initialize(); }\n",
                encoding="utf-8",
            )
            api.write_text(
                "part of 'app_store.dart';\n"
                "mixin _ForwardingApi {\n"
                "  Future<void> initialize() async {}\n"
                "}\n",
                encoding="utf-8",
            )

            original_root = CHECKER.ROOT
            original_api_files = CHECKER.APP_STORE_API_FILES
            try:
                CHECKER.ROOT = root
                CHECKER.APP_STORE_API_FILES = [api]
                selectors = CHECKER.app_store_selectors(
                    CHECKER.public_app_store_members()
                )
            finally:
                CHECKER.ROOT = original_root
                CHECKER.APP_STORE_API_FILES = original_api_files

            self.assertEqual(selectors, {})

    def test_counts_only_public_appstore_extensions_as_facade_members(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            api = root / "lib" / "data" / "app_store_forwarding_api.dart"
            backup = root / "lib" / "data" / "app_store_backup.dart"
            api.parent.mkdir(parents=True)
            api.write_text(
                "part of 'app_store.dart';\n"
                "mixin _ForwardingApi {\n"
                "  Future<void> _initialize() async {}\n"
                "}\n",
                encoding="utf-8",
            )
            backup.write_text(
                "part of 'app_store.dart';\n"
                "extension _InternalBackup on AppStore {\n"
                "  String internalMethod() => '';\n"
                "}\n"
                "extension PublicBackup on AppStore {\n"
                "  String validateBackupJson() => '';\n"
                "}\n",
                encoding="utf-8",
            )

            original_root = CHECKER.ROOT
            original_api_files = CHECKER.APP_STORE_API_FILES
            try:
                CHECKER.ROOT = root
                CHECKER.APP_STORE_API_FILES = [api]
                members = CHECKER.public_app_store_members()
            finally:
                CHECKER.ROOT = original_root
                CHECKER.APP_STORE_API_FILES = original_api_files

            self.assertEqual(members, {"validateBackupJson"})


class IndependentLayerBoundaryTest(unittest.TestCase):
    def check_files(self, files: dict[str, str]) -> list[str]:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            for name, source in files.items():
                path = root / "lib" / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(source, encoding="utf-8")
            return CHECKER.layer_boundary_violations(root)

    def test_rejects_core_to_data_and_contract_to_service_imports(self):
        errors = self.check_files({
            "core/services/sync.dart": "import '../../data/app_store.dart';",
            "core/contracts/sync.dart": "export '../services/sync.dart';",
        })
        self.assertEqual(len(errors), 2)

    def test_checks_package_and_conditional_imports(self):
        errors = self.check_files({
            "features/sales/page.dart": "import 'package:ventio/core/contracts/session.dart'\n"
                " if (dart.library.io) 'package:ventio/data/app_store.dart';",
        })
        self.assertEqual(len(errors), 1)

    def test_allows_contract_models_and_data_implementation(self):
        self.assertEqual(self.check_files({
            "core/contracts/sales.dart": "import '../../models/sale.dart';",
            "data/app_store.dart": "import '../core/contracts/sales.dart';",
            "features/sales/page.dart": "import 'package:ventio/core/contracts/sales.dart';",
        }), [])

    def test_rejects_model_dependency_on_storage(self):
        errors = self.check_files({
            "models/sale.dart": "import '../core/storage/sqlite/database.dart';",
        })
        self.assertEqual(len(errors), 1)

    def test_mutable_state_is_private_to_the_data_layer(self):
        errors = self.check_files({
            "features/sales/page.dart": "import '../../data/state/commerce_state.dart';",
            "data/app_store.dart": "import 'state/commerce_state.dart';",
        })
        self.assertEqual(len(errors), 1)

    def test_reviewable_file_sizes_and_semantic_data_names(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            data = root / "lib" / "data"
            data.mkdir(parents=True)
            (data / "app_store_split_02.dart").write_text("// workflow\n", encoding="utf-8")
            (data / "large.dart").write_text("// line\n" * 1001, encoding="utf-8")
            (data / "generated.g.dart").write_text("// line\n" * 1001, encoding="utf-8")
            errors = CHECKER.module_structure_violations(root)
        self.assertEqual(len(errors), 2)
        self.assertTrue(any("1000-line" in error for error in errors))
        self.assertTrue(any("by responsibility" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
