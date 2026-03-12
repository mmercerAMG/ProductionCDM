"""
manager_agent.py (Gemini version) - CDM-Manager Workflow Assistant.

Uses the Vertex AI Python SDK (gemini-2.0-flash) with function calling to
orchestrate 8 specialized sub-agents, working step-by-step with the user.

Run:
    python manager_agent.py
"""

import json
import os
import subprocess
import sys
from agents.config import REPO_DIR

from dotenv import load_dotenv
import vertexai
from vertexai.generative_models import (
    GenerativeModel,
    Tool,
    FunctionDeclaration,
    Part,
)

# Ensure the agents package is importable when running this file directly
sys.path.insert(0, os.path.dirname(__file__))

load_dotenv()

from agents.auth_agent         import run_auth_agent
from agents.branch_agent       import run_branch_agent
from agents.deploy_agent       import run_deploy_agent
from agents.debug_agent        import run_debug_agent
from agents.cleanup_agent      import run_cleanup_agent
from agents.requirements_agent import run_requirements_agent
from agents.assistant_agent    import run_assistant_agent

# ------------------------------------------------------------------
# Config
# ------------------------------------------------------------------
VERTEX_PROJECT  = os.getenv("GOOGLE_CLOUD_PROJECT",  "g-20260202-240969652002")
VERTEX_LOCATION = os.getenv("GOOGLE_CLOUD_LOCATION", "us-central1")
GEMINI_MODEL    = os.getenv("GEMINI_MODEL",           "gemini-2.0-flash")

vertexai.init(project=VERTEX_PROJECT, location=VERTEX_LOCATION)

# ------------------------------------------------------------------
# System prompt
# ------------------------------------------------------------------
SYSTEM_PROMPT = """\
You are the CDM-Manager Workflow Assistant — a collaborative, step-by-step guide that works WITH the user to set up, test, and debug the CDM-Manager Power BI change management process.

## Critical Rule: You Cannot Do Everything Automatically
Some actions require the USER to operate CDM-Manager (a Windows GUI app) or Power BI Desktop. You must guide them through those steps and WAIT for their confirmation before proceeding.

## Two categories of actions:

### Actions YOU can do autonomously (use your tools):
- Run git commands via run_git_command (create branches, push, fetch, check status)
- Run PowerShell via run_powershell (deploy-pbi.ps1, any PS command)
- Extract PBIX to PBIP via run_pbi_tools
- Read CDM-Manager console output via read_cdm_log (call after user performs GUI action)
- Validate Power BI state via auth/branch/deploy/debug/cleanup agents
- Read documentation and codebase via requirements/assistant agents

### Actions the USER must do (you guide, then wait for "done"):
- Open and authenticate in CDM-Manager (browser OAuth login)
- Click buttons in CDM-Manager (Download CDM, Create Branch, Deploy, etc.)
- Open Power BI Desktop
- Any file operations on their local machine outside the repo

## How to work with the user step by step:
1. Break every task into small numbered steps
2. For steps YOU can do: do them immediately and show the result
3. For steps the USER must do: clearly tell them exactly what to do, then end your message with:
   "Let me know when that's done and I'll continue."
4. When the user confirms ("done", "ok", "finished", etc.): validate the result, then move to the next step
5. Never skip ahead — always confirm one step completed before giving the next

## CDM-Manager workflow knowledge:
- CDM-Manager.ps1 is a PowerShell WPF GUI — the user launches it, not you
- Authentication: CDM-Manager opens browser to microsoft.com/devicelogin, code auto-copied to clipboard
- Token saved to %TEMP%\\pbi_token.txt — your agents read it to validate PBI state
- PBIX files cannot be committed to git — only PBIP folders (.SemanticModel/, .Report/) are tracked
- Branch naming: feature/[TopBranch]/[Name] or hotfix/[TopBranch]/[Name]
- Dev deployments limited to 4 pages max
- Live Connect mode: clones "Live Connection Template" in Dev, binds to Production dataset
- New Semantic Model mode: uploads full PBIX with its own dataset

## Tone:
- Be concise and clear
- Number every step
- Show validation results as PASS/FAIL/WARN
- When something fails, explain exactly why and what to do
- Never overwhelm — one set of steps at a time
"""

# ------------------------------------------------------------------
# Function declarations (one per agent)
# ------------------------------------------------------------------

_decl_auth = FunctionDeclaration(
    name="run_auth_agent",
    description=(
        "Validates Power BI token, workspace access, pbi-tools presence, "
        "and Live Connection Template. Always call this first when testing or debugging."
    ),
    parameters={
        "type": "object",
        "properties": {},
    },
)

_decl_branch = FunctionDeclaration(
    name="run_branch_agent",
    description=(
        "Validates branch creation state. Checks git remote, PBI report existence, "
        "deploy mode (auto-detected), dataset binding, and orphan detection."
    ),
    parameters={
        "type": "object",
        "properties": {
            "branch_name": {
                "type": "string",
                "description": "Full branch name e.g. feature/Production-Main/MM-TEST12",
            }
        },
        "required": ["branch_name"],
    },
)

_decl_deploy = FunctionDeclaration(
    name="run_deploy_agent",
    description=(
        "Validates deployment state. Checks report exists in correct workspace, "
        "page count, duplicates."
    ),
    parameters={
        "type": "object",
        "properties": {
            "branch_name": {
                "type": "string",
                "description": "Full branch name to check deployment for",
            },
            "environment": {
                "type": "string",
                "enum": ["dev", "prod"],
                "description": "Target environment. Default: dev",
            },
        },
        "required": ["branch_name"],
    },
)

_decl_debug = FunctionDeclaration(
    name="run_debug_agent",
    description=(
        "Full workspace scan. Lists all reports and datasets, finds orphans, "
        "checks Live Connect Template. Use when something is wrong and you need "
        "to see everything in the workspace."
    ),
    parameters={
        "type": "object",
        "properties": {
            "workspace": {
                "type": "string",
                "enum": ["dev", "prod"],
                "description": "Which workspace to scan. Default: dev",
            },
            "filter_name": {
                "type": "string",
                "description": "Optional: filter results to items containing this string",
            },
        },
    },
)

_decl_cleanup = FunctionDeclaration(
    name="run_cleanup_agent",
    description=(
        "Finds orphan datasets and reports in Dev workspace. Can optionally delete them."
    ),
    parameters={
        "type": "object",
        "properties": {
            "auto_delete": {
                "type": "boolean",
                "description": "If true, deletes orphans. Default: false (just lists them)",
            }
        },
    },
)

_decl_requirements = FunctionDeclaration(
    name="run_requirements_agent",
    description=(
        "Gathers codebase context for implementing a new requirement. "
        "Reads CDM-Manager.ps1, deploy-pbi.ps1, WORKFLOW.md, README.md "
        "and returns relevant sections."
    ),
    parameters={
        "type": "object",
        "properties": {
            "requirement": {
                "type": "string",
                "description": "The new requirement in plain English",
            }
        },
        "required": ["requirement"],
    },
)

_decl_assistant = FunctionDeclaration(
    name="run_assistant_agent",
    description=(
        "Answers questions about the CDM-Manager workflow. "
        "Reads WORKFLOW.md, README.md, instructions.md and optionally "
        "checks live PBI state."
    ),
    parameters={
        "type": "object",
        "properties": {
            "question": {
                "type": "string",
                "description": "The question to answer about the CDM-Manager workflow",
            }
        },
        "required": ["question"],
    },
)

_decl_log = FunctionDeclaration(
    name="read_cdm_log",
    description=(
        "Reads the CDM-Manager console log file so you can see exactly what "
        "is happening inside CDM-Manager in real time. Call this after asking "
        "the user to perform an action in CDM-Manager to verify it worked."
    ),
    parameters={
        "type": "object",
        "properties": {
            "tail": {"type": "integer", "description": "Number of recent lines to return. Default: 50"},
        },
    },
)

_decl_powershell = FunctionDeclaration(
    name="run_powershell",
    description=(
        "Run deploy-pbi.ps1 or any PowerShell command directly. "
        "Use to deploy reports to Dev or Prod without CDM-Manager GUI."
    ),
    parameters={
        "type": "object",
        "properties": {
            "command": {"type": "string", "description": "Full PowerShell command"},
            "description": {"type": "string", "description": "What this command does"},
            "working_dir": {"type": "string", "description": "Working directory. Defaults to repo root."},
        },
        "required": ["command", "description"],
    },
)

_decl_pbi_tools = FunctionDeclaration(
    name="run_pbi_tools",
    description="Run pbi-tools to extract a PBIX into PBIP folder format for git.",
    parameters={
        "type": "object",
        "properties": {
            "pbix_path": {"type": "string", "description": "Full path to the .pbix file"},
            "extract_folder": {"type": "string", "description": "Output folder. Defaults to repo root."},
        },
        "required": ["pbix_path"],
    },
)

_decl_git = FunctionDeclaration(
    name="run_git_command",
    description=(
        "Runs a git command in the CDM repo. Use this to create branches, "
        "push to ADO, fetch remotes, check status, commit PBIP files, etc. "
        "You can run any git operation that does not require user interaction."
    ),
    parameters={
        "type": "object",
        "properties": {
            "args": {
                "type": "array",
                "items": {"type": "string"},
                "description": "Git arguments e.g. ['checkout', '-b', 'Production-Test-Data-Main']",
            },
            "description": {
                "type": "string",
                "description": "Human-readable description of what this command does",
            },
        },
        "required": ["args", "description"],
    },
)

# ------------------------------------------------------------------
# Build model
# ------------------------------------------------------------------
_all_tools = Tool(
    function_declarations=[
        _decl_auth,
        _decl_branch,
        _decl_deploy,
        _decl_debug,
        _decl_cleanup,
        _decl_requirements,
        _decl_assistant,
        _decl_git,
        _decl_log,
        _decl_powershell,
        _decl_pbi_tools,
    ]
)

model = GenerativeModel(
    model_name=GEMINI_MODEL,
    system_instruction=SYSTEM_PROMPT,
    tools=[_all_tools],
)


# ------------------------------------------------------------------
# Git command runner
# ------------------------------------------------------------------

def _read_cdm_log(tail: int = 50) -> dict:
    log_file = os.path.join(os.environ.get("TEMP", os.environ.get("TMP", "/tmp")), "cdm-manager-log.txt")
    if not os.path.exists(log_file):
        return {"agent": "read_cdm_log", "status": "WARN", "checks": [],
                "findings": ["Log file not found. CDM-Manager may not be running."],
                "actions": ["Launch CDM-Manager and complete authentication first."],
                "data": {"lines": []}}
    with open(log_file, encoding="utf-8", errors="replace") as f:
        all_lines = [l.rstrip() for l in f.readlines() if l.strip()]
    recent = all_lines[-tail:] if len(all_lines) > tail else all_lines
    print(f"    (showing last {len(recent)} of {len(all_lines)} log lines)")
    for line in recent:
        print(f"        {line}")
    return {"agent": "read_cdm_log", "status": "PASS", "checks": [],
            "findings": recent, "actions": [],
            "data": {"log_file": log_file, "total_lines": len(all_lines), "lines": recent}}


def _run_powershell(command: str, description: str, working_dir: str = None) -> dict:
    cwd = working_dir or REPO_DIR
    cmd = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", command]
    print(f"    $ powershell: {command}")
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=cwd)
    if r.stdout:
        for line in r.stdout.strip().splitlines():
            print(f"        {line}")
    if r.stderr and r.returncode != 0:
        for line in r.stderr.strip().splitlines():
            print(f"    [!] {line}")
    return {"agent": "powershell", "status": "PASS" if r.returncode == 0 else "FAIL",
            "description": description, "command": command,
            "stdout": r.stdout.strip(), "stderr": r.stderr.strip(),
            "returncode": r.returncode,
            "findings": [r.stdout.strip() or "(no output)"],
            "actions": [] if r.returncode == 0 else [f"PowerShell error: {r.stderr.strip()}"],
            "checks": []}


def _run_pbi_tools(pbix_path: str, extract_folder: str = None) -> dict:
    pbi_exe = os.path.join(REPO_DIR, "pbi-tools.exe")
    if not os.path.exists(pbi_exe):
        pbi_exe = "pbi-tools"
    out_dir = extract_folder or REPO_DIR
    cmd = [pbi_exe, "extract", pbix_path, "-extractFolder", out_dir]
    print(f"    $ {' '.join(cmd)}")
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=REPO_DIR)
    if r.stdout:
        for line in r.stdout.strip().splitlines():
            print(f"        {line}")
    if r.stderr and r.returncode != 0:
        for line in r.stderr.strip().splitlines():
            print(f"    [!] {line}")
    return {"agent": "pbi_tools", "status": "PASS" if r.returncode == 0 else "FAIL",
            "description": f"Extract {pbix_path} -> {out_dir}",
            "stdout": r.stdout.strip(), "stderr": r.stderr.strip(),
            "returncode": r.returncode,
            "findings": [r.stdout.strip() or "(no output)"],
            "actions": [] if r.returncode == 0 else [
                f"pbi-tools error: {r.stderr.strip()}",
                "Ensure pbi-tools.exe is in the repo folder and Power BI Desktop is installed."],
            "checks": []}


def _run_git_command(args: list, description: str) -> dict:
    """Run a git command in the CDM repo and return structured result."""
    try:
        cmd = ["git", "-C", REPO_DIR] + args
        result = subprocess.run(cmd, capture_output=True, text=True)
        return {
            "agent": "git_command",
            "status": "PASS" if result.returncode == 0 else "FAIL",
            "description": description,
            "command": " ".join(cmd),
            "stdout": result.stdout.strip(),
            "stderr": result.stderr.strip(),
            "returncode": result.returncode,
            "findings": [
                result.stdout.strip() if result.stdout.strip() else "(no output)",
            ],
            "actions": [] if result.returncode == 0 else [
                f"Command failed with code {result.returncode}: {result.stderr.strip()}"
            ],
        }
    except Exception as exc:
        return {
            "agent": "git_command",
            "status": "FAIL",
            "description": description,
            "command": " ".join(args),
            "stdout": "",
            "stderr": str(exc),
            "returncode": -1,
            "findings": [f"Exception running git: {exc}"],
            "actions": ["Ensure git is installed and accessible in PATH."],
        }


# ------------------------------------------------------------------
# Agent dispatcher
# ------------------------------------------------------------------

def dispatch_agent(tool_name: str, tool_input: dict) -> dict:
    """Route a function call to the appropriate agent function."""
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
                filter_name=tool_input.get("filter_name", None),
            )
        elif tool_name == "run_cleanup_agent":
            return run_cleanup_agent(
                auto_delete=tool_input.get("auto_delete", False)
            )
        elif tool_name == "run_requirements_agent":
            return run_requirements_agent(
                requirement=tool_input.get("requirement", "")
            )
        elif tool_name == "run_assistant_agent":
            return run_assistant_agent(
                question=tool_input.get("question", "")
            )
        elif tool_name == "run_git_command":
            return _run_git_command(
                args=tool_input.get("args", []),
                description=tool_input.get("description", ""),
            )
        elif tool_name == "read_cdm_log":
            return _read_cdm_log(tail=tool_input.get("tail", 50))
        elif tool_name == "run_powershell":
            return _run_powershell(
                command=tool_input.get("command", ""),
                description=tool_input.get("description", ""),
                working_dir=tool_input.get("working_dir"),
            )
        elif tool_name == "run_pbi_tools":
            return _run_pbi_tools(
                pbix_path=tool_input.get("pbix_path", ""),
                extract_folder=tool_input.get("extract_folder"),
            )
        else:
            return {
                "agent": "unknown",
                "status": "FAIL",
                "checks": [],
                "findings": [f"Unknown function: {tool_name}"],
                "actions": [],
                "data": {},
            }
    except Exception as exc:
        return {
            "agent": tool_name,
            "status": "FAIL",
            "checks": [],
            "findings": [f"Unhandled exception in dispatch: {exc}"],
            "actions": ["Check agent logs for details."],
            "data": {},
        }


# ------------------------------------------------------------------
# Manager loop
# ------------------------------------------------------------------

def run_manager():
    print("\nCDM-Manager Agent (Gemini)")
    print("I work with you step by step — I'll tell you what to do in CDM-Manager,")
    print("wait for you to confirm, then validate the result automatically.")
    print("Type 'exit' to quit.\n")

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

        # Agentic loop — handle function calls until a final text response
        while True:
            candidate = response.candidates[0]

            # Check if any part in this response contains a function call
            has_function_call = any(
                part.function_call.name
                for part in candidate.content.parts
                if hasattr(part, "function_call") and part.function_call
            )

            if not has_function_call:
                for part in candidate.content.parts:
                    if hasattr(part, "text") and part.text:
                        print(f"\nAgent: {part.text}\n")
                break

            # Process all function calls in this response
            function_responses = []
            for part in candidate.content.parts:
                if hasattr(part, "function_call") and part.function_call:
                    fc = part.function_call
                    if not fc.name:
                        continue
                    print(f"  [Calling {fc.name}...]")
                    args = dict(fc.args) if fc.args else {}
                    result = dispatch_agent(fc.name, args)
                    function_responses.append(
                        Part.from_function_response(
                            name=fc.name,
                            response={"content": json.dumps(result, indent=2)},
                        )
                    )

            if not function_responses:
                for part in candidate.content.parts:
                    if hasattr(part, "text") and part.text:
                        print(f"\nAgent: {part.text}\n")
                break

            response = chat.send_message(function_responses)


if __name__ == "__main__":
    run_manager()
