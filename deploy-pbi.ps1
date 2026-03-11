# d:\GitHubRepos\ProductionCDM\deploy-pbi.ps1

param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("Dev", "Prod")]
    [string]$TargetEnv,

    [Parameter(Mandatory=$true)]
    [string]$BranchName,

    [switch]$CloudBackup
)

# --- Ensure Modules are Loaded ---
$modules = @("MicrosoftPowerBIMgmt.Profile", "MicrosoftPowerBIMgmt.Reports", "MicrosoftPowerBIMgmt.Workspaces")
foreach ($module in $modules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "Installing module $module..." -ForegroundColor Cyan
        Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module $module
}

# --- Configuration ---
$devWorkspaceId  = "2696b15d-427e-437b-ba5a-ca8d4fb188dd"
$prodWorkspaceId = "c05c8a73-79ee-4b7f-b798-831b5c260f1b"
$baseFolder      = "D:\GitHubRepos\ProductionCDM"
$pbixPath        = Join-Path $baseFolder "Production CDM.pbix"

# --- Login ---
Write-Host "Connecting to Power BI Service..." -ForegroundColor Cyan
Connect-PowerBIServiceAccount

# --- Logic ---
if ($TargetEnv -eq "Dev") {
    $workspaceId = $devWorkspaceId
    $reportName  = "Production CDM - $BranchName"
    Write-Host "Targeting Dev Workspace: $workspaceId" -ForegroundColor Yellow
    Write-Host "Renaming report to: $reportName" -ForegroundColor Yellow
} else {
    $workspaceId = $prodWorkspaceId
    $reportName  = "Production CDM"
    Write-Host "Targeting Prod Workspace: $workspaceId" -ForegroundColor Red
}

# --- Deployment ---
if (Test-Path $pbixPath) {
    Write-Host "Uploading $pbixPath..." -ForegroundColor Green
    try {
        New-PowerBIReport -Path $pbixPath -WorkspaceId $workspaceId -Name $reportName -ConflictAction CreateOrOverwrite -ErrorAction Stop
        Write-Host "Deployment of branch '$BranchName' to $TargetEnv successful!" -ForegroundColor Cyan
        
        # --- Cloud Backup Logic ---
        if ($CloudBackup) {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmm"
            $blobName = "Common Data Models/Production CDM/Production CDM_$timestamp.pbix"
            Write-Host "Creating Cloud Backup: $blobName" -ForegroundColor Green
            az storage blob upload --account-name aleaus2bigprodadlame01 --container-name dal3011 --name $blobName --file $pbixPath --auth-mode login
        }
    } catch {
        Write-Error "Deployment failed: $_"
    }
} else {
    Write-Error "Report file not found at: $pbixPath"
}