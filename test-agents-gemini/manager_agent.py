"""
manager_agent.py (Gemini version) - CDM-Manager Workflow Assistant.

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
import vertexai
from vertexai.generative_models import (
    GenerativeModel,
    Tool,
    FunctionDeclaration,
    Part,
)

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
VERTEX_PROJECT  = os.getenv("GOOGLE_CLOUD_PROJECT",  "g-20260202-240969652002")
VERTEX_LOCATION = os.getenv("GOOGLE_CLOUD_LOCATION", "us-central1")
GEMINI_MODEL    = os.getenv("GEMINI_MODEL",           "gemini-2.0-flash")

vertexai.init(project=VERTEX_PROJECT, location=VERTEX_LOCATION)

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
    status   = result.get("status", "?")
    checks   = result.get("checks", [])
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

# ── Function declarations ──────────────────────────────────────────────────────

_decl_auth = FunctionDeclaration(
    name="run_auth_agent",
    description="Validates PBI token, workspace access, pbi-tools, and Live Connection Template. Call after user authenticates in CDM-Manager.",
    parameters={"type": "object", "properties": {}},
)

_decl_branch = FunctionDeclaration(
    name="run_branch_agent",
    description="Validates branch state: git remote, PBI report, deploy mode, dataset binding. Call after user creates a branch in CDM-Manager.",
    parameters={
        "type": "object",
        "properties": {
            "branch_name": {"type": "string", "description": "Full branch name e.g. feature/Production-Main/MM-TEST12"}
        },
        "required": ["branch_name"],
    },
)

_decl_deploy = FunctionDeclaration(
    name="run_deploy_agent",
    description="Validates deployment: report in workspace, page count, duplicates. Call after user deploys in CDM-Manager.",
    parameters={
        "type": "object",
        "properties": {
            "branch_name": {"type": "string"},
            "environment": {"type": "string", "enum": ["dev", "prod"], "description": "Default: dev"},
        },
        "required": ["branch_name"],
    },
)

_decl_debug = FunctionDeclaration(
    name="run_debug_agent",
    description="Full workspace scan: all reports, datasets, orphans, Live Connect Template. Use when diagnosing problems.",
    parameters={
        "type": "object",
        "properties": {
            "workspace": {"type": "string", "enum": ["dev", "prod"], "description": "Default: dev"},
            "filter_name": {"type": "string", "description": "Optional name filter"},
        },
    },
)

_decl_cleanup = FunctionDeclaration(
    name="run_cleanup_agent",
    description="Find and optionally delete orphan datasets/reports in Dev workspace.",
    parameters={
        "type": "object",
        "properties": {
            "auto_delete": {"type": "boolean", "description": "If true, deletes orphans. Default: false"}
        },
    },
)

_decl_requirements = FunctionDeclaration(
    name="run_requirements_agent",
    description="Read codebase context to plan implementing a new requirement.",
    parameters={
        "type": "object",
        "properties": {
            "requirement": {"type": "string", "description": "New requirement in plain English"}
        },
        "required": ["requirement"],
    },
)

_decl_assistant = FunctionDeclaration(
    name="run_assistant_agent",
    description="Answer workflow questions using WORKFLOW.md, README.md, instructions.md and live PBI state.",
    parameters={
        "type": "object",
        "properties": {"question": {"type": "string"}},
        "required": ["question"],
    },
)

_decl_log = FunctionDeclaration(
    name="read_cdm_log",
    description="Read the CDM-Manager console log. Call this after EVERY action the user performs in CDM-Manager.",
    parameters={
        "type": "object",
        "properties": {
            "tail": {"type": "integer", "description": "Number of recent lines to return. Default: 50"}
        },
    },
)

# ── Build model ────────────────────────────────────────────────────────────────
_all_tools = Tool(
    function_declarations=[
        _decl_auth,
        _decl_branch,
        _decl_deploy,
        _decl_debug,
        _decl_cleanup,
        _decl_requirements,
        _decl_assistant,
        _decl_log,
    ]
)

model = GenerativeModel(
    model_name=GEMINI_MODEL,
    system_instruction=SYSTEM_PROMPT,
    tools=[_all_tools],
)


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
    _hdr("CDM-Manager Workflow Assistant (Gemini)")
    print("  I guide you through CDM-Manager step by step.")
    print("  After each action I read the CDM-Manager log and validate the result.")
    print("  Type 'exit' to quit.\n")

    chat = model.start_chat()

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

        response = chat.send_message(user_input)

        # Agentic loop
        while True:
            candidate = response.candidates[0]

            has_function_call = any(
                part.function_call.name
                for part in candidate.content.parts
                if hasattr(part, "function_call") and part.function_call
            )

            if not has_function_call:
                for part in candidate.content.parts:
                    if hasattr(part, "text") and part.text:
                        print(f"\nAgent:\n{part.text}\n")
                break

            function_responses = []
            for part in candidate.content.parts:
                if hasattr(part, "function_call") and part.function_call:
                    fc = part.function_call
                    if not fc.name:
                        continue
                    _tool_start(fc.name)
                    args   = dict(fc.args) if fc.args else {}
                    result = dispatch_agent(fc.name, args)
                    _tool_result(result)
                    function_responses.append(
                        Part.from_function_response(
                            name=fc.name,
                            response={"content": json.dumps(result, indent=2)},
                        )
                    )

            if not function_responses:
                for part in candidate.content.parts:
                    if hasattr(part, "text") and part.text:
                        print(f"\nAgent:\n{part.text}\n")
                break

            response = chat.send_message(function_responses)


if __name__ == "__main__":
    run_manager()
