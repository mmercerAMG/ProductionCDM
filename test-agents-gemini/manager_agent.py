"""
manager_agent.py (Gemini version) - CDM-Manager Test & Debug Orchestrator.

Uses the Vertex AI Python SDK (gemini-2.0-flash) with function calling to
orchestrate 7 specialized sub-agents.

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
# System prompt (identical to Claude version)
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
    ]
)

model = GenerativeModel(
    model_name=GEMINI_MODEL,
    system_instruction=SYSTEM_PROMPT,
    tools=[_all_tools],
)


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
    print("Type your request or question. Type 'exit' to quit.\n")

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
            finish_name = candidate.finish_reason.name

            # Check if any part in this response contains a function call
            has_function_call = any(
                part.function_call.name  # non-empty name means a real call
                for part in candidate.content.parts
                if hasattr(part, "function_call") and part.function_call
            )

            if not has_function_call:
                # No more function calls — print any text parts and break
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
                # Safety: no actual calls were extracted — print text and break
                for part in candidate.content.parts:
                    if hasattr(part, "text") and part.text:
                        print(f"\nAgent: {part.text}\n")
                break

            response = chat.send_message(function_responses)


if __name__ == "__main__":
    run_manager()
