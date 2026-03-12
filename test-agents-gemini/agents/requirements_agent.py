"""
requirements_agent.py - Gathers codebase context for implementing a new
requirement in the CDM-Manager workflow.

Reads key files from REPO_DIR and returns their content (with smart
truncation for large files) so the manager LLM can reason about what to
change or implement.
"""

import os
from .config import REPO_DIR


def _read_file_snippet(
    filepath: str,
    head_lines: int = 0,
    tail_lines: int = 0,
    keywords: list = None,
) -> tuple:
    """
    Read a file and return a (snippet, total_lines) tuple.

    If head_lines/tail_lines are specified, returns first + last N lines
    plus any lines that contain keywords from the requirement.
    If both are 0, returns the full file.
    Returns ("FILE_NOT_FOUND", 0) if the file doesn't exist.
    """
    if not os.path.isfile(filepath):
        return "FILE_NOT_FOUND", 0

    with open(filepath, "r", encoding="utf-8", errors="replace") as fh:
        lines = fh.readlines()

    total_lines = len(lines)

    if head_lines == 0 and tail_lines == 0:
        return "".join(lines), total_lines

    parts = []

    if head_lines > 0:
        parts.append(f"--- first {head_lines} lines ---\n")
        parts.extend(lines[:head_lines])

    if keywords:
        keyword_lines = []
        kw_lower = [k.lower() for k in keywords]
        for i, line in enumerate(lines):
            line_lower = line.lower()
            if any(kw in line_lower for kw in kw_lower):
                keyword_lines.append(f"  [{i+1}] {line}")
        if keyword_lines:
            parts.append(f"\n--- {len(keyword_lines)} line(s) matching keywords ---\n")
            parts.extend(keyword_lines)

    if tail_lines > 0:
        parts.append(f"\n--- last {tail_lines} lines ---\n")
        parts.extend(lines[-tail_lines:])

    return "".join(parts), total_lines


def _extract_keywords(requirement: str) -> list:
    """Extract meaningful keywords from the requirement string."""
    # Strip common stop words and return content words
    stop_words = {
        "a", "an", "the", "in", "on", "at", "to", "for", "of", "and", "or",
        "is", "are", "be", "was", "were", "as", "it", "its", "this", "that",
        "with", "from", "by", "not", "but", "if", "so", "we", "our", "i",
        "should", "would", "could", "will", "need", "want", "make", "add",
        "new", "when", "how", "what", "do", "does", "did"
    }
    words = requirement.lower().split()
    keywords = [w.strip(".,;:!?\"'()[]{}") for w in words if w not in stop_words and len(w) > 2]
    return list(set(keywords))[:20]  # cap at 20 keywords


def run_requirements_agent(requirement: str) -> dict:
    checks = []
    findings = []
    actions = []

    keywords = _extract_keywords(requirement)

    data = {
        "requirement": requirement,
        "files": {},
    }

    # ------------------------------------------------------------------
    # File definitions: (filename, head_lines, tail_lines, full=False)
    # ------------------------------------------------------------------
    file_specs = [
        ("CDM-Manager.ps1",  100, 100, False),
        ("deploy-pbi.ps1",    50,   0, False),
        ("WORKFLOW.md",        0,   0, True),
        ("README.md",          0,   0, True),
    ]

    for filename, head, tail, full in file_specs:
        filepath = os.path.join(REPO_DIR, filename)
        try:
            if full:
                snippet, total = _read_file_snippet(filepath)
            else:
                snippet, total = _read_file_snippet(
                    filepath,
                    head_lines=head,
                    tail_lines=tail,
                    keywords=keywords,
                )

            if snippet == "FILE_NOT_FOUND":
                data["files"][filename] = {
                    "snippet": "FILE_NOT_FOUND",
                    "total_lines": 0,
                }
                findings.append(f"{filename}: NOT FOUND at {filepath}")
                checks.append({
                    "name": f"Read {filename}",
                    "status": "WARN",
                    "detail": f"File not found: {filepath}",
                })
            else:
                data["files"][filename] = {
                    "snippet": snippet,
                    "total_lines": total,
                }
                findings.append(f"{filename}: read OK ({total} total lines)")
                checks.append({
                    "name": f"Read {filename}",
                    "status": "PASS",
                    "detail": f"{total} lines, snippet length={len(snippet)} chars",
                })
        except Exception as exc:
            data["files"][filename] = {
                "snippet": f"ERROR: {exc}",
                "total_lines": 0,
            }
            findings.append(f"{filename}: read ERROR — {exc}")
            checks.append({
                "name": f"Read {filename}",
                "status": "FAIL",
                "detail": str(exc),
            })

    findings.append(
        f"Requirement received: '{requirement}'. "
        f"Keywords extracted: {keywords}. "
        "Codebase context is available in data.files for the manager to analyze."
    )
    actions.append(
        "Review the gathered file snippets and propose specific code changes to "
        "CDM-Manager.ps1 or deploy-pbi.ps1 that implement the requirement."
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
        "agent": "requirements",
        "status": overall,
        "checks": checks,
        "findings": findings,
        "actions": actions,
        "data": data,
    }
