# CDM-Manager.ps1
# Power BI Workflow Manager - v3.0
# Thin orchestrator: loads config, helpers, and XAML from separate files,
# then wires up all UI element references and event handlers.

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# Load configuration constants (sets $ADO_REMOTE_URL, $SCRIPT_DIR, $LOCAL_PBIX_DIR, $DEV_WORKSPACE_ID)
. "$PSScriptRoot\CDM-Config.ps1"

# Load helper functions (Write-Log, Get-PbiToken, Find-PbiTools, Refresh-UI, etc.)
. "$PSScriptRoot\CDM-Helpers.ps1"

# Load XAML layout from external file
$xamlContent = [System.IO.File]::ReadAllText("$PSScriptRoot\CDM-Manager.xaml")
$reader = [XML.XmlReader]::Create([IO.StringReader]($xamlContent))
$window = [Windows.Markup.XamlReader]::Load($reader)

# Map Elements
$currentBranchText  = $window.FindName("CurrentBranchText")
$consoleLog         = $window.FindName("ConsoleLog")
$logScroller        = $window.FindName("LogScroller")
$pbixPathText       = $window.FindName("PbixPathText")
$btnBrowsePbix      = $window.FindName("BtnBrowsePbix")
$comboTopBranch     = $window.FindName("ComboTopBranch")
$comboSubBranch     = $window.FindName("ComboSubBranch")
$radioFeature       = $window.FindName("RadioFeature")
$radioHotfix        = $window.FindName("RadioHotfix")
$lblNewBranch       = $window.FindName("LblNewBranch")
$txtNewFeature      = $window.FindName("TxtNewFeature")
$btnSwitchBranch    = $window.FindName("BtnSwitchBranch")
$btnCreateFeature   = $window.FindName("BtnCreateFeature")
$btnDeployDev       = $window.FindName("BtnDeployDev")
$btnDeployProd      = $window.FindName("BtnDeployProd")
$btnGithubSync      = $window.FindName("BtnGithubSync")
$btnCloudBackupOnly = $window.FindName("BtnCloudBackupOnly")
$chkCloudBackup     = $window.FindName("ChkCloudBackup")
$radioSemanticModel = $window.FindName("RadioSemanticModel")
$radioLiveConnect   = $window.FindName("RadioLiveConnect")
$pbiStatusDot       = $window.FindName("PbiStatusDot")
$pbiStatusText      = $window.FindName("PbiStatusText")
$adoStatusDot       = $window.FindName("AdoStatusDot")
$adoStatusText      = $window.FindName("AdoStatusText")
$comboWorkspace      = $window.FindName("ComboWorkspace")
$comboCdm            = $window.FindName("ComboCdm")
$btnDownloadCdm      = $window.FindName("BtnDownloadCdm")
$radioNewProcess         = $window.FindName("RadioNewProcess")
$radioExistingProcess    = $window.FindName("RadioExistingProcess")
$processHint             = $window.FindName("ProcessHint")
$panelStep2Wrapper       = $window.FindName("PanelStep2Wrapper")
$radioModelService       = $window.FindName("RadioModelService")
$radioModelLocal         = $window.FindName("RadioModelLocal")
$panelServiceControls    = $window.FindName("PanelServiceControls")
$lblWorkspace            = $window.FindName("LblWorkspace")
$panelNewLocalWorkspace  = $window.FindName("PanelNewLocalWorkspace")
$comboProdWorkspace      = $window.FindName("ComboProdWorkspace")
$panelPbixRow            = $window.FindName("PanelPbixRow")
$panelNewProcessAction   = $window.FindName("PanelNewProcessAction")
$btnBeginRegistration    = $window.FindName("BtnBeginRegistration")
$branchMgmtSection       = $window.FindName("BranchMgmtSection")
$btnSyncFromDev      = $window.FindName("BtnSyncFromDev")
$btnCompilePbix      = $window.FindName("BtnCompilePbix")
$btnUpdateMainBranch  = $window.FindName("BtnUpdateMainBranch")
$btnCreateMainBranch  = $window.FindName("BtnCreateMainBranch")
$topBranchHint        = $window.FindName("TopBranchHint")

$btnOpenReport       = $window.FindName("BtnOpenReport")
$panelManualOps      = $window.FindName("PanelManualOps")
$panelCloudGit       = $window.FindName("PanelCloudGit")

# Script-scope state variables
$script:selectedWorkspaceId = ""
$script:selectedDatasetId   = ""
$script:selectedCdmName     = ""
$script:lastReportUrl       = ""
$script:resolvedPbixPath    = ""

# Action buttons locked during background operations (REQ-030)
$script:actionButtons = @(
    $btnDownloadCdm, $btnSyncFromDev, $btnCompilePbix, $btnUpdateMainBranch,
    $btnCreateMainBranch, $btnBeginRegistration, $btnCreateFeature,
    $btnDeployDev, $btnDeployProd, $btnCloudBackupOnly, $btnGithubSync
)

# --- Events ---

$comboTopBranch.Add_SelectionChanged({ Refresh-SubBranches })
$radioFeature.Add_Click({ $lblNewBranch.Text = "New Feature Name" })
$radioHotfix.Add_Click({  $lblNewBranch.Text = "New Hotfix Name"  })

# Q1 handlers - reveal Step 2 and reset downstream panels
$radioNewProcess.Add_Checked({
    $processHint.Text              = "Registering a model for the first time - a new Top Branch will be created"
    $processHint.Visibility        = "Visible"
    $panelStep2Wrapper.Visibility  = "Visible"
    # Reset Q2 and hide all downstream controls
    $radioModelService.IsChecked       = $false
    $radioModelLocal.IsChecked         = $false
    $panelServiceControls.Visibility   = "Collapsed"
    $panelNewLocalWorkspace.Visibility = "Collapsed"
    $panelPbixRow.Visibility           = "Collapsed"
    $panelNewProcessAction.Visibility  = "Collapsed"
    $branchMgmtSection.Visibility      = "Collapsed"
    $panelManualOps.Visibility         = "Collapsed"
    $panelCloudGit.Visibility          = "Collapsed"
    $script:resolvedPbixPath           = ""
})

$radioExistingProcess.Add_Checked({
    $processHint.Text              = "Working with a tracked model - create or modify Sub-Branches"
    $processHint.Visibility        = "Visible"
    $panelStep2Wrapper.Visibility  = "Visible"
    # Reset Q2 and hide all downstream controls
    $radioModelService.IsChecked       = $false
    $radioModelLocal.IsChecked         = $false
    $panelServiceControls.Visibility   = "Collapsed"
    $panelNewLocalWorkspace.Visibility = "Collapsed"
    $panelPbixRow.Visibility           = "Collapsed"
    $panelNewProcessAction.Visibility  = "Collapsed"
    $branchMgmtSection.Visibility      = "Collapsed"
    $panelManualOps.Visibility         = "Collapsed"
    $panelCloudGit.Visibility          = "Collapsed"
    $script:resolvedPbixPath           = ""
})

# Q2 handlers - reveal model-specific controls
$radioModelService.Add_Checked({
    $isNew = [bool]$radioNewProcess.IsChecked
    $lblWorkspace.Text                 = if ($isNew) { "Production Workspace" } else { "Workspace" }
    $panelServiceControls.Visibility   = "Visible"
    $panelNewLocalWorkspace.Visibility = "Collapsed"
    $panelPbixRow.Visibility           = "Collapsed"
    $panelNewProcessAction.Visibility  = if ($isNew) { "Visible" } else { "Collapsed" }
    $script:resolvedPbixPath           = ""
    $panelManualOps.Visibility         = "Collapsed"
    $panelCloudGit.Visibility          = "Collapsed"
    Update-BranchLock
})

$radioModelLocal.Add_Checked({
    $isNew = [bool]$radioNewProcess.IsChecked
    $panelServiceControls.Visibility   = "Collapsed"
    $panelNewLocalWorkspace.Visibility = if ($isNew) { "Visible" } else { "Collapsed" }
    $panelPbixRow.Visibility           = "Visible"
    $btnBrowsePbix.Visibility          = "Visible"
    $panelNewProcessAction.Visibility  = if ($isNew) { "Visible" } else { "Collapsed" }
    $pbixPathText.Text                 = "Browse to your PBIX file..."
    $pbixPathText.Foreground           = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#888888")
    $script:resolvedPbixPath           = ""
    $panelManualOps.Visibility         = "Collapsed"
    $panelCloudGit.Visibility          = "Collapsed"
    Update-BranchLock
})

$comboWorkspace.Add_SelectionChanged({
    $ws = $comboWorkspace.SelectedItem
    if (-not $ws -or [string]::IsNullOrEmpty($ws.id)) { return }
    $token = Get-PbiToken
    if (-not $token) { Write-Log "[ERROR] No PBI token. Wait for login to complete."; return }
    try {
        $headers = @{ Authorization = "Bearer $token" }
        $resp    = Invoke-RestMethod -Uri "https://api.powerbi.com/v1.0/myorg/groups/$($ws.id)/datasets" -Headers $headers
        $datasets = $resp.value | Sort-Object name
        $comboCdm.DisplayMemberPath = "name"
        $comboCdm.ItemsSource = $datasets
        Write-Log "Workspace '$($ws.name)' selected. $($datasets.Count) semantic model(s) found."
    } catch {
        Write-Log "[ERROR] Could not load datasets: $_"
    }
})

$comboCdm.Add_SelectionChanged({
    $cdm = $comboCdm.SelectedItem
    if (-not $cdm -or [string]::IsNullOrEmpty($cdm.id)) { return }
    $script:selectedWorkspaceId = $comboWorkspace.SelectedItem.id
    $script:selectedDatasetId   = $cdm.id
    $script:selectedCdmName     = $cdm.name
    $localPath = Join-Path $LOCAL_PBIX_DIR "$($cdm.name).pbix"
    $script:resolvedPbixPath = $localPath
    $panelManualOps.Visibility = "Visible"
    $panelCloudGit.Visibility  = "Visible"
    Update-BranchLock
    # For Existing Process + Service: reveal Branch Management and auto-select the matching Top Branch
    if ($radioExistingProcess.IsChecked) {
        $branchMgmtSection.Visibility = "Visible"
        $expectedTop = "$($cdm.name)-Main"
        $match = $comboTopBranch.Items | Where-Object { $_ -eq $expectedTop } | Select-Object -First 1
        if ($match) {
            $comboTopBranch.SelectedItem = $match
            Write-Log "Auto-selected Top Branch: '$expectedTop'"
        } else {
            Write-Log "[WARN] No Top Branch found matching '$expectedTop'. Select one manually."
        }
    }
    Write-Log "CDM selected: '$($cdm.name)' | Local path: $localPath$(if (Test-Path $localPath) { ' [found locally]' } else { ' [not downloaded yet]' })"
})

# --- Button Handlers ---

$btnBrowsePbix.Add_Click({
    $fd = New-Object System.Windows.Forms.OpenFileDialog
    $fd.Filter = "Power BI Files (*.pbix)|*.pbix"
    if ($fd.InitialDirectory -eq "" -and (Test-Path $LOCAL_PBIX_DIR)) { $fd.InitialDirectory = $LOCAL_PBIX_DIR }
    if ($fd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $pbixPathText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("White")
        $pbixPathText.Text = $fd.FileName
        $script:resolvedPbixPath = $fd.FileName
        $panelManualOps.Visibility = "Visible"
        $panelCloudGit.Visibility  = "Visible"
        Update-BranchLock
        Write-Log "PBIX selected: $($fd.FileName)"
        # Existing Process + Local: auto-select the matching Top Branch
        if ($radioExistingProcess.IsChecked) {
            $modelName   = [System.IO.Path]::GetFileNameWithoutExtension($fd.FileName)
            $expectedTop = "$modelName-Main"
            $match = $comboTopBranch.Items | Where-Object { $_ -eq $expectedTop } | Select-Object -First 1
            if ($match) {
                $comboTopBranch.SelectedItem = $match
                Write-Log "Auto-selected Top Branch: '$expectedTop'"
            } else {
                Write-Log "[WARN] No Top Branch found matching '$expectedTop'. Select one manually."
            }
        }
    }
})

$btnDownloadCdm.Add_Click({
    $ws  = $comboWorkspace.SelectedItem
    $cdm = $comboCdm.SelectedItem
    if (-not $ws -or -not $cdm) { Write-Log "[ERROR] Select a workspace and CDM first."; return }

    $localPath = Join-Path $LOCAL_PBIX_DIR "$($cdm.name).pbix"
    $script:resolvedPbixPath = $localPath
    $panelManualOps.Visibility = "Visible"
    $panelCloudGit.Visibility  = "Visible"

    if (-not $btnDeployDev.IsEnabled) { Write-Log "[WARN] An operation is already running. Please wait for it to complete."; return }
    Write-Log "Starting download of '$($cdm.name)' to $localPath..."
    $script:actionButtons | ForEach-Object { $_.IsEnabled = $false }

    $dlRs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $dlRs.ApartmentState = [System.Threading.ApartmentState]::STA
    $dlRs.ThreadOptions  = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
    $dlRs.Open()
    $dlRs.SessionStateProxy.SetVariable('window',               $window)
    $dlRs.SessionStateProxy.SetVariable('consoleLog',           $consoleLog)
    $dlRs.SessionStateProxy.SetVariable('logScroller',          $logScroller)
    $dlRs.SessionStateProxy.SetVariable('btnDownloadCdm',       $btnDownloadCdm)
    $dlRs.SessionStateProxy.SetVariable('comboTopBranch',       $comboTopBranch)
    $dlRs.SessionStateProxy.SetVariable('topBranchHint',        $topBranchHint)
    $dlRs.SessionStateProxy.SetVariable('pbixPathText',         $pbixPathText)
    $dlRs.SessionStateProxy.SetVariable('radioExistingProcess', $radioExistingProcess)
    $dlRs.SessionStateProxy.SetVariable('branchMgmtSection',    $branchMgmtSection)
    $dlRs.SessionStateProxy.SetVariable('actionButtons',         $script:actionButtons)
    $dlRs.SessionStateProxy.SetVariable('wsId',                 $ws.id)
    $dlRs.SessionStateProxy.SetVariable('wsName',               $ws.name)
    $dlRs.SessionStateProxy.SetVariable('dsId',                 $cdm.id)
    $dlRs.SessionStateProxy.SetVariable('dsName',               $cdm.name)
    $dlRs.SessionStateProxy.SetVariable('localPath',            $localPath)

    $dlPs = [System.Management.Automation.PowerShell]::Create()
    $dlPs.Runspace = $dlRs
    $dlPs.AddScript({
        function dl_Log ($msg) {
            $ts = Get-Date -Format "HH:mm:ss"
            $e  = "`n[$ts] $msg"
            $window.Dispatcher.Invoke([action]{ $consoleLog.AppendText($e); $logScroller.ScrollToEnd() }.GetNewClosure())
        }

        try {
            Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
            $tokenRaw = (Get-Content "$env:TEMP\pbi_token.txt" -Raw).Trim()
            try {
                $tokenEnc = [System.Convert]::FromBase64String($tokenRaw)
                $tokenDec = [System.Security.Cryptography.ProtectedData]::Unprotect($tokenEnc, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
                $token    = [System.Text.Encoding]::UTF8.GetString($tokenDec)
            } catch { $token = $tokenRaw }
            $headers = @{ Authorization = "Bearer $token" }

            # Find a report connected to this dataset
            dl_Log "Finding report for '$dsName' in workspace..."
            $reports = (Invoke-RestMethod -Uri "https://api.powerbi.com/v1.0/myorg/groups/$wsId/reports" -Headers $headers).value
            $report  = $reports | Where-Object { $_.datasetId -eq $dsId } | Select-Object -First 1
            if (-not $report) {
                dl_Log "[ERROR] No report found for dataset '$dsName'. Cannot export PBIX."
                $window.Dispatcher.Invoke([action]{ $btnDownloadCdm.IsEnabled = $true }.GetNewClosure())
                return
            }

            dl_Log "Exporting PBIX for report '$($report.name)'... (this may take a moment for large files)"
            $exportUri = "https://api.powerbi.com/v1.0/myorg/groups/$wsId/reports/$($report.id)/Export"
            Invoke-RestMethod -Uri $exportUri -Headers $headers -OutFile $localPath -Method GET

            dl_Log "[SUCCESS] CDM downloaded to: $localPath"
            # Run Update-BranchLock logic: unlock Top Branch and reveal Branch Management if Existing Process
            $window.Dispatcher.Invoke([action]{
                $valid = ($localPath -like "*.pbix") -and (Test-Path $localPath)
                $comboTopBranch.IsEnabled = $valid
                if ($valid) {
                    $topBranchHint.Text       = ""
                    $topBranchHint.Visibility = "Collapsed"
                    if ($radioExistingProcess -and $radioExistingProcess.IsChecked) {
                        $branchMgmtSection.Visibility = "Visible"
                    }
                } else {
                    $topBranchHint.Text       = "PBIX not found locally - download it first"
                    $topBranchHint.Visibility = "Visible"
                }
            }.GetNewClosure())
        } catch {
            dl_Log "[ERROR] Download failed: $_"
        } finally {
            $window.Dispatcher.Invoke([action]{ $actionButtons | ForEach-Object { $_.IsEnabled = $true } }.GetNewClosure())
        }
    }) | Out-Null
    $dlPs.BeginInvoke() | Out-Null
})

$btnOpenReport.Add_Click({
    # $script:lastReportUrl is set on UI thread; $window.Tag is the cross-runspace fallback
    $url = if ($script:lastReportUrl) { $script:lastReportUrl } else { [string]$window.Tag }
    if ($url) { Start-Process $url }
})

$btnBeginRegistration.Add_Click({
    # Delegate to the main Create Main Branch handler
    $btnCreateMainBranch.RaiseEvent(
        [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)
    )
})

$btnSyncFromDev.Add_Click({
    # --- Guards ---
    $pbiTools = Find-PbiTools
    if (-not $pbiTools) {
        Write-Log "[ERROR] pbi-tools.exe not found. Required for PBIX -> PBIP extraction."
        [System.Windows.MessageBox]::Show(
            "pbi-tools.exe is required.`n`nDownload from:`nhttps://github.com/pbi-tools/pbi-tools/releases`n`nPlace in: $SCRIPT_DIR",
            "pbi-tools Not Found", "OK", "Warning") | Out-Null
        return
    }

    $token = Get-PbiToken
    if (-not $token) { Write-Log "[ERROR] No PBI token. Wait for login to complete."; return }

    $branch = git -C $SCRIPT_DIR branch --show-current 2>$null
    if (-not $branch) { Write-Log "[ERROR] Not on any branch."; return }

    # --- Resolve sync source: selected workspace/CDM if available, else Dev fallback ---
    $headers = @{ Authorization = "Bearer $token" }
    $syncWorkspaceId = $null
    $match           = $null

    if ($script:selectedWorkspaceId -and $script:selectedDatasetId) {
        # Service path: use the selected workspace + find report by datasetId
        $syncWorkspaceId = $script:selectedWorkspaceId
        $wsLabel         = if ($script:selectedCdmName) { $script:selectedCdmName } else { $syncWorkspaceId }
        Write-Log "Syncing from selected workspace using model '$wsLabel'..."
        try {
            $reports = (Invoke-RestMethod -Uri "https://api.powerbi.com/v1.0/myorg/groups/$syncWorkspaceId/reports" -Headers $headers).value
            $match   = $reports | Where-Object { $_.datasetId -eq $script:selectedDatasetId } | Select-Object -First 1
        } catch {
            Write-Log "[ERROR] Could not load reports from selected workspace: $_"; return
        }
        if (-not $match) {
            Write-Log "[ERROR] No report found for the selected model in that workspace."
            [System.Windows.MessageBox]::Show(
                "No report was found connected to '$wsLabel' in the selected workspace.`n`nPublish the model to that workspace first.",
                "Report Not Found", "OK", "Warning") | Out-Null
            return
        }
    } else {
        # Fallback: Dev workspace, match by branch name segment
        $syncWorkspaceId = $DEV_WORKSPACE_ID
        $shortName = $branch -replace "^(feature|hotfix)/[^/]+/", ""
        Write-Log "No model selected - falling back to Dev workspace, matching by branch name '$shortName'..."
        try {
            $reports = (Invoke-RestMethod -Uri "https://api.powerbi.com/v1.0/myorg/groups/$DEV_WORKSPACE_ID/reports" -Headers $headers).value
        } catch {
            Write-Log "[ERROR] Could not load Dev workspace reports: $_"; return
        }
        $match = $reports | Where-Object { $_.name -eq $shortName } | Select-Object -First 1
        if (-not $match) { $match = $reports | Where-Object { $_.name -like "*$shortName*" } | Select-Object -First 1 }
        if (-not $match) {
            Write-Log "[ERROR] No report matching '$shortName' found in Dev workspace."
            [System.Windows.MessageBox]::Show(
                "No report matching '$shortName' found in the Dev workspace.`n`nDeploy the branch to Dev first, or select a model in CDM Selection.",
                "Report Not Found", "OK", "Warning") | Out-Null
            return
        }
    }

    # --- Determine PBIP base name ---
    $pbipBase = (Get-ChildItem $SCRIPT_DIR -Directory -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -like "*.SemanticModel" } |
                 Select-Object -First 1).Name -replace "\.SemanticModel$", ""
    if (-not $pbipBase) { $pbipBase = if ($script:selectedCdmName) { $script:selectedCdmName } else { "CDM" } }

    $tempPbix = Join-Path $env:TEMP "$pbipBase.pbix"

    $confirm = [System.Windows.MessageBox]::Show(
        "Sync branch '$branch' from report '$($match.name)'?`n`nThis will:`n  1. Download PBIX from the service`n  2. Extract PBIP files into repo ($SCRIPT_DIR)`n  3. Commit changes to '$branch'`n`nAny uncommitted local changes to PBIP files will be overwritten.",
        "Sync from Service", "YesNo", "Warning")
    if ($confirm -ne "Yes") { return }

    if (-not $btnDeployDev.IsEnabled) { Write-Log "[WARN] An operation is already running. Please wait for it to complete."; return }
    Write-Log "Starting sync of '$($match.name)' to branch '$branch'..."
    $script:actionButtons | ForEach-Object { $_.IsEnabled = $false }

    # --- Background runspace ---
    $syncRs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $syncRs.ApartmentState = [System.Threading.ApartmentState]::STA
    $syncRs.ThreadOptions  = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
    $syncRs.Open()
    $syncRs.SessionStateProxy.SetVariable('window',           $window)
    $syncRs.SessionStateProxy.SetVariable('consoleLog',       $consoleLog)
    $syncRs.SessionStateProxy.SetVariable('logScroller',      $logScroller)
    $syncRs.SessionStateProxy.SetVariable('btnSyncFromDev',   $btnSyncFromDev)
    $syncRs.SessionStateProxy.SetVariable('reportId',         $match.id)
    $syncRs.SessionStateProxy.SetVariable('reportName',       $match.name)
    $syncRs.SessionStateProxy.SetVariable('branch',           $branch)
    $syncRs.SessionStateProxy.SetVariable('tempPbix',         $tempPbix)
    $syncRs.SessionStateProxy.SetVariable('pbipBase',         $pbipBase)
    $syncRs.SessionStateProxy.SetVariable('SCRIPT_DIR',       $SCRIPT_DIR)
    $syncRs.SessionStateProxy.SetVariable('pbiTools',         $pbiTools)
    $syncRs.SessionStateProxy.SetVariable('syncWorkspaceId',  $syncWorkspaceId)
    $syncRs.SessionStateProxy.SetVariable('actionButtons',    $script:actionButtons)
    $syncRs.SessionStateProxy.SetVariable('currentUserUpn',  ([string]$window.Tag))

    $syncPs = [System.Management.Automation.PowerShell]::Create()
    $syncPs.Runspace = $syncRs
    $syncPs.AddScript({
        function sync_Log ($msg) {
            $ts = Get-Date -Format "HH:mm:ss"
            $e  = "`n[$ts] $msg"
            $window.Dispatcher.Invoke([action]{ $consoleLog.AppendText($e); $logScroller.ScrollToEnd() }.GetNewClosure())
        }
        try {
            Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
            $tokenRaw = (Get-Content "$env:TEMP\pbi_token.txt" -Raw).Trim()
            try {
                $tokenEnc = [System.Convert]::FromBase64String($tokenRaw)
                $tokenDec = [System.Security.Cryptography.ProtectedData]::Unprotect($tokenEnc, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
                $token    = [System.Text.Encoding]::UTF8.GetString($tokenDec)
            } catch { $token = $tokenRaw }
            $headers = @{ Authorization = "Bearer $token" }

            # Step 1: Download PBIX from service
            sync_Log "Step 1: Downloading '$reportName' from service..."
            $exportUri = "https://api.powerbi.com/v1.0/myorg/groups/$syncWorkspaceId/reports/$reportId/Export"
            Invoke-RestMethod -Uri $exportUri -Headers $headers -OutFile $tempPbix -Method GET
            sync_Log "Download complete: $tempPbix"

            # Step 2: Extract PBIP files using pbi-tools
            sync_Log "Step 2: Extracting PBIP files to repo ($SCRIPT_DIR)..."
            $extractOut = & $pbiTools extract $tempPbix -extractFolder $SCRIPT_DIR 2>&1
            sync_Log ($extractOut -join "`n")
            if ($LASTEXITCODE -ne 0) { throw "pbi-tools extract failed (exit $LASTEXITCODE)" }

            # Step 3: Stage all PBIP changes
            sync_Log "Step 3: Staging PBIP changes..."
            git -C $SCRIPT_DIR add -- "*.SemanticModel" "*.Report" 2>&1 | Out-Null
            # Catch any subfolder changes too
            $semanticFolder = Join-Path $SCRIPT_DIR "$pbipBase.SemanticModel"
            $reportFolder   = Join-Path $SCRIPT_DIR "$pbipBase.Report"
            if (Test-Path $semanticFolder) { git -C $SCRIPT_DIR add -- "$pbipBase.SemanticModel/" 2>&1 | Out-Null }
            if (Test-Path $reportFolder)   { git -C $SCRIPT_DIR add -- "$pbipBase.Report/" 2>&1 | Out-Null }

            # Step 4: Commit
            sync_Log "Step 4: Committing to branch '$branch'..."
            $upnSuffix = if ($currentUserUpn) { " [$currentUserUpn]" } else { "" }
            $commitMsg = "sync: update PBIP from Dev report '$reportName'$upnSuffix"
            $commitOut = git -C $SCRIPT_DIR commit -m $commitMsg 2>&1
            sync_Log ($commitOut -join "`n")

            if ($LASTEXITCODE -eq 0) {
                sync_Log "[SUCCESS] Branch '$branch' is now in sync with Dev report '$reportName'."
            } else {
                sync_Log "[INFO] No changes to commit - branch is already in sync."
            }

            # Cleanup temp file
            Remove-Item $tempPbix -ErrorAction SilentlyContinue

        } catch {
            sync_Log "[ERROR] Sync failed: $_"
        } finally {
            $window.Dispatcher.Invoke([action]{ $actionButtons | ForEach-Object { $_.IsEnabled = $true } }.GetNewClosure())
        }
    }) | Out-Null
    $syncPs.BeginInvoke() | Out-Null
})

$btnCompilePbix.Add_Click({
    $pbiTools = Find-PbiTools
    if (-not $pbiTools) {
        Write-Log "[ERROR] pbi-tools.exe not found. Required to compile PBIP to PBIX."
        [System.Windows.MessageBox]::Show(
            "pbi-tools.exe is required.`n`nDownload from:`nhttps://github.com/pbi-tools/pbi-tools/releases`n`nPlace in: $SCRIPT_DIR",
            "pbi-tools Not Found", "OK", "Warning") | Out-Null
        return
    }

    # Detect PBIP base name from current branch folder
    $pbipBase = (Get-ChildItem $SCRIPT_DIR -Directory -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -like "*.Report" } |
                 Select-Object -First 1).Name -replace "\.Report$", ""
    if (-not $pbipBase) {
        Write-Log "[ERROR] No PBIP folder found in the current branch. Switch to a branch that has PBIP files."
        return
    }

    # Ask user where to save the PBIX
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter      = "Power BI Files (*.pbix)|*.pbix"
    $sfd.FileName    = "$pbipBase.pbix"
    $sfd.InitialDirectory = $LOCAL_PBIX_DIR
    if ($sfd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $outPath = $sfd.FileName

    Write-Log "Compiling PBIP '$pbipBase' to PBIX: $outPath..."
    $btnCompilePbix.IsEnabled = $false

    $compileOut = & $pbiTools compile $SCRIPT_DIR -outPath $outPath 2>&1
    Write-Log ($compileOut -join "`n")

    if ($LASTEXITCODE -eq 0) {
        $pbixPathText.Text       = $outPath
        $pbixPathText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("White")
        $script:resolvedPbixPath = $outPath
        $panelManualOps.Visibility = "Visible"
        $panelCloudGit.Visibility  = "Visible"
        Update-BranchLock
        Write-Log "[SUCCESS] PBIX compiled to: $outPath - you can now Deploy from this file."
    } else {
        Write-Log "[ERROR] Compile failed. Check output above."
    }
    $btnCompilePbix.IsEnabled = $true
})

$btnUpdateMainBranch.Add_Click({
    $pbixPath = $script:resolvedPbixPath
    if (-not (Test-Path $pbixPath)) { Write-Log "[ERROR] PBIX not found: $pbixPath"; return }

    $branch = git branch --show-current 2>$null
    if ($branch -notlike "*Main*" -and $branch -ne "main") {
        $result = [System.Windows.MessageBox]::Show(
            "You are on branch '$branch', not a Main branch.`n`nUpdate Main Branch should only run on a Main branch to avoid overwriting in-progress work.`n`nContinue anyway?",
            "Branch Warning", "YesNo", "Warning")
        if ($result -ne "Yes") { return }
    }

    $pbiTools = Find-PbiTools
    if (-not $pbiTools) {
        Write-Log "[ERROR] pbi-tools.exe not found. Download it from https://github.com/pbi-tools/pbi-tools/releases and place it in: $SCRIPT_DIR"
        [System.Windows.MessageBox]::Show(
            "pbi-tools.exe is required to convert PBIX to PBIP format.`n`nDownload it from:`nhttps://github.com/pbi-tools/pbi-tools/releases`n`nPlace pbi-tools.exe in:`n$SCRIPT_DIR",
            "pbi-tools Not Found", "OK", "Warning") | Out-Null
        return
    }

    $confirm = [System.Windows.MessageBox]::Show(
        "This will extract '$pbixPath' into PBIP format and overwrite the current SemanticModel/ and Report/ folders in:`n$SCRIPT_DIR`n`nCommit the changes to branch '$branch'?",
        "Update Main Branch", "YesNo", "Warning")
    if ($confirm -ne "Yes") { return }

    Write-Log "Extracting PBIX to PBIP format using pbi-tools..."
    $btnUpdateMainBranch.IsEnabled = $false

    $extractOut = & $pbiTools extract $pbixPath -extractFolder $SCRIPT_DIR 2>&1
    Write-Log ($extractOut -join "`n")

    if ($LASTEXITCODE -ne 0) {
        Write-Log "[ERROR] pbi-tools extract failed. Check output above."
        $btnUpdateMainBranch.IsEnabled = $true
        return
    }

    Write-Log "Staging PBIP changes..."
    git -C $SCRIPT_DIR add "*.SemanticModel" "*.Report" 2>&1 | Out-Null
    git -C $SCRIPT_DIR add -A "*.SemanticModel/" "*.Report/" 2>&1 | Out-Null

    $upnTag    = if ($window.Tag) { " [$([string]$window.Tag)]" } else { "" }
    $commitMsg = "chore: update PBIP from downloaded PBIX [$($cdmName = $script:selectedCdmName; if ($cdmName) { $cdmName } else { (Split-Path $pbixPath -Leaf) -replace '\.pbix$','' })]$upnTag"
    $commitOut = git -C $SCRIPT_DIR commit -m $commitMsg 2>&1
    Write-Log ($commitOut -join "`n")

    if ($LASTEXITCODE -eq 0) {
        Write-Log "[SUCCESS] Main branch updated with latest PBIP files."
    } else {
        Write-Log "[WARN] Nothing to commit or commit failed. Check output above."
    }

    $btnUpdateMainBranch.IsEnabled = $true
})

$btnCreateMainBranch.Add_Click({
    # --- Guard: PBIX ---
    $pbixPath = $script:resolvedPbixPath
    if (-not (Test-Path $pbixPath)) {
        Write-Log "[ERROR] PBIX not found: $pbixPath. Browse to or download the PBIX first."
        return
    }

    # --- Guard: Production workspace (New+Service uses ComboWorkspace; New+Local uses ComboProdWorkspace) ---
    $prodWsItem = if ($radioModelLocal.IsChecked) { $comboProdWorkspace.SelectedItem } else { $comboWorkspace.SelectedItem }
    if (-not $prodWsItem -or [string]::IsNullOrEmpty($prodWsItem.id)) {
        Write-Log "[ERROR] Select a Production Workspace before creating a new Main branch."
        [System.Windows.MessageBox]::Show(
            "A Production Workspace must be selected before creating a new Main branch.`n`nIn CDM Selection, choose the workspace where this model will be published.",
            "Production Workspace Required", "OK", "Warning") | Out-Null
        return
    }

    # --- Guard: pbi-tools ---
    $pbiTools = Find-PbiTools
    if (-not $pbiTools) {
        Write-Log "[ERROR] pbi-tools.exe not found. Place it in: $SCRIPT_DIR"
        [System.Windows.MessageBox]::Show(
            "pbi-tools.exe is required for PBIP extraction.`n`nDownload from:`nhttps://github.com/pbi-tools/pbi-tools/releases`n`nPlace in: $SCRIPT_DIR",
            "pbi-tools Not Found", "OK", "Warning") | Out-Null
        return
    }

    $pbixName        = [System.IO.Path]::GetFileNameWithoutExtension($pbixPath)
    $mainBranch      = "$pbixName-Main"
    $prodWorkspaceId = $prodWsItem.id
    $prodWsName      = $prodWsItem.name
    $tempWorktree    = Join-Path $env:TEMP "pbi-new-model-$(Get-Date -Format 'yyyyMMddHHmmss')"

    $confirm = [System.Windows.MessageBox]::Show(
        "Register '$pbixName' as a new model?`n`nThis will:`n  1. Fetch latest from ADO`n  2. Create a clean orphan branch '$mainBranch' (no inherited history)`n  3. Extract PBIP files from the local PBIX`n  4. Commit PBIP to '$mainBranch' and push to ADO`n  5. Publish model to Production workspace:`n     '$prodWsName'",
        "Create Main Branch - New Model", "YesNo", "Warning")
    if ($confirm -ne "Yes") { return }

    if (-not $btnDeployDev.IsEnabled) { Write-Log "[WARN] An operation is already running. Please wait for it to complete."; return }
    Write-Log "Registering new model '$pbixName' - creating orphan branch '$mainBranch'..."
    $script:actionButtons | ForEach-Object { $_.IsEnabled = $false }

    $cmRs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $cmRs.ApartmentState = [System.Threading.ApartmentState]::STA
    $cmRs.ThreadOptions  = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
    $cmRs.Open()
    $cmRs.SessionStateProxy.SetVariable('window',              $window)
    $cmRs.SessionStateProxy.SetVariable('consoleLog',          $consoleLog)
    $cmRs.SessionStateProxy.SetVariable('logScroller',         $logScroller)
    $cmRs.SessionStateProxy.SetVariable('btnCreateMainBranch', $btnCreateMainBranch)
    $cmRs.SessionStateProxy.SetVariable('actionButtons',       $script:actionButtons)
    $cmRs.SessionStateProxy.SetVariable('currentUserUpn',     ([string]$window.Tag))
    $cmRs.SessionStateProxy.SetVariable('btnOpenReport',       $btnOpenReport)
    $cmRs.SessionStateProxy.SetVariable('comboTopBranch',      $comboTopBranch)
    $cmRs.SessionStateProxy.SetVariable('pbixPath',            $pbixPath)
    $cmRs.SessionStateProxy.SetVariable('pbixName',            $pbixName)
    $cmRs.SessionStateProxy.SetVariable('mainBranch',          $mainBranch)
    $cmRs.SessionStateProxy.SetVariable('SCRIPT_DIR',          $SCRIPT_DIR)
    $cmRs.SessionStateProxy.SetVariable('pbiTools',            $pbiTools)
    $cmRs.SessionStateProxy.SetVariable('prodWorkspaceId',     $prodWorkspaceId)
    $cmRs.SessionStateProxy.SetVariable('prodWsName',          $prodWsName)
    $cmRs.SessionStateProxy.SetVariable('tempWorktree',        $tempWorktree)

    $cmPs = [System.Management.Automation.PowerShell]::Create()
    $cmPs.Runspace = $cmRs
    $cmPs.AddScript({
        function cm_Log ($msg) {
            $ts = Get-Date -Format "HH:mm:ss"
            $e  = "`n[$ts] $msg"
            $window.Dispatcher.Invoke([action]{ $consoleLog.AppendText($e); $logScroller.ScrollToEnd() }.GetNewClosure())
        }

        try {
            # Step 1: Fetch latest from ADO
            cm_Log "Step 1: Fetching latest from ADO..."
            git -C $SCRIPT_DIR fetch azure 2>&1 | Out-Null

            # Guard: abort if branch already exists on remote
            $existing = git -C $SCRIPT_DIR branch -r 2>$null | Where-Object { $_ -match [regex]::Escape("azure/$mainBranch") }
            if ($existing) {
                cm_Log "[ERROR] Branch '$mainBranch' already exists on ADO remote. Aborting."
                $window.Dispatcher.Invoke([action]{ $btnCreateMainBranch.IsEnabled = $true }.GetNewClosure())
                return
            }

            # Step 2: Create an isolated worktree - main working directory is never touched
            cm_Log "Step 2: Creating isolated worktree at '$tempWorktree'..."
            $wtOut = git -C $SCRIPT_DIR worktree add --detach $tempWorktree 2>&1
            cm_Log ($wtOut -join "`n")
            if ($LASTEXITCODE -ne 0) { throw "Worktree creation failed (exit $LASTEXITCODE)" }

            # Step 3: Create orphan branch inside the worktree
            cm_Log "Step 3: Creating orphan branch '$mainBranch' inside worktree..."
            $orphanOut = git -C $tempWorktree checkout --orphan $mainBranch 2>&1
            cm_Log ($orphanOut -join "`n")
            if ($LASTEXITCODE -ne 0) { throw "Orphan branch creation failed (exit $LASTEXITCODE)" }

            # Step 4: Clear inherited index and worktree files - only affects the temp dir
            cm_Log "Step 4: Clearing inherited files from worktree (main directory untouched)..."
            git -C $tempWorktree rm -rf . --ignore-unmatch 2>&1 | Out-Null

            # Step 5: Extract PBIP files into the isolated worktree
            cm_Log "Step 5: Extracting PBIP files into worktree..."
            $extractOut = & $pbiTools extract $pbixPath -extractFolder $tempWorktree 2>&1
            cm_Log ($extractOut -join "`n")
            if ($LASTEXITCODE -ne 0) { throw "pbi-tools extract failed (exit $LASTEXITCODE)" }

            # Step 6: Stage only this model's PBIP folders
            cm_Log "Step 6: Staging PBIP for '$pbixName'..."
            git -C $tempWorktree add -- "$pbixName.SemanticModel/" "$pbixName.Report/" 2>&1 | Out-Null

            # Step 7: Commit to the orphan branch
            cm_Log "Step 7: Committing PBIP to orphan branch '$mainBranch'..."
            $upnSuffix = if ($currentUserUpn) { " [$currentUserUpn]" } else { "" }
            $commitOut = git -C $tempWorktree commit -m "init: add PBIP for $pbixName$upnSuffix" 2>&1
            cm_Log ($commitOut -join "`n")
            if ($LASTEXITCODE -ne 0) { throw "Commit failed - no PBIP files staged or nothing to commit" }

            # Step 8: Push orphan branch to ADO
            cm_Log "Step 8: Pushing orphan branch '$mainBranch' to ADO..."
            $pushOut = git -C $tempWorktree push azure "${mainBranch}:${mainBranch}" -u 2>&1
            cm_Log ($pushOut -join "`n")
            if ($LASTEXITCODE -ne 0) { throw "Push to ADO failed (exit $LASTEXITCODE)" }

            cm_Log "[SUCCESS] '$mainBranch' is live in ADO as a clean orphan branch."

            # Step 9: Remove the temporary worktree and refresh remote tracking
            cm_Log "Step 9: Cleaning up worktree..."
            git -C $SCRIPT_DIR worktree remove $tempWorktree --force 2>&1 | Out-Null
            git -C $SCRIPT_DIR fetch azure 2>&1 | Out-Null

            # Step 10: Auto-publish to Production
            cm_Log "Step 10: Publishing '$pbixName' to Production workspace '$prodWsName'..."
            $deployOut = powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_DIR\deploy-pbi.ps1" `
                -TargetEnv Prod -BranchName $mainBranch -PbixPath $pbixPath -ProdWorkspaceId $prodWorkspaceId 2>&1
            cm_Log ($deployOut -join "`n")

            $urlLine = $deployOut | Where-Object { $_ -match "^REPORT_URL: " } | Select-Object -Last 1
            if ($urlLine) {
                $reportUrl = $urlLine -replace "^REPORT_URL: ", ""
                # $window.Tag is the cross-runspace URL transport; $btnOpenReport.Add_Click reads it as fallback
                $window.Dispatcher.Invoke([action]{
                    $window.Tag = $reportUrl
                    $btnOpenReport.IsEnabled  = $true
                    $btnOpenReport.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#00897B")
                    $btnOpenReport.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("White")
                }.GetNewClosure())
                cm_Log "[SUCCESS] Model published. Click 'Open Last Deployed Report' to verify in the browser."
            } else {
                cm_Log "[WARN] Deploy completed but no report URL returned. Check output above."
            }

            # Refresh Top Branch dropdown to surface the new branch
            $updatedBranches = @(git -C $SCRIPT_DIR branch -r 2>$null |
                ForEach-Object { ($_.Trim() -replace "remotes/azure/|remotes/origin/|^azure/|^origin/","").Trim() } |
                Where-Object { $_ -notmatch "->|HEAD|^feature/|^hotfix/" -and ($_ -like "*Main*" -or $_ -match "^main$|^master$") } |
                Select-Object -Unique)
            $window.Dispatcher.Invoke([action]{
                $comboTopBranch.ItemsSource = $updatedBranches
            }.GetNewClosure())

        } catch {
            cm_Log "[ERROR] New model registration failed: $_"
            # Clean up worktree if it was created before the failure
            if (Test-Path $tempWorktree) {
                cm_Log "Cleaning up worktree after failure..."
                git -C $SCRIPT_DIR worktree remove $tempWorktree --force 2>&1 | Out-Null
            }
        } finally {
            $window.Dispatcher.Invoke([action]{ $actionButtons | ForEach-Object { $_.IsEnabled = $true } }.GetNewClosure())
        }
    }) | Out-Null
    $cmPs.BeginInvoke() | Out-Null
})

$btnSwitchBranch.Add_Click({
    $selected = $comboSubBranch.SelectedItem
    if ($selected) {
        $fullName = $selected.FullName
        Write-Log "Switching to $fullName..."
        $out = git -C $SCRIPT_DIR checkout $fullName 2>&1
        Write-Log $out
        Refresh-UI
    }
})

$btnCreateFeature.Add_Click({
    $top  = Get-CleanBranchName $comboTopBranch.SelectedItem
    $name = $txtNewFeature.Text.Trim()
    if (-not $top -or -not $name) { Write-Log "[ERROR] Select a Top Branch and enter a name."; return }

    $prefix     = if ($radioHotfix.IsChecked) { "hotfix/" } else { "feature/" }
    $newBranch  = "$prefix$top/$name"
    $selectedPbix = $script:resolvedPbixPath

    Write-Log "1. Fetching latest from ADO..."
    git -C $SCRIPT_DIR fetch azure 2>&1 | Out-Null

    Write-Log "2. Creating $newBranch from azure/$top (no branch switch)..."
    $branchOut = git -C $SCRIPT_DIR branch $newBranch "azure/$top" 2>&1
    Write-Log $branchOut
    if ($LASTEXITCODE -ne 0) {
        Write-Log "[ERROR] Branch creation failed."
        return
    }

    Write-Log "3. Pushing to ADO..."
    $pushOut = git -C $SCRIPT_DIR push azure "$newBranch`:$newBranch" -u 2>&1
    Write-Log $pushOut
    if ($LASTEXITCODE -ne 0) {
        Write-Log "[ERROR] Push to ADO failed."
        return
    }

    Write-Log "4. Deploying to DEV..."
    $backupParam = if ($chkCloudBackup.IsChecked) { "-CloudBackup" } else { "" }
    $liveParam   = if ($radioLiveConnect.IsChecked)  { "-LiveConnect" } else { "" }
    $wsParam     = if ($script:selectedWorkspaceId) { "-ProdWorkspaceId '$($script:selectedWorkspaceId)'" } else { "" }
    $dsParam     = if ($script:selectedDatasetId)   { "-ProdDatasetId '$($script:selectedDatasetId)'" }   else { "" }
    $output = powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$SCRIPT_DIR\deploy-pbi.ps1 -TargetEnv Dev -BranchName '$name' -PbixPath '$selectedPbix' $backupParam $liveParam $wsParam $dsParam *>&1"
    Write-Log ($output -join "`n")
    Set-LastReportUrl $output

    $prevTop = $comboTopBranch.SelectedItem
    Refresh-UI
    if ($prevTop -and $comboTopBranch.Items.Contains($prevTop)) { $comboTopBranch.SelectedItem = $prevTop }
    $txtNewFeature.Text = ""

    if ($output -match "successful|successfully") {
        Write-Log "[SUCCESS] $newBranch created and deployed to Dev."
    } else {
        Write-Log "[WARN] $newBranch created in ADO. Check deploy output above for Power BI status."
    }
})

$btnDeployDev.Add_Click({
    $branch       = git branch --show-current
    $cleanName    = $branch -replace "^(feature|hotfix)/", ""
    $selectedPbix = $script:resolvedPbixPath

    # --- 4-Page Governance Check ---
    # Count report pages in the current branch's PBIP Report folder (PBIP v1: definition/pages/; v0: sections in report.json)
    $reportFolders = Get-ChildItem -Path $SCRIPT_DIR -Filter "*.Report" -Directory -ErrorAction SilentlyContinue
    if ($reportFolders) {
        $reportFolder = $reportFolders[0].FullName
        # PBIP v1: pages are sub-folders inside definition/pages/
        $pagesDir = Join-Path $reportFolder "definition\pages"
        if (Test-Path $pagesDir) {
            $pageCount = @(Get-ChildItem -Path $pagesDir -Directory).Count
        } else {
            # PBIP v0: sections array in report.json
            $reportJson = Join-Path $reportFolder "report.json"
            if (Test-Path $reportJson) {
                $rpt = Get-Content $reportJson -Raw | ConvertFrom-Json
                $pageCount = if ($rpt.sections) { $rpt.sections.Count } elseif ($rpt.reportSection) { $rpt.reportSection.Count } else { 0 }
            } else { $pageCount = 0 }
        }
        if ($pageCount -gt 4) {
            $extra = $pageCount - 4
            $msg = "Dev deployments must contain only the first 4 pages (governance rule).`n`nThis branch has $pageCount pages ($extra too many).`n`nHide the extra pages in Power BI Desktop before deploying to Dev."
            [System.Windows.MessageBox]::Show($msg, "4-Page Limit Exceeded", "OK", "Warning") | Out-Null
            Write-Log "[BLOCKED] Dev deploy blocked: $pageCount pages found, max is 4."
            return
        } elseif ($pageCount -gt 0) {
            Write-Log "Page check passed: $pageCount page(s) found (max 4)."
        }
    }

    Write-Log "Deploying '$cleanName' to DEV..."
    $backupParam = if ($chkCloudBackup.IsChecked) { "-CloudBackup" } else { "" }
    $liveParam   = if ($radioLiveConnect.IsChecked)  { "-LiveConnect" } else { "" }
    $wsParam     = if ($script:selectedWorkspaceId) { "-ProdWorkspaceId '$($script:selectedWorkspaceId)'" } else { "" }
    $dsParam     = if ($script:selectedDatasetId)   { "-ProdDatasetId '$($script:selectedDatasetId)'" }   else { "" }
    $output = powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$SCRIPT_DIR\deploy-pbi.ps1 -TargetEnv Dev -BranchName '$cleanName' -PbixPath '$selectedPbix' $backupParam $liveParam $wsParam $dsParam *>&1"
    Write-Log ($output -join "`n")
    Set-LastReportUrl $output
})

$btnDeployProd.Add_Click({
    $branch = git -C $SCRIPT_DIR branch --show-current
    if ($branch -notlike "*Main*" -and $branch -ne "main") {
        Write-Log "[ERROR] Production deployments only allowed from Main branches."
        return
    }

    # --- REQ-020: PR Verification Gate ---
    $prCheck = [System.Windows.MessageBox]::Show(
        "PRE-DEPLOYMENT CHECKLIST`n`nBefore deploying to Production, confirm:`n`n" +
        "  [1] A Pull Request has been completed and merged into '$branch' in Azure DevOps.`n" +
        "  [2] The merged PBIX has been committed to this Main branch (Update Main Branch done).`n" +
        "  [3] The model has been validated in the Dev workspace.`n`n" +
        "Have all of these steps been completed?",
        "Production Gate - Confirm PR Merged", "YesNo", "Warning")
    if ($prCheck -ne "Yes") {
        Write-Log "[CANCELLED] Prod deploy cancelled - complete the PR and validation steps first."
        return
    }

    $result = [System.Windows.MessageBox]::Show("Deploy '$branch' to PRODUCTION workspace?", "Final Safety Check", "YesNo", "Warning")
    if ($result -eq "Yes") {
        $selectedPbix = $script:resolvedPbixPath
        Write-Log "Deploying '$branch' to PROD..."
        $backupParam = if ($chkCloudBackup.IsChecked) { "-CloudBackup" } else { "" }
        $wsParam     = if ($script:selectedWorkspaceId) { "-ProdWorkspaceId '$($script:selectedWorkspaceId)'" } else { "" }
        $dsParam     = if ($script:selectedDatasetId)   { "-ProdDatasetId '$($script:selectedDatasetId)'" }   else { "" }
        $output = powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$SCRIPT_DIR\deploy-pbi.ps1 -TargetEnv Prod -BranchName '$branch' -PbixPath '$selectedPbix' $backupParam $wsParam $dsParam *>&1"
        Write-Log ($output -join "`n")
        Set-LastReportUrl $output

        # --- REQ-028 + REQ-023: Deployment log + branch cleanup offer ---
        if ($output -match "successful") {
            Write-Log "[SUCCESS] Production deployment complete."

            # Write deployment-log.json entry (REQ-023)
            try {
                $logFile = Join-Path $SCRIPT_DIR "deployment-log.json"
                $existing = if (Test-Path $logFile) { @(Get-Content $logFile -Raw | ConvertFrom-Json) } else { @() }
                $entry = [ordered]@{
                    timestamp    = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    user_upn     = if ($window.Tag) { [string]$window.Tag } else { "unknown" }
                    branch       = $branch
                    workspace_id = if ($script:selectedWorkspaceId) { $script:selectedWorkspaceId } else { "default-prod" }
                    report_url   = if ($script:lastReportUrl) { $script:lastReportUrl } else { "" }
                    env          = "Prod"
                }
                ($existing + $entry) | ConvertTo-Json -Depth 3 | Set-Content $logFile -Encoding UTF8
                Write-Log "Deployment logged to deployment-log.json."
            } catch { Write-Log "[WARN] Could not write deployment-log.json: $_" }
            $cleanupResult = [System.Windows.MessageBox]::Show(
                "Deployment successful!`n`nWould you like to delete the remote branch '$branch' from Azure DevOps?`n`n(The Main branch stays - only sub-branches like feature/* or hotfix/* are deleted.)",
                "Branch Cleanup", "YesNo", "Information")
            if ($cleanupResult -eq "Yes" -and $branch -notlike "*Main") {
                Write-Log "Deleting remote branch '$branch' from ADO..."
                $delOut = git -C $SCRIPT_DIR push azure --delete $branch 2>&1
                Write-Log ($delOut -join "`n")
                Write-Log "Branch '$branch' deleted from ADO."
            }
        }
    }
})

$btnGithubSync.Add_Click({
    Write-Log "Syncing to GitHub..."
    $commands = @"
git checkout --orphan temp-gui-sync
git rm -rf . --cached
git add azure-pipelines.yml deploy-pbi.ps1 README.md CLI-GUIDE.md instructions.md CDM-Manager.ps1 CDM-Config.ps1 CDM-Helpers.ps1 CDM-Manager.xaml .gitignore
git commit -m 'docs: Sync from CDM Manager GUI'
git push origin temp-gui-sync:main -f
git checkout -f Production-Main
"@
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $commands 2>&1 | Out-Null
    Write-Log "GitHub Sync Complete."
})

$btnCloudBackupOnly.Add_Click({
    $timestamp = Get-Date -Format "yyyyMMdd_HHmm"
    $pbixPath  = $script:resolvedPbixPath
    Write-Log "Creating Manual Cloud Backup..."
    az storage blob upload --account-name aleaus2bigprodadlame01 --container-name dal3011 --name "Common Data Models/Production CDM/Production CDM_$timestamp.pbix" --file "$pbixPath" --auth-mode login 2>&1 | Out-Null
    Write-Log "Cloud Backup Saved."
})

# --- Background init: separate runspace so the UI never freezes ---
$window.Add_Loaded({

    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.ApartmentState = [System.Threading.ApartmentState]::STA
    $rs.ThreadOptions  = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
    $rs.Open()

    $rs.SessionStateProxy.SetVariable('window',            $window)
    $rs.SessionStateProxy.SetVariable('consoleLog',        $consoleLog)
    $rs.SessionStateProxy.SetVariable('logScroller',       $logScroller)
    $rs.SessionStateProxy.SetVariable('currentBranchText', $currentBranchText)
    $rs.SessionStateProxy.SetVariable('comboTopBranch',    $comboTopBranch)
    $rs.SessionStateProxy.SetVariable('comboSubBranch',    $comboSubBranch)
    $rs.SessionStateProxy.SetVariable('comboWorkspace',     $comboWorkspace)
    $rs.SessionStateProxy.SetVariable('comboProdWorkspace', $comboProdWorkspace)
    $rs.SessionStateProxy.SetVariable('comboCdm',           $comboCdm)
    $rs.SessionStateProxy.SetVariable('SCRIPT_DIR',         $SCRIPT_DIR)
    $rs.SessionStateProxy.SetVariable('pbiStatusDot',      $pbiStatusDot)
    $rs.SessionStateProxy.SetVariable('pbiStatusText',     $pbiStatusText)
    $rs.SessionStateProxy.SetVariable('adoStatusDot',      $adoStatusDot)
    $rs.SessionStateProxy.SetVariable('adoStatusText',     $adoStatusText)
    $rs.SessionStateProxy.SetVariable('ADO_REMOTE_URL',    $ADO_REMOTE_URL)

    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs
    $ps.AddScript({

        function bg_Log ($msg) {
            $ts = Get-Date -Format "HH:mm:ss"
            $e  = "`n[$ts] $msg"
            $window.Dispatcher.Invoke([action]{ $consoleLog.AppendText($e); $logScroller.ScrollToEnd() }.GetNewClosure())
        }
        function bg_SetPbi ($ok, $label) {
            $c = if ($ok) { "#00C853" } else { "#D32F2F" }
            $t = if ($label) { $label } elseif ($ok) { "Connected" } else { "Failed" }
            $window.Dispatcher.Invoke([action]{
                $brush = [System.Windows.Media.BrushConverter]::new().ConvertFromString($c)
                $pbiStatusDot.Background  = $brush
                $pbiStatusText.Foreground = $brush
                $pbiStatusText.Text       = $t
            }.GetNewClosure())
        }
        function bg_SetAdo ($ok, $label) {
            $c = if ($ok) { "#00C853" } else { "#D32F2F" }
            $t = if ($label) { $label } elseif ($ok) { "Connected" } else { "Failed" }
            $window.Dispatcher.Invoke([action]{
                $brush = [System.Windows.Media.BrushConverter]::new().ConvertFromString($c)
                $adoStatusDot.Background  = $brush
                $adoStatusText.Foreground = $brush
                $adoStatusText.Text       = $t
            }.GetNewClosure())
        }
        function bg_RefreshBranches {
            $bl  = git -C $SCRIPT_DIR branch --show-current 2>$null; if (-not $bl) { $bl = 'None' }
            $raw = git -C $SCRIPT_DIR branch -r 2>$null | ForEach-Object { ($_.Trim() -replace "remotes/azure/|remotes/origin/|^azure/|^origin/","").Trim() } | Where-Object { $_ -notmatch "->|HEAD" } | Select-Object -Unique
            $tr  = @($raw | Where-Object { $_ -notmatch "^feature/|^hotfix/" -and ($_ -like "*Main*" -or $_ -match "^main$|^master$") })
            $window.Dispatcher.Invoke([action]{
                $currentBranchText.Text     = "Current Branch: $bl"
                $comboTopBranch.ItemsSource = $tr
            }.GetNewClosure())
        }

        # 1. Connect to Power BI - try silent refresh first, then device code flow
        bg_Log "Connecting to Power BI Service..."
        bg_SetPbi $false "Signing in..."
        Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue

        # Helper: DPAPI encrypt a string to a file
        function Save-EncryptedFile ([string]$path, [string]$plain) {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($plain)
            try {
                $enc = [System.Security.Cryptography.ProtectedData]::Protect($bytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
                [System.Convert]::ToBase64String($enc) | Set-Content $path -NoNewline
            } catch { $plain | Set-Content $path -NoNewline }  # non-Windows fallback
        }

        # Helper: DPAPI decrypt a string from a file
        function Load-EncryptedFile ([string]$path) {
            $raw = (Get-Content $path -Raw).Trim()
            try {
                $enc   = [System.Convert]::FromBase64String($raw)
                $bytes = [System.Security.Cryptography.ProtectedData]::Unprotect($enc, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
                return [System.Text.Encoding]::UTF8.GetString($bytes)
            } catch { return $raw }
        }

        $clientId       = "ea0616ba-638b-4df5-95b9-636659ae5121"  # Power BI PowerShell app
        $tokenScope     = "https://analysis.windows.net/powerbi/api/.default"
        $refreshFile    = "$env:TEMP\pbi_refresh_token.txt"
        $accessToken    = $null

        # --- Attempt silent sign-in via saved refresh token (REQ-021) ---
        if (Test-Path $refreshFile) {
            try {
                bg_Log "Found saved session - attempting silent sign-in..."
                $savedRefresh = Load-EncryptedFile $refreshFile
                $silentResp = Invoke-RestMethod -Method POST `
                    -Uri "https://login.microsoftonline.com/organizations/oauth2/v2.0/token" `
                    -Body @{
                        grant_type    = "refresh_token"
                        client_id     = $clientId
                        refresh_token = $savedRefresh
                        scope         = $tokenScope
                    }
                if ($silentResp.access_token) {
                    $accessToken = $silentResp.access_token
                    Save-EncryptedFile "$env:TEMP\pbi_token.txt" $accessToken
                    if ($silentResp.refresh_token) { Save-EncryptedFile $refreshFile $silentResp.refresh_token }
                    bg_SetPbi $true "Connected"
                    bg_Log "[SUCCESS] Silent sign-in successful."
                }
            } catch {
                bg_Log "[INFO] Saved session expired - proceeding with interactive login..."
                Remove-Item $refreshFile -ErrorAction SilentlyContinue
            }
        }

        # --- Device code flow (if silent sign-in did not succeed) ---
        if (-not $accessToken) {
        try {
            $dcResp = Invoke-RestMethod -Method POST `
                -Uri "https://login.microsoftonline.com/organizations/oauth2/v2.0/devicecode" `
                -Body @{ client_id = $clientId; scope = $tokenScope }

            bg_Log "--- Power BI Login Required ---"
            bg_Log "Your browser will open automatically."
            bg_Log "Code copied to clipboard - just Ctrl+V in the browser: $($dcResp.user_code)"
            bg_SetPbi $false "Code: $($dcResp.user_code)"
            $window.Dispatcher.Invoke([action]{ [System.Windows.Clipboard]::SetText($dcResp.user_code) }.GetNewClosure())
            Start-Process $dcResp.verification_uri
            bg_Log "Waiting for you to sign in..."

            $tokenResp = $null
            $pollEvery = [int]$dcResp.interval
            $expireAt  = [DateTime]::Now.AddSeconds([int]$dcResp.expires_in)
            while ([DateTime]::Now -lt $expireAt) {
                Start-Sleep -Seconds $pollEvery
                try {
                    $tokenResp = Invoke-RestMethod -Method POST `
                        -Uri "https://login.microsoftonline.com/organizations/oauth2/v2.0/token" `
                        -Body @{
                            grant_type  = "urn:ietf:params:oauth:grant-type:device_code"
                            client_id   = $clientId
                            device_code = $dcResp.device_code
                        }
                    break
                } catch {
                    $err = ($_ | Select-Object -ExpandProperty ErrorDetails -ErrorAction SilentlyContinue)
                    if ($err -match "authorization_pending") { continue }
                    elseif ($err -match "slow_down") { $pollEvery += 5; continue }
                    else { throw $_ }
                }
            }

            if ($tokenResp -and $tokenResp.access_token) {
                $accessToken = $tokenResp.access_token
                Save-EncryptedFile "$env:TEMP\pbi_token.txt" $accessToken
                if ($tokenResp.refresh_token) { Save-EncryptedFile $refreshFile $tokenResp.refresh_token }
                bg_SetPbi $true "Connected"
                bg_Log "[SUCCESS] Power BI connected."
            } else {
                bg_SetPbi $false "Login timeout"
                bg_Log "[WARN] Power BI login timed out. Restart the app to try again."
            }
        } catch {
            bg_SetPbi $false "Login failed"
            bg_Log "[WARN] Power BI login failed: $_"
        }
        } # end device code block

            if ($accessToken) {
                # Fetch current user UPN for audit trail (REQ-023)
                try {
                    $meResp = Invoke-RestMethod -Uri "https://api.powerbi.com/v1.0/myorg/me" -Headers @{ Authorization = "Bearer $accessToken" }
                    $upn    = if ($meResp.userPrincipalName) { $meResp.userPrincipalName } elseif ($meResp.emailAddress) { $meResp.emailAddress } else { "unknown" }
                    $dispName = if ($meResp.displayName) { $meResp.displayName } else { $upn }
                    bg_Log "Signed in as: $dispName ($upn)"
                    $window.Dispatcher.Invoke([action]{ $window.Tag = $upn }.GetNewClosure())
                } catch { bg_Log "[WARN] Could not retrieve user profile: $_" }

                # Fetch workspaces and populate dropdown
                bg_Log "Loading Power BI workspaces..."
                try {
                    $hdrs = @{ Authorization = "Bearer $accessToken" }
                    $wsList  = [System.Collections.Generic.List[object]]::new()
                    $wsUri   = "https://api.powerbi.com/v1.0/myorg/groups?`$top=100&`$filter=type eq 'Workspace'"
                    do {
                        $wsResp = Invoke-RestMethod -Uri $wsUri -Headers $hdrs
                        $wsResp.value | ForEach-Object { $wsList.Add($_) }
                        $wsUri = if ($wsResp.'@odata.nextLink') { $wsResp.'@odata.nextLink' } else { $null }
                    } while ($wsUri)
                    $wsList = @($wsList | Sort-Object name)
                    $window.Dispatcher.Invoke([action]{
                        $comboWorkspace.DisplayMemberPath     = "name"
                        $comboWorkspace.ItemsSource           = $wsList
                        $comboProdWorkspace.DisplayMemberPath = "name"
                        $comboProdWorkspace.ItemsSource       = $wsList
                    }.GetNewClosure())
                    bg_Log "Loaded $($wsList.Count) workspace(s). Select one to see its CDMs."
                } catch {
                    bg_Log "[WARN] Could not load workspaces: $_"
                }
            }

        # 2. Configure ADO remote and fetch
        bg_Log "Configuring Azure DevOps remote..."
        $remotes = git -C $SCRIPT_DIR remote 2>$null
        if ($remotes -contains "azure") { git -C $SCRIPT_DIR remote set-url azure $ADO_REMOTE_URL 2>&1 | Out-Null }
        else                            { git -C $SCRIPT_DIR remote add azure $ADO_REMOTE_URL 2>&1 | Out-Null }

        bg_Log "Fetching branches from ADO (3011 - Distribution and Analytics)..."
        git -C $SCRIPT_DIR fetch azure 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            bg_SetAdo $true  "Branches Loaded"
            bg_Log "[SUCCESS] ADO branches loaded."
        } else {
            bg_SetAdo $false "Fetch Failed"
            bg_Log "[ERROR] Could not fetch from ADO. Check your network/credentials."
        }

        bg_RefreshBranches

    }) | Out-Null

    $ps.BeginInvoke() | Out-Null
})

$window.ShowDialog() | Out-Null
