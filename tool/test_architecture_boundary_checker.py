import importlib.util
import tempfile
import unittest
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "architecture_boundary_checker", ROOT / "tool" / "check_architecture_boundaries.py"
)
CHECKER = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(CHECKER)


class ArchitectureBoundaryCheckerTest(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
