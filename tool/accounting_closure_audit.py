#!/usr/bin/env python3
"""Read-only Ventio accounting closure audit.

This script never mutates the database. It validates the closure invariants that
can be checked directly from a Ventio SQLite file without launching Flutter.

Usage:
  python tool/accounting_closure_audit.py /path/to/ventio.sqlite
  python tool/accounting_closure_audit.py /path/to/ventio.sqlite --json report.json --markdown report.md
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

TOLERANCE = 0.005


@dataclass
class AuditIssue:
    code: str
    severity: str
    message: str
    entity_type: str = ""
    entity_id: str = ""
    difference: float = 0.0


@dataclass
class AuditMetric:
    name: str
    value: float
    counterpart: float | None = None
    difference: float | None = None


def _number(value: Any) -> float:
    try:
        return float(value or 0.0)
    except (TypeError, ValueError):
        return 0.0


def _round(value: float) -> float:
    return round(value + 0.0, 2)


def _table_exists(conn: sqlite3.Connection, name: str) -> bool:
    row = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1", (name,)
    ).fetchone()
    return row is not None


def _setting_account(conn: sqlite3.Connection, role_key: str, legacy_key: str, default_id: str) -> str:
    for key in (f"role_{role_key}_account_id", legacy_key):
        if not key:
            continue
        row = conn.execute(
            "SELECT account_id FROM accounting_settings WHERE key=? LIMIT 1", (key,)
        ).fetchone()
        if row and str(row[0] or "").strip():
            return str(row[0]).strip()
    return default_id


def _journal_balance_checks(conn: sqlite3.Connection, issues: list[AuditIssue], metrics: list[AuditMetric]) -> None:
    totals = conn.execute(
        """
        SELECT COALESCE(SUM(jl.debit), 0), COALESCE(SUM(jl.credit), 0)
        FROM journal_lines jl
        JOIN journal_entries je ON je.id = jl.entry_id
        WHERE je.deleted_at = '' AND je.status IN ('posted', 'reversed')
        """
    ).fetchone()
    debit, credit = _number(totals[0]), _number(totals[1])
    diff = _round(debit - credit)
    metrics.append(AuditMetric("journal_totals", _round(debit), _round(credit), diff))
    if abs(diff) > TOLERANCE:
        issues.append(AuditIssue(
            "trial_balance_mismatch", "critical",
            f"Posted/reversed journal totals do not balance: debit={debit}, credit={credit}.",
            "journal", "", diff,
        ))

    rows = conn.execute(
        """
        SELECT je.id, je.entry_no,
               COALESCE(SUM(jl.debit), 0) AS debits,
               COALESCE(SUM(jl.credit), 0) AS credits,
               COUNT(jl.id) AS line_count
        FROM journal_entries je
        LEFT JOIN journal_lines jl ON jl.entry_id = je.id
        WHERE je.deleted_at = '' AND je.status IN ('posted', 'reversed')
        GROUP BY je.id, je.entry_no
        HAVING COUNT(jl.id) = 0
            OR ABS(COALESCE(SUM(jl.debit), 0) - COALESCE(SUM(jl.credit), 0)) > ?
            OR COALESCE(SUM(jl.debit), 0) <= 0
        """, (TOLERANCE,)
    ).fetchall()
    for row in rows:
        issues.append(AuditIssue(
            "unbalanced_or_empty_journal", "critical",
            f"Journal {row['entry_no'] or row['id']} is empty or unbalanced.",
            "journal_entry", str(row["id"]), _round(_number(row["debits"]) - _number(row["credits"])),
        ))

    for row in conn.execute(
        """
        SELECT jl.id, jl.entry_id
        FROM journal_lines jl
        LEFT JOIN journal_entries je ON je.id = jl.entry_id
        WHERE je.id IS NULL
        """
    ):
        issues.append(AuditIssue(
            "orphan_journal_line", "critical",
            f"Journal line {row['id']} references missing entry {row['entry_id']}.",
            "journal_line", str(row["id"]),
        ))

    for row in conn.execute(
        """
        SELECT DISTINCT jl.account_id
        FROM journal_lines jl
        LEFT JOIN accounts a ON a.id = jl.account_id
        WHERE a.id IS NULL
        """
    ):
        issues.append(AuditIssue(
            "journal_account_missing", "critical",
            "A journal line references an account that does not exist.",
            "account", str(row["account_id"]),
        ))


def _cash_checks(conn: sqlite3.Connection, issues: list[AuditIssue], metrics: list[AuditMetric]) -> None:
    row = conn.execute(
        """
        WITH active_locations AS (
          SELECT id, account_id, current_balance
          FROM cash_locations
          WHERE deleted_at = '' AND is_active = 1 AND trim(account_id) <> ''
        ), location_balance AS (
          SELECT account_id, SUM(current_balance) AS balance
          FROM active_locations
          GROUP BY account_id
        ), gl_balance AS (
          SELECT jl.account_id, SUM(jl.debit - jl.credit) AS balance
          FROM journal_lines jl
          JOIN journal_entries je ON je.id = jl.entry_id
          WHERE je.deleted_at = '' AND je.status IN ('posted', 'reversed')
          GROUP BY jl.account_id
        )
        SELECT COALESCE(SUM(l.balance), 0) AS location_balance,
               COALESCE(SUM(COALESCE(g.balance, 0)), 0) AS gl_balance
        FROM location_balance l
        LEFT JOIN gl_balance g ON g.account_id = l.account_id
        """
    ).fetchone()
    location_balance = _number(row["location_balance"])
    gl_balance = _number(row["gl_balance"])
    diff = _round(location_balance - gl_balance)
    metrics.append(AuditMetric("cash_locations_vs_gl", _round(location_balance), _round(gl_balance), diff))

    for row in conn.execute(
        """
        WITH location_balance AS (
          SELECT account_id, SUM(current_balance) AS balance
          FROM cash_locations
          WHERE deleted_at = '' AND is_active = 1 AND trim(account_id) <> ''
          GROUP BY account_id
        ), gl_balance AS (
          SELECT jl.account_id, SUM(jl.debit - jl.credit) AS balance
          FROM journal_lines jl
          JOIN journal_entries je ON je.id = jl.entry_id
          WHERE je.deleted_at = '' AND je.status IN ('posted', 'reversed')
          GROUP BY jl.account_id
        )
        SELECT l.account_id, l.balance AS location_balance, COALESCE(g.balance, 0) AS gl_balance
        FROM location_balance l
        LEFT JOIN gl_balance g ON g.account_id = l.account_id
        WHERE ABS(l.balance - COALESCE(g.balance, 0)) > ?
        """, (TOLERANCE,)
    ):
        loc, gl = _number(row["location_balance"]), _number(row["gl_balance"])
        issues.append(AuditIssue(
            "cash_location_gl_mismatch", "critical",
            f"Cash-location balance ({loc}) does not reconcile to GL cash balance ({gl}).",
            "cash_account", str(row["account_id"]), _round(loc - gl),
        ))

    ledger = conn.execute(
        """
        SELECT COALESCE(SUM(CASE WHEN direction='in' THEN amount ELSE -amount END), 0) AS net,
               COALESCE(SUM(CASE WHEN direction='in' THEN amount ELSE 0 END), 0) AS cash_in,
               COALESCE(SUM(CASE WHEN direction='out' THEN amount ELSE 0 END), 0) AS cash_out,
               COUNT(*) AS movement_count
        FROM cash_ledger_transactions
        WHERE deleted_at = ''
        """
    ).fetchone()
    metrics.append(AuditMetric("cash_ledger_net", _round(_number(ledger["net"]))))
    metrics.append(AuditMetric("cash_ledger_in", _round(_number(ledger["cash_in"]))))
    metrics.append(AuditMetric("cash_ledger_out", _round(_number(ledger["cash_out"]))))
    metrics.append(AuditMetric("cash_ledger_movement_count", float(ledger["movement_count"] or 0)))


def _party_control_check(
    conn: sqlite3.Connection,
    issues: list[AuditIssue],
    metrics: list[AuditMetric],
    *,
    party_type: str,
    role_key: str,
    legacy_key: str,
    default_account_id: str,
    expected_expr: str,
    ledger_expr: str,
) -> None:
    account_id = _setting_account(conn, role_key, legacy_key, default_account_id)
    exists = conn.execute(
        "SELECT 1 FROM accounts WHERE id=? AND deleted_at='' LIMIT 1", (account_id,)
    ).fetchone()
    if not exists:
        issues.append(AuditIssue(
            "party_control_role_invalid", "critical",
            f"Control-account role {role_key} resolves to missing account {account_id}.",
            "account_role", role_key,
        ))
        return

    expected_row = conn.execute(
        f"""
        SELECT COALESCE(SUM({expected_expr}), 0) AS balance
        FROM account_transactions
        WHERE deleted_at = '' AND lower(trim(account_type)) = ?
        """, (party_type,)
    ).fetchone()
    ledger_row = conn.execute(
        f"""
        SELECT COALESCE(SUM({ledger_expr}), 0) AS balance
        FROM journal_lines jl
        JOIN journal_entries je ON je.id = jl.entry_id
        WHERE je.deleted_at = '' AND je.status IN ('posted', 'reversed')
          AND jl.account_id = ? AND jl.party_type = ?
        """, (account_id, party_type)
    ).fetchone()
    expected, ledger = _number(expected_row["balance"]), _number(ledger_row["balance"])
    diff = _round(expected - ledger)
    metrics.append(AuditMetric(f"{party_type}_subledger_vs_control", _round(expected), _round(ledger), diff))

    rows = conn.execute(
        f"""
        WITH parties AS (
          SELECT account_id AS party_id
          FROM account_transactions
          WHERE deleted_at = '' AND lower(trim(account_type)) = ? AND trim(account_id) <> ''
          UNION
          SELECT jl.party_id
          FROM journal_lines jl
          JOIN journal_entries je ON je.id = jl.entry_id
          WHERE je.deleted_at = '' AND je.status IN ('posted', 'reversed')
            AND jl.account_id = ? AND jl.party_type = ? AND trim(jl.party_id) <> ''
        ), expected AS (
          SELECT account_id AS party_id, SUM({expected_expr}) AS balance
          FROM account_transactions
          WHERE deleted_at = '' AND lower(trim(account_type)) = ? AND trim(account_id) <> ''
          GROUP BY account_id
        ), ledger AS (
          SELECT jl.party_id, SUM({ledger_expr}) AS balance
          FROM journal_lines jl
          JOIN journal_entries je ON je.id = jl.entry_id
          WHERE je.deleted_at = '' AND je.status IN ('posted', 'reversed')
            AND jl.account_id = ? AND jl.party_type = ? AND trim(jl.party_id) <> ''
          GROUP BY jl.party_id
        )
        SELECT parties.party_id,
               COALESCE(expected.balance, 0) AS expected_balance,
               COALESCE(ledger.balance, 0) AS ledger_balance
        FROM parties
        LEFT JOIN expected ON expected.party_id = parties.party_id
        LEFT JOIN ledger ON ledger.party_id = parties.party_id
        WHERE ABS(COALESCE(expected.balance, 0) - COALESCE(ledger.balance, 0)) > ?
        """,
        (party_type, account_id, party_type, party_type, account_id, party_type, TOLERANCE),
    ).fetchall()
    for row in rows:
        exp, gl = _number(row["expected_balance"]), _number(row["ledger_balance"])
        issues.append(AuditIssue(
            f"{party_type}_control_balance_mismatch", "critical",
            f"{party_type} subledger balance ({exp}) does not reconcile to control-account ledger ({gl}).",
            party_type, str(row["party_id"]), _round(exp - gl),
        ))


def audit_database(path: Path) -> dict[str, Any]:
    required_tables = (
        "accounts", "accounting_settings", "journal_entries", "journal_lines",
        "cash_locations", "cash_ledger_transactions", "account_transactions",
    )
    uri = f"{path.resolve().as_uri()}?mode=ro"
    conn = sqlite3.connect(uri, uri=True)
    conn.row_factory = sqlite3.Row
    issues: list[AuditIssue] = []
    metrics: list[AuditMetric] = []
    try:
        missing = [name for name in required_tables if not _table_exists(conn, name)]
        if missing:
            for name in missing:
                issues.append(AuditIssue(
                    "required_table_missing", "critical",
                    f"Required accounting closure table is missing: {name}.",
                    "table", name,
                ))
        else:
            _journal_balance_checks(conn, issues, metrics)
            _cash_checks(conn, issues, metrics)
            _party_control_check(
                conn, issues, metrics,
                party_type="customer", role_key="accounts_receivable",
                legacy_key="default_customers_account_id", default_account_id="acc_customers",
                expected_expr="debit - credit", ledger_expr="jl.debit - jl.credit",
            )
            _party_control_check(
                conn, issues, metrics,
                party_type="supplier", role_key="accounts_payable",
                legacy_key="default_suppliers_account_id", default_account_id="acc_suppliers",
                expected_expr="credit - debit", ledger_expr="jl.credit - jl.debit",
            )
    finally:
        conn.close()

    critical = sum(1 for issue in issues if issue.severity == "critical")
    warning = sum(1 for issue in issues if issue.severity == "warning")
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "database": str(path),
        "production_ready": critical == 0,
        "critical_count": critical,
        "warning_count": warning,
        "metrics": [asdict(metric) for metric in metrics],
        "issues": [asdict(issue) for issue in issues],
    }


def markdown_report(report: dict[str, Any]) -> str:
    lines = [
        "# Ventio Accounting Closure Audit",
        "",
        f"- Generated: `{report['generated_at']}`",
        f"- Database: `{report['database']}`",
        f"- Production ready: **{'YES' if report['production_ready'] else 'NO'}**",
        f"- Critical issues: **{report['critical_count']}**",
        f"- Warnings: **{report['warning_count']}**",
        "",
        "## Reconciliation metrics",
        "",
        "| Metric | Value | Counterpart | Difference |",
        "|---|---:|---:|---:|",
    ]
    for metric in report["metrics"]:
        counterpart = "" if metric["counterpart"] is None else f"{metric['counterpart']:.2f}"
        difference = "" if metric["difference"] is None else f"{metric['difference']:.2f}"
        lines.append(f"| {metric['name']} | {metric['value']:.2f} | {counterpart} | {difference} |")
    lines += ["", "## Issues", ""]
    if not report["issues"]:
        lines.append("No closure issues detected by this read-only audit.")
    else:
        lines += ["| Severity | Code | Entity | Difference | Message |", "|---|---|---|---:|---|"]
        for issue in report["issues"]:
            entity = f"{issue['entity_type']}:{issue['entity_id']}".strip(":")
            lines.append(
                f"| {issue['severity']} | {issue['code']} | {entity} | {issue['difference']:.2f} | {issue['message']} |"
            )
    lines += [
        "",
        "## Scope note",
        "",
        "This utility is read-only. It validates journal balance, cash-location vs GL reconciliation, "
        "and customer/supplier subledger vs control-account reconciliation. The application-level "
        "AccountingProductionIntegrityService remains authoritative for the broader production gate "
        "(documents, vouchers, manufacturing, inventory counts, reversals, FIFO, and inventory valuation).",
        "",
    ]
    return "\n".join(lines)


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Read-only Ventio accounting closure audit")
    parser.add_argument("database", type=Path)
    parser.add_argument("--json", dest="json_path", type=Path)
    parser.add_argument("--markdown", dest="markdown_path", type=Path)
    args = parser.parse_args(list(argv) if argv is not None else None)

    if not args.database.is_file():
        parser.error(f"database not found: {args.database}")

    try:
        report = audit_database(args.database)
    except sqlite3.Error as exc:
        print(f"SQLite audit failed: {exc}", file=sys.stderr)
        return 2

    text = markdown_report(report)
    print(text)
    if args.json_path:
        args.json_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    if args.markdown_path:
        args.markdown_path.write_text(text, encoding="utf-8")
    return 0 if report["production_ready"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
