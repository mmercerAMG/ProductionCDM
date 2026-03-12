"""
assistant_agent.py - Answers questions about the CDM-Manager workflow.

Reads WORKFLOW.md, README.md, and instructions.md to provide documentation
context. If the question relates to reports/datasets/workspaces and a PBI
token is available, also fetches the live Dev workspace state.
"""

import os
from .config import REPO_DIR, DEV_WORKSPACE_ID


def _read_file(filepath: str) -> str:
    """Read a file fully; return 'FILE_NOT_FOUND' if missing."""
    if not os.path.isfile(filepath):
        return "FILE_NOT_FOUND"
    with open(filepath, "r", encoding="utf-8", errors="replace") as fh:
        return fh.read()


_PBI_KEYWORDS = {"report", "dataset", "workspace", "deploy", "publish", "pbix", "pbip"}


def _question_needs_live_state(question: str) -> bool:
    """Return True if the question likely requires live PBI data."""
    q_lower = question.lower()
    return any(kw in q_lower for kw in _PBI_KEYWORDS)


def run_assistant_agent(question: str) -> dict:
    checks = []
    findings = []
    actions = []

    data = {
        "question": question,
        "docs": {
            "WORKFLOW.md": None,
            "README.md": None,
            "instructions.md": None,
        },
        "live_state": None,
    }

    # ------------------------------------------------------------------
    # Read documentation files
    # ------------------------------------------------------------------
    doc_files = ["WORKFLOW.md", "README.md", "instructions.md"]

    for filename in doc_files:
        filepath = os.path.join(REPO_DIR, filename)
        try:
            content = _read_file(filepath)
            data["docs"][filename] = content
            if content == "FILE_NOT_FOUND":
                findings.append(f"{filename}: not found at {filepath}")
                checks.append({
                    "name": f"Read {filename}",
                    "status": "WARN",
                    "detail": f"File not found: {filepath}",
                })
            else:
                findings.append(f"{filename}: read OK ({len(content)} chars)")
                checks.append({
                    "name": f"Read {filename}",
                    "status": "PASS",
                    "detail": f"{len(content)} characters",
                })
        except Exception as exc:
            data["docs"][filename] = f"ERROR: {exc}"
            findings.append(f"{filename}: read error — {exc}")
            checks.append({
                "name": f"Read {filename}",
                "status": "FAIL",
                "detail": str(exc),
            })

    # ------------------------------------------------------------------
    # Optionally fetch live PBI state
    # ------------------------------------------------------------------
    if _question_needs_live_state(question):
        try:
            from .pbi_client import PBIClient
            client = PBIClient()
            dev_reports = client.get_reports(DEV_WORKSPACE_ID)
            dev_datasets = client.get_datasets(DEV_WORKSPACE_ID)
            data["live_state"] = {
                "dev_reports": [
                    {"id": r.get("id"), "name": r.get("name"), "datasetId": r.get("datasetId")}
                    for r in dev_reports
                ],
                "dev_datasets": [
                    {"id": d.get("id"), "name": d.get("name")}
                    for d in dev_datasets
                ],
            }
            findings.append(
                f"Live Dev workspace state fetched: "
                f"{len(dev_reports)} report(s), {len(dev_datasets)} dataset(s)."
            )
            checks.append({
                "name": "Live PBI state (Dev)",
                "status": "PASS",
                "detail": f"{len(dev_reports)} reports, {len(dev_datasets)} datasets",
            })
        except Exception as exc:
            # Token not available or API error — skip gracefully
            findings.append(
                f"Live PBI state not available (token missing or API error): {exc}"
            )
            checks.append({
                "name": "Live PBI state (Dev)",
                "status": "WARN",
                "detail": f"Skipped: {exc}",
            })
            data["live_state"] = None
    else:
        findings.append(
            "Question does not appear to require live PBI state — skipping API call."
        )

    findings.append(
        "Documentation context loaded. "
        "Manager will synthesize an answer from the docs and live state."
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
        "agent": "assistant",
        "status": overall,
        "checks": checks,
        "findings": findings,
        "actions": actions,
        "data": data,
    }
