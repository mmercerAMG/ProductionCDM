"""
manager_agent.py (Claude version) - CDM-Manager Workflow Assistant.

The agent works EXCLUSIVELY through CDM-Manager. It does not run scripts,
git commands, or API calls on your behalf. Instead it:
  1. Guides you step-by-step through what to do in CDM-Manager
  2. Reads the CDM-Manager console log to see what happened
  3. Validates results via Power BI REST API agents
  4. Answers questions and plans new requirements

Run:
    python manager_agent.py
"""

import json
import os
import sys

from dotenv import load_dotenv
import anthropic

sys.path.insert(0, os.path.dirname(__file__))
load_dotenv()

from agents.auth_agent         import run_auth_agent
from agents.branch_agent       import run_branch_agent
from agents.deploy_agent       import run_deploy_agent
from agents.debug_agent        import run_debug_agent
from agents.cleanup_agent      import run_cleanup_agent
from agents.requirements_agent import run_requirements_agent
from agents.assistant_agent    import run_assistant_agent

# ── Config ─────────────────────────────────────────────────────────────────────
CLAUDE_MODEL = os.getenv("CLAUDE_MODEL", "claude-sonnet-4-6")
client = anthropic.Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))

# ── Output helpers ─────────────────────────────────────────────────────────────
SEP  = "─" * 60
SSEP = "  " + "·" * 40

def _hdr(title):
    print(f"\n┌{SEP}┐")
    print(f"│  {title}")
    print(f"└{SEP}┘")

def _tool_start(name, description=""):
    print(f"\n  ▶ {name}")
    if description:
        print(f"    {description}")

def _tool_result(result: dict):
    status  = result.get("status", "?")
    checks  = result.get("checks", [])
    findings = result.get("findings", [])

    print(f"  {SSEP}")
    for c in checks:
        s   = c.get("status", "?")
        sym = "✓" if s == "PASS" else ("✗" if s == "FAIL" else "!")
        detail = f"  ({c['detail']})" if c.get("detail") else ""
        print(f"    [{sym}] {c.get('name','')}{detail}")

    for f in findings:
        if f and f != "(no output)":
            print(f"    → {f}")

    sym = "✓" if status == "PASS" else ("✗" if status == "FAIL" else "!")
    print(f"  {SSEP}")
    print(f"    Result: {sym} {status}")


# ── System prompt ──────────────────────────────────────────────────────────────
SYSTEM_PROMPT = """\
You are the CDM-Manager Workflow Assistant. You work exclusively through \
CDM-Manager — you never run scripts, git commands, or API calls directly.

## Your role:
1. GUIDE — tell the user exactly what to do in CDM-Manager, one step at a time
2. OBSERVE — after each step, read the CDM-Manager console log to see what happened
3. VALIDATE — use your API agents to confirm the result is correct
4. ANSWER — answer questions and plan new requirements using docs and live PBI state

## Rules:
- Every action must be performed by the user in CDM-Manager
- After any CDM-Manager action, always call read_cdm_log to see the output
- Then call the appropriate validation agent (auth/branch/deploy/debug/cleanup)
- If something failed, read the log carefully and tell the user exactly what went wrong
  and what to try next in CDM-Manager
- Never ask the user to run scripts, PowerShell, or git commands manually
- End every instruction step with: "Let me know when that's done."

## CDM-Manager actions you can guide:
- Launch CDM-Manager (double-click Launch-CDM-Manager.bat)
- Authenticate (browser device code login — code auto-copies to clipboard)
- Select Workspace and Semantic Model (CDM Selection dropdowns)
- Download CDM (saves PBIX locally, unlocks Top Branch)
- Create & Deploy New Branch (choose top branch, type, mode, name)
- Deploy to DEV (redeploy after changes)
- Sync Branch from Dev Report (pulls browser edits back to git)
- Update Main Branch (extracts PBIX to PBIP and commits to Main)
- Deploy to PROD (Main branch only, requires confirmation)
- Manual Cloud Backup (archives PBIX to Azure Blob)
- Open Last Deployed Report (opens in browser)

## CDM-Manager console log:
- Every log line from CDM-Manager is mirrored to %TEMP%\\cdm-manager-log.txt
- Call read_cdm_log after each user action to see exactly what happened
- Look for errors, REPORT_URL lines, and success/failure messages

## Step format:
Always number your steps. Example:
  Step 1 (You do this): Open CDM-Manager by double-clicking Launch-CDM-Manager.bat
  Step 2 (I'll check): [calls read_cdm_log and run_auth_agent automatically]
  Step 3 (You do this): In the CDM Selection section, choose workspace "3011 - AMG - Production"
  ...

## Validation agents available:
- run_auth_agent: token valid, workspaces accessible, pbi-tools present, template exists
- run_branch_agent(branch_name): git branch + PBI report + dataset binding
- run_deploy_agent(branch_name, environment): report in workspace, page count
- run_debug_agent(workspace, filter_name): full workspace scan, orphans
- run_cleanup_agent(auto_delete): find/remove orphan resources
- run_requirements_agent(requirement): read codebase to plan a new feature
- run_assistant_agent(question): answer questions using workflow docs + live state
- read_cdm_log(tail): read CDM-Manager console output
"""

# ── Tool definitions ───────────────────────────────────────────────────────────
tools = [
    {
        "name": "run_auth_agent",
        "description": "Validates PBI token, workspace access, pbi-tools, and Live Connection Template. Call after user authenticates in CDM-Manager.",
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
    {
        "name": "run_branch_agent",
        "description": "Validates branch state: git remote, PBI report existence, deploy mode, dataset binding. Call after user creates a branch in CDM-Manager.",
        "input_schema": {
            "type": "object",
            "properties": {
                "branch_name": {"type": "string", "description": "Full branch name e.g. feature/Production-Main/MM-TEST12"}
            },
            "required": ["branch_name"],
        },
    },
    {
        "name": "run_deploy_agent",
        "description": "Validates deployment: report in workspace, page count, duplicates. Call after user deploys in CDM-Manager.",
        "input_schema": {
            "type": "object",
            "properties": {
                "branch_name": {"type": "string"},
                "environment": {"type": "string", "enum": ["dev", "prod"], "description": "Default: dev"},
            },
            "required": ["branch_name"],
        },
    },
    {
        "name": "run_debug_agent",
        "description": "Full workspace scan: all reports, datasets, orphans, Live Connect Template status.",
        "input_schema": {
            "type": "object",
            "properties": {
                "workspace": {"type": "string", "enum": ["dev", "prod"], "description": "Default: dev"},
                "filter_name": {"type": "string", "description": "Optional name filter"},
            },
            "required": [],
        },
    },
    {
        "name": "run_cleanup_agent",
        "description": "Find and optionally delete orphan datasets/reports in Dev workspace.",
        "input_schema": {
            "type": "object",
            "properties": {
                "auto_delete": {"type": "boolean", "description": "If true, deletes orphans. Default: false"}
            },
            "required": [],
        },
    },
    {
        "name": "run_requirements_agent",
        "description": "Read codebase context to plan implementing a new requirement.",
        "input_schema": {
            "type": "object",
            "properties": {
                "requirement": {"type": "string", "description": "New requirement in plain English"}
            },
            "required": ["requirement"],
        },
    },
    {
        "name": "run_assistant_agent",
        "description": "Answer workflow questions using WORKFLOW.md, README.md, instructions.md and live PBI state.",
        "input_schema": {
            "type": "object",
            "properties": {"question": {"type": "string"}},
            "required": ["question"],
        },
    },
    {
        "name": "read_cdm_log",
        "description": "Read the CDM-Manager console log. Call this after EVERY action the user performs in CDM-Manager to see what happened.",
        "input_schema": {
            "type": "object",
            "properties": {
                "tail": {"type": "integer", "description": "Number of recent lines to return. Default: 50"}
            },
            "required": [],
        },
    },
]


# ── CDM log reader ─────────────────────────────────────────────────────────────

def _read_cdm_log(tail: int = 50) -> dict:
    log_file = os.path.join(
        os.environ.get("TEMP", os.environ.get("TMP", "/tmp")),
        "cdm-manager-log.txt"
    )
    if not os.path.exists(log_file):
        return {
            "agent": "read_cdm_log",
            "status": "WARN",
            "checks": [],
            "findings": ["Log file not found. CDM-Manager may not be open yet."],
            "actions": ["Launch CDM-Manager (Launch-CDM-Manager.bat) and complete authentication."],
            "data": {"lines": []},
        }

    with open(log_file, encoding="utf-8", errors="replace") as f:
        all_lines = [l.rstrip() for l in f.readlines() if l.strip()]

    recent = all_lines[-tail:] if len(all_lines) > tail else all_lines
    print(f"    ({len(recent)} of {len(all_lines)} log lines)")
    for line in recent:
        print(f"        {line}")

    return {
        "agent": "read_cdm_log",
        "status": "PASS",
        "checks": [],
        "findings": recent,
        "actions": [],
        "data": {"log_file": log_file, "total_lines": len(all_lines), "lines": recent},
    }


# ── Dispatcher ─────────────────────────────────────────────────────────────────

def dispatch_agent(tool_name: str, tool_input: dict) -> dict:
    try:
        if tool_name == "run_auth_agent":
            return run_auth_agent()
        elif tool_name == "run_branch_agent":
            return run_branch_agent(branch_name=tool_input.get("branch_name", ""))
        elif tool_name == "run_deploy_agent":
            return run_deploy_agent(
                branch_name=tool_input.get("branch_name", ""),
                environment=tool_input.get("environment", "dev"),
            )
        elif tool_name == "run_debug_agent":
            return run_debug_agent(
                workspace=tool_input.get("workspace", "dev"),
                filter_name=tool_input.get("filter_name"),
            )
        elif tool_name == "run_cleanup_agent":
            return run_cleanup_agent(auto_delete=tool_input.get("auto_delete", False))
        elif tool_name == "run_requirements_agent":
            return run_requirements_agent(requirement=tool_input.get("requirement", ""))
        elif tool_name == "run_assistant_agent":
            return run_assistant_agent(question=tool_input.get("question", ""))
        elif tool_name == "read_cdm_log":
            return _read_cdm_log(tail=tool_input.get("tail", 50))
        else:
            return {"agent": "unknown", "status": "FAIL", "checks": [],
                    "findings": [f"Unknown tool: {tool_name}"], "actions": [], "data": {}}
    except Exception as exc:
        return {"agent": tool_name, "status": "FAIL", "checks": [],
                "findings": [f"Exception: {exc}"], "actions": ["Check logs."], "data": {}}


# ── Manager loop ───────────────────────────────────────────────────────────────

def run_manager():
    _hdr("CDM-Manager Workflow Assistant (Claude)")
    print("  I guide you through CDM-Manager step by step.")
    print("  After each action I read the CDM-Manager log and validate the result.")
    print("  Type 'exit' to quit.\n")

    conversation_history = []

    while True:
        try:
            user_input = input("You: ").strip()
        except (KeyboardInterrupt, EOFError):
            print("\nExiting.")
            break

        if user_input.lower() in ("exit", "quit"):
            break
        if not user_input:
            continue

        conversation_history.append({"role": "user", "content": user_input})

        # Agentic loop
        while True:
            response = client.messages.create(
                model=CLAUDE_MODEL,
                max_tokens=4096,
                system=SYSTEM_PROMPT,
                tools=tools,
                messages=conversation_history,
            )

            if response.stop_reason == "end_turn":
                for block in response.content:
                    if hasattr(block, "text") and block.text:
                        print(f"\nAgent:\n{block.text}\n")
                conversation_history.append({"role": "assistant", "content": response.content})
                break

            if response.stop_reason == "tool_use":
                conversation_history.append({"role": "assistant", "content": response.content})
                tool_results = []

                for block in response.content:
                    if block.type == "tool_use":
                        _tool_start(block.name, block.input.get("description", ""))
                        result = dispatch_agent(block.name, block.input)
                        _tool_result(result)
                        tool_results.append({
                            "type": "tool_result",
                            "tool_use_id": block.id,
                            "content": json.dumps(result, indent=2),
                        })

                conversation_history.append({"role": "user", "content": tool_results})
            else:
                print(f"  [Unexpected stop_reason: {response.stop_reason}]")
                break


if __name__ == "__main__":
    run_manager()
