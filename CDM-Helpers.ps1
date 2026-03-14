# CDM-Helpers.ps1
# Reusable helper functions for CDM-Manager.
# Dot-sourced by CDM-Manager.ps1 - all functions land in the caller's scope.
# UI element variables ($consoleLog, $logScroller, etc.) are resolved at call time
# from the main script's scope, so no forward-reference issues.

$LOG_FILE = "$env:TEMP\cdm-manager-log.txt"
# Clear log file on startup so agents always see fresh output
"" | Set-Content $LOG_FILE -Encoding UTF8

function Write-Log ($Message) {
    $timestamp = Get-Date -Format "HH:mm:ss"
    $line = "[$timestamp] $Message"
    $consoleLog.AppendText("`n$line")
    $logScroller.ScrollToEnd()
    # Mirror every log line to file so AI agents can monitor it
    Add-Content -Path $LOG_FILE -Value $line -Encoding UTF8
}

function Set-PbiStatus ($Connected, $Label) {
    $color = if ($Connected) { "#00C853" } else { "#D32F2F" }
    $text  = if ($Label) { $Label } elseif ($Connected) { "Connected" } else { "Failed" }
    $pbiStatusDot.Background  = [System.Windows.Media.BrushConverter]::new().ConvertFromString($color)
    $pbiStatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($color)
    $pbiStatusText.Text       = $text
}

function Set-AdoStatus ($Connected, $Label) {
    $color = if ($Connected) { "#00C853" } else { "#D32F2F" }
    $text  = if ($Label) { $Label } elseif ($Connected) { "Connected" } else { "Failed" }
    $adoStatusDot.Background  = [System.Windows.Media.BrushConverter]::new().ConvertFromString($color)
    $adoStatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($color)
    $adoStatusText.Text       = $text
}

function Get-CleanBranchName ($fullName) {
    # Trim leading/trailing whitespace and git markers FIRST, then strip remote prefixes
    $t = $fullName.Trim("* ").Trim()
    return ($t -replace "^remotes/azure/|^remotes/origin/|^azure/|^origin/", "").Trim()
}

function Get-PbiToken {
    $f = "$env:TEMP\pbi_token.txt"
    if (-not (Test-Path $f)) { return $null }
    Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
    $raw = (Get-Content $f -Raw).Trim()
    try {
        $enc   = [System.Convert]::FromBase64String($raw)
        $bytes = [System.Security.Cryptography.ProtectedData]::Unprotect($enc, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        return [System.Text.Encoding]::UTF8.GetString($bytes)
    } catch { return $raw }  # fallback: plaintext (first-run or non-Windows)
}

function Update-BranchLock {
    $path  = $script:resolvedPbixPath
    $valid = ($path -like "*.pbix") -and (Test-Path $path)
    $comboTopBranch.IsEnabled = $valid
    if ($valid) {
        $topBranchHint.Text       = ""
        $topBranchHint.Visibility = "Collapsed"
        # Reveal Branch Management only for Existing Process
        if ($radioExistingProcess -and $radioExistingProcess.IsChecked) {
            $branchMgmtSection.Visibility = "Visible"
        }
    } else {
        $topBranchHint.Text       = if ($path -like "*.pbix") { "PBIX not found locally - download it first" } else { "Select a PBIX first" }
        $topBranchHint.Visibility = "Visible"
    }
}

function Find-PbiTools {
    # Check PATH first, then common install locations
    $cmd = Get-Command "pbi-tools.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        "$SCRIPT_DIR\pbi-tools.exe",
        "$LOCAL_PBIX_DIR\pbi-tools.exe",
        "$env:LOCALAPPDATA\pbi-tools\pbi-tools.exe",
        "$env:ProgramFiles\pbi-tools\pbi-tools.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    return $null
}

function Set-LastReportUrl ($deployOutput) {
    $line = $deployOutput | Where-Object { $_ -match "^REPORT_URL: " } | Select-Object -Last 1
    if ($line) {
        $script:lastReportUrl = $line -replace "^REPORT_URL: ", ""
        $btnOpenReport.IsEnabled  = $true
        $btnOpenReport.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#00897B")
        $btnOpenReport.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("White")
    }
}

function Refresh-SubBranches {
    $topBranch = $comboTopBranch.SelectedItem
    if (-not $topBranch) { $comboSubBranch.ItemsSource = @(); return }

    # Items stored as [PSCustomObject]@{ Display="feature/MM-TEST04"; FullName="feature/Production-Main/MM-TEST04" }
    $results  = [System.Collections.Generic.List[object]]::new()
    $seen     = [System.Collections.Generic.HashSet[string]]::new()
    $patterns = @("feature/$topBranch/*", "hotfix/$topBranch/*")

    $allBranches = @(git branch -r 2>$null | ForEach-Object { $_.Trim() } | Where-Object { $_ -notmatch "->|HEAD" } |
                    ForEach-Object { Get-CleanBranchName $_ }) +
                   @(git branch 2>$null | ForEach-Object { Get-CleanBranchName $_ })

    foreach ($clean in $allBranches) {
        foreach ($p in $patterns) {
            if ($clean -like $p -and $seen.Add($clean)) {
                # Display: drop the [TopBranch] segment -> "feature/MM-TEST04" instead of "feature/Production-Main/MM-TEST04"
                $display = $clean -replace "^(feature|hotfix)/[^/]+/", '$1/'
                $results.Add([PSCustomObject]@{ Display = $display; FullName = $clean })
                break
            }
        }
    }

    $comboSubBranch.DisplayMemberPath = "Display"
    $comboSubBranch.ItemsSource = ($results | Sort-Object Display)
}

function Refresh-UI {
    $branch = git branch --show-current 2>$null
    $currentBranchText.Text = "Current Branch: $(if ($branch) { $branch } else { 'None' })"

    # Clean names stored - strips azure/ so dropdown shows "Production-Main" not "azure/Production-Main"
    $topBranches = @(git branch -r 2>$null |
        ForEach-Object { Get-CleanBranchName $_ } |
        Where-Object { $_ -notmatch "->|HEAD|^feature/|^hotfix/" -and ($_ -like "*Main*" -or $_ -match "^main$|^master$") } |
        Select-Object -Unique)
    $comboTopBranch.ItemsSource = $topBranches
    Refresh-SubBranches
    Update-BranchLock
}
