#!/usr/bin/env python3
"""Keep AppStore compatibility use and cross-feature imports from growing.

The selector inventory is intentionally source-based: it follows identifiers
declared with the AppStore type (including widget.store and this.store) and
compares their public facade selectors to a checked-in baseline. It is a
regression guard, not a replacement for Dart's type checker.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
BASELINE_PATH = ROOT / "tool" / "architecture_boundary_baseline.json"
APP_STORE_API_FILES = sorted(
    (ROOT / "lib" / "data").glob("app_store_forwarding_api*.dart")
) + [ROOT / "lib" / "data" / "app_store_orchestration.dart"]
CONTROL_WORDS = {
    "assert",
    "catch",
    "do",
    "else",
    "for",
    "if",
    "return",
    "switch",
    "throw",
    "try",
    "while",
}
APP_STORE_CONTEXT_MEMBERS = {
    "activeUser",
    "appIdentity",
    "currentRole",
    "deviceId",
    "hasPermission",
    "inventoryCostingMethod",
    "refreshAfterDatabaseChange",
    "requirePermission",
    "storeProfile",
}


def read_source(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig")


def app_library_parts() -> dict[Path, list[Path]]:
    """Group Dart part files with the library that owns their declarations.

    A selector may be used in a part that does not repeat the AppStore field's
    declaration, so scanning each source file in isolation misses real uses.
    Dart's `part of` URI points back to the library root.
    """
    sources = sorted((ROOT / "lib").rglob("*.dart"))
    source_by_resolved_path = {path.resolve(): path for path in sources}
    owner_by_path = {path: path for path in sources}
    part_of = re.compile(
        r"^\s*part\s+of\s+['\"]([^'\"]+)['\"]\s*;", re.MULTILINE
    )

    for path in sources:
        match = part_of.search(read_source(path))
        if not match:
            continue
        uri = match.group(1)
        if uri.startswith("package:ventio/"):
            candidate = ROOT / "lib" / uri.removeprefix("package:ventio/")
        elif uri.startswith("package:"):
            continue
        else:
            candidate = path.parent / uri
        owner = source_by_resolved_path.get(candidate.resolve())
        if owner is not None:
            owner_by_path[path] = owner

    grouped: dict[Path, list[Path]] = {}
    for path, owner in owner_by_path.items():
        grouped.setdefault(owner, []).append(path)
    return grouped


def public_app_store_members() -> set[str]:
    """Collect public forwarding methods and public extensions on AppStore."""
    members: set[str] = set()
    method_decl = re.compile(
        r"^ {2}[A-Za-z_$][\w$<>?,. ]*?\s+([A-Za-z_$][\w$]*)\s*\("
    )
    getter_decl = re.compile(
        r"^ {2}[^/\n]*?\bget\s+([A-Za-z_$][\w$]*)\s*(?:=>|\{)"
    )
    for path in APP_STORE_API_FILES:
        for line in read_source(path).splitlines():
            for pattern in (method_decl, getter_decl):
                match = pattern.match(line)
                if not match:
                    continue
                name = match.group(1)
                if not name.startswith("_") and name not in CONTROL_WORDS:
                    members.add(name)

    extension_header = re.compile(
        r"^extension\s+(?P<name>[A-Za-z_$][\w$]*)\s+on\s+AppStore\s*\{\s*$"
    )
    data_root = ROOT / "lib" / "data"
    for path in sorted(data_root.glob("app_store*.dart")):
        lines = read_source(path).splitlines()
        for index, line in enumerate(lines):
            header = extension_header.match(line)
            if not header or header.group("name").startswith("_"):
                continue
            for body_line in lines[index + 1 :]:
                if body_line == "}":
                    break
                for pattern in (method_decl, getter_decl):
                    match = pattern.match(body_line)
                    if not match:
                        continue
                    name = match.group(1)
                    if not name.startswith("_") and name not in CONTROL_WORDS:
                        members.add(name)
                    break
    return members


def app_store_mentions() -> Counter[str]:
    counts: Counter[str] = Counter()
    for path in sorted((ROOT / "lib").rglob("*.dart")):
        if path.is_relative_to(ROOT / "lib" / "data"):
            continue
        source = read_source(path)
        count = len(re.findall(r"\bAppStore\b", source))
        if count:
            counts[path.relative_to(ROOT).as_posix()] = count
    return counts


def app_store_selectors(members: set[str]) -> dict[str, Counter[str]]:
    """Count facade selectors on names declared with the AppStore type."""
    result: dict[str, Counter[str]] = {}
    if not members:
        return result

    member_pattern = "|".join(re.escape(member) for member in sorted(members))
    type_decl = re.compile(r"\bAppStore\s*\??\s+([A-Za-z_$][\w$]*)")
    direct_alias = re.compile(
        r"\b(?:final|var|late\s+final)\s+([A-Za-z_$][\w$]*)\s*=\s*"
        r"(?:[A-Za-z_$][\w$]*\s*\.\s*)*([A-Za-z_$][\w$]*)"
        r"\s*(?=[;,)]|$)"
    )

    for library_path, parts in sorted(app_library_parts().items()):
        library_source = "\n".join(read_source(path) for path in parts)
        names = set(type_decl.findall(library_source))
        if not names:
            continue

        # Follow straightforward local aliases such as `final store = widget.store`.
        changed = True
        while changed:
            changed = False
            for alias, source_name in direct_alias.findall(library_source):
                if source_name in names and alias not in names:
                    names.add(alias)
                    changed = True

        name_pattern = "|".join(re.escape(name) for name in sorted(names))
        selector = re.compile(
            rf"\b(?:(?:[A-Za-z_$][\w$]*\s*\.\s*){{0,2}})"
            rf"(?:{name_pattern})\s*\.\s*(?P<member>{member_pattern})\b"
        )
        for path in parts:
            if path.is_relative_to(ROOT / "lib" / "data"):
                continue
            source = read_source(path)
            found = Counter(
                match.group("member") for match in selector.finditer(source)
            )
            if found:
                result[path.relative_to(ROOT).as_posix()] = found
    return result


def domain_adapter_app_store_calls(members: set[str]) -> Counter[str]:
    """Find domain adapters that call back into the public AppStore surface."""
    source = "\n".join(
        read_source(path)
        for path in sorted((ROOT / "lib" / "data").glob("app_store_domains*.dart"))
    )
    if not members:
        return Counter()
    member_pattern = "|".join(re.escape(member) for member in sorted(members))
    selector = re.compile(
        rf"\b_store\s*\.\s*(?P<member>{member_pattern})\b"
    )
    return Counter(match.group("member") for match in selector.finditer(source))


def cross_feature_imports() -> Counter[str]:
    feature_root = ROOT / "lib" / "features"
    counts: Counter[str] = Counter()
    import_decl = re.compile(r"^\s*import\s+['\"]([^'\"]+)['\"]", re.MULTILINE)

    for path in sorted(feature_root.rglob("*.dart")):
        source_area = path.relative_to(feature_root).parts[0]
        source = read_source(path)
        for match in import_decl.finditer(source):
            import_uri = match.group(1)
            if import_uri.startswith("package:ventio/features/"):
                target = import_uri.removeprefix("package:ventio/features/")
                target_parts = Path(target).parts
            elif import_uri.startswith("."):
                resolved = (path.parent / import_uri).resolve()
                try:
                    target_parts = resolved.relative_to(feature_root.resolve()).parts
                except ValueError:
                    continue
            else:
                continue

            if len(target_parts) < 2:
                continue
            target_area = target_parts[0]
            if source_area == target_area:
                continue

            key = "|".join(
                (
                    path.relative_to(ROOT).as_posix(),
                    source_area,
                    target_area,
                    Path(*target_parts).as_posix(),
                )
            )
            counts[key] += 1
    return counts


def nested_selector_json(
    selectors: dict[str, Counter[str]],
) -> dict[str, dict[str, int]]:
    return {
        path: dict(sorted(counts.items()))
        for path, counts in sorted(selectors.items())
    }


def current_inventory() -> dict[str, Any]:
    members = public_app_store_members()
    return {
        "schemaVersion": 1,
        "appStorePublicMemberCount": len(members),
        "appStorePublicMembers": sorted(members),
        "appStoreMentions": dict(sorted(app_store_mentions().items())),
        "appStoreSelectors": nested_selector_json(app_store_selectors(members)),
        "crossFeatureImports": dict(sorted(cross_feature_imports().items())),
    }


def count_total(values: dict[str, Any]) -> int:
    return sum(int(value) for value in values.values())


def validate_against_baseline(current: dict[str, Any], baseline: dict[str, Any]) -> list[str]:
    errors: list[str] = []

    unexpected_members = sorted(
        set(current["appStorePublicMembers"]) - APP_STORE_CONTEXT_MEMBERS
    )
    for member in unexpected_members:
        errors.append(
            f"AppStore public member is outside BusinessSessionContext: {member}"
        )

    new_members = sorted(
        set(current["appStorePublicMembers"])
        - set(baseline.get("appStorePublicMembers", []))
    )
    for member in new_members:
        errors.append(f"AppStore public facade member added: {member}")

    adapter_calls = domain_adapter_app_store_calls(
        set(current["appStorePublicMembers"])
    )
    for member, count in sorted(adapter_calls.items()):
        errors.append(
            f"AppStore domain adapter calls public facade member {member}: {count}"
        )

    def compare_flat(label: str, current_values: dict[str, int], base_values: dict[str, int]) -> None:
        for key, value in current_values.items():
            allowed = int(base_values.get(key, 0))
            if int(value) > allowed:
                errors.append(f"{label}: {key} is {value}, baseline is {allowed}")

    compare_flat(
        "AppStore source mention",
        current["appStoreMentions"],
        baseline.get("appStoreMentions", {}),
    )
    compare_flat(
        "Cross-feature import",
        current["crossFeatureImports"],
        baseline.get("crossFeatureImports", {}),
    )

    current_selectors = current["appStoreSelectors"]
    base_selectors = baseline.get("appStoreSelectors", {})
    for path, members in current_selectors.items():
        for member, value in members.items():
            allowed = int(base_selectors.get(path, {}).get(member, 0))
            if int(value) > allowed:
                errors.append(
                    f"AppStore selector: {path}: .{member} is {value}, baseline is {allowed}"
                )
    return errors


def area_import_edge_count(imports: dict[str, int]) -> int:
    edges = set()
    for key in imports:
        _, source_area, target_area, _ = key.split("|", 3)
        edges.add((source_area, target_area))
    return len(edges)


def print_summary(current: dict[str, Any], baseline: dict[str, Any], errors: list[str]) -> None:
    mentions = current["appStoreMentions"]
    selectors = current["appStoreSelectors"]
    imports = current["crossFeatureImports"]
    selector_total = sum(
        sum(members.values()) for members in selectors.values()
    )
    baseline_selector_total = sum(
        sum(members.values()) for members in baseline.get("appStoreSelectors", {}).values()
    )
    print(
        "AppStore source mentions: "
        f"{count_total(mentions)} across {len(mentions)} files"
    )
    print(
        "AppStore public facade members: "
        f"{current['appStorePublicMemberCount']} "
        f"(baseline {baseline.get('appStorePublicMemberCount', 0)})"
    )
    print(
        "AppStore compatibility selectors: "
        f"{selector_total} across {len(selectors)} files"
        f" (baseline {baseline_selector_total})"
    )
    adapter_call_total = sum(
        domain_adapter_app_store_calls(set(current["appStorePublicMembers"])).values()
    )
    print(f"AppStore domain adapter facade calls: {adapter_call_total}")
    print(
        "Cross-feature imports: "
        f"{count_total(imports)} across {area_import_edge_count(imports)} directed area edges"
    )
    if errors:
        print("Architecture boundary check: FAIL")
        for error in errors:
            print(f"  - {error}")
    else:
        print("Architecture boundary check: PASS")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--refresh-baseline",
        action="store_true",
        help="write current measurements to the reviewed baseline file",
    )
    args = parser.parse_args()

    current = current_inventory()
    if args.refresh_baseline:
        BASELINE_PATH.write_text(
            json.dumps(current, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        print(f"Updated architecture boundary baseline: {BASELINE_PATH.relative_to(ROOT)}")
        return 0

    if not BASELINE_PATH.exists():
        print(f"Missing architecture boundary baseline: {BASELINE_PATH}", file=sys.stderr)
        return 2

    baseline = json.loads(BASELINE_PATH.read_text(encoding="utf-8"))
    errors = validate_against_baseline(current, baseline)
    print_summary(current, baseline, errors)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
