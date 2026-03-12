# Development & Deployment Instructions

## Feature Branch Deployment Rules
For every feature branch that is being added or deployed to the **Dev** workspace, the following process must be followed:

1.  **Source of Truth**: The **PBIP folders** (`.Report` and `.SemanticModel`) are the absolute source of truth. Deployment scripts and pipelines MUST deploy from these folders, not from a static `.pbix` file.
    
2.  **Deployment Type Confirmation**: Always ask the user if the deployment should be:
    *   A **Live Connection Report** (connecting to an existing published semantic model).
    *   A **New Semantic Model** (uploading the local `.SemanticModel` definition/metadata).

3.  **Report Page Reduction**: For every report created or updated via a feature branch, the report definition must be modified to keep **only the first 4 pages**. All other pages must be removed.
    *   This rule applies to **both** Live Connected reports and reports with their own Semantic Model.
    *   The modification should be performed on the `report.json` file within the `.Report` folder before deployment.

## Existing Dev Workspaces
*   **Dev Workspace ID**: `2696b15d-427e-437b-ba5a-ca8d4fb188dd`
*   **Production CDM Dataset ID**: `10ad1784-d53f-4877-b9f0-f77641efbff4`

---

## Power BI Module Setup (Required on Every New Computer)

> **Honest note:** This is not plug-and-play. Every user machine requires a one-time manual setup before the workflow can deploy to Power BI Service. Plan for 5–10 minutes per machine. The main blockers are a broken version of PowerShellGet that ships with Windows and OneDrive's Known Folder Move protection, both of which prevent the standard `Install-Module` command from working. Follow the steps below exactly.

### Why the normal approach fails

Windows ships with **PowerShellGet 1.0.0.1**, which has a bug where it does not create nested directories when installing modules. It fails with:
```
Could not find a part of the path '...\WindowsPowerShell\Modules\MicrosoftPowerBIMgmt.Profile\1.3.80'
```
Separately, if the user has **OneDrive Known Folder Move** enabled (common on company laptops), the `Documents` folder is OneDrive-protected. PowerShell's default module path (`Documents\WindowsPowerShell\Modules`) silently fails to be created — `New-Item` appears to succeed but the folder never appears. Both issues must be worked around together.

### One-time setup (run once per machine)

Open **PowerShell** (does not need to be admin) and run the following two commands:

```powershell
# Step 1 — Create a writable module folder outside of OneDrive/Documents
New-Item -ItemType Directory -Path "C:\Users\$env:USERNAME\PSModules" -Force
```

```powershell
# Step 2 — Download and install the Power BI modules
$dest = "C:\Users\$env:USERNAME\PSModules"
$temp = "$env:TEMP\pbi_install"
New-Item -ItemType Directory -Path $temp -Force | Out-Null
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
Save-Module -Name MicrosoftPowerBIMgmt -Path $temp -Force
Get-ChildItem $temp | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination $dest -Recurse -Force
    Write-Host "Installed: $($_.Name)"
}
Remove-Item $temp -Recurse -Force
Write-Host "Done. Verify with: Get-Module -ListAvailable -Name MicrosoftPowerBIMgmt*"
```

### Verify the install worked

```powershell
$env:PSModulePath = "C:\Users\$env:USERNAME\PSModules;$env:PSModulePath"
Get-Module -ListAvailable -Name MicrosoftPowerBIMgmt*
```

You should see 7 modules listed (Profile, Reports, Workspaces, Admin, Capacities, Data, and the meta-module), all at version 1.3.80 or higher.

### What deploy-pbi.ps1 does automatically

The deploy script injects `C:\Users\<YourUsername>\PSModules` into the module path at runtime using `$env:USERNAME`, so it resolves correctly on any machine without any code changes.

### Power BI login (Okta SSO)

When the workflow deploys to Power BI for the first time in a session, it calls `Connect-PowerBIServiceAccount`, which opens a browser window for Okta login. This is expected. After logging in once, the token is cached for the rest of the session. It will prompt again the next time the workflow is opened.
