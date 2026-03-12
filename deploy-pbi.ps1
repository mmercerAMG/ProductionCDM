# deploy-pbi.ps1

param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("Dev", "Prod")]
    [string]$TargetEnv,

    [Parameter(Mandatory=$true)]
    [string]$BranchName,

    [Parameter(Mandatory=$true)]
    [string]$PbixPath,

    [switch]$CloudBackup,
    [switch]$LiveConnect
)

# --- Load token saved by CDM-Manager on startup ---
$tokenFile = "$env:TEMP\pbi_token.txt"
if (-not (Test-Path $tokenFile)) {
    Write-Error "No Power BI token found. Open CDM-Manager and sign in first (the code appears at startup)."
    exit 1
}
$token = Get-Content $tokenFile -Raw
Write-Host "Power BI token loaded." -ForegroundColor Green

# --- Helper: upload a PBIX file to PBI Service via REST ---
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

    if ($response.IsSuccessStatusCode) {
        Write-Host "Upload accepted by Power BI Service." -ForegroundColor Green
        return $true
    } else {
        Write-Error "Upload failed ($($response.StatusCode)): $responseBody"
        return $false
    }
}

# --- Configuration ---
$devWorkspaceId  = "2696b15d-427e-437b-ba5a-ca8d4fb188dd"
$prodWorkspaceId = "c05c8a73-79ee-4b7f-b798-831b5c260f1b"
$prodDatasetId   = "10ad1784-d53f-4877-b9f0-f77641efbff4"
$reportFolder    = Join-Path (Split-Path $PbixPath -Parent) "Production CDM.Report"

# --- Target ---
if ($TargetEnv -eq "Dev") {
    $workspaceId = $devWorkspaceId
    $reportName  = "Production CDM - $BranchName"
    Write-Host "Targeting Dev Workspace: $workspaceId" -ForegroundColor Yellow
} else {
    $workspaceId = $prodWorkspaceId
    $reportName  = "Production CDM"
    Write-Host "Targeting Prod Workspace: $workspaceId" -ForegroundColor Red
}

# --- Deployment ---
try {
    if ($LiveConnect -and $TargetEnv -eq "Dev") {
        Write-Host "MODE: Live Connection to Production Semantic Model" -ForegroundColor Magenta

        $tempDeploy = Join-Path $env:TEMP "PBI_Deploy_$(Get-Random)"
        New-Item -ItemType Directory -Path $tempDeploy -Force | Out-Null

        if (Test-Path $reportFolder) {
            Copy-Item -Path "$reportFolder\*" -Destination $tempDeploy -Recurse -Force
        }

        @"
{
  "version": "1.0",
  "datasetReference": {
    "byConnection": {
      "connectionString": "Data Source=pbiazure://api.powerbi.com;Initial Catalog=$prodDatasetId;Identity Provider=\"https://login.microsoftonline.com/common, https://analysis.windows.net/powerbi/api, 7f67af8a-fedc-4b08-8b4e-37c4d127b6cf\";Integrated Security=ClaimsToken",
      "pbiServiceModelId": "12763409",
      "pbiModelVirtualServerName": "sobe_wowvirtualserver",
      "pbiModelDatabaseName": "$prodDatasetId",
      "name": "EntityDataSource",
      "connectionType": "pbiServiceLive"
    }
  }
}
"@ | Set-Content -Path (Join-Path $tempDeploy "definition.pbir") -Force

        $tempZip = Join-Path $env:TEMP "deploy_live_$(Get-Random).pbix"
        Compress-Archive -Path "$tempDeploy\*" -DestinationPath $tempZip
        Write-Host "Uploading Live-Connected report layout..." -ForegroundColor Green
        $ok = Invoke-PBIUpload -FilePath $tempZip -WorkspaceId $workspaceId -ReportName $reportName

        Remove-Item $tempDeploy -Recurse -Force
        Remove-Item $tempZip -Force
        if (-not $ok) { exit 1 }

    } else {
        Write-Host "MODE: Standard .pbix Upload" -ForegroundColor Cyan
        if (-not (Test-Path $PbixPath)) { Write-Error "PBIX not found at: $PbixPath"; exit 1 }
        $ok = Invoke-PBIUpload -FilePath $PbixPath -WorkspaceId $workspaceId -ReportName $reportName
        if (-not $ok) { exit 1 }
    }

    Write-Host "Deployment of '$BranchName' to $TargetEnv successful!" -ForegroundColor Cyan

    # --- Cloud Backup ---
    if ($CloudBackup -and (Test-Path $PbixPath)) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmm"
        $blobName  = "Common Data Models/Production CDM/Production CDM_$timestamp.pbix"
        Write-Host "Creating Cloud Backup: $blobName" -ForegroundColor Green
        az storage blob upload --account-name aleaus2bigprodadlame01 --container-name dal3011 --name $blobName --file $PbixPath --auth-mode login
    }

} catch {
    Write-Error "Deployment failed: $_"
    exit 1
}
