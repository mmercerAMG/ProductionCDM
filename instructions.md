# Development & Deployment Instructions

## Feature Branch Deployment Rules

For every feature branch deployed to the **Dev** workspace:

1. **Source of Truth**: The **PBIP folders** (`.Report` and `.SemanticModel`) are the absolute source of truth. Never commit `.pbix` files to git — they are too large and go to Azure Blob Storage instead.

2. **Deployment Type**: Choose in CDM-Manager before creating the branch:
   - **New Semantic Model** — uploads the full PBIX with its own dataset in Dev
   - **Live Connect to Prod Dataset** — clones the Live Connection Template, no PBIX upload

3. **Report Page Reduction**: Dev deployments must contain only the **first 4 pages**. Modify `report.json` in the `.Report` folder before deploying.

4. **Production Deployments**: Only allowed from `Main` branches. CDM-Manager enforces this with a confirmation dialog.

---

## One-Time Machine Setup

Every new computer requires these steps before CDM-Manager can run. Plan for 10-15 minutes.

### Step 1 — Install pbi-tools (required for PBIX-to-PBIP conversion)

`pbi-tools` is used by the **Sync Branch from Dev Report** and **Update Main Branch** buttons to extract a PBIX file into the PBIP folder format that git tracks.

1. Download the latest release from: **https://github.com/pbi-tools/pbi-tools/releases**
   - Get `pbi-tools.zip` (not the Core version)
2. Extract `pbi-tools.exe` and place it in the repo folder:
   ```
   H:\GitRepos\Airgas\Power BI Workflow\ProductionCDM-main\pbi-tools.exe
   ```
   CDM-Manager looks for it there first, then checks PATH and common install locations.

3. Verify it works by opening PowerShell and running:
   ```powershell
   cd "H:\GitRepos\Airgas\Power BI Workflow\ProductionCDM-main"
   .\pbi-tools.exe info
   ```

### Step 2 — Power BI Authentication (OAuth Device Code)

CDM-Manager handles Power BI authentication automatically on startup using the **OAuth 2.0 Device Code flow** — no modules required. On first launch:

1. The app opens your browser to `https://microsoft.com/devicelogin`
2. A code is automatically copied to your clipboard
3. Paste the code (`Ctrl+V`) in the browser and sign in with your Okta/company credentials
4. Once signed in, return to CDM-Manager — it detects the login and continues

The token is saved to `%TEMP%\pbi_token.txt` and reused for the session. Restart CDM-Manager to re-authenticate.

> **Note:** The MicrosoftPowerBIMgmt PowerShell module is **not required**. CDM-Manager uses the Power BI REST API directly.

### Step 3 — Azure CLI (required for Cloud Backup only)

The **Manual Cloud Backup** and **Include Cloud Backup** features upload PBIX files to Azure Blob Storage using the Azure CLI (`az`).

1. Download and install: **https://aka.ms/installazurecliwindows**
2. After install, open PowerShell and run:
   ```powershell
   az login
   ```
3. Sign in with your company account. The CLI caches your credentials.

If you do not use the cloud backup features, this step can be skipped.

### Step 4 — Git and Azure DevOps Remote

CDM-Manager automatically configures the `azure` remote on startup. Ensure git is installed and you have access to the ADO repository. On first push you may be prompted for ADO credentials — use your company email and a Personal Access Token (PAT) with Code Read/Write permissions.

---

## Live Connection Template Setup (One-time per Dev Workspace)

The Live Connect deploy mode requires a **"Live Connection Template"** report in the Dev workspace:

1. Open **Power BI Desktop**
2. Go to **Get Data > Power BI Datasets**
3. Select the **Production CDM** dataset (or any CDM dataset)
4. Do not add any visuals — just save the file
5. **Publish** to the Dev workspace (`3011 - AMG - Development`)
6. Name it exactly: **`Live Connection Template`**

This template is cloned for every Live Connect branch deploy. The Clone API rebinds the clone to the correct dataset based on your CDM Selection in the app. You only need **one template** for all 6 CDMs.

**Current template report ID:** `3c564eb5-8c02-40bb-a5c2-f20695874b8c`

---

## Workspace & Dataset Reference

| CDM | Prod Workspace | Dataset ID |
|-----|---------------|------------|
| Production CDM | 3011 - AMG - Production (`c05c8a73-79ee-4b7f-b798-831b5c260f1b`) | `10ad1784-d53f-4877-b9f0-f77641efbff4` |

Additional CDM workspace and dataset IDs are discovered dynamically via the CDM Selection dropdowns in CDM-Manager — no hardcoding required for the other 5 CDMs.

**Dev Workspace (all CDMs):** `2696b15d-427e-437b-ba5a-ca8d4fb188dd`

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| "No Power BI token found" | Restart CDM-Manager and complete the browser login |
| "No 'Live Connection Template' found" | Publish the template report to Dev (see setup above) |
| "pbi-tools.exe not found" | Place pbi-tools.exe in the repo folder or add to PATH |
| Top Branch dropdown is grayed out | Select a CDM and download it, or browse to a local PBIX |
| Branch shows `azure/feature/...` in dropdown | Known issue fixed in v2.0 — restart the app |
| `Install-Module` fails on company laptop | Not needed — CDM-Manager uses REST API, not PowerShell modules |
