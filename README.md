# Production CDM - Power BI Enterprise Analytics

This repository contains the metadata, report definitions, and deployment automation for the **Production Common Data Model (CDM)**. It leverages the Power BI Project (PBIP) format to enable professional software engineering workflows, including version control, branching, and CI/CD.

## Repository Structure

- **`Production CDM.SemanticModel/`** — TMDL-based definitions for the semantic model (tables, measures, relationships). Source of truth for the data model.
- **`Production CDM.Report/`** — `report.json` and visual definitions. Source of truth for the report layout.
- **`CDM-Manager.ps1`** — WPF desktop GUI for managing branches, deploying to Power BI Service, and syncing with Azure DevOps. This is the primary tool for day-to-day workflow.
- **`deploy-pbi.ps1`** — PowerShell deployment script called by CDM-Manager. Uploads PBIX to Power BI Service via REST API.
- **`azure-pipelines.yml`** — CI/CD pipeline definition for automated deployments via Azure DevOps.
- **`instructions.md`** — Deployment rules, environment IDs, and one-time Power BI module setup guide.
- **`CLI-GUIDE.md`** — Reference for manual CLI operations.

## Branch Naming Convention

All branches follow a three-part hierarchy to organize work by CDM:

| Type | Format | Example |
|------|--------|---------|
| Feature | `feature/[TopBranch]/[Name]` | `feature/Production-Main/My-Feature` |
| Hotfix | `hotfix/[TopBranch]/[Name]` | `hotfix/Production-Main/Critical-Fix` |

The **Top Branch** (e.g. `Production-Main`, `main`) identifies which CDM the work belongs to. CDM-Manager enforces this convention automatically when creating branches.

## CDM-Manager Workflow (Recommended)

`CDM-Manager.ps1` is the primary interface. Launch it from the repository root:

```powershell
.\CDM-Manager.ps1
```

**On startup it automatically:**
1. Authenticates to Power BI Service via browser (code auto-copied to clipboard — just Ctrl+V)
2. Connects to Azure DevOps and loads all branches
3. Populates Top Branch and Sub-Branch dropdowns

**Creating a new branch:**
1. Select the **Top Branch** (CDM) you are working under
2. Choose **Feature** or **Hotfix**
3. Enter a name and click **Create & Deploy New Branch**

This creates the branch in ADO, pushes it, and deploys the current PBIX to the Dev workspace — all in one step.

**One-time setup per machine** — see `instructions.md` for the Power BI module install steps (required before first deploy).

## Manual Deployment

For direct script use without the GUI:

```powershell
.\deploy-pbi.ps1 -TargetEnv Dev -BranchName "MyFeature" -PbixPath ".\Production CDM.pbix"
```

> Note: Requires a valid Power BI token at `$env:TEMP\pbi_token.txt`. Launch CDM-Manager first to generate it, or run the OAuth device code flow manually.

## Environment Configuration

| Environment | Workspace ID |
|-------------|-------------|
| Dev | `2696b15d-427e-437b-ba5a-ca8d4fb188dd` |
| Prod | `c05c8a73-79ee-4b7f-b798-831b5c260f1b` |
| Prod Dataset ID | `10ad1784-d53f-4877-b9f0-f77641efbff4` |

## Governance

- **Source of Truth**: Text-based PBIP folder definitions (`.SemanticModel/`, `.Report/`)
- **Binary Files**: `.pbix` files are excluded from version control to prevent merge conflicts
- **Page Limit**: All Dev workspace deployments must contain only the first 4 pages (see `instructions.md`)
- **Production Deployments**: Only allowed from `Main` branches via CDM-Manager safety check
