"""
manager_agent.py (Claude version) - CDM-Manager Test & Debug Orchestrator.

Uses the Anthropic Python SDK (claude-sonnet-4-6) with tool use to
orchestrate 7 specialized sub-agents.

Run:
    python manager_agent.py
"""

import json
import os
import subprocess
import sys

from dotenv import load_dotenv
import anthropic

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
from agents.config             import REPO_DIR

# ------------------------------------------------------------------
# Config
# ------------------------------------------------------------------
CLAUDE_MODEL = os.getenv("CLAUDE_MODEL", "claude-sonnet-4-6")

client = anthropic.Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))

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
# Tool definitions
# ------------------------------------------------------------------
tools = [
    {
        "name": "run_auth_agent",
        "description": (
            "Validates Power BI token, workspace access, pbi-tools presence, "
            "and Live Connection Template. Always call this first when testing or debugging."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "run_branch_agent",
        "description": (
            "Validates branch creation state. Checks git remote, PBI report existence, "
            "deploy mode (auto-detected), dataset binding, and orphan detection."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "branch_name": {
                    "type": "string",
                    "description": "Full branch name e.g. feature/Production-Main/MM-TEST12",
                }
            },
            "required": ["branch_name"],
        },
    },
    {
        "name": "run_deploy_agent",
        "description": (
            "Validates deployment state. Checks report exists in correct workspace, "
            "page count, duplicates."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "branch_name": {"type": "string"},
                "environment": {
                    "type": "string",
                    "enum": ["dev", "prod"],
                    "description": "Default: dev",
                },
            },
            "required": ["branch_name"],
        },
    },
    {
        "name": "run_debug_agent",
        "description": (
            "Full workspace scan. Lists all reports and datasets, finds orphans, "
            "checks Live Connect Template. Use when something is wrong and you need "
            "to see everything in the workspace."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "workspace": {
                    "type": "string",
                    "enum": ["dev", "prod"],
                    "description": "Default: dev",
                },
                "filter_name": {
                    "type": "string",
                    "description": "Optional: filter results to items containing this string",
                },
            },
            "required": [],
        },
    },
    {
        "name": "run_cleanup_agent",
        "description": (
            "Finds orphan datasets and reports in Dev workspace. Can optionally delete them."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "auto_delete": {
                    "type": "boolean",
                    "description": "If true, deletes orphans. Default: false (just lists them)",
                }
            },
            "required": [],
        },
    },
    {
        "name": "run_requirements_agent",
        "description": (
            "Gathers codebase context for implementing a new requirement. "
            "Reads CDM-Manager.ps1, deploy-pbi.ps1, WORKFLOW.md, README.md "
            "and returns relevant sections."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "requirement": {
                    "type": "string",
                    "description": "The new requirement in plain English",
                }
            },
            "required": ["requirement"],
        },
    },
    {
        "name": "run_assistant_agent",
        "description": (
            "Answers questions about the CDM-Manager workflow. "
            "Reads WORKFLOW.md, README.md, instructions.md and optionally "
            "checks live PBI state."
        ),
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
        "description": (
            "Runs a git command in the CDM repo. Use this to create branches, "
            "push to ADO, fetch remotes, check status, commit PBIP files, etc. "
            "You can run any git operation that does not require user interaction."
        ),
        "input_schema": {
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
    },
]


# ------------------------------------------------------------------
# Agent dispatcher
# ------------------------------------------------------------------

def dispatch_agent(tool_name: str, tool_input: dict) -> dict:
    """Route a tool call to the appropriate agent function."""
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
        else:
            return {
                "agent": "unknown",
                "status": "FAIL",
                "checks": [],
                "findings": [f"Unknown tool: {tool_name}"],
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
# Git command runner
# ------------------------------------------------------------------

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
# Manager loop
# ------------------------------------------------------------------

def run_manager():
    print("\nCDM-Manager Agent (Claude)")
    print("I work with you step by step — I'll tell you what to do in CDM-Manager,")
    print("wait for you to confirm, then validate the result automatically.")
    print("Type 'exit' to quit.\n")

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
                    if hasattr(block, "text"):
                        print(f"\nAgent: {block.text}\n")
                conversation_history.append(
                    {"role": "assistant", "content": response.content}
                )
                break

            if response.stop_reason == "tool_use":
                conversation_history.append(
                    {"role": "assistant", "content": response.content}
                )
                tool_results = []
                for block in response.content:
                    if block.type == "tool_use":
                        print(f"  [Calling {block.name}...]")
                        result = dispatch_agent(block.name, block.input)
                        tool_results.append(
                            {
                                "type": "tool_result",
                                "tool_use_id": block.id,
                                "content": json.dumps(result, indent=2),
                            }
                        )
                conversation_history.append(
                    {"role": "user", "content": tool_results}
                )
            else:
                # Unexpected stop reason — break out to avoid infinite loop
                print(f"  [Unexpected stop_reason: {response.stop_reason}]")
                break


if __name__ == "__main__":
    run_manager()
