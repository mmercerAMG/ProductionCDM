# CLI Workflow Guide

This guide covers manual git and PowerShell operations for the Power BI workflow. For day-to-day work, **CDM-Manager.ps1 is the recommended interface** — it handles branching, deployment, and ADO sync automatically. Use this guide for manual operations, troubleshooting, or scripting outside of CDM-Manager.

---

## 1. Authentication

CDM-Manager authenticates automatically on startup using the **OAuth 2.0 Device Code flow** — no PowerShell modules required.

For manual REST API calls or scripting, retrieve the cached token:

```powershell
# Read the token CDM-Manager saved after login
$token = (Get-Content "$env:TEMP\pbi_token.txt" -Raw).Trim()
$headers = @{ Authorization = "Bearer $token" }

# Example: list workspaces
Invoke-RestMethod -Uri "https://api.powerbi.com/v1.0/myorg/groups" -Headers $headers
```

> The token expires after approximately 1 hour. Restart CDM-Manager to refresh it.

---

## 2. Remote Configuration

CDM-Manager configures the `azure` remote on startup. To set it up manually:

```powershell
$ADO_URL = "https://dev.azure.com/bigroupairliquide/_git/3011%20-%20Distribution%20and%20Analytics"

# Add the remote (first time)
git remote add azure $ADO_URL

# Update the remote URL (if it already exists)
git remote set-url azure $ADO_URL

# Fetch all branches
git fetch azure
```

---

## 3. Branching

CDM-Manager creates and pushes branches automatically. The required naming convention is:

| Type | Format | Example |
|------|--------|---------|
| Top Branch | `[ModelName]-Main` | `Production-Main` |
| Feature | `feature/[TopBranch]/[Name]` | `feature/Production-Main/My-Feature` |
| Hotfix | `hotfix/[TopBranch]/[Name]` | `hotfix/Production-Main/HF-Fix-01` |

To create a branch manually from the ADO remote:

```powershell
# Fetch latest from ADO first
git -C $SCRIPT_DIR fetch azure

# Create branch from the remote Top Branch (no local checkout)
git -C $SCRIPT_DIR branch feature/Production-Main/My-Feature azure/Production-Main

# Push to ADO
git -C $SCRIPT_DIR push azure feature/Production-Main/My-Feature:feature/Production-Main/My-Feature -u
```

To switch branches:

```powershell
git -C $SCRIPT_DIR checkout feature/Production-Main/My-Feature
```

---

## 4. Saving & Committing Changes

When you save changes in Power BI Desktop (PBIP format), commit them to git manually if not using CDM-Manager's sync buttons:

```powershell
$SCRIPT_DIR = "H:\GitRepos\Airgas\Power BI Workflow\Main"

# Check which PBIP files were modified
git -C $SCRIPT_DIR status

# Stage all PBIP changes
git -C $SCRIPT_DIR add "*.SemanticModel/" "*.Report/"

# Commit with a descriptive message
git -C $SCRIPT_DIR commit -m "feat: add new measures and update layout"

# Push to ADO
git -C $SCRIPT_DIR push azure
```

---

## 5. Deployment

CDM-Manager calls `deploy-pbi.ps1` automatically. To run it manually:

```powershell
$SCRIPT_DIR = "H:\GitRepos\Airgas\Power BI Workflow\Main"

# Deploy to Dev (New Semantic Model mode)
& "$SCRIPT_DIR\deploy-pbi.ps1" -TargetEnv Dev -BranchName "My-Feature" -PbixPath "C:\path\to\model.pbix"

# Deploy to Dev (Live Connect mode)
& "$SCRIPT_DIR\deploy-pbi.ps1" -TargetEnv Dev -BranchName "My-Feature" -PbixPath "C:\path\to\model.pbix" `
    -LiveConnect -ProdWorkspaceId "c05c8a73-..." -ProdDatasetId "10ad1784-..."

# Deploy to Production (Main branches only)
& "$SCRIPT_DIR\deploy-pbi.ps1" -TargetEnv Prod -BranchName "Production-Main" -PbixPath "C:\path\to\model.pbix"

# Deploy to Production with cloud backup
& "$SCRIPT_DIR\deploy-pbi.ps1" -TargetEnv Prod -BranchName "Production-Main" -PbixPath "C:\path\to\model.pbix" -CloudBackup
```

> `deploy-pbi.ps1` reads the PBI token from `%TEMP%\pbi_token.txt`. Log into CDM-Manager first to ensure the token is current.

---

## 6. pbi-tools Operations

`pbi-tools` converts between PBIX and PBIP format. CDM-Manager calls it automatically for Sync and Update operations.

```powershell
# Extract PBIX to PBIP (PBIX -> folder)
pbi-tools extract "C:\path\to\model.pbix" -extractFolder "H:\GitRepos\Airgas\Power BI Workflow\Main"

# Compile PBIP to PBIX (folder -> PBIX)
pbi-tools compile "H:\GitRepos\Airgas\Power BI Workflow\Main" -outPath "C:\path\to\output.pbix"

# Check pbi-tools version and Power BI Desktop compatibility
pbi-tools info
```

---

## 7. Cloud Backup

PBIX files are archived to Azure Blob Storage for versioning. CDM-Manager's **Manual Cloud Backup** button runs this automatically. To run manually:

```powershell
$timestamp = Get-Date -Format "yyyyMMdd_HHmm"
$pbixPath  = "C:\path\to\model.pbix"
$modelName = "Production CDM"

az storage blob upload `
    --account-name aleaus2bigprodadlame01 `
    --container-name dal3011 `
    --name "Common Data Models/$modelName/${modelName}_$timestamp.pbix" `
    --file $pbixPath `
    --auth-mode login
```

> Requires Azure CLI installed and authenticated (`az login`).

---

## 8. Repository Cleanup

```powershell
$SCRIPT_DIR = "H:\GitRepos\Airgas\Power BI Workflow\Main"

# Reset local branch to exactly match the ADO remote (discards local changes)
git -C $SCRIPT_DIR reset --hard azure/Production-Main

# Remove untracked files, preserving PBIX files
git -C $SCRIPT_DIR clean -fd -e "*.pbix"

# List all remote branches (Top Branches and sub-branches)
git -C $SCRIPT_DIR branch -r | Where-Object { $_ -notmatch "HEAD" }

# List only Top Branches (Main)
git -C $SCRIPT_DIR branch -r | Where-Object { $_ -like "*Main*" }
```

---

## 9. Troubleshooting

| Problem | Command |
|---------|---------|
| Check current branch | `git -C $SCRIPT_DIR branch --show-current` |
| Check remote connection | `git -C $SCRIPT_DIR remote -v` |
| Re-fetch all branches | `git -C $SCRIPT_DIR fetch azure` |
| View recent commits | `git -C $SCRIPT_DIR log --oneline -10` |
| Check token exists | `Test-Path "$env:TEMP\pbi_token.txt"` |
| Check pbi-tools version | `pbi-tools info` |
