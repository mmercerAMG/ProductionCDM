# CDM-Tester.ps1
# AI End-to-End Tester for CDM-Manager Workflow v1.0
#
# PURPOSE: Validates the outcomes of CDM-Manager operations by querying the
#          Power BI REST API and local git state. Run AFTER performing an
#          action in CDM-Manager to verify it succeeded correctly.
#
# USAGE:
#   Interactive menu:  .\CDM-Tester.ps1
#   Specific suite:    .\CDM-Tester.ps1 -Suite BranchLive -BranchName "feature/Production-Main/MM-TEST12"
#   CI / non-interactive: .\CDM-Tester.ps1 -Suite All -BranchName "feature/Production-Main/MM-TEST12"

param (
    [ValidateSet("Interactive","Auth","LiveTemplate","BranchNew","BranchLive","SyncBranch","DeployDev","DeployProd","All")]
    [string]$Suite = "Interactive",

    # Full branch name e.g. "feature/Production-Main/MM-TEST12"
    [string]$BranchName,

    # Workspace / dataset defaults (same as CDM-Manager)
    [string]$DevWorkspaceId  = "2696b15d-427e-437b-ba5a-ca8d4fb188dd",
    [string]$ProdWorkspaceId = "c05c8a73-79ee-4b7f-b798-831b5c260f1b",
    [string]$ProdDatasetId   = "10ad1784-d53f-4877-b9f0-f77641efbff4"
)

$ErrorActionPreference = "Continue"
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path

# ============================================================
#  State counters
# ============================================================
$script:pass  = 0
$script:fail  = 0
$script:warn  = 0
$script:token = $null

# ============================================================
#  Output helpers
# ============================================================

function Write-Pass ($msg) { $script:pass++;  Write-Host "  [PASS] $msg" -ForegroundColor Green  }
function Write-Fail ($msg) { $script:fail++;  Write-Host "  [FAIL] $msg" -ForegroundColor Red    }
function Write-Warn ($msg) { $script:warn++;  Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-Info ($msg) {                  Write-Host "         $msg"  -ForegroundColor DarkGray }
function Write-Section ($title) {
    Write-Host ""
    Write-Host "--- $title ---" -ForegroundColor Cyan
}

function Reset-Counters { $script:pass = 0; $script:fail = 0; $script:warn = 0 }

function Show-Summary {
    $total = $script:pass + $script:fail + $script:warn
    Write-Host ""
    Write-Host ("=" * 44) -ForegroundColor White
    Write-Host ("  Results: {0,3} checks" -f $total)   -ForegroundColor White
    Write-Host ("  PASS:    {0,3}" -f $script:pass)     -ForegroundColor Green
    Write-Host ("  FAIL:    {0,3}" -f $script:fail)     -ForegroundColor Red
    Write-Host ("  WARN:    {0,3}" -f $script:warn)     -ForegroundColor Yellow
    Write-Host ("=" * 44) -ForegroundColor White
    if    ($script:fail -gt 0) { Write-Host "  STATUS: FAILED"                -ForegroundColor Red    }
    elseif($script:warn -gt 0) { Write-Host "  STATUS: PASSED WITH WARNINGS"  -ForegroundColor Yellow }
    else                       { Write-Host "  STATUS: ALL PASSED"             -ForegroundColor Green  }
    Write-Host ""
}

# ============================================================
#  PBI REST helpers
# ============================================================

function Get-Headers { @{ Authorization = "Bearer $($script:token)" } }

function Invoke-Pbi ($uri) {
    Invoke-RestMethod -Method GET -Uri $uri -Headers (Get-Headers) -ErrorAction Stop
}

function Get-DevReports   { (Invoke-Pbi "https://api.powerbi.com/v1.0/myorg/groups/$DevWorkspaceId/reports").value }
function Get-DevDatasets  { (Invoke-Pbi "https://api.powerbi.com/v1.0/myorg/groups/$DevWorkspaceId/datasets").value }
function Get-ProdReports  { (Invoke-Pbi "https://api.powerbi.com/v1.0/myorg/groups/$ProdWorkspaceId/reports").value }

function Get-ReportPages ($wsId, $reportId) {
    (Invoke-Pbi "https://api.powerbi.com/v1.0/myorg/groups/$wsId/reports/$reportId/pages").value
}

# ============================================================
#  Git helper — fetch azure remote before checking
# ============================================================

function Sync-AzureRemote {
    Write-Info "Fetching azure remote..."
    & git -C $SCRIPT_DIR fetch azure --quiet 2>&1 | Out-Null
}

function Get-RemoteBranches {
    (& git -C $SCRIPT_DIR branch -r 2>&1) -split "`n" | ForEach-Object { $_.Trim() }
}

# ============================================================
#  TEST SUITES
# ============================================================

# ----------------------------------------------------------
# 1. Authentication
# ----------------------------------------------------------
function Test-Auth {
    Write-Section "SUITE: Authentication"

    $tokenFile = "$env:TEMP\pbi_token.txt"

    if (Test-Path $tokenFile) {
        Write-Pass "Token file exists: $tokenFile"
        $script:token = (Get-Content $tokenFile -Raw).Trim()
    } else {
        Write-Fail "Token file NOT found at $tokenFile"
        Write-Info "Open CDM-Manager.ps1 and sign in first."
        return $false
    }

    if ($script:token.Length -gt 20) {
        Write-Pass "Token is non-empty ($($script:token.Length) chars)"
    } else {
        Write-Fail "Token looks empty or invalid"
        return $false
    }

    # Verify token against PBI API
    try {
        Invoke-Pbi "https://api.powerbi.com/v1.0/myorg/" | Out-Null
        Write-Pass "Power BI API is reachable and token is valid"
    } catch {
        Write-Fail "Power BI API call failed: $($_.Exception.Message)"
        Write-Info "Token may be expired - restart CDM-Manager to re-authenticate."
        return $false
    }

    # Dev workspace
    try {
        $ws = Invoke-Pbi "https://api.powerbi.com/v1.0/myorg/groups/$DevWorkspaceId"
        Write-Pass "Dev workspace accessible: '$($ws.name)' ($DevWorkspaceId)"
    } catch {
        Write-Fail "Cannot access Dev workspace ($DevWorkspaceId): $($_.Exception.Message)"
    }

    # Prod workspace
    try {
        $ws = Invoke-Pbi "https://api.powerbi.com/v1.0/myorg/groups/$ProdWorkspaceId"
        Write-Pass "Prod workspace accessible: '$($ws.name)' ($ProdWorkspaceId)"
    } catch {
        Write-Fail "Cannot access Prod workspace ($ProdWorkspaceId): $($_.Exception.Message)"
    }

    return $true
}

# ----------------------------------------------------------
# 2. Live Connection Template prerequisite
# ----------------------------------------------------------
function Test-LiveTemplate {
    Write-Section "SUITE: Live Connection Template (Dev prerequisite)"

    try {
        $reports  = Get-DevReports
        $template = $reports | Where-Object { $_.name -like "*Live Connection Template*" } | Select-Object -First 1

        if ($template) {
            Write-Pass "Template report found in Dev workspace"
            Write-Pass "  Name: '$($template.name)'"
            Write-Pass "  ID:   $($template.id)"

            # Verify it's actually live-connected to a prod dataset
            if ($template.datasetId -eq $ProdDatasetId) {
                Write-Pass "  Template is bound to Production CDM dataset ($ProdDatasetId)"
            } else {
                Write-Warn "  Template dataset binding: $($template.datasetId)"
                Write-Info "  Expected it to point to Production CDM ($ProdDatasetId)."
                Write-Info "  If you plan to test other CDMs, this may be fine."
            }
        } else {
            Write-Fail "No 'Live Connection Template' report found in Dev workspace"
            Write-Info "Publish a live-connected blank report named 'Live Connection Template' to Dev."
            Write-Info "See instructions.md > 'Live Connection Template Setup'."
        }
    } catch {
        Write-Fail "Error querying Dev workspace: $($_.Exception.Message)"
    }
}

# ----------------------------------------------------------
# 3. Branch Created - New Semantic Model mode
# ----------------------------------------------------------
function Test-BranchNew ($branchName) {
    Write-Section "SUITE: Branch Created (New Semantic Model) - $branchName"

    # --- Git checks ---
    Sync-AzureRemote
    $branches = Get-RemoteBranches
    $found    = $branches | Where-Object { $_ -match [regex]::Escape($branchName) }

    if ($found) {
        Write-Pass "Git: Branch '$branchName' exists in azure remote"
    } else {
        Write-Fail "Git: Branch '$branchName' NOT found in azure remote"
        Write-Info "Branches containing 'feature':"
        $branches | Where-Object { $_ -match "feature" } | Select-Object -First 8 | ForEach-Object { Write-Info $_ }
    }

    # --- PBI checks ---
    try {
        $reports = Get-DevReports
        $report  = $reports | Where-Object { $_.name -eq $branchName } | Select-Object -First 1

        if ($report) {
            Write-Pass "PBI: Report '$branchName' exists in Dev workspace (ID: $($report.id))"
            Write-Pass "PBI: URL: https://app.powerbi.com/groups/$DevWorkspaceId/reports/$($report.id)"

            $boundDsId = $report.datasetId
            if ($boundDsId -and $boundDsId -ne $ProdDatasetId) {
                Write-Pass "PBI: Report has its own dataset ($boundDsId) - correct for New Semantic Model"

                # Confirm dataset actually exists (not orphaned)
                $datasets = Get-DevDatasets
                $ds       = $datasets | Where-Object { $_.id -eq $boundDsId } | Select-Object -First 1
                if ($ds) {
                    Write-Pass "PBI: Dataset '$($ds.name)' exists in Dev workspace"
                } else {
                    Write-Warn "PBI: Dataset $boundDsId not visible in workspace datasets list"
                }
            } elseif ($boundDsId -eq $ProdDatasetId) {
                Write-Fail "PBI: Report is bound to Prod dataset ($ProdDatasetId)"
                Write-Info "For New Semantic Model mode the report should have its own uploaded dataset."
            } else {
                Write-Warn "PBI: datasetId is null or unavailable on the report object"
            }

            # Page count check
            try {
                $pages = Get-ReportPages $DevWorkspaceId $report.id
                Write-Pass "PBI: Report has $($pages.Count) page(s)"
                if ($pages.Count -gt 4) {
                    Write-Warn "PBI: Page count $($pages.Count) exceeds the Dev 4-page limit (see instructions.md)"
                }
            } catch {
                Write-Warn "PBI: Could not fetch report pages: $($_.Exception.Message)"
            }

        } else {
            Write-Fail "PBI: Report '$branchName' NOT found in Dev workspace"
            Write-Info "Dev reports (first 10):"
            $reports | Select-Object -First 10 | ForEach-Object { Write-Info "  $($_.name)" }
        }
    } catch {
        Write-Fail "Error querying Dev workspace: $($_.Exception.Message)"
    }
}

# ----------------------------------------------------------
# 4. Branch Created - Live Connect mode
# ----------------------------------------------------------
function Test-BranchLive ($branchName) {
    Write-Section "SUITE: Branch Created (Live Connect) - $branchName"

    # --- Git checks ---
    Sync-AzureRemote
    $branches = Get-RemoteBranches
    $found    = $branches | Where-Object { $_ -match [regex]::Escape($branchName) }

    if ($found) {
        Write-Pass "Git: Branch '$branchName' exists in azure remote"
    } else {
        Write-Fail "Git: Branch '$branchName' NOT found in azure remote"
    }

    # --- PBI checks ---
    try {
        $reports  = Get-DevReports
        $report   = $reports | Where-Object { $_.name -eq $branchName } | Select-Object -First 1

        if ($report) {
            Write-Pass "PBI: Report '$branchName' exists in Dev workspace (ID: $($report.id))"
            Write-Pass "PBI: URL: https://app.powerbi.com/groups/$DevWorkspaceId/reports/$($report.id)"

            # Must be bound to prod dataset for true live connect
            $boundDsId = $report.datasetId
            if ($boundDsId -eq $ProdDatasetId) {
                Write-Pass "PBI: Report is live-connected to Production dataset ($ProdDatasetId) - CORRECT"
            } elseif ($boundDsId) {
                Write-Fail "PBI: Report is bound to dataset $boundDsId"
                Write-Info "Expected: Production CDM dataset $ProdDatasetId"
                Write-Info "The Clone API may have bound to the wrong dataset, or a different CDM was selected."
            } else {
                Write-Warn "PBI: Cannot determine dataset binding (datasetId is null)"
            }

            # Orphan dataset check - Live Connect should NOT create its own dataset
            $datasets = Get-DevDatasets
            $orphan   = $datasets | Where-Object { $_.name -eq $branchName } | Select-Object -First 1
            if (-not $orphan) {
                Write-Pass "PBI: No orphan dataset named '$branchName' in Dev - CORRECT for Live Connect"
            } else {
                Write-Fail "PBI: Orphan dataset '$branchName' ($($orphan.id)) found in Dev workspace"
                Write-Info "Live Connect mode should not upload a dataset. Run Remove-PBIDataset manually or re-deploy."
            }

        } else {
            Write-Fail "PBI: Report '$branchName' NOT found in Dev workspace"
            Write-Info "Dev reports (first 10):"
            $reports | Select-Object -First 10 | ForEach-Object { Write-Info "  $($_.name)" }
        }
    } catch {
        Write-Fail "Error querying Dev workspace: $($_.Exception.Message)"
    }
}

# ----------------------------------------------------------
# 5. Sync Branch from Dev Report
# ----------------------------------------------------------
function Test-SyncBranch ($branchName) {
    Write-Section "SUITE: Sync Branch from Dev Report - $branchName"

    # --- Git: branch has commits ---
    Sync-AzureRemote
    $ref = "azure/$branchName"

    $log = & git -C $SCRIPT_DIR log $ref --oneline -5 2>&1
    if ($LASTEXITCODE -eq 0 -and $log) {
        Write-Pass "Git: Branch '$ref' has commit history"
        Write-Pass "Git: Latest commit: $($log | Select-Object -First 1)"

        # Most recent commit should contain PBIP files
        $commitFiles = & git -C $SCRIPT_DIR show $ref --name-only --format="" 2>&1
        $pbipFiles   = $commitFiles | Where-Object { $_ -match "\.(Report|SemanticModel)" -or $_ -match "report\.json" }

        if ($pbipFiles) {
            Write-Pass "Git: Most recent commit contains PBIP-related files:"
            $pbipFiles | Select-Object -First 6 | ForEach-Object { Write-Info "  $_" }
        } else {
            Write-Warn "Git: Most recent commit has no PBIP files"
            Write-Info "Sync Branch may not have run yet, or the last commit was for something else."
            Write-Info "Files in last commit:"
            $commitFiles | Select-Object -First 6 | ForEach-Object { Write-Info "  $_" }
        }
    } else {
        Write-Fail "Git: Cannot read branch '$ref'"
        Write-Info "Ensure 'git fetch azure' succeeds and the branch exists."
    }

    # --- Local: .Report folder freshness ---
    $reportFolder = Join-Path $SCRIPT_DIR "Production CDM.Report"
    $reportJson   = Join-Path $reportFolder "report.json"

    if (Test-Path $reportJson) {
        $age = (Get-Date) - (Get-Item $reportJson).LastWriteTime
        if ($age.TotalHours -lt 1) {
            Write-Pass "Local: report.json updated $([int]$age.TotalMinutes) minute(s) ago"
        } elseif ($age.TotalHours -lt 24) {
            Write-Warn "Local: report.json updated $([int]$age.TotalHours) hour(s) ago - may be from a prior sync"
        } else {
            Write-Warn "Local: report.json last modified $([int]($age.TotalDays)) day(s) ago - likely not from this sync"
        }
    } elseif (Test-Path $reportFolder) {
        Write-Warn "Local: .Report folder exists but report.json is missing"
    } else {
        Write-Warn "Local: 'Production CDM.Report' folder not found at expected path"
        Write-Info "Expected: $reportFolder"
    }

    # --- pbi-tools presence ---
    $pbiToolsPath = Join-Path $SCRIPT_DIR "pbi-tools.exe"
    if (Test-Path $pbiToolsPath) {
        Write-Pass "Local: pbi-tools.exe found at $pbiToolsPath"
    } else {
        $inPath = & where.exe pbi-tools 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Pass "Local: pbi-tools.exe found in PATH"
        } else {
            Write-Fail "Local: pbi-tools.exe not found in repo folder or PATH"
            Write-Info "Sync Branch from Dev requires pbi-tools.exe. See instructions.md > Step 1."
        }
    }
}

# ----------------------------------------------------------
# 6. Deploy to Dev  (after clicking "Deploy to DEV")
# ----------------------------------------------------------
function Test-DeployDev ($branchName) {
    Write-Section "SUITE: Deploy to Dev - $branchName"

    try {
        $reports = Get-DevReports
        $report  = $reports | Where-Object { $_.name -eq $branchName } | Select-Object -First 1

        if ($report) {
            Write-Pass "PBI: Report '$branchName' found in Dev workspace"
            Write-Pass "PBI: ID:  $($report.id)"
            Write-Pass "PBI: URL: https://app.powerbi.com/groups/$DevWorkspaceId/reports/$($report.id)"

            try {
                $pages = Get-ReportPages $DevWorkspaceId $report.id
                Write-Pass "PBI: Report has $($pages.Count) page(s)"
                if ($pages.Count -gt 4) {
                    Write-Warn "PBI: Page count $($pages.Count) exceeds the Dev 4-page limit"
                    Write-Info "Dev deployments must contain only the first 4 pages (see instructions.md)."
                    Write-Info "Edit report.json before the next deploy."
                } else {
                    Write-Pass "PBI: Page count is within Dev limit (max 4)"
                }
            } catch {
                Write-Warn "PBI: Could not retrieve report pages: $($_.Exception.Message)"
            }
        } else {
            Write-Fail "PBI: Report '$branchName' NOT found in Dev workspace"
            Write-Info "Dev reports (first 10):"
            $reports | Select-Object -First 10 | ForEach-Object { Write-Info "  $($_.name)" }
        }
    } catch {
        Write-Fail "Error querying Dev workspace: $($_.Exception.Message)"
    }
}

# ----------------------------------------------------------
# 7. Deploy to Production  (after clicking "Deploy to PROD")
# ----------------------------------------------------------
function Test-DeployProd ($reportShortName) {
    Write-Section "SUITE: Deploy to Production - $reportShortName"

    if (-not $reportShortName) {
        Write-Fail "No report name provided. Pass the short report name as it appears in Prod."
        return
    }

    try {
        $reports = Get-ProdReports
        $matches = $reports | Where-Object { $_.name -eq $reportShortName }

        if ($matches.Count -eq 1) {
            $report = $matches[0]
            Write-Pass "PBI: Report '$reportShortName' found in Prod workspace"
            Write-Pass "PBI: ID:  $($report.id)"
            Write-Pass "PBI: URL: https://app.powerbi.com/groups/$ProdWorkspaceId/reports/$($report.id)"
            Write-Pass "PBI: No duplicates"
        } elseif ($matches.Count -gt 1) {
            Write-Fail "PBI: $($matches.Count) reports named '$reportShortName' found in Prod (duplicates!)"
            $matches | ForEach-Object { Write-Info "  ID: $($_.id)" }
        } else {
            Write-Fail "PBI: Report '$reportShortName' NOT found in Prod workspace"
            Write-Info "Prod reports (first 10):"
            $reports | Select-Object -First 10 | ForEach-Object { Write-Info "  $($_.name)" }
        }
    } catch {
        Write-Fail "Error querying Prod workspace: $($_.Exception.Message)"
    }
}

# ----------------------------------------------------------
# Interactive menu
# ----------------------------------------------------------
function Show-Menu {
    Write-Host ""
    Write-Host ("=" * 50) -ForegroundColor Cyan
    Write-Host "  CDM-Manager AI Tester v1.0" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1  - Auth: token + workspace access"
    Write-Host "  2  - Prereq: Live Connection Template"
    Write-Host "  3  - Branch created (New Semantic Model)"
    Write-Host "  4  - Branch created (Live Connect)"
    Write-Host "  5  - Sync Branch from Dev Report"
    Write-Host "  6  - Deploy to Dev"
    Write-Host "  7  - Deploy to Production"
    Write-Host "  A  - Run Auth + ask which tests to run"
    Write-Host "  Q  - Quit"
    Write-Host ""
}

function Prompt-Branch {
    param([string]$current)
    if ($current) { return $current }
    return (Read-Host "  Branch name (e.g. feature/Production-Main/MM-TEST12)").Trim()
}

# ============================================================
#  ENTRY POINT
# ============================================================

Write-Host ""
Write-Host "CDM-Manager AI Tester" -ForegroundColor Cyan
Write-Host "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor DarkGray
Write-Host "Repo: $SCRIPT_DIR" -ForegroundColor DarkGray

# Pre-load token (may be null if not authenticated yet)
$tokenFile = "$env:TEMP\pbi_token.txt"
if (Test-Path $tokenFile) { $script:token = (Get-Content $tokenFile -Raw).Trim() }

if ($Suite -eq "Interactive") {
    :mainLoop while ($true) {
        Show-Menu
        $choice = (Read-Host "Select").Trim().ToUpper()
        Reset-Counters

        switch ($choice) {
            "1" { Test-Auth; Show-Summary }
            "2" {
                if (-not $script:token) { Write-Host "  Run option 1 (Auth) first." -ForegroundColor Yellow; continue }
                Test-LiveTemplate; Show-Summary
            }
            "3" {
                if (-not $script:token) { Write-Host "  Run option 1 (Auth) first." -ForegroundColor Yellow; continue }
                $b = Prompt-Branch $BranchName
                Test-BranchNew $b; Show-Summary; $BranchName = $null
            }
            "4" {
                if (-not $script:token) { Write-Host "  Run option 1 (Auth) first." -ForegroundColor Yellow; continue }
                $b = Prompt-Branch $BranchName
                Test-BranchLive $b; Show-Summary; $BranchName = $null
            }
            "5" {
                if (-not $script:token) { Write-Host "  Run option 1 (Auth) first." -ForegroundColor Yellow; continue }
                $b = Prompt-Branch $BranchName
                Test-SyncBranch $b; Show-Summary; $BranchName = $null
            }
            "6" {
                if (-not $script:token) { Write-Host "  Run option 1 (Auth) first." -ForegroundColor Yellow; continue }
                $b = Prompt-Branch $BranchName
                Test-DeployDev $b; Show-Summary; $BranchName = $null
            }
            "7" {
                if (-not $script:token) { Write-Host "  Run option 1 (Auth) first." -ForegroundColor Yellow; continue }
                $shortName = (Read-Host "  Short report name in Prod (e.g. MM-TEST12)").Trim()
                Test-DeployProd $shortName; Show-Summary
            }
            "A" {
                Test-Auth
                if ($script:fail -gt 0) { Write-Host "  Auth failed - fix before running other tests." -ForegroundColor Red; Show-Summary; continue }
                Test-LiveTemplate
                $b = Prompt-Branch $BranchName
                $modeChoice = (Read-Host "  Branch deploy mode? [N=New Semantic Model / L=Live Connect]").Trim().ToUpper()
                if ($modeChoice -eq "L") { Test-BranchLive $b } else { Test-BranchNew $b }
                Test-DeployDev $b
                $synced = (Read-Host "  Has Sync Branch from Dev been run? [Y/N]").Trim().ToUpper()
                if ($synced -eq "Y") { Test-SyncBranch $b }
                $prodDeployed = (Read-Host "  Has Deploy to Prod been run? [Y/N]").Trim().ToUpper()
                if ($prodDeployed -eq "Y") {
                    $shortName = ($b -replace "^.*/", "").Trim()
                    Test-DeployProd $shortName
                }
                Show-Summary; $BranchName = $null
            }
            "Q" { break mainLoop }
            default { Write-Host "  Unknown option." -ForegroundColor Yellow }
        }
    }

} else {
    # Non-interactive / CI mode

    $authOk = Test-Auth
    if (-not $authOk -or $script:fail -gt 0) {
        Show-Summary
        exit 1
    }

    switch ($Suite) {
        "Auth"         { }   # already ran
        "LiveTemplate" { Test-LiveTemplate }
        "BranchNew"    { Test-BranchNew  $BranchName }
        "BranchLive"   { Test-BranchLive $BranchName }
        "SyncBranch"   { Test-SyncBranch $BranchName }
        "DeployDev"    { Test-DeployDev  $BranchName }
        "DeployProd"   { Test-DeployProd ($BranchName -replace "^.*/","") }
        "All" {
            Test-LiveTemplate
            if ($BranchName) {
                # Default: run both New and Live checks so caller sees all relevant results
                Test-BranchNew  $BranchName
                Test-BranchLive $BranchName
                Test-SyncBranch $BranchName
                Test-DeployDev  $BranchName
                Test-DeployProd ($BranchName -replace "^.*/","")
            } else {
                Write-Warn "No -BranchName provided; skipping branch/deploy tests."
            }
        }
    }

    Show-Summary
    if ($script:fail -gt 0) { exit 1 } else { exit 0 }
}
