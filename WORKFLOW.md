# CDM-Manager — Complete Workflow Guide

This document is the end-to-end reference for every step of the CDM-Manager process, from first-time machine setup through Production deployment.

---

## Table of Contents

1. [One-Time Machine Setup](#part-1--one-time-machine-setup)
2. [Starting CDM-Manager](#part-2--starting-cdm-manager)
3. [CDM Selection Wizard](#part-3--cdm-selection-wizard)
4. [New Process — Register a Model for the First Time](#part-4--new-process--register-a-model-for-the-first-time)
5. [Existing Process — Creating a Branch](#part-5--existing-process--creating-a-branch)
6. [Making Changes & Iterating](#part-6--making-changes--iterating)
7. [Syncing Service Changes Back to Git](#part-7--syncing-service-changes-back-to-git)
8. [Compiling a Branch to PBIX](#part-8--compiling-a-branch-to-pbix)
9. [Merging to Main](#part-9--merging-to-main)
10. [Deploying to Production](#part-10--deploying-to-production)
11. [Post-Deployment Data Configuration](#step-4--post-deployment-data-configuration)
12. [Quick Reference](#quick-reference)
13. [Data Sources & Cross-Environment Configuration](#data-sources--cross-environment-configuration)
14. [Multi-Contributor Coordination](#multi-contributor-coordination)
15. [Power BI Deployment Pipelines — Strategic Evaluation](#power-bi-deployment-pipelines--strategic-evaluation)

---

## PART 1 — One-Time Machine Setup

*Do this once per computer. Estimated time: 10–15 minutes.*

---

### Step 1 — Unblock the Scripts

Windows marks files downloaded from the internet as untrusted. You must unblock the PowerShell scripts before they will run.

1. Open File Explorer and navigate to the repo folder
2. Right-click **`CDM-Manager.ps1`** → **Properties**
3. At the bottom of the General tab, check **Unblock** → click **OK**
4. Repeat for **`deploy-pbi.ps1`**

> **Alternative:** Run this in PowerShell from the repo folder:
> ```powershell
> Unblock-File -Path ".\CDM-Manager.ps1"
> Unblock-File -Path ".\deploy-pbi.ps1"
> ```

> **If unblocking is blocked by Group Policy:** Use `Launch-CDM-Manager.bat` (double-click it) instead of running the `.ps1` directly. The `.bat` uses `ExecutionPolicy Bypass` scoped to that process only.

---

### Step 2 — Install pbi-tools

`pbi-tools` converts PBIX files into the PBIP folder format that git can track, and compiles PBIP folders back into PBIX. It is required for **Sync from Service**, **Compile Branch to PBIX**, **Update Main Branch**, and the **Create Top Branch and Publish Model** flow.

1. Download the latest release from:
   **https://github.com/pbi-tools/pbi-tools/releases**
   - Download `pbi-tools.zip` (not the Core version)

2. Extract `pbi-tools.exe` and place it in **your system PATH**, or in one of these locations that CDM-Manager checks automatically:
   ```
   [repo root]\Main\pbi-tools.exe
   [repo root]\pbi-tools.exe
   ```

3. Verify it works — open PowerShell and run:
   ```powershell
   pbi-tools info
   ```
   You should see version information. If you see an error, confirm that Power BI Desktop is installed on the machine.

---

### Step 3 — Azure CLI *(Cloud Backup only)*

The **Manual Cloud Backup** and **Include Cloud Backup** features upload PBIX files to Azure Blob Storage. Skip this step if you do not use cloud backup.

1. Download and install from: **https://aka.ms/installazurecliwindows**
2. After install, open a new PowerShell window and run:
   ```powershell
   az login
   ```
3. Sign in with your company account. Credentials are cached for future sessions.

---

### Step 4 — Git and Azure DevOps Access

CDM-Manager manages branches and pushes commits to Azure DevOps automatically.

1. Confirm **git is installed**: run `git --version` in PowerShell
2. CDM-Manager configures the `azure` remote on startup — no manual setup needed
3. On your **first push**, Windows will prompt for ADO credentials:
   - Username: your company email
   - Password: a **Personal Access Token (PAT)** with **Code Read + Write** permissions
   - Generate a PAT in Azure DevOps under **User Settings > Personal Access Tokens**

---

## PART 2 — Starting CDM-Manager

*Do this at the beginning of every working session.*

---

### Step 1 — Launch the App

**Option A (recommended):** Double-click **`Launch-CDM-Manager.bat`** in the repo folder

**Option B:** Right-click `CDM-Manager.ps1` → **Run with PowerShell**

**Option C:** From a PowerShell terminal in the repo folder:
```powershell
.\CDM-Manager.ps1
```

---

### Step 2 — Sign In to Power BI

CDM-Manager uses the OAuth 2.0 Device Code flow — no modules or admin rights required.

1. On startup, a **device code is automatically copied to your clipboard**
2. Your browser opens to `https://microsoft.com/devicelogin`
3. Paste the code (`Ctrl+V`) into the browser and click **Next**
4. Sign in with your company (Okta/Microsoft) credentials
5. Return to CDM-Manager — it detects the completed login and continues automatically

> The token is saved to `%TEMP%\pbi_token.txt` and reused for the session. To re-authenticate, restart CDM-Manager.

---

### Step 3 — App Loads

Once authenticated, CDM-Manager automatically:
- Loads all Power BI workspaces you have access to
- Fetches all Azure DevOps branches and loads them into the Top Branch dropdown
- The log panel on the right confirms each step with timestamps

---

## PART 3 — CDM Selection Wizard

*Do this at the start of any new piece of work. The wizard gates everything downstream.*

CDM Selection uses a two-step wizard. Controls reveal progressively as you answer each step.

---

### Step 1 — Is this a New or Existing change management process?

| Choice | When to use |
|--------|-------------|
| **New Process** | This model has never been registered in the workflow before. CDM-Manager will create a brand-new Top Branch for it. |
| **Existing Process** | The model is already tracked — you are creating a feature or hotfix branch off an existing Top Branch. |

A hint line appears below your selection confirming the meaning of your choice.

---

### Step 2 — Where is the model?

This step appears after Step 1 is answered.

| Choice | When to use |
|--------|-------------|
| **Power BI Service** | The model exists in a Power BI workspace. CDM-Manager will let you pick the workspace and download the PBIX. |
| **Local computer** | You already have the PBIX saved on your machine and don't need to download it. |

Your answers to Steps 1 and 2 determine which controls appear next and which workflow path applies.

---

### What appears after the wizard

| Q1 | Q2 | Controls shown |
|----|----|----------------|
| New Process | Power BI Service | **Production Workspace** dropdown + **Semantic Model** dropdown + **Download Model** button + PBIX path + **Create Top Branch and Publish Model** button |
| New Process | Local computer | **Target Production Workspace** dropdown + **Browse** button + PBIX path + **Create Top Branch and Publish Model** button |
| Existing Process | Power BI Service | **Workspace** dropdown + **Semantic Model** dropdown + **Download Model** button + PBIX path → **Branch Management** section auto-reveals when a model is selected |
| Existing Process | Local computer | **Browse** button + PBIX path → **Branch Management** section reveals when a valid PBIX is confirmed |

> **Branch Management** (Top Branch, Sub-Branch, Create & Deploy New Branch) is shown **only for Existing Process** and only after a model is identified.

---

## PART 4 — New Process — Register a Model for the First Time

*Use this path when a model has never been tracked in the workflow before.*

---

### Step 1 — Answer the Wizard

- Q1: **New Process**
- Q2: **Power BI Service** or **Local computer**

---

### Step 2 — Identify the Model and Target Workspace

**If you chose Power BI Service:**
1. Select the **Production Workspace** where this model lives (the dropdown is labeled "Production Workspace")
2. Select the **Semantic Model** from the dropdown — this is the dataset the report is connected to
3. Click **Download Model**
   - CDM-Manager finds the report connected to that dataset and exports it as a PBIX
   - The PBIX path auto-fills once the download completes

**If you chose Local computer:**
1. Select the **Target Production Workspace** — this is where the model will be published
2. Click **Browse** and navigate to the PBIX file on your machine

> In both cases, **the PBIX file must exist locally before the registration can proceed.**

---

### Step 3 — Click "Create Top Branch and Publish Model"

A confirmation dialog appears listing the workspace name and all 5 steps that will run. Click **Yes** to proceed.

CDM-Manager performs all of these steps automatically in the background:

1. **Fetch** — pulls the latest branch list from Azure DevOps
2. **Guard** — aborts if a branch with this name already exists on the remote
3. **Create isolated worktree** — a temporary git working directory in `%TEMP%`, completely separate from your main repo folder
4. **Orphan branch** — creates `[ModelName]-Main` with no commit history (no inherited files from any other branch)
5. **Extract PBIP** — runs `pbi-tools extract` on the PBIX, placing the `SemanticModel/` and `Report/` folders into the worktree
6. **Stage** — stages only this model's PBIP folders
7. **Commit** — `init: add PBIP for [ModelName]`
8. **Push** — pushes the orphan branch to Azure DevOps
9. **Cleanup** — removes the temp worktree, refreshes remote tracking
10. **Publish** — runs `deploy-pbi.ps1` to publish the model to the selected Production workspace

When complete:
- The **Open Last Deployed Report** button turns green and activates
- The **Top Branch dropdown** in Branch Management refreshes to include the new `[ModelName]-Main` branch
- The log shows a success line with the report URL

> **Branch naming:** The Top Branch name is derived from the PBIX filename. For example, `Sales Report.pbix` → `Sales Report-Main`.

---

## PART 5 — Existing Process — Creating a Branch

*Use this path when the model is already tracked. Do this when starting new development work.*

---

### Step 1 — Answer the Wizard

- Q1: **Existing Process**
- Q2: **Power BI Service** or **Local computer**

---

### Step 2 — Identify the Model

**If you chose Power BI Service:**
1. Select the **Workspace** containing the model
2. Select the **Semantic Model** — Branch Management reveals automatically and the matching Top Branch (`[ModelName]-Main`) is auto-selected

**If you chose Local computer:**
1. Click **Browse** and select the PBIX file
2. Branch Management reveals once a valid `.pbix` is confirmed

> If the PBIX is not on your machine yet, use **Download Model** to fetch it from the service first.

---

### Step 3 — Select the Top Branch

In the **Branch Management** section, confirm the **Top Branch** is correct. It identifies which model your branch will be created under (e.g. `Production-Main`).

If the auto-selection missed or you need a different branch, choose one from the dropdown manually.

---

### Step 4 — Choose Branch Type

| Type | When to use |
|------|-------------|
| **Feature** | New feature, enhancement, or report update |
| **Hotfix** | Urgent fix that needs to go to Production quickly |

---

### Step 5 — Choose Dev Deploy Mode

| Mode | When to use | What happens |
|------|-------------|--------------|
| **New Semantic Model** | You are changing the data model — measures, tables, relationships, or the full report | Uploads the full PBIX to Dev. Creates its own dataset. Changes are isolated in Dev. |
| **Live Connect to Prod Dataset** | You are only changing report visuals, layout, or formatting — no model changes | Clones the "Live Connection Template" in Dev and binds it to the selected Production semantic model. No PBIX upload. Changes to the Production model are instantly reflected. |

> **Live Connect requires the template:** A report named `Live Connection Template` must exist in the Dev workspace. One template supports all CDMs.

---

### Step 6 — Enter a Branch Name

- Short and descriptive
- No spaces — use hyphens (e.g. `My-Feature`, `HF-Fix-01`, `Mass-Balance-Update`)
- CDM-Manager builds the full branch name automatically:
  `feature/[TopBranch]/[Your Name]` or `hotfix/[TopBranch]/[Your Name]`

---

### Step 7 — Click "Create & Deploy New Branch"

CDM-Manager performs all of these steps automatically:

1. Fetches the latest from Azure DevOps
2. Creates the branch from the selected Top Branch (no local branch switch)
3. Pushes the branch to the remote
4. Deploys the report to the Dev workspace (upload or clone, depending on mode)
5. Prints the report URL to the log panel
6. Activates the **Open Last Deployed Report** button

Click **Open Last Deployed Report** to open the deployed report in your browser and confirm it loaded correctly.

---

## PART 6 — Making Changes & Iterating

*Repeat this loop throughout development.*

---

### Step 1 — Edit in Power BI Desktop

Open the PBIX locally and make your changes in Power BI Desktop. Save when done.

Alternatively, you can edit directly in the Power BI Service in the browser — use **Sync from Service** (Part 7) afterward to pull those changes back into git.

---

### Step 2 — Trim Pages for Dev *(important)*

Dev workspace deployments must contain only the **first 4 pages**.

Before deploying:
1. Open `[CDM Name].Report\report.json`
2. Find the `pages` array
3. Remove any pages beyond the first 4
4. Save the file

> This is a governance rule. Full-page reports are for Production only.

---

### Step 3 — Redeploy to Dev

- In CDM-Manager, confirm the correct branch is shown in the header
- Select your **Dev Deploy Mode** (New Semantic Model or Live Connect)
- Click **Deploy to DEV**
- The log shows the deploy progress and the report URL when complete
- Click **Open Last Deployed Report** to verify your changes in the browser

Repeat Steps 1–3 as many times as needed during development.

---

## PART 7 — Syncing Service Changes Back to Git

*Do this if edits were made directly in the Power BI Service (browser), not in Desktop.*

Changes made in the browser are not automatically tracked in git. Use this step to pull them back.

---

### Step 1 — Click "Sync from Service"

*(Located in the Cloud & Git card)*

CDM-Manager resolves the source automatically:

**If you selected a workspace and model in CDM Selection (recommended):**
- Downloads the report connected to your selected dataset from that workspace
- This works regardless of what branch you're on

**Fallback — if no model is selected:**
- Searches the Dev workspace for a report whose name matches your current branch name
- Deploy the branch to Dev first if no match is found

CDM-Manager then performs all of these steps automatically:

1. Downloads the report as a PBIX via the Power BI Export API
2. Runs `pbi-tools extract` to convert the PBIX into PBIP folder format
3. Stages the updated PBIP files
4. Commits the changes to your current branch in Azure DevOps

After this completes, the PBIP files in your branch reflect the current state of the report in the Service.

> **Requires pbi-tools.exe** — see Part 1, Step 2.

---

## PART 8 — Compiling a Branch to PBIX

*Use this to convert the current branch's PBIP files into a local PBIX file.*

This is useful when you have pulled changes from ADO (e.g. someone else committed to your branch) and want to open the updated model in Power BI Desktop or redeploy it without having a local PBIX.

---

### Step 1 — Switch to the Target Branch

Confirm CDM-Manager's header shows the branch whose PBIP files you want to compile.

---

### Step 2 — Click "Compile Branch to PBIX"

*(Located in the Cloud & Git card)*

1. CDM-Manager detects the PBIP model name from the `*.Report` folder in the current branch
2. A **Save As** dialog opens — choose where to save the compiled PBIX file
3. CDM-Manager runs `pbi-tools compile` on the branch's PBIP folder
4. When complete, the PBIX path in CDM Selection auto-fills with the new file path

You can immediately click **Deploy to DEV** or **Deploy to PROD** using the compiled file.

> **Requires pbi-tools.exe** — see Part 1, Step 2.

---

## PART 9 — Merging to Main

*Do this when development is complete and has been reviewed.*

---

### Step 1 — Create a Pull Request in Azure DevOps

1. Open Azure DevOps in your browser
2. Navigate to **Repos > Pull Requests > New Pull Request**
3. Source branch: your `feature/` or `hotfix/` branch
4. Target branch: the appropriate Main branch (e.g. `Production-Main`)
5. Add reviewers per your team's process
6. Complete the merge once approved

---

### Step 2 — Update Main Branch (PBIX to PBIP)

After the merge, the Main branch PBIP files need to reflect the merged state.

1. In CDM-Manager, confirm you are on the Main branch (shown in the header)
2. Ensure your local PBIX is up to date — re-download if needed using **Download Model**
3. Click **Update Main Branch (PBIX to PBIP)**
4. CDM-Manager runs `pbi-tools extract` on the local PBIX and commits the updated PBIP files to Main

---

## PART 10 — Deploying to Production

*Do this after merging to Main. This is the final step.*

---

### Step 1 — Confirm You Are on a Main Branch

CDM-Manager enforces this rule — if you click **Deploy to PROD** while on a feature or hotfix branch, the deploy is blocked and an error is logged. The header shows your current branch at all times.

---

### Step 2 — Click "Deploy to PROD (Main Only)"

1. A confirmation dialog appears — read it and confirm
2. CDM-Manager deploys the report to the Production workspace
3. The report URL is printed to the log panel
4. Click **Open Last Deployed Report** to verify in the browser

---

### Step 3 — Cloud Backup *(optional)*

Archive the PBIX file to Azure Blob Storage for version history.

**Option A — During Dev deploy:**
- Check **Include Cloud Backup** before clicking **Deploy to DEV**

**Option B — After any deploy:**
- Click **Manual Cloud Backup** at any time to archive the current PBIX

> Requires Azure CLI installed and logged in (Part 1, Step 3).

---

### Step 4 — Post-Deployment Data Configuration

> **Important:** Every deployment creates a new dataset in the target workspace. Credentials and scheduled refresh do **not** carry over automatically — they must be configured after each Prod deploy.

CDM-Manager will display a post-deployment checklist in the log panel listing each data source. Complete the following steps in the **Power BI Service**:

1. Open Power BI Service → navigate to the Production workspace
2. Find the newly deployed dataset (same name as the report) → click **...** → **Settings**
3. Expand **Data source credentials** → click **Edit credentials** for each source listed
4. Set the correct authentication method (e.g., OAuth2, Basic, or Service Account) and save
5. If using an on-premises gateway: expand **Gateway connection** and bind the correct gateway
6. Expand **Scheduled refresh** → toggle it **On** → configure the schedule → **Apply**
7. Click **Refresh now** to verify the dataset refreshes without errors
8. Confirm data freshness in the report before notifying stakeholders

> If the dataset has already been deployed before and ownership was taken, credentials from the previous deployment may already be configured — verify rather than re-enter.

---

### Step 5 — Branch Cleanup *(optional)*

After a successful Production deployment, CDM-Manager will offer to delete the remote feature or hotfix branch from Azure DevOps. Click **Yes** to keep the branch list clean. The **Main branch is never deleted** by this operation.

---

## Quick Reference

### Button Reference

| Button | Card | When to use |
|--------|------|-------------|
| **Download Model** | CDM Selection | Download the latest PBIX from a Power BI workspace |
| **Browse** | CDM Selection | Point to an existing local PBIX |
| **Create Top Branch and Publish Model** | CDM Selection | New Process only — create the Top Branch and publish the model to Production |
| **Switch to Selected Branch** | Branch Management | Check out an existing sub-branch locally |
| **Create & Deploy New Branch** | Branch Management | Existing Process — create a feature or hotfix branch and deploy it to Dev |
| **Deploy to DEV** | Manual Operations | Redeploy current PBIX to the Dev workspace during iteration |
| **Deploy to PROD (Main Only)** | Manual Operations | Deploy the final report to Production (Main branches only) |
| **Open Last Deployed Report** | Manual Operations | Open the most recently deployed report in the browser |
| **Sync from Service** | Cloud & Git | Pull browser edits from the Power BI Service back into the current branch |
| **Compile Branch to PBIX** | Cloud & Git | Convert the current branch's PBIP files into a local PBIX |
| **Update Main Branch (PBIX to PBIP)** | Cloud & Git | After merging to Main, commit the merged PBIX as PBIP files |
| **Create Main Branch (New Model)** | Cloud & Git | Same as "Create Top Branch and Publish Model" — direct access for advanced users |
| **Manual Cloud Backup** | Cloud & Git | Archive the current PBIX to Azure Blob Storage |

---

### Branch Naming Convention

| Type | Format | Example |
|------|--------|---------|
| Top Branch (Main) | `[ModelName]-Main` | `Production-Main`, `Sales Report-Main` |
| Feature | `feature/[TopBranch]/[Name]` | `feature/Production-Main/My-Feature` |
| Hotfix | `hotfix/[TopBranch]/[Name]` | `hotfix/Production-Main/HF-Fix-01` |

---

### Workflow Path Decision

```
Starting a new piece of work?
|
+-- New model (never been in the workflow before)?
|     --> Part 4: New Process
|         Q2: Service (have workspace) or Local (have PBIX)
|         Action: Create Top Branch and Publish Model
|
+-- Existing model (already has a Top Branch)?
      --> Part 5: Existing Process
          Q2: Service (download latest) or Local (browse to PBIX)
          Action: Create & Deploy New Branch
```

---

### Dev Deploy Mode Decision

```
Are you changing the data model (measures, tables, relationships)?
  YES --> New Semantic Model
  NO  --> Live Connect to Prod Dataset
```

---

### Troubleshooting

| Problem | Fix |
|---------|-----|
| Script blocked — "not digitally signed" | Right-click `.ps1` → Properties → Unblock. Or use `Launch-CDM-Manager.bat` |
| "No Power BI token found" | Restart CDM-Manager and complete the browser login |
| Branch Management section not visible | Only shown for Existing Process after a model is selected — check Q1 answer |
| "PBIX not found" when clicking Create Top Branch | You must download or browse to the PBIX first — the file must exist locally |
| Top Branch dropdown is grayed out | Only unlocks after a valid PBIX is confirmed (Existing Process path) |
| "No Live Connection Template found" | Publish the Live Connection Template report to the Dev workspace |
| "pbi-tools.exe not found" | Place `pbi-tools.exe` in the `Main\` folder or add it to your system PATH (Part 1, Step 2) |
| Prompted for credentials on git push | Enter company email + Azure DevOps PAT (Part 1, Step 4) |
| SmartScreen blocks the `.bat` file | Right-click `.bat` → Properties → Unblock, or click More Info → Run Anyway |
| "Sync from Service" finds no report | Select a workspace and model in CDM Selection first, or deploy the branch to Dev and try again |
| Compile Branch to PBIX finds no PBIP folder | Switch to a branch that has PBIP files (has been synced or updated via pbi-tools) |
| "An operation is already running" warning | A background download or sync is in progress — wait for the log to show completion before clicking again |
| Dev deploy times out on large PBIX | Call `deploy-pbi.ps1` directly with `-ImportTimeoutSeconds 300` to extend the timeout for files over 500 MB |

---

## Data Sources & Cross-Environment Configuration

Power BI data source connection strings are **embedded in the PBIX** and do not automatically update between environments. Follow these practices to manage environment-specific connections.

### Using Power BI Parameters for Environment Switching

1. In Power BI Desktop, open **Home → Transform data → Manage parameters**
2. Create a parameter named `ServerName` (or `DatabaseName`, `Environment`, etc.)
3. Reference the parameter in each query instead of hardcoding the connection string
4. After deploying, in the Power BI Service go to **Dataset Settings → Parameters** and set the correct value for that environment

> This eliminates the need to manually reconfigure data sources after each deployment — only the parameter value differs between Dev and Prod.

### Per-Environment Credential Configuration

Even with parameters, credentials must be set after each deployment to a new workspace:

| Environment | Typical action |
|-------------|---------------|
| **Dev** | Use personal OAuth or a shared service account; data can point to UAT/staging |
| **Prod** | Use a service account with Production database access; configured by the data engineering team |

If you receive a "Data source credentials are missing" error when opening a report, go to **Dataset Settings → Data source credentials** and re-enter credentials for all listed sources.

### Gateway Requirements

On-premises data sources (SQL Server, Oracle, SSAS, etc.) require a **Power BI On-Premises Data Gateway**:

1. Ensure the gateway is installed and registered in the Power BI Service
2. After deploying, go to **Dataset Settings → Gateway connection**
3. Select the gateway cluster and map each data source to the correct gateway data source
4. Test the connection before enabling scheduled refresh

---

## Multi-Contributor Coordination

When multiple people work on the same model, follow these conventions to avoid conflicts.

### One Active Branch per Model

Only one feature or hotfix branch should be actively worked on per model at a time. Parallel branches that modify the same TMDL files (measures, tables, relationships) will produce merge conflicts in ADO that require manual resolution.

**Convention:** Before creating a new branch, check ADO to confirm no existing feature branch for the same model is in progress. Communicate with your team via Teams or the ADO work item linked to the PR.

### Coordinating Power BI Desktop Access

Power BI Desktop locks the `.pbix` file while it is open. If two users need the same file:
- Only the person actively making changes should have the PBIX open in Desktop
- Others should work from the PBIP text files in git (read-only review or measure editing in a text editor)
- The active user should commit and push their branch before passing the PBIX to the next person

### Merge Conflict Resolution for TMDL Files

TMDL files (`.tmdl`) are plain text and can be diff-merged by git. If a merge conflict occurs in ADO:

1. Check out both branches locally
2. Open the conflicting `.tmdl` file in a text editor — conflicts are marked with standard `<<<<<<`/`======`/`>>>>>>` markers
3. Resolve the conflict by keeping the correct measure/table definition
4. Stage the resolved file and push — ADO will mark the conflict as resolved
5. Compile the resolved PBIP back to PBIX using **Compile Branch to PBIX** and test before merging

> DAX measure conflicts are the most common. Keep DAX edits small and focused per branch to minimize overlap.

### Checking Who Has a Branch Active

```powershell
# List all remote branches and their last commit author
git -C $SCRIPT_DIR fetch azure
git -C $SCRIPT_DIR for-each-ref --format="%(refname:short) | %(authorname) | %(committerdate:short)" refs/remotes/azure/
```

This shows each branch, who last committed to it, and when — useful for identifying stale or active branches before starting new work.

---

## Power BI Deployment Pipelines — Strategic Evaluation

Microsoft's native **Deployment Pipelines** feature is an alternative to the Import API approach used by CDM-Manager. This section documents when to consider migrating.

### What Deployment Pipelines Provide

| Capability | Deployment Pipelines | CDM-Manager (current) |
|-----------|---------------------|----------------------|
| Dev → Test → Prod promotion | Built-in UI + API | Manual per deploy |
| Dataset rebinding across stages | Automatic | Manual credential config |
| Incremental delta (only changed items) | Yes (semantic model changes) | Full PBIX upload each time |
| Selective deploy (report only, model only) | Yes | Not supported |
| Rollback to previous stage | Not native (use backup) | Azure Blob versioning |
| Git/PBIP integration | Indirect (via Fabric Git) | Direct (this workflow) |
| Custom automation hooks | Pipelines REST API | Full control (deploy-pbi.ps1) |

### Licensing Requirements

Deployment Pipelines require **one** of:
- Power BI Premium Per User (PPU) — `$20/user/month`
- Power BI Premium capacity (P1 or higher)
- Microsoft Fabric capacity (F64 or higher)

Standard Pro licenses do **not** include Deployment Pipelines.

### When to Prefer Deployment Pipelines

Consider migrating when:
1. The organization already has PPU or Premium capacity
2. Multiple datasets need coordinated promotion (Pipelines promotes all artifacts atomically)
3. The report-only vs model-only selective deploy capability is needed
4. The team wants the built-in Service UI rather than a PowerShell tool

### What Would Change in CDM-Manager

A Deployment Pipelines migration would require:
1. Create a 3-stage pipeline (Dev/Test/Prod) per model in the Power BI Service via the REST API (`POST /pipelines`)
2. Assign workspaces to stages (`POST /pipelines/{pipelineId}/stages/{stageOrder}/assignWorkspace`)
3. Replace `Invoke-PBIUpload` / `Wait-PBIImport` in `deploy-pbi.ps1` with `POST /pipelines/{pipelineId}/deploy`
4. The PBIP → PBIX compile step (pbi-tools) remains unchanged
5. Credential configuration per stage is handled by the pipeline's stage settings

### Current Recommendation

**Remain on the Import API approach** until Premium licensing is confirmed. The current workflow is fully functional, gives complete control over deployment timing, and does not require Premium. Revisit this decision if the organization adopts Fabric or PPU licensing.

