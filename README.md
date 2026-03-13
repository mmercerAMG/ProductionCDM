# Production CDM - Power BI Enterprise Analytics

This repository contains the metadata, report definitions, and deployment automation for the **Production Common Data Model (CDM)**. It leverages the Power BI Project (PBIP) format to enable professional software engineering workflows, including version control, branching, and CI/CD.

## Repository Structure

- **`Production CDM.SemanticModel/`** — TMDL-based definitions for the semantic model (tables, measures, relationships). Source of truth for the data model.
- **`Production CDM.Report/`** — `report.json` and visual definitions. Source of truth for the report layout.
- **`CDM-Manager.ps1`** — WPF desktop GUI (v2.0) for managing branches, deploying to Power BI Service, and syncing with Azure DevOps. Primary tool for day-to-day workflow.
- **`deploy-pbi.ps1`** — PowerShell deployment script called by CDM-Manager. Handles PBIX upload and Live Connect cloning via Power BI REST API.
- **`azure-pipelines.yml`** — CI/CD pipeline definition for automated deployments via Azure DevOps.
- **`instructions.md`** — One-time machine setup guide and deployment rules.
- **`CLI-GUIDE.md`** — Reference for manual CLI operations.

## Branch Naming Convention

All branches follow a three-part hierarchy to organize work by CDM:

| Type | Format | Example |
|------|--------|---------|
| Feature | `feature/[TopBranch]/[Name]` | `feature/Production-Main/My-Feature` |
| Hotfix | `hotfix/[TopBranch]/[Name]` | `hotfix/Production-Main/Critical-Fix` |

The **Top Branch** (e.g. `Production-Main`) identifies which CDM the work belongs to. CDM-Manager enforces this convention automatically.

## CDM-Manager v2.0 Workflow (Recommended)

`CDM-Manager.ps1` is the primary interface. Launch it from the repository root:

```powershell
.\CDM-Manager.ps1
```

> **First time on a new machine?** Windows may block the script with _"not digitally signed"_. Use the included launcher instead:
> ```
> Double-click: Launch-CDM-Manager.bat
> ```
> Or run once in PowerShell to unblock for your user account:
> ```powershell
> Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```

**On startup it automatically:**
1. Authenticates to Power BI Service via browser OAuth device code flow (code auto-copied to clipboard)
2. Loads all Power BI workspaces you have access to
3. Connects to Azure DevOps and loads all branches

### Step-by-step workflow

**1. Select your CDM**
- Choose the **Workspace** containing the CDM you are working on
- Choose the **Semantic Model (CDM)** from the dropdown — this auto-fills the local PBIX path
- If you need the latest version locally, click **Download CDM** to export it from the Service

**2. Select a PBIX (required before branching)**
- The Top Branch dropdown is locked until a local PBIX file is confirmed
- Either download the CDM (above) or click **Browse** to point to an existing local PBIX
- Once a valid PBIX is selected, the Top Branch dropdown unlocks

**3. Create a branch**
- Select the **Top Branch** (CDM) you are working under
- Choose **Feature** or **Hotfix**
- Choose **Dev Deploy Mode**:
  - **New Semantic Model** — uploads full PBIX with its own dataset in Dev
  - **Live Connect to Prod Dataset** — clones the Live Connection Template in Dev, bound to the selected Production semantic model (no PBIX upload)
- Enter a name and click **Create & Deploy New Branch**

This creates the branch in ADO, pushes it, and deploys to the Dev workspace in one step.

**4. Make changes**
- Work in Power BI Desktop against the PBIP files in the repo folder
- Re-deploy to Dev using **Deploy to DEV** as needed
- After deploy, click **Open Last Deployed Report** to verify changes in the browser

**5. Sync changes from Service back to branch (if edits were made in browser)**
- Click **Sync Branch from Dev Report** (Cloud & Git card)
- Downloads the Dev report, extracts PBIP files via pbi-tools, and commits to the current branch

**6. Merge and publish to Production**
- After merging to the Main branch, switch to the Main branch
- Click **Deploy to PROD (Main Only)** — requires confirmation
- Optionally check **Include Cloud Backup** to archive the PBIX to Azure Blob Storage

## Cloud & Git Operations

| Button | Action |
|--------|--------|
| **Sync Branch from Dev Report** | Downloads current branch's Dev report, extracts to PBIP, commits to branch |
| **Update Main Branch (PBIX to PBIP)** | Extracts a local PBIX to PBIP files and commits to the current Main branch |
| **Sync to GitHub** | Pushes workflow scripts to the GitHub mirror |
| **Manual Cloud Backup** | Uploads the local PBIX to Azure Blob Storage |

## Live Connection Template

A report named **"Live Connection Template"** must exist in the Dev workspace. This is a blank report published from Power BI Desktop connected to the Production semantic model via **Get Data > Power BI Datasets** (no local data model). CDM-Manager clones this template for every Live Connect branch deploy and rebinds the clone to the appropriate semantic model.

**Template Report ID (Dev workspace):** `3c564eb5-8c02-40bb-a5c2-f20695874b8c`

## Environment Configuration

| Environment | Workspace ID |
|-------------|-------------|
| Dev | `2696b15d-427e-437b-ba5a-ca8d4fb188dd` |
| Prod | `c05c8a73-79ee-4b7f-b798-831b5c260f1b` |
| Prod Dataset ID (Production CDM) | `10ad1784-d53f-4877-b9f0-f77641efbff4` |

Workspace and dataset IDs for all 6 CDMs are selected dynamically at runtime via the CDM Selection dropdowns. The Dev workspace ID is the shared environment for all CDMs.

## Governance

- **Source of Truth**: Text-based PBIP folder definitions (`.SemanticModel/`, `.Report/`)
- **Binary Files**: `.pbix` files are excluded from version control — stored in Azure Blob for versioning
- **Page Limit**: All Dev workspace deployments must contain only the first 4 pages (see `instructions.md`)
- **Production Deployments**: Only allowed from `Main` branches via CDM-Manager safety check
- **pbi-tools**: Required on each machine for PBIX-to-PBIP extraction (see `instructions.md`)
