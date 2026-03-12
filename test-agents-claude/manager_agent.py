"""
manager_agent.py (Claude version) - CDM-Manager Test & Debug Orchestrator.

Uses the Anthropic Python SDK (claude-sonnet-4-6) with tool use to
orchestrate 7 specialized sub-agents.

Run:
    python manager_agent.py
"""

import json
import os
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

# ------------------------------------------------------------------
# Config
# ------------------------------------------------------------------
CLAUDE_MODEL = os.getenv("CLAUDE_MODEL", "claude-sonnet-4-6")

client = anthropic.Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))

# ------------------------------------------------------------------
# System prompt
# ------------------------------------------------------------------
SYSTEM_PROMPT = """\
You are the CDM-Manager Test & Debug Orchestrator. You help test, debug, and improve the CDM-Manager Power BI enterprise analytics workflow.

The workflow involves:
- Authenticating to Power BI Service via OAuth device code
- Selecting a CDM (semantic model) from Dev/Prod workspaces
- Creating feature/hotfix branches in Azure DevOps
- Deploying reports to Dev workspace (New Semantic Model or Live Connect mode)
- Live Connect mode clones a template report and binds it to the Production dataset
- New Semantic Model mode uploads a full PBIX with its own dataset
- Syncing changes from Service back to git via pbi-tools
- Merging to Main and deploying to Production
- Dev deployments are limited to 4 pages max

You have 7 specialized agents available as tools. Use them to gather data, then reason about the results and provide clear, actionable responses.

When testing: call auth first, then the relevant agent for the operation being tested.
When debugging: call debug_agent to get a full workspace inventory, then analyze.
When asked about requirements: call requirements_agent to gather codebase context, then provide an implementation plan.
When answering questions: call assistant_agent to gather documentation context, then answer.
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
# Manager loop
# ------------------------------------------------------------------

def run_manager():
    print("\nCDM-Manager Agent (Claude)")
    print("Type your request or question. Type 'exit' to quit.\n")

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
