"""
cleanup_agent.py - Finds and optionally removes orphan datasets and reports
from the Dev workspace.

Orphan datasets: datasets where no report in the workspace references their ID.
Orphan reports: reports whose datasetId doesn't match any dataset in the workspace
                (and isn't the Production dataset for live-connect reports).
"""

from .config import DEV_WORKSPACE_ID, PROD_DATASET_ID
from .pbi_client import PBIClient


def run_cleanup_agent(auto_delete: bool = False) -> dict:
    checks = []
    findings = []
    actions = []
    data = {
        "orphan_datasets": [],
        "orphan_reports": [],
        "deleted": [],
        "skipped": [],
    }

    # ------------------------------------------------------------------
    # PBI client
    # ------------------------------------------------------------------
    try:
        client = PBIClient()
    except Exception as exc:
        return {
            "agent": "cleanup",
            "status": "FAIL",
            "checks": [{"name": "PBI token", "status": "FAIL", "detail": str(exc)}],
            "findings": [f"PBI token unavailable: {exc}"],
            "actions": ["Authenticate via CDM-Manager before running cleanup."],
            "data": data,
        }

    # ------------------------------------------------------------------
    # Fetch all reports and datasets from Dev workspace
    # ------------------------------------------------------------------
    try:
        all_reports = client.get_reports(DEV_WORKSPACE_ID)
    except Exception as exc:
        return {
            "agent": "cleanup",
            "status": "FAIL",
            "checks": [{"name": "Fetch Dev reports", "status": "FAIL", "detail": str(exc)}],
            "findings": [f"Failed to fetch reports: {exc}"],
            "actions": ["Verify access to Dev workspace."],
            "data": data,
        }

    try:
        all_datasets = client.get_datasets(DEV_WORKSPACE_ID)
    except Exception as exc:
        return {
            "agent": "cleanup",
            "status": "FAIL",
            "checks": [{"name": "Fetch Dev datasets", "status": "FAIL", "detail": str(exc)}],
            "findings": [f"Failed to fetch datasets: {exc}"],
            "actions": ["Verify access to Dev workspace."],
            "data": data,
        }

    checks.append({
        "name": "Fetched Dev workspace inventory",
        "status": "PASS",
        "detail": f"{len(all_reports)} report(s), {len(all_datasets)} dataset(s)",
    })

    # ------------------------------------------------------------------
    # Identify orphans
    # ------------------------------------------------------------------
    report_dataset_ids = {r.get("datasetId") for r in all_reports}
    dataset_ids = {d.get("id") for d in all_datasets}

    orphan_datasets = [
        {"id": d.get("id"), "name": d.get("name")}
        for d in all_datasets
        if d.get("id") not in report_dataset_ids
    ]

    orphan_reports = [
        {"id": r.get("id"), "name": r.get("name"), "datasetId": r.get("datasetId")}
        for r in all_reports
        if r.get("datasetId") not in dataset_ids
        and r.get("datasetId") != PROD_DATASET_ID
    ]

    data["orphan_datasets"] = orphan_datasets
    data["orphan_reports"] = orphan_reports

    findings.append(
        f"Found {len(orphan_datasets)} orphan dataset(s) and "
        f"{len(orphan_reports)} orphan report(s) in Dev workspace."
    )

    if not orphan_datasets and not orphan_reports:
        findings.append("Dev workspace is clean — no orphans to remove.")
        checks.append({
            "name": "Orphan scan",
            "status": "PASS",
            "detail": "No orphans found",
        })
        return {
            "agent": "cleanup",
            "status": "PASS",
            "checks": checks,
            "findings": findings,
            "actions": actions,
            "data": data,
        }

    checks.append({
        "name": "Orphan scan",
        "status": "WARN",
        "detail": (
            f"{len(orphan_datasets)} orphan dataset(s), "
            f"{len(orphan_reports)} orphan report(s)"
        ),
    })

    # ------------------------------------------------------------------
    # Delete or list
    # ------------------------------------------------------------------
    if not auto_delete:
        # List mode
        if orphan_datasets:
            findings.append(
                "Orphan datasets: "
                + ", ".join(f"'{d['name']}' ({d['id']})" for d in orphan_datasets)
            )
        if orphan_reports:
            findings.append(
                "Orphan reports: "
                + ", ".join(f"'{r['name']}' ({r['id']})" for r in orphan_reports)
            )

        for d in orphan_datasets:
            data["skipped"].append({"type": "dataset", "id": d["id"], "name": d["name"]})
        for r in orphan_reports:
            data["skipped"].append({"type": "report", "id": r["id"], "name": r["name"]})

        actions.append(
            "Run cleanup_agent with auto_delete=True to delete the orphans listed above."
        )

        return {
            "agent": "cleanup",
            "status": "WARN",
            "checks": checks,
            "findings": findings,
            "actions": actions,
            "data": data,
        }

    # ------------------------------------------------------------------
    # auto_delete=True: delete each orphan
    # ------------------------------------------------------------------
    delete_errors = []

    for d in orphan_datasets:
        try:
            status_code = client.delete_dataset(DEV_WORKSPACE_ID, d["id"])
            if status_code in (200, 204):
                data["deleted"].append({"type": "dataset", "id": d["id"], "name": d["name"]})
                checks.append({
                    "name": f"Delete dataset '{d['name']}'",
                    "status": "PASS",
                    "detail": f"HTTP {status_code}",
                })
            else:
                data["skipped"].append({"type": "dataset", "id": d["id"], "name": d["name"]})
                checks.append({
                    "name": f"Delete dataset '{d['name']}'",
                    "status": "WARN",
                    "detail": f"Unexpected HTTP {status_code}",
                })
                delete_errors.append(f"Dataset '{d['name']}' returned HTTP {status_code}")
        except Exception as exc:
            data["skipped"].append({"type": "dataset", "id": d["id"], "name": d["name"]})
            checks.append({
                "name": f"Delete dataset '{d['name']}'",
                "status": "FAIL",
                "detail": str(exc),
            })
            delete_errors.append(f"Dataset '{d['name']}': {exc}")

    for r in orphan_reports:
        try:
            status_code = client.delete_report(DEV_WORKSPACE_ID, r["id"])
            if status_code in (200, 204):
                data["deleted"].append({"type": "report", "id": r["id"], "name": r["name"]})
                checks.append({
                    "name": f"Delete report '{r['name']}'",
                    "status": "PASS",
                    "detail": f"HTTP {status_code}",
                })
            else:
                data["skipped"].append({"type": "report", "id": r["id"], "name": r["name"]})
                checks.append({
                    "name": f"Delete report '{r['name']}'",
                    "status": "WARN",
                    "detail": f"Unexpected HTTP {status_code}",
                })
                delete_errors.append(f"Report '{r['name']}' returned HTTP {status_code}")
        except Exception as exc:
            data["skipped"].append({"type": "report", "id": r["id"], "name": r["name"]})
            checks.append({
                "name": f"Delete report '{r['name']}'",
                "status": "FAIL",
                "detail": str(exc),
            })
            delete_errors.append(f"Report '{r['name']}': {exc}")

    deleted_count = len(data["deleted"])
    skipped_count = len(data["skipped"])

    findings.append(
        f"Deleted {deleted_count} item(s). "
        + (f"Skipped {skipped_count} item(s) due to errors." if skipped_count else "")
    )

    if delete_errors:
        actions.append(
            "Some deletions failed. Review errors: " + "; ".join(delete_errors)
        )

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
        "agent": "cleanup",
        "status": overall,
        "checks": checks,
        "findings": findings,
        "actions": actions,
        "data": data,
    }
