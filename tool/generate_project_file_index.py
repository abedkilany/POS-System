#!/usr/bin/env python3
"""Generate the searchable index of Ventio's first-party source files."""

from __future__ import annotations

import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOTS = (
    "lib",
    "test",
    "integration_test",
    "server_api",
    "scripts",
    "tool",
    "database",
)
ROOT_SOURCE_FILES = ("server.js",)
PLATFORM_ROOTS = (".github", "android", "assets", "installer", "ios", "linux", "macos", "web", "windows")
DOCUMENTATION_FILES = {
    "README.md": "Canonical project overview, runtime architecture, and durable business rules.",
    "AGENTS.md": "Repository-specific coding-agent context, task routing, and focused-reading rules.",
    "docs/PROJECT_MAP.md": "Directory ownership, architecture path, feature map, and navigation guidance.",
    "docs/FILE_INDEX.md": "Generated searchable index of source and test files, declarations, and test cases.",
    "docs/PLATFORM_INDEX.md": "Generated index of platform scaffolding, configuration, and bundled resources.",
}
ROOT_CONFIG_FILES = {
    ".gitignore": "Git ignore policy for local files, secrets, caches, and build output.",
    ".metadata": "Flutter project metadata used when managing platform scaffolds.",
    "analysis_options.yaml": "Dart analyzer and lint policy.",
    "dart_test.yaml": "Default Dart test runner configuration.",
    "package.json": "Node API package metadata, scripts, and dependencies.",
    "package-lock.json": "Resolved npm dependency lockfile.",
    "pubspec.yaml": "Flutter package metadata, dependencies, assets, and fonts.",
    "pubspec.lock": "Resolved Dart/Flutter dependency lockfile.",
}
OUTPUT = ROOT / "docs" / "FILE_INDEX.md"
PLATFORM_OUTPUT = ROOT / "docs" / "PLATFORM_INDEX.md"

DART_TYPES = re.compile(
    r"(?m)^\s*(?:(?:abstract|base|final|sealed|interface)\s+)*"
    r"(?:class|enum|mixin|extension|typedef)\s+([A-Za-z_$][\w$]*)"
)
DART_MEMBERS = re.compile(
    r"(?m)^ {2}(?:static\s+)?"
    r"[A-Za-z_$][\w$<>?,.\[\] ]*?\s+"
    r"([A-Za-z_$][\w$]*)\s*(?:<[^\n;]+>)?\s*\("
)
TOP_LEVEL_FUNCTIONS = re.compile(
    r"(?m)^(?:export\s+)?(?:async\s+)?"
    r"(?:function\s+|def\s+)([A-Za-z_$][\w$]*)"
)
TEST_GROUP_TITLES = re.compile(r"\bgroup\s*\(\s*(['\"])(.*?)\1", re.DOTALL)
TEST_CASE_TITLES = re.compile(r"\b(?:testWidgets|test)\s*\(\s*(['\"])(.*?)\1", re.DOTALL)
SQL_PURPOSES = {
    "rebuild_snapshots_from_events.sql": "Rebuilds entity snapshots from retained sync events, including stock movements.",
    "sync_backfill_from_events.sql": "Backfills entity snapshots from previously uploaded restore-snapshot events.",
}


def unique(values: list[str]) -> list[str]:
    return list(dict.fromkeys(value.strip() for value in values if value.strip()))


def short_list(values: list[str], limit: int = 6) -> str:
    values = unique(values)
    if not values:
        return ""
    shown = values[:limit]
    result = ", ".join(f"`{value}`" for value in shown)
    if len(values) > limit:
        result += f", … ({len(values) - limit} more)"
    return result


def readable_module_name(path: Path) -> str:
    stem = path.stem
    platform = ""
    for suffix, label in (("_stub", "platform stub"), ("_io", "IO implementation"), ("_web", "web implementation")):
        if stem.endswith(suffix):
            stem = stem[: -len(suffix)]
            platform = f" ({label})"
            break
    return re.sub(r"\s+", " ", stem.replace("_", " ")).strip() + platform


def dart_declared_names(text: str) -> list[str]:
    declarations = re.findall(
        r"(?m)^(?:Future(?:<[^>]+>)?|Stream(?:<[^>]+>)?|void|bool|int|double|String|[A-Z][\w<>?,. ]*)\s+([a-z_$][\w$]*)\s*(?:<[^\n;]+>)?\s*\(",
        text,
    )
    return unique(declarations)


def dart_summary(path: Path, text: str) -> str:
    relative = path.relative_to(ROOT).as_posix()
    part_match = re.search(r"(?m)^part of ['\"]([^'\"]+)['\"]\s*;", text)
    types = unique(DART_TYPES.findall(text))

    if part_match:
        parent = part_match.group(1)
        members = unique(DART_MEMBERS.findall(text) + dart_declared_names(text))
        if relative.startswith(("test/", "integration_test/")):
            groups = unique([title.replace("\n", " ").strip() for _, title in TEST_GROUP_TITLES.findall(text)])
            cases = unique([title.replace("\n", " ").strip() for _, title in TEST_CASE_TITLES.findall(text)])
            coverage = []
            if groups:
                coverage.append(f"covers groups {'; '.join(f'‘{title}’' for title in groups[:2])}")
            if cases:
                coverage.append(f"cases: {short_list(cases, 3)}")
            if not coverage:
                coverage.append(f"declares {short_list(members) or short_list(types) or 'test helpers'}")
            return f"Test implementation part of `{parent}`; {'; '.join(coverage)}."
        if members:
            return f"Implementation part of `{parent}`; contains {short_list(members)}."
        return f"Implementation part of `{parent}`; contains {short_list(types) or 'supporting declarations'}."

    if relative.startswith(("test/", "integration_test/")):
        groups = unique([title.replace("\n", " ").strip() for _, title in TEST_GROUP_TITLES.findall(text)])
        cases = unique([title.replace("\n", " ").strip() for _, title in TEST_CASE_TITLES.findall(text)])
        group_text = "; ".join(f"‘{title}’" for title in groups[:2])
        case_text = short_list(cases, limit=3)
        parts = unique(re.findall(r"(?m)^part ['\"]([^'\"]+)['\"]\s*;", text))
        if parts:
            return f"Test suite entry point; composes {short_list(parts, 5)} and delegates test cases to those parts."
        if group_text and case_text:
            return f"Tests {len(cases)} cases in groups {group_text}; examples: {case_text}."
        if group_text:
            return f"Test suite with {len(cases)} cases; covers {group_text}."
        if case_text:
            return f"Test suite with {len(cases)} cases; examples: {case_text}."
        support_kind = next((kind for kind in ("helpers", "fakes", "support") if f"/{kind}/" in f"/{relative}"), None)
        names = dart_declared_names(text) + unique(DART_MEMBERS.findall(text)) + types
        if support_kind:
            return f"Test {support_kind} module; provides {short_list(names) or '`' + readable_module_name(path) + '` test support'}."
        return f"Test suite for {readable_module_name(path)}; no inline test cases, see its registrations or imports."

    parts = unique(re.findall(r"(?m)^part ['\"]([^'\"]+)['\"]\s*;", text))
    functions = unique(dart_declared_names(text) + TOP_LEVEL_FUNCTIONS.findall(text))
    units = short_list(types + functions, limit=5)
    if relative == "lib/main.dart":
        return "Flutter application entry point; initializes app services and launches the UI."
    if parts:
        part_text = short_list(parts, limit=5)
        return f"Library entry; declares {units or 'shared library definitions'} and composes parts {part_text}."
    if units:
        return f"Declares {units}."
    return f"Dart module for {readable_module_name(path)} in `{path.parent.relative_to(ROOT).as_posix()}/`."


def source_summary(path: Path) -> str:
    text = path.read_text(encoding="utf-8", errors="replace")
    suffix = path.suffix.lower()
    relative = path.relative_to(ROOT).as_posix()
    name = path.name
    if suffix == ".dart":
        return dart_summary(path, text)
    if suffix in {".js", ".mjs", ".cjs"}:
        names = unique(TOP_LEVEL_FUNCTIONS.findall(text))
        exports = unique(re.findall(r"(?m)^\s*(?:exports|module\.exports)\.([A-Za-z_$][\w$]*)\s*=", text))
        endpoint_paths = unique(re.findall(r"(?m)^\s*(?:app|router)\.(?:get|post|put|patch|delete)\(['\"]([^'\"]+)", text))
        details = []
        if names:
            details.append(f"defines helpers/handlers {short_list(names, 6)}")
        if exports:
            details.append(f"exports {short_list(exports, 6)}")
        if endpoint_paths:
            details.append(f"routes {short_list(endpoint_paths, 4)}")
        if details:
            return "; ".join(details) + "."
        if re.search(r"\bmodule\.exports\s*=", text):
            return "Default-exported API handler or service module."
        if relative.startswith("server_api/"):
            route = relative.removeprefix("server_api/").removesuffix(suffix).replace("/", " ").replace("-", " ")
            return f"API endpoint handler for {route}."
        return "JavaScript module; see its exports and route registration."
    if suffix == ".py":
        names = unique(re.findall(r"(?m)^(?:async\s+)?(?:def|class)\s+([A-Za-z_]\w*)", text))
        return f"Defines {short_list(names, 6)}." if names else "Python utility module; inspect its entry point."
    if suffix == ".sql":
        if name in SQL_PURPOSES:
            return SQL_PURPOSES[name]
        objects = unique(re.findall(r"(?im)^\s*CREATE\s+(?:TABLE|INDEX|VIEW|TRIGGER)\s+(?:IF\s+NOT\s+EXISTS\s+)?([A-Za-z_][\w]*)", text))
        return f"Schema/migration SQL for {short_list(objects, 8)}." if objects else "SQL schema or migration script."
    if suffix == ".ps1":
        names = unique(re.findall(r"(?im)^\s*function\s+([A-Za-z_]\w*)", text))
        return f"PowerShell workflow; defines {short_list(names, 6)}." if names else "PowerShell script; see its filename for the workflow."
    if suffix in {".yaml", ".yml", ".json", ".toml", ".xml"}:
        return f"Project configuration/data file ({suffix[1:]})."
    return f"Project source/resource file ({suffix or 'no extension'})."


def platform_summary(path: Path) -> str:
    relative = path.relative_to(ROOT).as_posix()
    suffix = path.suffix.lower()
    name = path.name
    if relative in DOCUMENTATION_FILES:
        return DOCUMENTATION_FILES[relative]
    if name == ".gitignore":
        return f"Ignore rules for generated and local `{path.parent.relative_to(ROOT).as_posix()}` files."
    if name == "key.properties.example":
        return "Example Android signing properties; contains placeholders, not signing secrets."
    if name == "proguard-rules.pro":
        return "Android R8/ProGuard keep and obfuscation rules."
    if name == "generated_plugins.cmake":
        return "Generated Flutter plugin registration for the native desktop runner."
    if name == "README.md" and "LaunchImage" in relative:
        return "Apple launch image asset-catalog instructions and required image variants."
    if name.lower().startswith("launchimage") and suffix in {".png", ".jpg", ".jpeg"}:
        return "Apple launch-screen image asset."
    if name == "ic_launcher.png":
        return "Android launcher icon image for the app's adaptive icon resource."
    if relative.startswith("assets/translations/"):
        locale = path.stem
        return f"Localized UI text for the `{locale}` locale."
    if relative.startswith("assets/sounds/"):
        return f"UI audio asset: `{path.stem}` sound."
    if relative.startswith("assets/fonts/"):
        return f"Bundled font face `{path.stem}`."
    if relative.startswith("assets/branding/"):
        return f"Ventio branding image: `{path.stem}`."
    if name == "AndroidManifest.xml":
        variant = "main app" if "/src/main/" in relative else "Android build variant"
        return f"Android manifest for the {variant}: package, permissions, and components."
    if name == "MainActivity.kt":
        return "Android Flutter activity entry point."
    if suffix in {".gradle", ".kts"}:
        return f"Gradle build configuration for `{path.parent.relative_to(ROOT).as_posix()}`."
    if suffix == ".properties":
        return "Gradle/Android build properties for this platform project."
    if suffix in {".swift", ".m", ".mm"} or (suffix == ".h" and relative.startswith(("ios/", "macos/"))):
        if "AppDelegate" in name:
            return "Apple-platform Flutter application bootstrap."
        if "GeneratedPluginRegistrant" in name or "generated_plugin_registrant" in name:
            return "Generated native plugin registration; do not edit by hand."
        return f"Native Apple-platform source or plugin bridge for `{path.parent.relative_to(ROOT).as_posix()}`."
    if suffix == ".plist":
        return "Apple-platform bundle, build, or signing metadata."
    if suffix == ".entitlements":
        return "Apple-platform app capabilities and signing entitlements."
    if suffix == ".pbxproj":
        return "Xcode project targets, build settings, and file membership."
    if suffix == ".xcconfig":
        return "Xcode/Flutter build configuration."
    if suffix == ".xcworkspacedata":
        return "Xcode workspace membership configuration."
    if suffix == ".xcscheme":
        return "Xcode build and launch scheme."
    if suffix == ".xcsettings":
        return "Xcode workspace or project user settings."
    if suffix in {".cc", ".cpp", ".c", ".h"}:
        if "GeneratedPluginRegistrant" in name or "generated_plugin_registrant" in name:
            return "Generated native plugin registration; do not edit by hand."
        if name in {"main.cc", "main.cpp"}:
            return "Native desktop runner entry point."
        return f"Native desktop runner or plugin implementation for `{path.parent.relative_to(ROOT).as_posix()}`."
    if name.lower().startswith("cmakelists"):
        return f"CMake build configuration for `{path.parent.relative_to(ROOT).as_posix()}`."
    if suffix in {".rc", ".manifest", ".ico", ".icns"}:
        return "Native desktop app resource or application manifest."
    if suffix in {".xml", ".storyboard", ".xib"}:
        return "Native platform resource, launch UI, or component configuration."
    if suffix in {".html", ".js"} and relative.startswith("web/"):
        return "Web app bootstrap and browser integration."
    if suffix == ".json" and relative.startswith("web/"):
        return "Installable web app metadata or web resource manifest."
    if suffix in {".png", ".jpg", ".jpeg", ".svg", ".webp"}:
        return "Platform app icon or bundled image resource."
    if suffix == ".exe" and relative.startswith("web/releases/windows/"):
        return "Published Windows installer download bundled with web release files."
    if suffix == ".json":
        return "Platform resource catalog or configuration."
    if suffix == ".sh":
        return "Platform build wrapper script."
    if suffix == ".bat":
        return "Windows platform build wrapper script."
    if suffix == ".txt":
        return "Platform build or resource metadata."
    if suffix in {".yml", ".yaml"} and relative.startswith(".github/workflows/"):
        return f"GitHub Actions workflow for `{path.stem.replace('-', ' ')}`."
    if suffix == ".iss":
        return "Inno Setup recipe for packaging the Windows application installer."
    return f"Platform support file ({suffix or 'no extension'}) for `{path.parent.relative_to(ROOT).as_posix()}`."


def git_project_files() -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
    )
    paths = (ROOT / item.decode("utf-8") for item in result.stdout.split(b"\0") if item)
    # Unstaged renames leave the old path in Git's index until staging.
    # Index the working tree, including new files and excluding removed ones.
    return [path for path in paths if path.is_file()]


def main() -> None:
    project_files = git_project_files()
    files = {
        path
        for path in project_files
        if any(path.relative_to(ROOT).as_posix().startswith(f"{directory}/") for directory in SOURCE_ROOTS)
        or path.relative_to(ROOT).as_posix() in ROOT_SOURCE_FILES
    }

    grouped: dict[str, list[Path]] = {}
    for path in sorted(files):
        folder = path.parent.relative_to(ROOT).as_posix()
        grouped.setdefault(folder, []).append(path)

    lines = [
        "# Source File Index",
        "",
        "This searchable catalog is generated from first-party source declarations and test names.",
        "It covers `lib/`, `test/`, `integration_test/`, `server_api/`, `scripts/`, `tool/`, `database/`, and the root `server.js` entry point.",
        "Platform scaffolding, root build configuration, and bundled assets are cataloged in [PLATFORM_INDEX.md](PLATFORM_INDEX.md).",
        "",
        "Use search to open the matching row; the source file remains authoritative for behavior. Regenerate both catalogs after adding, removing, or renaming indexed files with `python tool/generate_project_file_index.py`.",
        "",
    ]
    for folder, paths in grouped.items():
        lines.extend((f"## `{folder}/`", "", "| File | Contents / responsibility clue |", "| --- | --- |"))
        for path in paths:
            relative = path.relative_to(ROOT).as_posix()
            summary = source_summary(path).replace("|", "\\|")
            lines.append(f"| [`{path.name}`](../{relative}) | {summary} |")
        lines.append("")

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote {OUTPUT.relative_to(ROOT)} ({len(files)} source files).")

    platform_files = {
        path
        for path in project_files
        if any(path.relative_to(ROOT).as_posix().startswith(f"{directory}/") for directory in PLATFORM_ROOTS)
    }
    platform_groups: dict[str, list[Path]] = {}
    for path in sorted(platform_files):
        folder = path.parent.relative_to(ROOT).as_posix()
        platform_groups.setdefault(folder, []).append(path)

    platform_lines = [
        "# Platform, Resource, and Configuration File Index",
        "",
        "This catalog documents checked-in and non-ignored platform scaffolding and bundled resources. Flutter-generated build output, dependency caches, and ignored local files are intentionally excluded.",
        "For Dart application and test files, use [FILE_INDEX.md](FILE_INDEX.md). For directory responsibilities, use [PROJECT_MAP.md](PROJECT_MAP.md).",
        "",
    ]
    documentation_files = [(name, summary) for name, summary in DOCUMENTATION_FILES.items() if (ROOT / name).is_file()]
    if documentation_files:
        platform_lines.extend(("## Documentation map", "", "| File | Responsibility |", "| --- | --- |"))
        for name, summary in documentation_files:
            platform_lines.append(f"| [`{Path(name).name}`](../{name}) | {summary} |")
        platform_lines.append("")
    root_configs = [(name, summary) for name, summary in ROOT_CONFIG_FILES.items() if (ROOT / name).is_file()]
    if root_configs:
        platform_lines.extend(("## Root project configuration", "", "| File | Responsibility |", "| --- | --- |"))
        for name, summary in root_configs:
            platform_lines.append(f"| [`{name}`](../{name}) | {summary} |")
        platform_lines.append("")
    for folder, paths in platform_groups.items():
        platform_lines.extend((f"## `{folder}/`", "", "| File | Responsibility |", "| --- | --- |"))
        for path in paths:
            relative = path.relative_to(ROOT).as_posix()
            platform_lines.append(f"| [`{path.name}`](../{relative}) | {platform_summary(path)} |")
        platform_lines.append("")
    PLATFORM_OUTPUT.write_text("\n".join(platform_lines), encoding="utf-8")
    print(f"Wrote {PLATFORM_OUTPUT.relative_to(ROOT)} ({len(platform_files) + len(root_configs) + len(documentation_files)} entries).")


if __name__ == "__main__":
    main()
