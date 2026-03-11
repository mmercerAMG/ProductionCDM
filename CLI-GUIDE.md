# CLI Workflow Guide - Production CDM

This guide provides the terminal commands required to execute the professional Power BI engineering workflow defined for this project.

## 1. Environment Setup
Run these once to ensure your local machine is ready to interact with Power BI.

```powershell
# Install the Power BI management modules for the current user
Install-Module -Name MicrosoftPowerBIMgmt -Scope CurrentUser -Force -AllowClobber

# Verify the modules are installed correctly
Get-Command -Module MicrosoftPowerBIMgmt*
```

## 2. Feature Branching
Always work in a feature branch to keep the `Production-Main` branch clean.

```powershell
# Create a new feature branch and switch to it
git checkout -b feature/your-feature-name

# List all local branches to see where you are
git branch

# Switch back to the main branch
git switch Production-Main
```

## 3. Saving & Committing Changes
When you save changes in Power BI Desktop (PBIP format), use these to save your work to Git.

```powershell
# Check which files were modified (look for report.json or .tmdl files)
git status

# Stage all text-based changes for the next commit
git add .

# Commit the changes with a descriptive message
git commit -m "feat: Add new measures and limit report to 4 pages"

# Push the feature branch to Azure DevOps
git push azure feature/your-feature-name
```

## 4. Local Deployment (Testing)
Use this to push your branch's current state to the Dev workspace for validation.

```powershell
# Deploy the current branch to the Dev workspace
# Replace "MyFeature" with the short name you want in the report title
.\deploy-pbi.ps1 -TargetEnv Dev -BranchName "MyFeature"

# Deploy specifically to Production (Use with CAUTION)
.\deploy-pbi.ps1 -TargetEnv Prod -BranchName "Production-Main"
```

## 5. Security & Service Principals
Commands for setting up the Azure DevOps pipeline authorization.

```powershell
# Create a Service Principal for the CI/CD pipeline
# Replace <subscriptionId> with your actual Azure Subscription ID
az ad sp create-for-rbac --name "ProductionCDM-Pipeline-SPN" --role Contributor --scopes /subscriptions/<subscriptionId>
```

## 6. Cloud Versioning (Manual Backup)
Since `.pbix` files are not tracked in Git, use this command to save a versioned backup to Azure Blob Storage.

```powershell
# Upload a timestamped backup to the production storage account
$timestamp = Get-Date -Format "yyyyMMdd_HHmm"
az storage blob upload --account-name aleaus2bigprodadlame01 --container-name dal3011 --name "Common Data Models/Production CDM/Production CDM_$timestamp.pbix" --file "Production CDM.pbix" --auth-mode login
```

## 7. Repository Cleanup
Use these if your local folder gets out of sync or cluttered.

```powershell
# Reset your local branch to exactly match the remote Production-Main
git reset --hard azure/Production-Main

# Remove untracked files and folders (Preserving your .pbix files)
git clean -fd -e "*.pbix"
```
