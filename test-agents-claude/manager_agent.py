"""
manager_agent.py (Claude version) - CDM-Manager Workflow Assistant.

Uses the Anthropic Python SDK (claude-sonnet-4-6) with tool use to
orchestrate specialized sub-agents, working step-by-step with the user.

The agent can:
  - Run git commands directly (branch creation, push, fetch, etc.)
  - Run PowerShell scripts directly (deploy-pbi.ps1, pbi-tools)
  - Validate Power BI state via REST API agents
  - Answer questions and plan new requirements

The agent CANNOT:
  - Click buttons in CDM-Manager's GUI
  - Authenticate via browser on your behalf (you must do this in CDM-Manager)

Run:
    python manager_agent.py
"""

import json
import os
import subprocess
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
from agents.config             import REPO_DIR

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

def _tool_start(name, description):
    print(f"\n  ▶ {name}")
    if description:
        print(f"    {description}")

def _tool_result(result: dict):
    status  = result.get("status", "?")
    agent   = result.get("agent", "?")
    icon    = "✓" if status == "PASS" else ("✗" if status == "FAIL" else "!")
    color   = ""

    checks   = result.get("checks", [])
    findings = result.get("findings", [])
    stdout   = result.get("stdout", "")
    stderr   = result.get("stderr", "")

    print(f"  {SSEP}")
    # Individual checks
    for c in checks:
        s = c.get("status", "?")
        sym = "✓" if s == "PASS" else ("✗" if s == "FAIL" else "!")
        detail = f"  ({c['detail']})" if c.get("detail") else ""
        print(f"    [{sym}] {c.get('name','')}{detail}")

    # Git / PowerShell stdout
    if stdout:
        for line in stdout.splitlines():
            print(f"        {line}")
    if stderr and status == "FAIL":
        for line in stderr.splitlines():
            print(f"    [!] {line}")

    # Findings
    for f in findings:
        if f and f != "(no output)":
            print(f"    → {f}")

    print(f"  {SSEP}")
    print(f"    Result: {icon} {status}")


# ── System prompt ──────────────────────────────────────────────────────────────
SYSTEM_PROMPT = """\
You are the CDM-Manager Workflow Assistant — a collaborative, step-by-step guide \
that works WITH the user to set up, test, and debug the CDM-Manager Power BI \
change management process.

## What you can do autonomously (use your tools — no user action needed):
- run_git_command: create branches, push, fetch, check status, commit
- run_powershell: run deploy-pbi.ps1 to deploy reports to Dev or Prod
- run_pbi_tools: extract a PBIX into PBIP folder format using pbi-tools
- read_cdm_log: read the CDM-Manager console log in real time — call this
  after asking the user to perform an action in CDM-Manager to see what happened
- run_auth_agent / run_branch_agent / run_deploy_agent / run_debug_agent /
  run_cleanup_agent: validate Power BI state via REST API
- run_requirements_agent / run_assistant_agent: read docs and plan changes

## What requires USER action (guide them, then wait for confirmation):
- Opening CDM-Manager.ps1 and completing browser OAuth login
  (this writes the PBI token to %TEMP%\\pbi_token.txt which your tools then use)
- Opening Power BI Desktop to edit a report
- Any manual file operations outside the repo

## Authentication flow (important):
- Before ANY Power BI API call, run run_auth_agent to check the token
- If token is missing or expired: tell the user to open CDM-Manager, complete
  browser login, then say "done" — then call run_auth_agent again to confirm
- Once token is valid, proceed autonomously

## Workflow knowledge:
- PBIX files cannot go in git — only PBIP folders (.SemanticModel/, .Report/)
- Branch naming: feature/[TopBranch]/[Name] or hotfix/[TopBranch]/[Name]
- deploy-pbi.ps1 parameters: -PbixPath, -ReportName, -TargetEnv (Dev|Prod),
  -DevWorkspaceId, -ProdWorkspaceId, -ProdDatasetId, -LiveConnect (switch)
- pbi-tools extract [pbix_path] -extractFolder [output_dir]
- Dev deployments limited to 4 pages max

## Step-by-step behaviour:
1. Break every task into numbered steps
2. For steps YOU handle: run the tool, show the result, move to next step
3. For steps the USER must do: tell them exactly what to do, end with
   "Let me know when that's done and I'll continue."
4. On user confirmation: validate, then continue
5. Always show what you are doing — never silently skip steps
"""

# ── Tool definitions ───────────────────────────────────────────────────────────
tools = [
    {
        "name": "run_auth_agent",
        "description": "Validates PBI token, workspace access, pbi-tools, and Live Connection Template. Call this before any PBI operation.",
        "input_schema": {"type": "object", "properties": {}, "required": []},
    },
    {
        "name": "run_branch_agent",
        "description": "Validates branch state: git remote, PBI report existence, deploy mode, dataset binding, orphan check.",
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
        "description": "Validates deployment: report exists in workspace, page count, duplicates.",
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
        "description": "Read codebase context (CDM-Manager.ps1, deploy-pbi.ps1, WORKFLOW.md, README.md) to plan a new requirement.",
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
            "properties": {
                "question": {"type": "string"}
            },
            "required": ["question"],
        },
    },
    {
        "name": "run_git_command",
        "description": "Run a git command in the CDM repo. Use for branch creation, push, fetch, status, commits.",
        "input_schema": {
            "type": "object",
            "properties": {
                "args": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Git args e.g. ['checkout', '-b', 'Production-Main']",
                },
                "description": {"type": "string", "description": "What this command does"},
            },
            "required": ["args", "description"],
        },
    },
    {
        "name": "run_powershell",
        "description": (
            "Run deploy-pbi.ps1 or any PowerShell command directly. "
            "Use this to deploy reports to Dev or Prod without needing CDM-Manager GUI. "
            "Example: run deploy-pbi.ps1 -PbixPath '...' -ReportName '...' -TargetEnv Dev"
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "command": {
                    "type": "string",
                    "description": "Full PowerShell command to run e.g. \"& '.\\deploy-pbi.ps1' -PbixPath 'C:\\file.pbix' -TargetEnv Dev\"",
                },
                "description": {"type": "string", "description": "What this command does"},
                "working_dir": {
                    "type": "string",
                    "description": "Working directory. Defaults to repo root.",
                },
            },
            "required": ["command", "description"],
        },
    },
    {
        "name": "read_cdm_log",
        "description": (
            "Reads the CDM-Manager console log file so you can see exactly what "
            "is happening inside CDM-Manager in real time. Call this after asking "
            "the user to perform an action in CDM-Manager to verify it worked."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "tail": {
                    "type": "integer",
                    "description": "Number of most recent lines to return. Default: 50",
                }
            },
            "required": [],
        },
    },
    {
        "name": "run_pbi_tools",
        "description": "Run pbi-tools to extract a PBIX into PBIP folder format (required before committing to git).",
        "input_schema": {
            "type": "object",
            "properties": {
                "pbix_path": {
                    "type": "string",
                    "description": "Full path to the .pbix file",
                },
                "extract_folder": {
                    "type": "string",
                    "description": "Output folder for PBIP files. Defaults to repo root.",
                },
            },
            "required": ["pbix_path"],
        },
    },
]


# ── Runners ────────────────────────────────────────────────────────────────────

def _run_git_command(args: list, description: str) -> dict:
    cmd = ["git", "-C", REPO_DIR] + args
    print(f"    $ {' '.join(cmd)}")
    r = subprocess.run(cmd, capture_output=True, text=True)
    return {
        "agent": "git_command",
        "status": "PASS" if r.returncode == 0 else "FAIL",
        "description": description,
        "command": " ".join(cmd),
        "stdout": r.stdout.strip(),
        "stderr": r.stderr.strip(),
        "returncode": r.returncode,
        "findings": [r.stdout.strip() or "(no output)"],
        "actions": [] if r.returncode == 0 else [f"git error: {r.stderr.strip()}"],
        "checks": [],
    }


def _run_powershell(command: str, description: str, working_dir: str = None) -> dict:
    cwd = working_dir or REPO_DIR
    cmd = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", command]
    print(f"    $ powershell: {command}")
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=cwd)
    stdout = r.stdout.strip()
    stderr = r.stderr.strip()

    # Stream output lines to console as they appear in result
    if stdout:
        for line in stdout.splitlines():
            print(f"        {line}")
    if stderr:
        for line in stderr.splitlines():
            print(f"    [!] {line}")

    return {
        "agent": "powershell",
        "status": "PASS" if r.returncode == 0 else "FAIL",
        "description": description,
        "command": command,
        "stdout": stdout,
        "stderr": stderr,
        "returncode": r.returncode,
        "findings": [stdout or "(no output)"],
        "actions": [] if r.returncode == 0 else [f"PowerShell error (code {r.returncode}): {stderr}"],
        "checks": [],
    }


def _read_cdm_log(tail: int = 50) -> dict:
    """Read the CDM-Manager log file mirrored from the GUI console."""
    log_file = os.path.join(os.environ.get("TEMP", os.environ.get("TMP", "/tmp")), "cdm-manager-log.txt")
    if not os.path.exists(log_file):
        return {
            "agent": "read_cdm_log",
            "status": "WARN",
            "checks": [],
            "findings": ["Log file not found. CDM-Manager may not be running or has not written any output yet."],
            "actions": ["Launch CDM-Manager and complete authentication first."],
            "data": {"log_file": log_file, "lines": []},
        }
    with open(log_file, encoding="utf-8", errors="replace") as f:
        all_lines = [l.rstrip() for l in f.readlines() if l.strip()]
    recent = all_lines[-tail:] if len(all_lines) > tail else all_lines
    print(f"    (showing last {len(recent)} of {len(all_lines)} log lines)")
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


def _run_pbi_tools(pbix_path: str, extract_folder: str = None) -> dict:
    pbi_tools_exe = os.path.join(REPO_DIR, "pbi-tools.exe")
    if not os.path.exists(pbi_tools_exe):
        pbi_tools_exe = "pbi-tools"  # fall back to PATH

    out_dir = extract_folder or REPO_DIR
    cmd = [pbi_tools_exe, "extract", pbix_path, "-extractFolder", out_dir]
    print(f"    $ {' '.join(cmd)}")
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=REPO_DIR)

    if r.stdout:
        for line in r.stdout.splitlines():
            print(f"        {line}")
    if r.stderr and r.returncode != 0:
        for line in r.stderr.splitlines():
            print(f"    [!] {line}")

    return {
        "agent": "pbi_tools",
        "status": "PASS" if r.returncode == 0 else "FAIL",
        "description": f"Extract {pbix_path} → {out_dir}",
        "command": " ".join(cmd),
        "stdout": r.stdout.strip(),
        "stderr": r.stderr.strip(),
        "returncode": r.returncode,
        "findings": [r.stdout.strip() or "(no output)"],
        "actions": [] if r.returncode == 0 else [
            f"pbi-tools error: {r.stderr.strip()}",
            "Ensure pbi-tools.exe is in the repo folder and Power BI Desktop is installed.",
        ],
        "checks": [],
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
        elif tool_name == "run_git_command":
            return _run_git_command(
                args=tool_input.get("args", []),
                description=tool_input.get("description", ""),
            )
        elif tool_name == "run_powershell":
            return _run_powershell(
                command=tool_input.get("command", ""),
                description=tool_input.get("description", ""),
                working_dir=tool_input.get("working_dir"),
            )
        elif tool_name == "read_cdm_log":
            return _read_cdm_log(tail=tool_input.get("tail", 50))
        elif tool_name == "run_pbi_tools":
            return _run_pbi_tools(
                pbix_path=tool_input.get("pbix_path", ""),
                extract_folder=tool_input.get("extract_folder"),
            )
        else:
            return {"agent": "unknown", "status": "FAIL", "checks": [],
                    "findings": [f"Unknown tool: {tool_name}"], "actions": [], "data": {}}
    except Exception as exc:
        return {"agent": tool_name, "status": "FAIL", "checks": [],
                "findings": [f"Exception: {exc}"], "actions": ["Check logs."], "data": {}}


# ── Manager loop ───────────────────────────────────────────────────────────────

def run_manager():
    _hdr("CDM-Manager Workflow Assistant (Claude)")
    print("  I work alongside you — I'll handle git, deployments, and validation")
    print("  automatically. For anything requiring CDM-Manager's browser login,")
    print("  I'll guide you through it and wait for your confirmation.")
    print(f"\n  Repo : {REPO_DIR}")
    print(f"  Model: {CLAUDE_MODEL}")
    print(f"\n  Type 'exit' to quit.\n")

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
                        # Show what the agent is about to do
                        _tool_start(block.name, block.input.get("description", ""))

                        result = dispatch_agent(block.name, block.input)

                        # Show the result
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
