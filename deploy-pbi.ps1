# deploy-pbi.ps1

param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("Dev", "Prod")]
    [string]$TargetEnv,

    [Parameter(Mandatory=$true)]
    [string]$BranchName,

    [Parameter(Mandatory=$true)]
    [string]$PbixPath,

    [string]$DevWorkspaceId  = "2696b15d-427e-437b-ba5a-ca8d4fb188dd",
    [string]$ProdWorkspaceId = "c05c8a73-79ee-4b7f-b798-831b5c260f1b",
    [string]$ProdDatasetId   = "10ad1784-d53f-4877-b9f0-f77641efbff4",

    [switch]$CloudBackup,
    [switch]$LiveConnect
)

$ErrorActionPreference = "Stop"

# --- Load token saved by CDM-Manager on startup ---
$tokenFile = "$env:TEMP\pbi_token.txt"
if (-not (Test-Path $tokenFile)) {
    Write-Error "No Power BI token found. Open CDM-Manager and sign in first."
    exit 1
}
$token = Get-Content $tokenFile -Raw
Write-Host "Power BI token loaded." -ForegroundColor Green

# --- Helpers ---

# Upload a PBIX and return the import ID for polling
function Invoke-PBIUpload ($FilePath, $WorkspaceId, $ReportName) {
    Add-Type -AssemblyName System.Net.Http
    $uri     = "https://api.powerbi.com/v1.0/myorg/groups/$WorkspaceId/imports?datasetDisplayName=$([uri]::EscapeDataString($ReportName))&nameConflict=CreateOrOverwrite"
    $client  = [System.Net.Http.HttpClient]::new()
    $client.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $token)

    $stream      = [System.IO.File]::OpenRead($FilePath)
    $fileContent = [System.Net.Http.StreamContent]::new($stream)
    $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new("application/octet-stream")
    $multipart   = [System.Net.Http.MultipartFormDataContent]::new()
    $multipart.Add($fileContent, "file", [System.IO.Path]::GetFileName($FilePath))

    $response     = $client.PostAsync($uri, $multipart).Result
    $responseBody = $response.Content.ReadAsStringAsync().Result
    $stream.Close()
    $client.Dispose()

    if (-not $response.IsSuccessStatusCode) {
        Write-Error "Upload failed ($($response.StatusCode)): $responseBody"
        return $null
    }

    $importId = ($responseBody | ConvertFrom-Json).id
    Write-Host "Upload accepted. Import ID: $importId" -ForegroundColor Green
    return $importId
}

# Poll import until complete, return hashtable with ReportId and DatasetId
function Wait-PBIImport ($WorkspaceId, $ImportId) {
    $headers = @{ Authorization = "Bearer $token" }
    $uri     = "https://api.powerbi.com/v1.0/myorg/groups/$WorkspaceId/imports/$ImportId"
    $timeout = [DateTime]::Now.AddSeconds(120)

    while ([DateTime]::Now -lt $timeout) {
        Start-Sleep -Seconds 3
        $resp   = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers
        Write-Host "  Import status: $($resp.importState)" -ForegroundColor DarkGray
        if ($resp.importState -eq "Succeeded") {
            $reportId  = $resp.reports[0].id
            $datasetId = if ($resp.datasets -and $resp.datasets.Count -gt 0) { $resp.datasets[0].id } else { $null }
            Write-Host "Report ID: $reportId" -ForegroundColor Green
            if ($datasetId) { Write-Host "Dataset ID: $datasetId" -ForegroundColor Green }
            return @{ ReportId = $reportId; DatasetId = $datasetId }
        }
        if ($resp.importState -eq "Failed") {
            Write-Error "Import failed: $($resp | ConvertTo-Json)"
            return $null
        }
    }
    Write-Error "Import timed out after 120 seconds."
    return $null
}

# Delete a dataset from a workspace
function Remove-PBIDataset ($WorkspaceId, $DatasetId) {
    if (-not $DatasetId) { return }
    $headers = @{ Authorization = "Bearer $token" }
    $uri     = "https://api.powerbi.com/v1.0/myorg/groups/$WorkspaceId/datasets/$DatasetId"
    try {
        Invoke-RestMethod -Method DELETE -Uri $uri -Headers $headers
        Write-Host "Orphan dataset ($DatasetId) removed from Dev workspace." -ForegroundColor Green
    } catch {
        Write-Warning "Could not delete dataset $DatasetId`: $_"
    }
}

# Clone a report in the same workspace, bound to a specific dataset
function Invoke-PBICloneReport ($WorkspaceId, $TemplateReportId, $NewName, $TargetDatasetId) {
    $headers = @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" }
    $uri     = "https://api.powerbi.com/v1.0/myorg/groups/$WorkspaceId/reports/$TemplateReportId/Clone"
    $body    = [ordered]@{
        name              = $NewName
        targetWorkspaceId = $WorkspaceId
        targetModelId     = $TargetDatasetId
    } | ConvertTo-Json
    $resp = Invoke-RestMethod -Method POST -Uri $uri -Headers $headers -Body $body
    Write-Host "Cloned report '$NewName' (ID: $($resp.id)) bound to dataset $TargetDatasetId" -ForegroundColor Green
    return $resp.id
}

# Delete a report from a workspace
function Remove-PBIReport ($WorkspaceId, $ReportId) {
    $headers = @{ Authorization = "Bearer $token" }
    $uri     = "https://api.powerbi.com/v1.0/myorg/groups/$WorkspaceId/reports/$ReportId"
    try {
        Invoke-RestMethod -Method DELETE -Uri $uri -Headers $headers
        Write-Host "Existing report ($ReportId) removed." -ForegroundColor DarkGray
    } catch {
        Write-Warning "Could not delete report $ReportId`: $_"
    }
}

# --- Target ---
if ($TargetEnv -eq "Dev") {
    $workspaceId = $DevWorkspaceId
    $reportName  = "$BranchName"
    Write-Host "Targeting Dev Workspace: $workspaceId" -ForegroundColor Yellow
} else {
    $workspaceId = $ProdWorkspaceId
    $reportName  = $BranchName -replace "^.*/", ""   # strip prefix, use short name for Prod
    Write-Host "Targeting Prod Workspace: $workspaceId" -ForegroundColor Red
}

# --- Deployment ---
try {
    $deployedReportId = $null

    if ($LiveConnect -and $TargetEnv -eq "Dev") {
        Write-Host "MODE: Live Connect - Clone Template and Bind to Dataset" -ForegroundColor Magenta

        # Step 1: Find the Live Connect Template in Dev workspace
        $headers  = @{ Authorization = "Bearer $token" }
        $reports  = (Invoke-RestMethod -Method GET -Uri "https://api.powerbi.com/v1.0/myorg/groups/$workspaceId/reports" -Headers $headers).value
        $template = $reports | Where-Object { $_.name -like "*Live Connection Template*" } | Select-Object -First 1

        if (-not $template) {
            Write-Error "No 'Live Connection Template' report found in Dev workspace ($workspaceId).`nPublish a live-connected report named 'Live Connection Template' to Dev first."
            exit 1
        }
        Write-Host "Template found: '$($template.name)' (ID: $($template.id))" -ForegroundColor DarkGray

        # Step 2: Delete existing report with this name if it exists (overwrite)
        $existing = $reports | Where-Object { $_.name -eq $reportName } | Select-Object -First 1
        if ($existing) {
            Write-Host "Removing existing report '$reportName'..." -ForegroundColor DarkGray
            Remove-PBIReport -WorkspaceId $workspaceId -ReportId $existing.id
        }

        # Step 3: Clone template into Dev workspace bound to the selected dataset
        Write-Host "Cloning template as '$reportName' bound to dataset $ProdDatasetId..." -ForegroundColor Cyan
        $deployedReportId = Invoke-PBICloneReport -WorkspaceId $workspaceId -TemplateReportId $template.id -NewName $reportName -TargetDatasetId $ProdDatasetId
        if (-not $deployedReportId) { exit 1 }

    } else {
        if (-not (Test-Path $PbixPath)) { Write-Error "PBIX not found at: $PbixPath"; exit 1 }
        Write-Host "MODE: New Semantic Model (.pbix upload)" -ForegroundColor Cyan
        $importId = Invoke-PBIUpload -FilePath $PbixPath -WorkspaceId $workspaceId -ReportName $reportName
        if (-not $importId) { exit 1 }
        Write-Host "Waiting for import to complete..." -ForegroundColor Cyan
        $result = Wait-PBIImport -WorkspaceId $workspaceId -ImportId $importId
        if (-not $result) { exit 1 }
        $deployedReportId = $result.ReportId
    }

    if ($deployedReportId) {
        Write-Host "REPORT_URL: https://app.powerbi.com/groups/$workspaceId/reports/$deployedReportId" -ForegroundColor Cyan
    }
    Write-Host "Deployment of '$BranchName' to $TargetEnv successful!" -ForegroundColor Cyan

    # --- Cloud Backup ---
    if ($CloudBackup) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmm"
        $blobName  = "Common Data Models/Production CDM/Production CDM_$timestamp.pbix"
        Write-Host "Creating Cloud Backup: $blobName" -ForegroundColor Green
        az storage blob upload --account-name aleaus2bigprodadlame01 --container-name dal3011 --name $blobName --file $PbixPath --auth-mode login
    }

} catch {
    Write-Error "Deployment failed: $_"
    exit 1
}
