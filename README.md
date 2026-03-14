# Power BI Workflow Manager

This repository contains the metadata, report definitions, and deployment automation for Power BI models managed under the enterprise change management workflow. It uses the Power BI Project (PBIP) format to enable version control, branching, and automated deployment through Azure DevOps.

Each tracked model has its own Top Branch (`[ModelName]-Main`) containing that model's PBIP folders. Multiple models coexist in the same repository under separate branches.

---

## Repository Structure

```
Main/
├── CDM-Manager.ps1          # WPF desktop GUI — primary tool for all day-to-day work
├── deploy-pbi.ps1           # Deployment engine called by CDM-Manager (REST API)
├── azure-pipelines.yml      # CI/CD pipeline definition for Azure DevOps
├── WORKFLOW.md              # Complete end-to-end workflow guide
├── CLI-GUIDE.md             # Reference for manual git/CLI operations
├── instructions.md          # Live Connection Template setup and governance rules
├── agents/                  # AI agent definitions for the pbi-workflow-orchestrator system
└── PBI-Tools/
    └── pbi-tools.exe        # PBIP extract/compile tool (or install to PATH)
```

Each model branch also contains:
```
[ModelName].SemanticModel/   # TMDL definitions — tables, measures, relationships
[ModelName].Report/          # report.json and visual definitions
```

> **PBIX files are never committed to git.** They are too large for version control. Only the extracted PBIP text files are tracked. PBIX files are stored in Azure Blob Storage for versioning.

---

## Quick Start

### Prerequisites (one time per machine)

1. **Unblock the scripts** — right-click `CDM-Manager.ps1` → Properties → Unblock (or use `Launch-CDM-Manager.bat`)
2. **Install pbi-tools** — download from [github.com/pbi-tools/pbi-tools/releases](https://github.com/pbi-tools/pbi-tools/releases), place `pbi-tools.exe` in `Main\` or add to PATH
3. **Git + ADO access** — git must be installed; on first push, Windows prompts for your ADO PAT (Code Read + Write)
4. **Azure CLI** *(optional)* — only needed for cloud backup features

### Launch

```powershell
# Recommended (bypasses execution policy prompts)
Launch-CDM-Manager.bat

# Or from PowerShell
.\CDM-Manager.ps1
```

On startup, CDM-Manager automatically authenticates to Power BI via browser OAuth device code flow (code is auto-copied to clipboard), loads all workspaces, and fetches all ADO branches.

---

## Workflow Overview

CDM-Manager uses a two-step wizard to route you into the correct workflow path.

### Step 1 — CDM Selection Wizard

**Q1: New or Existing process?**
- **New Process** — the model has never been registered in the workflow. CDM-Manager will create its Top Branch.
- **Existing Process** — the model already has a Top Branch. You are creating a feature or hotfix branch.

**Q2: Where is the model?**
- **Power BI Service** — select workspace + semantic model from dropdowns; optionally download the PBIX
- **Local computer** — browse to a PBIX already saved on your machine

### Path A — New Process (Register a Model)

1. Answer Q1 = New Process, Q2 = Service or Local
2. Select the **Production Workspace** (the workspace where this model will be published)
3. Select or browse to the PBIX — **Download Model** is available for the Service path
4. Click **Create Top Branch and Publish Model**

CDM-Manager will automatically:
- Fetch ADO, guard against duplicate branch names
- Create an isolated git worktree in `%TEMP%`
- Create a clean orphan branch `[ModelName]-Main` (no inherited history)
- Extract PBIP files from the PBIX via `pbi-tools`
- Commit and push the branch to ADO
- Publish the model to the selected Production workspace via `deploy-pbi.ps1`

### Path B — Existing Process (Feature / Hotfix Work)

1. Answer Q1 = Existing Process, Q2 = Service or Local
2. Select workspace + model (Service) or browse (Local) — Branch Management reveals automatically
3. The matching Top Branch (`[ModelName]-Main`) is auto-selected
4. Choose **Feature** or **Hotfix**, select **Dev Deploy Mode**, enter a name
5. Click **Create & Deploy New Branch**

CDM-Manager creates the branch in ADO, pushes it, and deploys to the Dev workspace in one step.

**Iterate:**
- Edit in Power BI Desktop → click **Deploy to DEV** → verify with **Open Last Deployed Report**
- If edits were made in the browser: click **Sync from Service** to pull changes back into git
- If you need a local PBIX from the branch's current PBIP state: click **Compile Branch to PBIX**

**Merge and publish:**
- Create a Pull Request in ADO, merge to `[ModelName]-Main`
- Click **Update Main Branch (PBIX to PBIP)** to commit the merged PBIP to Main
- Click **Deploy to PROD (Main Only)** — safety-gated, requires confirmation

---

## Button Reference

### CDM Selection

| Button | When to use |
|--------|-------------|
| **Download Model** | Download the latest PBIX from a Power BI workspace |
| **Browse** | Point to an existing local PBIX (Local path) |
| **Create Top Branch and Publish Model** | New Process — create the Top Branch and publish to Production |

### Branch Management *(Existing Process only)*

| Button | When to use |
|--------|-------------|
| **Switch to Selected Branch** | Check out an existing sub-branch locally |
| **Create & Deploy New Branch** | Create a feature or hotfix branch and deploy it to Dev |

### Manual Operations

| Button | When to use |
|--------|-------------|
| **Deploy to DEV** | Redeploy current PBIX to Dev workspace during iteration |
| **Deploy to PROD (Main Only)** | Final deploy to Production — Main branches only |
| **Open Last Deployed Report** | Open the most recently deployed report in the browser |

### Cloud & Git

| Button | When to use |
|--------|-------------|
| **Sync from Service** | Pull browser edits from the Power BI Service into the current branch |
| **Compile Branch to PBIX** | Convert current branch PBIP files into a local PBIX |
| **Update Main Branch (PBIX to PBIP)** | After merging to Main, commit PBIP files from the merged PBIX |
| **Create Main Branch (New Model)** | Same as "Create Top Branch and Publish Model" — direct access |
| **Manual Cloud Backup** | Archive the current PBIX to Azure Blob Storage |

---

## Branch Naming Convention

| Type | Format | Example |
|------|--------|---------|
| Top Branch | `[ModelName]-Main` | `Production-Main`, `Sales Report-Main` |
| Feature | `feature/[TopBranch]/[Name]` | `feature/Production-Main/My-Feature` |
| Hotfix | `hotfix/[TopBranch]/[Name]` | `hotfix/Production-Main/HF-Fix-01` |

CDM-Manager enforces this convention automatically. The Top Branch name is derived from the PBIX filename.

---

## Dev Deploy Modes

| Mode | Use when | What happens |
|------|----------|--------------|
| **New Semantic Model** | Changing measures, tables, or relationships | Full PBIX upload — isolated dataset in Dev |
| **Live Connect to Prod Dataset** | Changing report visuals or layout only | Clones "Live Connection Template" in Dev, binds to Production dataset — no upload |

> A report named **"Live Connection Template"** must exist in the Dev workspace. See `instructions.md` for setup.

---

## Environment Configuration

| Environment | Workspace ID |
|-------------|-------------|
| Dev | `2696b15d-427e-437b-ba5a-ca8d4fb188dd` |
| Prod (default) | `c05c8a73-79ee-4b7f-b798-831b5c260f1b` |

Workspace and dataset IDs are selected dynamically at runtime. The Production workspace for a new model is chosen in the CDM Selection wizard.

---

## Governance

| Rule | Detail |
|------|--------|
| **Source of truth** | PBIP text files (`.SemanticModel/`, `.Report/`) in git |
| **PBIX files** | Never committed — archived to Azure Blob Storage |
| **Dev page limit** | Deployments to Dev must contain only the first 4 pages |
| **Production gate** | `Deploy to PROD` is blocked on non-Main branches |
| **pbi-tools** | Required on each machine — install to PATH or place in `Main\` |

For the complete step-by-step workflow, see **[WORKFLOW.md](WORKFLOW.md)**.
