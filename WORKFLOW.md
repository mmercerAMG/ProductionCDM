# CDM-Manager — Complete Workflow Guide

This document is the end-to-end reference for every step of the CDM-Manager process, from first-time machine setup through Production deployment.

---

## Table of Contents

1. [One-Time Machine Setup](#part-1--one-time-machine-setup)
2. [Starting CDM-Manager](#part-2--starting-cdm-manager)
3. [Selecting Your CDM](#part-3--selecting-your-cdm)
4. [Creating a Branch](#part-4--creating-a-branch)
5. [Making Changes & Iterating](#part-5--making-changes--iterating)
6. [Syncing Service Changes Back to Git](#part-6--syncing-service-changes-back-to-git)
7. [Merging to Main](#part-7--merging-to-main)
8. [Deploying to Production](#part-8--deploying-to-production)
9. [Quick Reference](#quick-reference)

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

`pbi-tools` converts PBIX files into the PBIP folder format that git can track. It is required for **Sync Branch from Dev Report** and **Update Main Branch**.

1. Download the latest release from:
   **https://github.com/pbi-tools/pbi-tools/releases**
   - Download `pbi-tools.zip` (not the Core version)

2. Extract `pbi-tools.exe` and place it in the repo folder:
   ```
   [repo root]\pbi-tools.exe
   ```
   CDM-Manager looks for it there first, then checks your PATH and common install locations.

3. Verify it works — open PowerShell in the repo folder and run:
   ```powershell
   .\pbi-tools.exe info
   ```
   You should see version information. If you see an error, check that Power BI Desktop is installed on the machine.

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
- Loads all Power BI workspaces you have access to into the Workspace dropdown
- Fetches all Azure DevOps branches and loads them into the Top Branch dropdown
- The log panel on the right confirms each step with timestamps

---

## PART 3 — Selecting Your CDM

*Do this at the start of any new piece of work.*

---

### Step 1 — Choose a Workspace

In the **CDM Selection** section, choose the Power BI workspace that contains the CDM you are working on (e.g. `3011 - AMG - Production`).

---

### Step 2 — Choose a Semantic Model (CDM)

Select the specific CDM from the **Semantic Model** dropdown. There are 6 CDMs available. Once selected:
- The local PBIX path auto-fills if a matching file already exists locally
- The workspace and dataset IDs are captured for all subsequent API calls

---

### Step 3 — Get the Latest PBIX

You need a local PBIX before you can create a branch. Choose one of these options:

**Option A — Download CDM** *(recommended to get latest)*
1. Click **Download CDM**
2. A folder picker opens — choose where to save the file
3. CDM-Manager exports the PBIX from the Power BI Service via the Export API
4. The file saves as `[CDM Name].pbix`
5. The Top Branch dropdown unlocks automatically when the download completes

**Option B — Browse to existing PBIX**
1. Click **Browse**
2. Navigate to a PBIX file already saved on your machine
3. The Top Branch dropdown unlocks once a valid `.pbix` path is confirmed

> **Note:** PBIX files are never committed to git — they are too large. Only the extracted PBIP files (`.SemanticModel/` and `.Report/` folders) are tracked in version control.

---

## PART 4 — Creating a Branch

*Do this when starting new development work.*

---

### Step 1 — Select Top Branch

Choose the **Top Branch** that your work will branch off of. This identifies which CDM the branch belongs to (e.g. `Production-Main`).

The Top Branch dropdown is locked until a valid local PBIX is confirmed (see Part 3).

---

### Step 2 — Choose Branch Type

| Type | When to use |
|------|-------------|
| **Feature** | New feature, enhancement, or report update |
| **Hotfix** | Urgent fix that needs to go to Production quickly |

---

### Step 3 — Choose Dev Deploy Mode

This determines how the report is deployed to the Dev workspace when the branch is created.

| Mode | When to use | What happens |
|------|-------------|--------------|
| **New Semantic Model** | You are changing the data model — measures, tables, relationships, or the full report | Uploads the full PBIX to Dev. Creates its own dataset. Changes are isolated in Dev. |
| **Live Connect to Prod Dataset** | You are only changing report visuals, layout, or formatting — no model changes | Clones the "Live Connection Template" in Dev and binds it to the selected Production semantic model. No PBIX upload. Changes to the Production model are instantly reflected. |

> **Live Connect requires the template:** A report named `Live Connection Template` must exist in the Dev workspace. See `instructions.md` for setup details. One template supports all 6 CDMs.

---

### Step 4 — Enter a Branch Name

- Short and descriptive
- No spaces — use hyphens (e.g. `My-Feature`, `HF-Fix-01`, `Mass-Balance-Update`)
- CDM-Manager builds the full branch name automatically:
  `feature/[TopBranch]/[Your Name]`

---

### Step 5 — Click "Create & Deploy New Branch"

CDM-Manager performs all of these steps automatically:

1. Creates the branch in Azure DevOps from the selected Top Branch
2. Pushes the branch to the remote
3. Deploys the report to the Dev workspace (upload or clone, depending on mode)
4. Prints the report URL to the log panel
5. Activates the **Open Last Deployed Report** button

Click **Open Last Deployed Report** to open the deployed report in your browser and confirm it loaded correctly.

---

## PART 5 — Making Changes & Iterating

*Repeat this loop throughout development.*

---

### Step 1 — Edit in Power BI Desktop

- Open the PBIP folder in Power BI Desktop
- The `.SemanticModel/` folder contains the data model (measures, tables, relationships)
- The `.Report/` folder contains the report layout (`report.json`)
- Make your changes and **Save**

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

- In CDM-Manager, confirm the correct branch is shown
- Click **Deploy to DEV**
- The log shows the deploy progress and the report URL when complete
- Click **Open Last Deployed Report** to verify your changes in the browser

Repeat Steps 1–3 as many times as needed during development.

---

## PART 6 — Syncing Service Changes Back to Git

*Do this if edits were made directly in the Power BI Service (browser), not in Desktop.*

Changes made in the browser are not automatically tracked in git. Use this step to pull them back.

---

### Step 1 — Click "Sync Branch from Dev Report"

*(Located in the Cloud & Git card)*

CDM-Manager performs all of these steps automatically:

1. Finds the Dev workspace report that matches your current branch name
2. Downloads it as a PBIX file via the Power BI Export API
3. Runs `pbi-tools extract` to convert the PBIX into PBIP folder format
4. Commits the updated PBIP files to your branch in Azure DevOps

> **Requires pbi-tools.exe** — see Part 1, Step 2.

After this completes, the PBIP files in your branch reflect the current state of the report in the Service.

---

## PART 7 — Merging to Main

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

1. In CDM-Manager, select the Main branch in the Top Branch dropdown
2. Ensure your local PBIX is up to date (re-download if needed)
3. Click **Update Main Branch (PBIX to PBIP)**
4. CDM-Manager runs `pbi-tools extract` on the local PBIX and commits the PBIP files to Main

---

## PART 8 — Deploying to Production

*Do this after merging to Main. This is the final step.*

---

### Step 1 — Confirm You Are on a Main Branch

CDM-Manager enforces this rule — the **Deploy to PROD** button is only active when a Main branch is selected. You cannot accidentally deploy a feature branch to Production.

---

### Step 2 — Click "Deploy to PROD (Main Only)"

1. A confirmation dialog appears — read it and confirm
2. CDM-Manager deploys the report to the Production workspace
3. The report URL is printed to the log panel
4. Click **Open Last Deployed Report** to verify in the browser

---

### Step 3 — Cloud Backup *(optional)*

Archive the PBIX file to Azure Blob Storage for version history.

**Option A — During deploy:**
- Check **Include Cloud Backup** before clicking Deploy to PROD

**Option B — After deploy:**
- Click **Manual Cloud Backup** at any time

> Requires Azure CLI installed and logged in (Part 1, Step 3).

---

## Quick Reference

### Button Reference

| Button | When to use |
|--------|-------------|
| **Download CDM** | Get latest CDM PBIX from the Power BI Service |
| **Browse** | Point to an existing local PBIX |
| **Create & Deploy New Branch** | Start new feature or hotfix work |
| **Deploy to DEV** | Push changes to Dev workspace during development |
| **Open Last Deployed Report** | Verify the deployed report in the browser |
| **Sync Branch from Dev Report** | Pull browser edits back into git |
| **Update Main Branch** | Commit merged PBIX to Main as PBIP files |
| **Deploy to PROD (Main Only)** | Push final report to Production |
| **Manual Cloud Backup** | Archive PBIX to Azure Blob Storage |

---

### Branch Naming Convention

| Type | Format | Example |
|------|--------|---------|
| Feature | `feature/[TopBranch]/[Name]` | `feature/Production-Main/My-Feature` |
| Hotfix | `hotfix/[TopBranch]/[Name]` | `hotfix/Production-Main/HF-Fix-01` |

---

### Deploy Mode Decision

```
Are you changing the data model (measures, tables, relationships)?
  YES → New Semantic Model
  NO  → Live Connect to Prod Dataset
```

---

### Troubleshooting

| Problem | Fix |
|---------|-----|
| Script blocked — "not digitally signed" | Right-click `.ps1` → Properties → Unblock. Or use `Launch-CDM-Manager.bat` |
| "No Power BI token found" | Restart CDM-Manager and complete the browser login |
| Top Branch dropdown is grayed out | Download or browse to a local PBIX first (Part 3) |
| "No Live Connection Template found" | Publish the template to Dev — see `instructions.md` |
| "pbi-tools.exe not found" | Place `pbi-tools.exe` in the repo root folder (Part 1, Step 2) |
| Prompted for credentials on git push | Enter company email + Azure DevOps PAT (Part 1, Step 4) |
| SmartScreen blocks the `.bat` file | Right-click `.bat` → Properties → Unblock, or click More Info → Run Anyway |
