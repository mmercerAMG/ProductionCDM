"""
debug_agent.py - Full workspace inventory scan.

Lists all reports and datasets, identifies orphans, checks Live Connection
Template status, and surfaces live-connected reports.
"""

from .config import (
    DEV_WORKSPACE_ID,
    PROD_WORKSPACE_ID,
    PROD_DATASET_ID,
    LIVE_TEMPLATE_NAME,
)
from .pbi_client import PBIClient


def run_debug_agent(workspace: str = "dev", filter_name: str = None) -> dict:
    checks = []
    findings = []
    actions = []

    workspace = workspace.lower()
    if workspace not in ("dev", "prod"):
        workspace = "dev"

    ws_id = DEV_WORKSPACE_ID if workspace == "dev" else PROD_WORKSPACE_ID
    ws_label = "Dev" if workspace == "dev" else "Prod"

    data = {
        "workspace": workspace,
        "reports": [],
        "datasets": [],
        "orphan_datasets": [],
        "orphan_reports": [],
        "live_connected_reports": [],
        "template_report": None,
    }

    # ------------------------------------------------------------------
    # PBI client
    # ------------------------------------------------------------------
    try:
        client = PBIClient()
    except Exception as exc:
        return {
            "agent": "debug",
            "status": "FAIL",
            "checks": [{"name": "PBI token", "status": "FAIL", "detail": str(exc)}],
            "findings": [f"PBI token unavailable: {exc}"],
            "actions": ["Authenticate via CDM-Manager before running debug scan."],
            "data": data,
        }

    # ------------------------------------------------------------------
    # Fetch reports
    # ------------------------------------------------------------------
    try:
        all_reports = client.get_reports(ws_id)
        checks.append({
            "name": f"Fetch {ws_label} reports",
            "status": "PASS",
            "detail": f"{len(all_reports)} report(s) retrieved",
        })
    except Exception as exc:
        checks.append({
            "name": f"Fetch {ws_label} reports",
            "status": "FAIL",
            "detail": str(exc),
        })
        findings.append(f"Failed to fetch reports from {ws_label} workspace: {exc}")
        return {
            "agent": "debug",
            "status": "FAIL",
            "checks": checks,
            "findings": findings,
            "actions": actions,
            "data": data,
        }

    # ------------------------------------------------------------------
    # Fetch datasets
    # ------------------------------------------------------------------
    try:
        all_datasets = client.get_datasets(ws_id)
        checks.append({
            "name": f"Fetch {ws_label} datasets",
            "status": "PASS",
            "detail": f"{len(all_datasets)} dataset(s) retrieved",
        })
    except Exception as exc:
        checks.append({
            "name": f"Fetch {ws_label} datasets",
            "status": "FAIL",
            "detail": str(exc),
        })
        findings.append(f"Failed to fetch datasets from {ws_label} workspace: {exc}")
        # Continue with empty dataset list
        all_datasets = []

    # ------------------------------------------------------------------
    # Build lookup sets
    # ------------------------------------------------------------------
    report_dataset_ids = {r.get("datasetId") for r in all_reports}
    dataset_ids = {d.get("id") for d in all_datasets}

    # ------------------------------------------------------------------
    # Orphan datasets: datasets where no report references that datasetId
    # ------------------------------------------------------------------
    orphan_datasets = [
        {"id": d.get("id"), "name": d.get("name"), "isRefreshable": d.get("isRefreshable")}
        for d in all_datasets
        if d.get("id") not in report_dataset_ids
    ]

    # ------------------------------------------------------------------
    # Orphan reports: reports whose datasetId doesn't match any known dataset
    # (excludes live-connect reports bound to PROD_DATASET_ID)
    # ------------------------------------------------------------------
    orphan_reports = [
        {"id": r.get("id"), "name": r.get("name"), "datasetId": r.get("datasetId")}
        for r in all_reports
        if r.get("datasetId") not in dataset_ids
        and r.get("datasetId") != PROD_DATASET_ID
    ]

    # ------------------------------------------------------------------
    # Live-connected reports (bound to PROD_DATASET_ID) — dev only
    # ------------------------------------------------------------------
    live_connected = []
    template_report = None
    if workspace == "dev":
        live_connected = [
            {"id": r.get("id"), "name": r.get("name"), "datasetId": r.get("datasetId")}
            for r in all_reports
            if r.get("datasetId") == PROD_DATASET_ID
        ]
        template_report = next(
            (
                {"id": r.get("id"), "name": r.get("name")}
                for r in all_reports
                if LIVE_TEMPLATE_NAME in r.get("name", "")
            ),
            None,
        )

    # ------------------------------------------------------------------
    # Apply optional filter
    # ------------------------------------------------------------------
    filtered_reports = all_reports
    filtered_datasets = all_datasets

    if filter_name:
        fn_lower = filter_name.lower()
        filtered_reports = [r for r in all_reports if fn_lower in r.get("name", "").lower()]
        filtered_datasets = [d for d in all_datasets if fn_lower in d.get("name", "").lower()]
        findings.append(
            f"Filter '{filter_name}' applied: "
            f"{len(filtered_reports)} report(s), {len(filtered_datasets)} dataset(s) matched."
        )

    # ------------------------------------------------------------------
    # Populate data
    # ------------------------------------------------------------------
    data["reports"] = [
        {"id": r.get("id"), "name": r.get("name"), "datasetId": r.get("datasetId")}
        for r in filtered_reports
    ]
    data["datasets"] = [
        {"id": d.get("id"), "name": d.get("name"), "isRefreshable": d.get("isRefreshable")}
        for d in filtered_datasets
    ]
    data["orphan_datasets"] = orphan_datasets
    data["orphan_reports"] = orphan_reports
    data["live_connected_reports"] = live_connected
    data["template_report"] = template_report

    # ------------------------------------------------------------------
    # Findings summary
    # ------------------------------------------------------------------
    findings.append(
        f"{ws_label} workspace: {len(all_reports)} report(s), {len(all_datasets)} dataset(s)."
    )

    if orphan_datasets:
        findings.append(
            f"Found {len(orphan_datasets)} orphan dataset(s) (no reports bound to them): "
            + ", ".join(f"'{d['name']}'" for d in orphan_datasets[:5])
            + ("..." if len(orphan_datasets) > 5 else "")
        )
        actions.append(
            "Run cleanup_agent to review and optionally remove orphan datasets."
        )

    if orphan_reports:
        findings.append(
            f"Found {len(orphan_reports)} orphan report(s) (dataset missing): "
            + ", ".join(f"'{r['name']}'" for r in orphan_reports[:5])
            + ("..." if len(orphan_reports) > 5 else "")
        )
        actions.append(
            "Run cleanup_agent to review and optionally remove orphan reports."
        )

    if workspace == "dev":
        if live_connected:
            findings.append(
                f"{len(live_connected)} live-connected report(s) bound to the Production dataset."
            )
        if template_report:
            findings.append(
                f"Live Connection Template found: '{template_report['name']}' (id={template_report['id']})."
            )
        else:
            findings.append("Live Connection Template NOT found in Dev workspace.")
            actions.append("Upload the Live Connection Template .pbix to the Dev workspace.")

    if not orphan_datasets and not orphan_reports:
        findings.append("No orphans found — workspace is clean.")

    # ------------------------------------------------------------------
    # Checks for orphan status
    # ------------------------------------------------------------------
    if orphan_datasets:
        checks.append({
            "name": "Orphan datasets",
            "status": "WARN",
            "detail": f"{len(orphan_datasets)} orphan dataset(s) found",
        })
    else:
        checks.append({
            "name": "Orphan datasets",
            "status": "PASS",
            "detail": "None found",
        })

    if orphan_reports:
        checks.append({
            "name": "Orphan reports",
            "status": "WARN",
            "detail": f"{len(orphan_reports)} orphan report(s) found",
        })
    else:
        checks.append({
            "name": "Orphan reports",
            "status": "PASS",
            "detail": "None found",
        })

    if workspace == "dev":
        checks.append({
            "name": "Live Connection Template",
            "status": "PASS" if template_report else "FAIL",
            "detail": (
                f"Found: '{template_report['name']}'"
                if template_report
                else f"Template containing '{LIVE_TEMPLATE_NAME}' not found"
            ),
        })

    # ------------------------------------------------------------------
    # Overall status
    # ------------------------------------------------------------------
    statuses = [c["status"] for c in checks]
    if "FAIL" in statuses:
        overall = "FAIL"
    elif "WARN" in statuses:
        overall = "WARN"
    else:
        overall = "PASS"

    return {
        "agent": "debug",
        "status": overall,
        "checks": checks,
        "findings": findings,
        "actions": actions,
        "data": data,
    }
