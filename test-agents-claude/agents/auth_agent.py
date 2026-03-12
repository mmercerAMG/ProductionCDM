"""
auth_agent.py - Validates all prerequisites for CDM-Manager operation.

Checks:
  1. Token file exists
  2. Token is non-trivially long
  3. Power BI API is reachable
  4. Dev workspace accessible
  5. Prod workspace accessible
  6. pbi-tools.exe available (repo-local or on PATH)
  7. Live Connection Template report exists in Dev workspace
"""

import os
import shutil

from .config import (
    DEV_WORKSPACE_ID,
    PROD_WORKSPACE_ID,
    REPO_DIR,
    LIVE_TEMPLATE_NAME,
    PBI_TOKEN_PATH,
)
from .pbi_client import PBIClient


def run_auth_agent() -> dict:
    checks = []
    findings = []
    actions = []
    data = {
        "dev_workspace_name": None,
        "prod_workspace_name": None,
        "template_report_id": None,
        "pbi_tools_path": None,
    }

    # ------------------------------------------------------------------
    # Check 1 – Token file exists
    # ------------------------------------------------------------------
    token_exists = os.path.isfile(PBI_TOKEN_PATH)
    checks.append({
        "name": "Token file exists",
        "status": "PASS" if token_exists else "FAIL",
        "detail": PBI_TOKEN_PATH,
    })

    if not token_exists:
        findings.append(f"Token file not found at {PBI_TOKEN_PATH}.")
        actions.append("Open CDM-Manager and sign in.")
        return {
            "agent": "auth",
            "status": "FAIL",
            "checks": checks,
            "findings": findings,
            "actions": actions,
            "data": data,
        }

    # ------------------------------------------------------------------
    # Check 2 – Token is non-empty
    # ------------------------------------------------------------------
    with open(PBI_TOKEN_PATH, "r", encoding="utf-8") as fh:
        token_text = fh.read().strip()

    token_ok = len(token_text) > 20
    checks.append({
        "name": "Token non-empty (length > 20)",
        "status": "PASS" if token_ok else "FAIL",
        "detail": f"Token length: {len(token_text)}",
    })

    if not token_ok:
        findings.append("Token file exists but is too short — likely invalid.")
        actions.append("Open CDM-Manager and sign in.")
        return {
            "agent": "auth",
            "status": "FAIL",
            "checks": checks,
            "findings": findings,
            "actions": actions,
            "data": data,
        }

    # ------------------------------------------------------------------
    # Instantiate PBI client (token exists and is non-empty)
    # ------------------------------------------------------------------
    try:
        client = PBIClient()
    except Exception as exc:
        checks.append({"name": "PBIClient init", "status": "FAIL", "detail": str(exc)})
        findings.append(f"Failed to initialize PBI client: {exc}")
        actions.append("Restart CDM-Manager to re-authenticate.")
        return {
            "agent": "auth",
            "status": "FAIL",
            "checks": checks,
            "findings": findings,
            "actions": actions,
            "data": data,
        }

    # ------------------------------------------------------------------
    # Check 3 – PBI API reachable
    # ------------------------------------------------------------------
    api_ok = client.validate_token()
    checks.append({
        "name": "Power BI API reachable",
        "status": "PASS" if api_ok else "FAIL",
        "detail": "GET / returned 200" if api_ok else "GET / failed",
    })

    if not api_ok:
        findings.append("Power BI API call failed — token may be expired.")
        actions.append("Restart CDM-Manager to re-authenticate.")
        return {
            "agent": "auth",
            "status": "FAIL",
            "checks": checks,
            "findings": findings,
            "actions": actions,
            "data": data,
        }

    # ------------------------------------------------------------------
    # Check 4 – Dev workspace accessible
    # ------------------------------------------------------------------
    try:
        dev_ws = client.get_workspace(DEV_WORKSPACE_ID)
        dev_name = dev_ws.get("name", DEV_WORKSPACE_ID)
        data["dev_workspace_name"] = dev_name
        checks.append({
            "name": "Dev workspace accessible",
            "status": "PASS",
            "detail": f"'{dev_name}' ({DEV_WORKSPACE_ID})",
        })
    except Exception as exc:
        checks.append({
            "name": "Dev workspace accessible",
            "status": "FAIL",
            "detail": str(exc),
        })
        findings.append(f"Cannot access Dev workspace {DEV_WORKSPACE_ID}: {exc}")
        actions.append("Verify DEV_WORKSPACE_ID is correct and the account has access.")

    # ------------------------------------------------------------------
    # Check 5 – Prod workspace accessible
    # ------------------------------------------------------------------
    try:
        prod_ws = client.get_workspace(PROD_WORKSPACE_ID)
        prod_name = prod_ws.get("name", PROD_WORKSPACE_ID)
        data["prod_workspace_name"] = prod_name
        checks.append({
            "name": "Prod workspace accessible",
            "status": "PASS",
            "detail": f"'{prod_name}' ({PROD_WORKSPACE_ID})",
        })
    except Exception as exc:
        checks.append({
            "name": "Prod workspace accessible",
            "status": "FAIL",
            "detail": str(exc),
        })
        findings.append(f"Cannot access Prod workspace {PROD_WORKSPACE_ID}: {exc}")
        actions.append("Verify PROD_WORKSPACE_ID is correct and the account has access.")

    # ------------------------------------------------------------------
    # Check 6 – pbi-tools.exe available
    # ------------------------------------------------------------------
    pbi_tools_local = os.path.join(REPO_DIR, "pbi-tools.exe")
    pbi_tools_path = None

    if os.path.isfile(pbi_tools_local):
        pbi_tools_path = pbi_tools_local
    else:
        pbi_tools_path = shutil.which("pbi-tools")

    data["pbi_tools_path"] = pbi_tools_path
    if pbi_tools_path:
        checks.append({
            "name": "pbi-tools.exe available",
            "status": "PASS",
            "detail": pbi_tools_path,
        })
    else:
        checks.append({
            "name": "pbi-tools.exe available",
            "status": "FAIL",
            "detail": "Not found in repo root or on PATH",
        })
        findings.append("pbi-tools.exe not found. Sync-to-git step will fail.")
        actions.append(
            "Download pbi-tools.exe and place it in the repo root or add it to PATH."
        )

    # ------------------------------------------------------------------
    # Check 7 – Live Connection Template exists in Dev workspace
    # ------------------------------------------------------------------
    try:
        dev_reports = client.get_reports(DEV_WORKSPACE_ID)
        template = next(
            (r for r in dev_reports if LIVE_TEMPLATE_NAME in r.get("name", "")),
            None,
        )
        if template:
            data["template_report_id"] = template.get("id")
            checks.append({
                "name": "Live Connection Template exists in Dev",
                "status": "PASS",
                "detail": f"Found: '{template.get('name')}' (id={template.get('id')})",
            })
        else:
            checks.append({
                "name": "Live Connection Template exists in Dev",
                "status": "FAIL",
                "detail": f"No report containing '{LIVE_TEMPLATE_NAME}' found in Dev workspace",
            })
            findings.append(
                "Live Connection Template report is missing from Dev workspace. "
                "Live Connect deployments will fail."
            )
            actions.append(
                "Upload the Live Connection Template .pbix to the Dev workspace manually."
            )
    except Exception as exc:
        checks.append({
            "name": "Live Connection Template exists in Dev",
            "status": "FAIL",
            "detail": str(exc),
        })
        findings.append(f"Could not list Dev reports to check for template: {exc}")

    # ------------------------------------------------------------------
    # Compute overall status
    # ------------------------------------------------------------------
    statuses = [c["status"] for c in checks]
    if "FAIL" in statuses:
        overall = "FAIL"
    elif "WARN" in statuses:
        overall = "WARN"
    else:
        overall = "PASS"

    if overall == "PASS":
        findings.append("All authentication and prerequisite checks passed.")

    return {
        "agent": "auth",
        "status": overall,
        "checks": checks,
        "findings": findings,
        "actions": actions,
        "data": data,
    }
