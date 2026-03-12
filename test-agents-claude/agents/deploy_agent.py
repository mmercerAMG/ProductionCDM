"""
deploy_agent.py - Validates deployment state for a branch in dev or prod.

For dev: confirms the report is present, has pages, page count <= 4.
For prod: confirms the short-name report is present, no duplicates.
"""

from .config import (
    DEV_WORKSPACE_ID,
    PROD_WORKSPACE_ID,
)
from .pbi_client import PBIClient


def run_deploy_agent(branch_name: str, environment: str = "dev") -> dict:
    checks = []
    findings = []
    actions = []
    data = {
        "report_id": None,
        "report_url": None,
        "page_count": None,
        "environment": environment,
        "duplicate_count": None,
    }

    environment = environment.lower()
    if environment not in ("dev", "prod"):
        environment = "dev"

    # ------------------------------------------------------------------
    # PBI client
    # ------------------------------------------------------------------
    try:
        client = PBIClient()
    except Exception as exc:
        return {
            "agent": "deploy",
            "status": "FAIL",
            "checks": [{"name": "PBI token", "status": "FAIL", "detail": str(exc)}],
            "findings": [f"PBI token unavailable: {exc}"],
            "actions": ["Authenticate via CDM-Manager before running deploy checks."],
            "data": data,
        }

    if environment == "dev":
        ws_id = DEV_WORKSPACE_ID
        report_name = branch_name
        ws_label = "Dev"
    else:
        ws_id = PROD_WORKSPACE_ID
        report_name = branch_name.split("/")[-1]
        ws_label = "Prod"

    data["environment"] = environment

    # ------------------------------------------------------------------
    # Fetch all reports in the target workspace
    # ------------------------------------------------------------------
    try:
        reports = client.get_reports(ws_id)
    except Exception as exc:
        return {
            "agent": "deploy",
            "status": "FAIL",
            "checks": [{"name": f"Get {ws_label} reports", "status": "FAIL", "detail": str(exc)}],
            "findings": [f"Could not fetch reports from {ws_label} workspace: {exc}"],
            "actions": [f"Verify access to the {ws_label} workspace."],
            "data": data,
        }

    # ------------------------------------------------------------------
    # Check 1 (prod only) – Duplicate detection
    # ------------------------------------------------------------------
    if environment == "prod":
        matching = [r for r in reports if r.get("name") == report_name]
        dup_count = len(matching)
        data["duplicate_count"] = dup_count
        if dup_count > 1:
            checks.append({
                "name": f"No duplicate reports named '{report_name}' in Prod",
                "status": "FAIL",
                "detail": f"{dup_count} reports with this name found",
            })
            findings.append(
                f"Found {dup_count} reports named '{report_name}' in Prod workspace. "
                "Duplicate reports indicate a failed or double deployment."
            )
            actions.append(
                f"Manually delete the extra report(s) named '{report_name}' in Prod workspace."
            )
        elif dup_count == 0:
            checks.append({
                "name": f"Report '{report_name}' exists in Prod",
                "status": "FAIL",
                "detail": "Report not found in Prod workspace",
            })
            findings.append(
                f"Report '{report_name}' does not exist in Prod workspace. "
                "Prod deployment has not completed."
            )
            actions.append("Run the CDM-Manager prod deploy step for this branch.")
        else:
            checks.append({
                "name": f"No duplicate reports named '{report_name}' in Prod",
                "status": "PASS",
                "detail": f"Exactly 1 report found",
            })

    # ------------------------------------------------------------------
    # Find the target report
    # ------------------------------------------------------------------
    report = next((r for r in reports if r.get("name") == report_name), None)

    if environment == "dev" and report is None:
        checks.append({
            "name": f"Report '{report_name}' exists in Dev",
            "status": "FAIL",
            "detail": "Report not found in Dev workspace",
        })
        findings.append(
            f"Report '{report_name}' not found in Dev workspace. "
            "Dev deployment may not have run yet."
        )
        actions.append("Run the CDM-Manager deploy step for this branch.")

        return {
            "agent": "deploy",
            "status": "FAIL",
            "checks": checks,
            "findings": findings,
            "actions": actions,
            "data": data,
        }

    if environment == "dev":
        checks.append({
            "name": f"Report '{report_name}' exists in Dev",
            "status": "PASS",
            "detail": f"report_id={report.get('id')}",
        })

    if report is None:
        # prod duplicate check already captured status above
        statuses = [c["status"] for c in checks]
        overall = "FAIL" if "FAIL" in statuses else ("WARN" if "WARN" in statuses else "PASS")
        return {
            "agent": "deploy",
            "status": overall,
            "checks": checks,
            "findings": findings,
            "actions": actions,
            "data": data,
        }

    # ------------------------------------------------------------------
    # Populate report data
    # ------------------------------------------------------------------
    data["report_id"] = report.get("id")
    data["report_url"] = (
        f"https://app.powerbi.com/groups/{ws_id}/reports/{report.get('id')}"
    )

    if environment == "prod":
        checks.append({
            "name": f"Report URL ({ws_label})",
            "status": "PASS",
            "detail": data["report_url"],
        })
        findings.append(f"Prod report URL: {data['report_url']}")

    # ------------------------------------------------------------------
    # Check 2 – Report has pages (dev) / URL only (prod already done)
    # ------------------------------------------------------------------
    try:
        pages = client.get_report_pages(ws_id, report.get("id"))
        page_count = len(pages)
        data["page_count"] = page_count

        if environment == "dev":
            if page_count == 0:
                checks.append({
                    "name": "Report has pages (> 0)",
                    "status": "FAIL",
                    "detail": "0 pages returned",
                })
                findings.append("Dev report has 0 pages — it may be empty or broken.")
                actions.append("Re-publish the report to Dev with at least one page.")
            else:
                checks.append({
                    "name": "Report has pages (> 0)",
                    "status": "PASS",
                    "detail": f"{page_count} page(s)",
                })

            # ------------------------------------------------------------------
            # Check 3 – Page count <= 4 (dev only)
            # ------------------------------------------------------------------
            if page_count > 4:
                checks.append({
                    "name": "Page count <= 4",
                    "status": "WARN",
                    "detail": f"{page_count} pages — Dev limit is 4",
                })
                findings.append(
                    f"Report has {page_count} pages. Dev deployments are limited to 4 pages."
                )
                actions.append("Reduce the report to 4 pages or fewer.")
            elif page_count > 0:
                checks.append({
                    "name": "Page count <= 4",
                    "status": "PASS",
                    "detail": f"{page_count} page(s) (within limit)",
                })

            # ------------------------------------------------------------------
            # Check 4 – Report URL (dev)
            # ------------------------------------------------------------------
            checks.append({
                "name": "Report URL (Dev)",
                "status": "PASS",
                "detail": data["report_url"],
            })
            findings.append(f"Dev report URL: {data['report_url']}")

    except Exception as exc:
        checks.append({
            "name": "Report pages",
            "status": "WARN",
            "detail": str(exc),
        })
        findings.append(f"Could not retrieve page count: {exc}")

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
        "agent": "deploy",
        "status": overall,
        "checks": checks,
        "findings": findings,
        "actions": actions,
        "data": data,
    }
