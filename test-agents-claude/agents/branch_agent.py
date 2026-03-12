"""
branch_agent.py - Validates the state of a CDM feature/hotfix branch.

Checks git remote state AND Power BI workspace state to confirm a branch
has been fully deployed to Dev and is in a healthy condition.
"""

from .config import (
    DEV_WORKSPACE_ID,
    PROD_DATASET_ID,
    REPO_DIR,
)
from .pbi_client import PBIClient
from .git_client import GitClient


def run_branch_agent(branch_name: str) -> dict:
    checks = []
    findings = []
    actions = []
    data = {
        "report_id": None,
        "report_url": None,
        "dataset_id": None,
        "deploy_mode": None,
        "page_count": None,
        "orphan_dataset": None,
    }

    git = GitClient(REPO_DIR)

    # ------------------------------------------------------------------
    # Check 1 – Branch exists in azure remote
    # ------------------------------------------------------------------
    try:
        exists = git.branch_exists(branch_name)
        checks.append({
            "name": "Branch exists in azure remote",
            "status": "PASS" if exists else "FAIL",
            "detail": f"branch_name='{branch_name}', found={exists}",
        })
        if not exists:
            findings.append(f"Branch '{branch_name}' not found in azure remote.")
            actions.append(
                f"Push the branch to azure: git push azure {branch_name}"
            )
    except Exception as exc:
        checks.append({
            "name": "Branch exists in azure remote",
            "status": "FAIL",
            "detail": str(exc),
        })
        findings.append(f"Git error checking branch existence: {exc}")
        actions.append("Verify git remote 'azure' is configured and reachable.")

    # ------------------------------------------------------------------
    # Check 2 – Branch has commits
    # ------------------------------------------------------------------
    try:
        commits = git.get_commits(branch_name, n=5)
        has_commits = len(commits) > 0
        checks.append({
            "name": "Branch has commits",
            "status": "PASS" if has_commits else "FAIL",
            "detail": f"{len(commits)} commit(s) found" if has_commits else "No commits found",
        })
        if not has_commits:
            findings.append(f"Branch '{branch_name}' has no commits on the azure remote.")
            actions.append("Commit and push changes to the branch before deploying.")
    except Exception as exc:
        checks.append({
            "name": "Branch has commits",
            "status": "FAIL",
            "detail": str(exc),
        })
        findings.append(f"Could not read commits for '{branch_name}': {exc}")

    # ------------------------------------------------------------------
    # Check 3 – Latest commit contains PBIP files
    # ------------------------------------------------------------------
    try:
        has_pbip = git.has_pbip_files(branch_name)
        checks.append({
            "name": "Latest commit contains PBIP files",
            "status": "PASS" if has_pbip else "WARN",
            "detail": (
                ".Report/ or .SemanticModel/ files present"
                if has_pbip
                else "No PBIP files in latest commit — may be a non-PBI commit"
            ),
        })
        if not has_pbip:
            findings.append(
                "Latest commit on this branch does not contain PBIP files. "
                "This is expected for non-PBI commits but unusual for a deploy branch."
            )
    except Exception as exc:
        checks.append({
            "name": "Latest commit contains PBIP files",
            "status": "WARN",
            "detail": str(exc),
        })
        findings.append(f"Could not inspect PBIP files in latest commit: {exc}")

    # ------------------------------------------------------------------
    # PBI checks — require a live token
    # ------------------------------------------------------------------
    try:
        client = PBIClient()
    except Exception as exc:
        msg = f"PBI token unavailable — skipping PBI checks: {exc}"
        checks.append({"name": "PBI token available", "status": "FAIL", "detail": str(exc)})
        findings.append(msg)
        actions.append("Authenticate via CDM-Manager before running branch checks.")
        statuses = [c["status"] for c in checks]
        overall = "FAIL" if "FAIL" in statuses else ("WARN" if "WARN" in statuses else "PASS")
        return {
            "agent": "branch",
            "status": overall,
            "checks": checks,
            "findings": findings,
            "actions": actions,
            "data": data,
        }

    # ------------------------------------------------------------------
    # Check 4 – Report named exactly branch_name exists in Dev workspace
    # ------------------------------------------------------------------
    report = None
    try:
        dev_reports = client.get_reports(DEV_WORKSPACE_ID)
        report = next((r for r in dev_reports if r.get("name") == branch_name), None)
        if report:
            data["report_id"] = report.get("id")
            data["dataset_id"] = report.get("datasetId")
            data["report_url"] = (
                f"https://app.powerbi.com/groups/{DEV_WORKSPACE_ID}"
                f"/reports/{report.get('id')}"
            )
            checks.append({
                "name": f"Report '{branch_name}' exists in Dev",
                "status": "PASS",
                "detail": f"report_id={report.get('id')}, datasetId={report.get('datasetId')}",
            })
        else:
            checks.append({
                "name": f"Report '{branch_name}' exists in Dev",
                "status": "FAIL",
                "detail": "Report not found in Dev workspace",
            })
            findings.append(
                f"No report named '{branch_name}' found in Dev workspace. "
                "Deployment may not have completed yet."
            )
            actions.append(
                "Run the CDM-Manager deploy step for this branch to create the report."
            )
    except Exception as exc:
        checks.append({
            "name": f"Report '{branch_name}' exists in Dev",
            "status": "FAIL",
            "detail": str(exc),
        })
        findings.append(f"Failed to list Dev reports: {exc}")

    if report is None:
        # Cannot continue PBI checks without the report
        statuses = [c["status"] for c in checks]
        overall = "FAIL" if "FAIL" in statuses else ("WARN" if "WARN" in statuses else "PASS")
        return {
            "agent": "branch",
            "status": overall,
            "checks": checks,
            "findings": findings,
            "actions": actions,
            "data": data,
        }

    # ------------------------------------------------------------------
    # Check 5 – Detect deploy mode and validate dataset binding
    # ------------------------------------------------------------------
    report_dataset_id = report.get("datasetId", "")
    try:
        dev_datasets = client.get_datasets(DEV_WORKSPACE_ID)
        dataset_ids = {d.get("id") for d in dev_datasets}
        dataset_names = {d.get("id"): d.get("name") for d in dev_datasets}

        if report_dataset_id == PROD_DATASET_ID:
            # Live Connect mode
            data["deploy_mode"] = "live_connect"
            checks.append({
                "name": "Deploy mode detected",
                "status": "PASS",
                "detail": "Live Connect — report is bound to Production dataset",
            })
            findings.append("Deploy mode: Live Connect (bound to Production dataset).")

            # Verify no orphan dataset named branch_name exists in Dev
            orphan_ds = next(
                (d for d in dev_datasets if d.get("name") == branch_name),
                None,
            )
            if orphan_ds:
                data["orphan_dataset"] = {"id": orphan_ds.get("id"), "name": orphan_ds.get("name")}
                checks.append({
                    "name": "No orphan dataset in Dev (Live Connect)",
                    "status": "WARN",
                    "detail": (
                        f"Orphan dataset named '{branch_name}' found "
                        f"(id={orphan_ds.get('id')}) — should not exist for Live Connect"
                    ),
                })
                findings.append(
                    f"Orphan dataset '{branch_name}' exists in Dev alongside a Live Connect report. "
                    "This may be a leftover from a previous deployment."
                )
                actions.append(
                    "Run cleanup_agent to remove the orphan dataset."
                )
            else:
                checks.append({
                    "name": "No orphan dataset in Dev (Live Connect)",
                    "status": "PASS",
                    "detail": "No orphan dataset found — Live Connect is clean",
                })

        else:
            # New Semantic Model mode
            data["deploy_mode"] = "new_semantic_model"
            checks.append({
                "name": "Deploy mode detected",
                "status": "PASS",
                "detail": f"New Semantic Model — datasetId={report_dataset_id}",
            })
            findings.append("Deploy mode: New Semantic Model (has own dataset in Dev).")

            # Verify that the dataset exists in Dev
            if report_dataset_id in dataset_ids:
                ds_name = dataset_names.get(report_dataset_id, report_dataset_id)
                checks.append({
                    "name": "Dataset exists in Dev (New Semantic Model)",
                    "status": "PASS",
                    "detail": f"Dataset '{ds_name}' ({report_dataset_id}) found in Dev",
                })
            else:
                checks.append({
                    "name": "Dataset exists in Dev (New Semantic Model)",
                    "status": "FAIL",
                    "detail": f"datasetId={report_dataset_id} not found in Dev datasets list",
                })
                findings.append(
                    f"Report's dataset ({report_dataset_id}) is missing from Dev workspace. "
                    "The report may be broken."
                )
                actions.append(
                    "Re-deploy the branch to recreate the dataset or investigate the missing dataset."
                )

    except Exception as exc:
        checks.append({
            "name": "Deploy mode / dataset binding",
            "status": "FAIL",
            "detail": str(exc),
        })
        findings.append(f"Failed to inspect datasets for deploy mode detection: {exc}")

    # ------------------------------------------------------------------
    # Check 6 – Page count (warn if > 4)
    # ------------------------------------------------------------------
    try:
        pages = client.get_report_pages(DEV_WORKSPACE_ID, report.get("id"))
        page_count = len(pages)
        data["page_count"] = page_count
        if page_count == 0:
            checks.append({
                "name": "Report page count",
                "status": "WARN",
                "detail": "0 pages returned — may indicate an API error or empty report",
            })
            findings.append("Report returned 0 pages. Verify the report is published correctly.")
        elif page_count > 4:
            checks.append({
                "name": "Report page count",
                "status": "WARN",
                "detail": f"{page_count} pages — Dev deployments are limited to 4 pages max",
            })
            findings.append(
                f"Report has {page_count} pages. Dev deployments are limited to 4 pages. "
                "This may cause issues."
            )
            actions.append("Reduce the report to 4 pages or fewer before deploying to Dev.")
        else:
            checks.append({
                "name": "Report page count",
                "status": "PASS",
                "detail": f"{page_count} page(s)",
            })
    except Exception as exc:
        checks.append({
            "name": "Report page count",
            "status": "WARN",
            "detail": str(exc),
        })
        findings.append(f"Could not retrieve page count: {exc}")

    # ------------------------------------------------------------------
    # Check 7 – Report URL
    # ------------------------------------------------------------------
    if data.get("report_url"):
        checks.append({
            "name": "Report URL",
            "status": "PASS",
            "detail": data["report_url"],
        })
        findings.append(f"Report URL: {data['report_url']}")

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
        "agent": "branch",
        "status": overall,
        "checks": checks,
        "findings": findings,
        "actions": actions,
        "data": data,
    }
