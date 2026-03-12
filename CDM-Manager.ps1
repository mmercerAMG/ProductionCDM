# CDM-Manager.ps1
# Production CDM Workflow Manager - v2.0

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# Hard-coded service endpoints
$ADO_REMOTE_URL  = "https://dev.azure.com/bigroupairliquide/_git/3011%20-%20Distribution%20and%20Analytics"
$DEFAULT_PBIX    = "H:\GitRepos\Airgas\Power BI Workflow\Production CDM.pbix"
$SCRIPT_DIR      = Split-Path -Parent $MyInvocation.MyCommand.Path
$LOCAL_PBIX_DIR  = Split-Path -Parent $SCRIPT_DIR
$DEV_WORKSPACE_ID = "2696b15d-427e-437b-ba5a-ca8d4fb188dd"

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Production CDM - Workflow Manager v2.0" Height="920" Width="1500" Background="#1E1E1E">
    <Window.Resources>
        <Style TargetType="ComboBox">
            <Setter Property="Background" Value="White"/>
            <Setter Property="Foreground" Value="Black"/>
        </Style>
    </Window.Resources>

    <!-- Outer two-column layout: controls left, log right -->
    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto">
    <Grid Margin="20">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="420"/>
        </Grid.ColumnDefinitions>

        <!-- ===== LEFT COLUMN: all controls ===== -->
        <Grid Grid.Column="0" Margin="0,0,12,0">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- Header -->
            <StackPanel Grid.Row="0" Margin="0,0,0,15">
                <TextBlock Text="Production CDM Manager" FontSize="28" Foreground="#007ACC" FontWeight="Bold"/>
                <TextBlock x:Name="CurrentBranchText" Text="Current Branch: Loading..." FontSize="14" Foreground="#AAAAAA" Margin="0,5,0,0"/>
            </StackPanel>

            <!-- Connections Status Bar -->
            <Border Grid.Row="1" Background="#2D2D30" CornerRadius="8" Padding="12,10" Margin="0,0,0,10">
                <UniformGrid Columns="2">
                    <StackPanel Orientation="Horizontal" Margin="0,0,10,0">
                        <TextBlock Text="Power BI Service" Foreground="White" FontSize="13" FontWeight="SemiBold" VerticalAlignment="Center"/>
                        <Border x:Name="PbiStatusDot" Width="10" Height="10" CornerRadius="5" Background="#888888" VerticalAlignment="Center" Margin="8,0,5,0"/>
                        <TextBlock x:Name="PbiStatusText" Text="Checking..." Foreground="#888888" FontSize="11" VerticalAlignment="Center"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="Azure DevOps" Foreground="White" FontSize="13" FontWeight="SemiBold" VerticalAlignment="Center"/>
                        <Border x:Name="AdoStatusDot" Width="10" Height="10" CornerRadius="5" Background="#888888" VerticalAlignment="Center" Margin="8,0,5,0"/>
                        <TextBlock x:Name="AdoStatusText" Text="Connecting..." Foreground="#888888" FontSize="11" VerticalAlignment="Center"/>
                    </StackPanel>
                </UniformGrid>
            </Border>

            <!-- CDM Selection Section -->
            <Border Grid.Row="2" Background="#2D2D30" CornerRadius="8" Padding="15" Margin="0,0,0,10">
                <StackPanel>
                    <TextBlock Text="CDM Selection" FontSize="16" Foreground="White" Margin="0,0,0,10"/>
                    <UniformGrid Columns="2" Margin="0,0,0,10">
                        <StackPanel Margin="0,0,10,0">
                            <TextBlock Text="Workspace" Foreground="#AAAAAA" FontSize="12" Margin="0,0,0,4"/>
                            <ComboBox x:Name="ComboWorkspace" Height="30"/>
                        </StackPanel>
                        <StackPanel>
                            <TextBlock Text="Semantic Model (CDM)" Foreground="#AAAAAA" FontSize="12" Margin="0,0,0,4"/>
                            <ComboBox x:Name="ComboCdm" Height="30"/>
                        </StackPanel>
                    </UniformGrid>
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="PbixPathText" Grid.Column="0" Height="25" VerticalContentAlignment="Center"
                                 Background="#3E3E42" Foreground="#888888" BorderThickness="0" Padding="5" IsReadOnly="True"
                                 Text="Select a workspace and CDM above..."/>
                        <Button x:Name="BtnDownloadCdm" Grid.Column="1" Content="Download CDM" Width="120" Height="25" Margin="10,0,5,0"
                                Background="#007ACC" Foreground="White"/>
                        <Button x:Name="BtnBrowsePbix" Grid.Column="2" Content="Browse..." Width="80" Height="25"
                                Background="#3E3E42" Foreground="White"/>
                    </Grid>
                </StackPanel>
            </Border>

            <!-- Branch Management Section -->
            <Border Grid.Row="3" Background="#2D2D30" CornerRadius="8" Padding="15" Margin="0,0,0,10">
                <StackPanel>
                    <TextBlock Text="Branch Management" FontSize="16" Foreground="White" Margin="0,0,0,10"/>
                    <UniformGrid Columns="4">
                        <StackPanel Margin="5">
                            <TextBlock Text="Top Branch (Main)" Foreground="#AAAAAA" FontSize="12"/>
                            <ComboBox x:Name="ComboTopBranch" Height="30" IsEnabled="False"/>
                            <TextBlock x:Name="TopBranchHint" Text="Select a PBIX first" Foreground="#D32F2F" FontSize="10" Margin="2,2,0,0"/>
                        </StackPanel>
                        <StackPanel Margin="5">
                            <TextBlock Text="Sub-Branch (Feature)" Foreground="#AAAAAA" FontSize="12"/>
                            <ComboBox x:Name="ComboSubBranch" Height="30"/>
                        </StackPanel>
                        <StackPanel Margin="5">
                            <TextBlock Text="Branch Type" Foreground="#AAAAAA" FontSize="12" Margin="0,0,0,2"/>
                            <RadioButton x:Name="RadioFeature" Content="Feature" IsChecked="True" Foreground="White" VerticalAlignment="Center"/>
                            <RadioButton x:Name="RadioHotfix" Content="Hotfix" Foreground="White" VerticalAlignment="Center" Margin="0,2,0,0"/>
                        </StackPanel>
                        <StackPanel Margin="5">
                            <TextBlock x:Name="LblNewBranch" Text="New Feature Name" Foreground="#AAAAAA" FontSize="12"/>
                            <TextBox x:Name="TxtNewFeature" Height="30" VerticalContentAlignment="Center" Background="#3E3E42" Foreground="White" BorderThickness="0" Padding="5"/>
                        </StackPanel>
                    </UniformGrid>
                    <UniformGrid Columns="2" Margin="0,10,0,0">
                        <Button x:Name="BtnSwitchBranch" Content="Switch to Selected Branch" Height="30" Background="#007ACC" Foreground="White" Margin="5"/>
                        <Button x:Name="BtnCreateFeature" Content="Create &amp; Deploy New Branch" Height="30" Background="#43A047" Foreground="White" Margin="5"/>
                    </UniformGrid>
                </StackPanel>
            </Border>

            <!-- Actions Section -->
            <UniformGrid Grid.Row="4" Columns="2" Margin="0,0,0,10">
                <!-- Deployment Card -->
                <Border Background="#2D2D30" CornerRadius="8" Margin="0,0,5,0" Padding="15">
                    <StackPanel>
                        <TextBlock Text="Manual Operations" FontSize="16" Foreground="White" Margin="0,0,0,10"/>
                        <TextBlock Text="Dev Deploy Mode" Foreground="#AAAAAA" FontSize="12" Margin="0,0,0,4"/>
                        <Border Background="#3E3E42" CornerRadius="4" Padding="10,8" Margin="0,0,0,8">
                            <StackPanel>
                                <RadioButton x:Name="RadioSemanticModel" Content="New Semantic Model" Foreground="White" IsChecked="True" Margin="0,0,0,2"/>
                                <TextBlock Text="Uploads full PBIX with its own dataset" Foreground="#666666" FontSize="11" Margin="16,0,0,6"/>
                                <RadioButton x:Name="RadioLiveConnect" Content="Live Connect to Prod Dataset" Foreground="White" Margin="0,0,0,2"/>
                                <TextBlock Text="Report only - links to the Production semantic model" Foreground="#666666" FontSize="11" Margin="16,0,0,0"/>
                            </StackPanel>
                        </Border>
                        <Button x:Name="BtnDeployDev" Content="Deploy to DEV" Height="30" Background="#007ACC" Foreground="White" Margin="0,0,0,5"/>
                        <Button x:Name="BtnDeployProd" Content="Deploy to PROD (Main Only)" Height="30" Background="#D32F2F" Foreground="White" Margin="0,5"/>
                        <Button x:Name="BtnOpenReport" Content="Open Last Deployed Report" Height="30" Background="#37474F" Foreground="#888888" Margin="0,5" IsEnabled="False"/>
                        <CheckBox x:Name="ChkCloudBackup" Content="Include Cloud Backup" Foreground="#AAAAAA" Margin="0,5,0,0"/>
                    </StackPanel>
                </Border>

                <!-- Sync Card -->
                <Border Background="#2D2D30" CornerRadius="8" Margin="5,0,0,0" Padding="15">
                    <StackPanel>
                        <TextBlock Text="Cloud &amp; Git" FontSize="16" Foreground="White" Margin="0,0,0,10"/>
                        <Button x:Name="BtnSyncFromDev" Content="Sync Branch from Dev Report" Height="30" Background="#E65100" Foreground="White" Margin="0,5"/>
                        <Button x:Name="BtnUpdateMainBranch" Content="Update Main Branch (PBIX to PBIP)" Height="30" Background="#6A1B9A" Foreground="White" Margin="0,5"/>
                        <Button x:Name="BtnGithubSync" Content="Sync to GitHub" Height="30" Background="#333333" Foreground="White" Margin="0,5"/>
                        <Button x:Name="BtnCloudBackupOnly" Content="Manual Cloud Backup" Height="30" Background="#43A047" Foreground="White" Margin="0,5"/>
                    </StackPanel>
                </Border>
            </UniformGrid>

            <!-- Spacer -->
            <Grid Grid.Row="5"/>

            <!-- Footer -->
            <TextBlock Grid.Row="6" Text="CDM Workflow Manager v2.0 - Dynamic Multi-CDM Edition" Foreground="#555555" HorizontalAlignment="Right" Margin="0,10,0,0"/>
        </Grid>

        <!-- ===== RIGHT COLUMN: Console Log ===== -->
        <Grid Grid.Column="1">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <TextBlock Grid.Row="0" Text="Console Log" FontSize="16" Foreground="White" FontWeight="SemiBold" Margin="0,0,0,8"/>
            <Border Grid.Row="1" Background="Black" CornerRadius="5" Padding="10">
                <ScrollViewer x:Name="LogScroller" VerticalScrollBarVisibility="Auto">
                    <TextBox x:Name="ConsoleLog" TextWrapping="Wrap" FontFamily="Consolas" Foreground="#00FF00" FontSize="12"
                             Background="Black" BorderThickness="0" IsReadOnly="True" Text="[SYSTEM] Dashboard v2.0 Ready..."
                             VerticalScrollBarVisibility="Disabled"/>
                </ScrollViewer>
            </Border>
        </Grid>

    </Grid>
    </ScrollViewer>
</Window>
"@

# Load XAML
$reader = [XML.XmlReader]::Create([IO.StringReader]($xaml))
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
$btnSyncFromDev      = $window.FindName("BtnSyncFromDev")
$btnUpdateMainBranch = $window.FindName("BtnUpdateMainBranch")
$topBranchHint       = $window.FindName("TopBranchHint")

$btnOpenReport       = $window.FindName("BtnOpenReport")

# Script-scope state variables
$script:selectedWorkspaceId = ""
$script:selectedDatasetId   = ""
$script:selectedCdmName     = ""
$script:lastReportUrl       = ""

# --- UI Helper Functions (called from UI thread via button handlers) ---

function Write-Log ($Message) {
    $timestamp = Get-Date -Format "HH:mm:ss"
    $consoleLog.AppendText("`n[$timestamp] $Message")
    $logScroller.ScrollToEnd()
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
    if (Test-Path $f) { return (Get-Content $f -Raw).Trim() }
    return $null
}

function Update-BranchLock {
    $path  = $pbixPathText.Text
    $valid = ($path -like "*.pbix") -and (Test-Path $path)
    $comboTopBranch.IsEnabled = $valid
    if ($valid) {
        $topBranchHint.Text       = ""
        $topBranchHint.Visibility = "Collapsed"
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

# --- Events ---

$comboTopBranch.Add_SelectionChanged({ Refresh-SubBranches })
$radioFeature.Add_Click({ $lblNewBranch.Text = "New Feature Name" })
$radioHotfix.Add_Click({  $lblNewBranch.Text = "New Hotfix Name"  })

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
    $pbixPathText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("White")
    $pbixPathText.Text = $localPath
    Update-BranchLock
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
        Update-BranchLock
        Write-Log "PBIX selected: $($fd.FileName)"
    }
})

$btnDownloadCdm.Add_Click({
    $ws  = $comboWorkspace.SelectedItem
    $cdm = $comboCdm.SelectedItem
    if (-not $ws -or -not $cdm) { Write-Log "[ERROR] Select a workspace and CDM first."; return }

    # Let user pick the save folder
    $fb = New-Object System.Windows.Forms.FolderBrowserDialog
    $fb.Description  = "Select folder to save '$($cdm.name).pbix'"
    $fb.SelectedPath = $LOCAL_PBIX_DIR
    if ($fb.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    $localPath = Join-Path $fb.SelectedPath "$($cdm.name).pbix"
    $pbixPathText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("White")
    $pbixPathText.Text = $localPath

    Write-Log "Starting download of '$($cdm.name)' to $localPath..."
    $btnDownloadCdm.IsEnabled = $false

    $dlRs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $dlRs.ApartmentState = [System.Threading.ApartmentState]::STA
    $dlRs.ThreadOptions  = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
    $dlRs.Open()
    $dlRs.SessionStateProxy.SetVariable('window',          $window)
    $dlRs.SessionStateProxy.SetVariable('consoleLog',      $consoleLog)
    $dlRs.SessionStateProxy.SetVariable('logScroller',     $logScroller)
    $dlRs.SessionStateProxy.SetVariable('btnDownloadCdm',  $btnDownloadCdm)
    $dlRs.SessionStateProxy.SetVariable('comboTopBranch',  $comboTopBranch)
    $dlRs.SessionStateProxy.SetVariable('topBranchHint',   $topBranchHint)
    $dlRs.SessionStateProxy.SetVariable('wsId',            $ws.id)
    $dlRs.SessionStateProxy.SetVariable('wsName',          $ws.name)
    $dlRs.SessionStateProxy.SetVariable('dsId',            $cdm.id)
    $dlRs.SessionStateProxy.SetVariable('dsName',          $cdm.name)
    $dlRs.SessionStateProxy.SetVariable('localPath',       $localPath)

    $dlPs = [System.Management.Automation.PowerShell]::Create()
    $dlPs.Runspace = $dlRs
    $dlPs.AddScript({
        function dl_Log ($msg) {
            $ts = Get-Date -Format "HH:mm:ss"
            $e  = "`n[$ts] $msg"
            $window.Dispatcher.Invoke([action]{ $consoleLog.AppendText($e); $logScroller.ScrollToEnd() }.GetNewClosure())
        }

        try {
            $token   = (Get-Content "$env:TEMP\pbi_token.txt" -Raw).Trim()
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
            # Unlock Top Branch dropdown now that a valid PBIX exists
            $window.Dispatcher.Invoke([action]{
                $comboTopBranch.IsEnabled    = $true
                $topBranchHint.Text          = ""
                $topBranchHint.Visibility    = "Collapsed"
            }.GetNewClosure())
        } catch {
            dl_Log "[ERROR] Download failed: $_"
        } finally {
            $window.Dispatcher.Invoke([action]{ $btnDownloadCdm.IsEnabled = $true }.GetNewClosure())
        }
    }) | Out-Null
    $dlPs.BeginInvoke() | Out-Null
})

$btnOpenReport.Add_Click({
    if ($script:lastReportUrl) {
        Start-Process $script:lastReportUrl
    }
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

    $branch = git branch --show-current 2>$null
    if (-not $branch) { Write-Log "[ERROR] Not on any branch."; return }

    # --- Find matching report in Dev workspace ---
    # Try the short segment of the branch name for matching
    $shortName = $branch -replace "^(feature|hotfix)/[^/]+/", ""   # e.g. "MM-HF-100"

    try {
        $headers = @{ Authorization = "Bearer $token" }
        $reports = (Invoke-RestMethod -Uri "https://api.powerbi.com/v1.0/myorg/groups/$DEV_WORKSPACE_ID/reports" -Headers $headers).value
    } catch {
        Write-Log "[ERROR] Could not load Dev workspace reports: $_"
        return
    }

    # Match by exact short name, then by full branch name segment, then by contains
    $match = $reports | Where-Object { $_.name -eq $shortName } | Select-Object -First 1
    if (-not $match) { $match = $reports | Where-Object { $_.name -like "*$shortName*" } | Select-Object -First 1 }
    if (-not $match) {
        Write-Log "[ERROR] No report matching '$shortName' found in Dev workspace."
        [System.Windows.MessageBox]::Show(
            "No report matching '$shortName' found in the Dev workspace.`n`nDeploy the branch to Dev first, then sync.",
            "Report Not Found", "OK", "Warning") | Out-Null
        return
    }

    # --- Determine the PBIP folder name from the repo (to name the temp PBIX correctly) ---
    $pbipBase = (Get-ChildItem $SCRIPT_DIR -Directory -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -like "*.SemanticModel" } |
                 Select-Object -First 1).Name -replace "\.SemanticModel$", ""
    if (-not $pbipBase) { $pbipBase = if ($script:selectedCdmName) { $script:selectedCdmName } else { "CDM" } }

    $tempPbix = Join-Path $env:TEMP "$pbipBase.pbix"

    $confirm = [System.Windows.MessageBox]::Show(
        "Sync branch '$branch' from Dev report '$($match.name)'?`n`nThis will:`n  1. Download PBIX from Dev workspace`n  2. Extract PBIP files into repo ($SCRIPT_DIR)`n  3. Commit changes to '$branch'`n`nAny uncommitted local changes to PBIP files will be overwritten.",
        "Sync Branch from Dev", "YesNo", "Warning")
    if ($confirm -ne "Yes") { return }

    Write-Log "Starting sync of '$($match.name)' from Dev to branch '$branch'..."
    $btnSyncFromDev.IsEnabled = $false

    # --- Background runspace ---
    $syncRs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $syncRs.ApartmentState = [System.Threading.ApartmentState]::STA
    $syncRs.ThreadOptions  = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
    $syncRs.Open()
    $syncRs.SessionStateProxy.SetVariable('window',          $window)
    $syncRs.SessionStateProxy.SetVariable('consoleLog',      $consoleLog)
    $syncRs.SessionStateProxy.SetVariable('logScroller',     $logScroller)
    $syncRs.SessionStateProxy.SetVariable('btnSyncFromDev',  $btnSyncFromDev)
    $syncRs.SessionStateProxy.SetVariable('reportId',        $match.id)
    $syncRs.SessionStateProxy.SetVariable('reportName',      $match.name)
    $syncRs.SessionStateProxy.SetVariable('branch',          $branch)
    $syncRs.SessionStateProxy.SetVariable('tempPbix',        $tempPbix)
    $syncRs.SessionStateProxy.SetVariable('pbipBase',        $pbipBase)
    $syncRs.SessionStateProxy.SetVariable('SCRIPT_DIR',      $SCRIPT_DIR)
    $syncRs.SessionStateProxy.SetVariable('pbiTools',        $pbiTools)
    $syncRs.SessionStateProxy.SetVariable('DEV_WORKSPACE_ID', $DEV_WORKSPACE_ID)

    $syncPs = [System.Management.Automation.PowerShell]::Create()
    $syncPs.Runspace = $syncRs
    $syncPs.AddScript({
        function sync_Log ($msg) {
            $ts = Get-Date -Format "HH:mm:ss"
            $e  = "`n[$ts] $msg"
            $window.Dispatcher.Invoke([action]{ $consoleLog.AppendText($e); $logScroller.ScrollToEnd() }.GetNewClosure())
        }
        try {
            $token   = (Get-Content "$env:TEMP\pbi_token.txt" -Raw).Trim()
            $headers = @{ Authorization = "Bearer $token" }

            # Step 1: Download PBIX from Dev workspace
            sync_Log "Step 1: Downloading '$reportName' from Dev workspace..."
            $exportUri = "https://api.powerbi.com/v1.0/myorg/groups/$DEV_WORKSPACE_ID/reports/$reportId/Export"
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
            $commitMsg = "sync: update PBIP from Dev report '$reportName'"
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
            $window.Dispatcher.Invoke([action]{ $btnSyncFromDev.IsEnabled = $true }.GetNewClosure())
        }
    }) | Out-Null
    $syncPs.BeginInvoke() | Out-Null
})

$btnUpdateMainBranch.Add_Click({
    $pbixPath = $pbixPathText.Text
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

    $commitMsg = "chore: update PBIP from downloaded PBIX [$($cdmName = $script:selectedCdmName; if ($cdmName) { $cdmName } else { (Split-Path $pbixPath -Leaf) -replace '\.pbix$','' })]"
    $commitOut = git -C $SCRIPT_DIR commit -m $commitMsg 2>&1
    Write-Log ($commitOut -join "`n")

    if ($LASTEXITCODE -eq 0) {
        Write-Log "[SUCCESS] Main branch updated with latest PBIP files."
    } else {
        Write-Log "[WARN] Nothing to commit or commit failed. Check output above."
    }

    $btnUpdateMainBranch.IsEnabled = $true
})

$btnSwitchBranch.Add_Click({
    $selected = $comboSubBranch.SelectedItem
    if ($selected) {
        $fullName = $selected.FullName
        Write-Log "Switching to $fullName..."
        $out = git checkout $fullName 2>&1
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
    $selectedPbix = $pbixPathText.Text

    Write-Log "1. Fetching latest from ADO..."
    git fetch azure 2>&1 | Out-Null

    Write-Log "2. Creating $newBranch from azure/$top (no branch switch)..."
    $branchOut = git branch $newBranch "azure/$top" 2>&1
    Write-Log $branchOut
    if ($LASTEXITCODE -ne 0) {
        Write-Log "[ERROR] Branch creation failed."
        return
    }

    Write-Log "3. Pushing to ADO..."
    $pushOut = git push azure "$newBranch`:$newBranch" -u 2>&1
    Write-Log $pushOut
    if ($LASTEXITCODE -ne 0) {
        Write-Log "[ERROR] Push to ADO failed."
        return
    }

    Write-Log "5. Deploying to DEV..."
    $backupParam = if ($chkCloudBackup.IsChecked) { "-CloudBackup" } else { "" }
    $liveParam   = if ($radioLiveConnect.IsChecked)  { "-LiveConnect" } else { "" }
    $wsParam     = if ($script:selectedWorkspaceId) { "-ProdWorkspaceId '$($script:selectedWorkspaceId)'" } else { "" }
    $dsParam     = if ($script:selectedDatasetId)   { "-ProdDatasetId '$($script:selectedDatasetId)'" }   else { "" }
    $output = powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ".\deploy-pbi.ps1 -TargetEnv Dev -BranchName '$name' -PbixPath '$selectedPbix' $backupParam $liveParam $wsParam $dsParam *>&1"
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
    $selectedPbix = $pbixPathText.Text
    Write-Log "Deploying '$cleanName' to DEV..."
    $backupParam = if ($chkCloudBackup.IsChecked) { "-CloudBackup" } else { "" }
    $liveParam   = if ($radioLiveConnect.IsChecked)  { "-LiveConnect" } else { "" }
    $wsParam     = if ($script:selectedWorkspaceId) { "-ProdWorkspaceId '$($script:selectedWorkspaceId)'" } else { "" }
    $dsParam     = if ($script:selectedDatasetId)   { "-ProdDatasetId '$($script:selectedDatasetId)'" }   else { "" }
    $output = powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ".\deploy-pbi.ps1 -TargetEnv Dev -BranchName '$cleanName' -PbixPath '$selectedPbix' $backupParam $liveParam $wsParam $dsParam *>&1"
    Write-Log ($output -join "`n")
    Set-LastReportUrl $output
})

$btnDeployProd.Add_Click({
    $branch = git branch --show-current
    if ($branch -notlike "*Main*" -and $branch -ne "main") {
        Write-Log "[ERROR] Production deployments only allowed from Main branches."
        return
    }
    $result = [System.Windows.MessageBox]::Show("Deploy to PRODUCTION?", "Safety Check", "YesNo", "Warning")
    if ($result -eq "Yes") {
        $selectedPbix = $pbixPathText.Text
        Write-Log "Deploying to PROD..."
        $wsParam = if ($script:selectedWorkspaceId) { "-ProdWorkspaceId '$($script:selectedWorkspaceId)'" } else { "" }
        $dsParam = if ($script:selectedDatasetId)   { "-ProdDatasetId '$($script:selectedDatasetId)'" }   else { "" }
        $output = powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ".\deploy-pbi.ps1 -TargetEnv Prod -BranchName '$branch' -PbixPath '$selectedPbix' -CloudBackup $wsParam $dsParam *>&1"
        Write-Log ($output -join "`n")
        Set-LastReportUrl $output
    }
})

$btnGithubSync.Add_Click({
    Write-Log "Syncing to GitHub..."
    $commands = @"
git checkout --orphan temp-gui-sync
git rm -rf . --cached
git add azure-pipelines.yml deploy-pbi.ps1 README.md CLI-GUIDE.md instructions.md CDM-Manager.ps1 .gitignore
git commit -m 'docs: Sync from CDM Manager GUI'
git push origin temp-gui-sync:main -f
git checkout -f Production-Main
"@
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $commands 2>&1 | Out-Null
    Write-Log "GitHub Sync Complete."
})

$btnCloudBackupOnly.Add_Click({
    $timestamp = Get-Date -Format "yyyyMMdd_HHmm"
    $pbixPath  = $pbixPathText.Text
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
    $rs.SessionStateProxy.SetVariable('comboWorkspace',    $comboWorkspace)
    $rs.SessionStateProxy.SetVariable('comboCdm',          $comboCdm)
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
            $bl  = git branch --show-current 2>$null; if (-not $bl) { $bl = 'None' }
            $raw = git branch -r 2>$null | ForEach-Object { ($_.Trim() -replace "remotes/azure/|remotes/origin/|^azure/|^origin/","").Trim() } | Where-Object { $_ -notmatch "->|HEAD" } | Select-Object -Unique
            $tr  = @($raw | Where-Object { $_ -notmatch "^feature/|^hotfix/" -and ($_ -like "*Main*" -or $_ -match "^main$|^master$") })
            $window.Dispatcher.Invoke([action]{
                $currentBranchText.Text     = "Current Branch: $bl"
                $comboTopBranch.ItemsSource = $tr
            }.GetNewClosure())
        }

        # 1. Connect to Power BI using OAuth device code flow (no module auth needed)
        bg_Log "Connecting to Power BI Service..."
        bg_SetPbi $false "Signing in..."
        try {
            # Request device code from Azure AD
            $clientId = "ea0616ba-638b-4df5-95b9-636659ae5121"  # Power BI PowerShell app
            $dcResp = Invoke-RestMethod -Method POST `
                -Uri "https://login.microsoftonline.com/organizations/oauth2/v2.0/devicecode" `
                -Body @{ client_id = $clientId; scope = "https://analysis.windows.net/powerbi/api/.default" }

            bg_Log "--- Power BI Login Required ---"
            bg_Log "Your browser will open automatically."
            bg_Log "Code copied to clipboard - just Ctrl+V in the browser: $($dcResp.user_code)"
            bg_SetPbi $false "Code: $($dcResp.user_code)"
            # Copy code to clipboard and open browser
            $window.Dispatcher.Invoke([action]{ [System.Windows.Clipboard]::SetText($dcResp.user_code) }.GetNewClosure())
            Start-Process $dcResp.verification_uri
            bg_Log "Waiting for you to sign in..."

            # Poll until authenticated or expired
            $tokenResp  = $null
            $pollEvery  = [int]$dcResp.interval
            $expireAt   = [DateTime]::Now.AddSeconds([int]$dcResp.expires_in)
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
                $tokenResp.access_token | Set-Content "$env:TEMP\pbi_token.txt" -NoNewline
                bg_SetPbi $true "Connected"
                bg_Log "[SUCCESS] Power BI connected."

                # Fetch workspaces and populate dropdown
                bg_Log "Loading Power BI workspaces..."
                try {
                    $tkn  = (Get-Content "$env:TEMP\pbi_token.txt" -Raw).Trim()
                    $hdrs = @{ Authorization = "Bearer $tkn" }
                    $wsResp = Invoke-RestMethod -Uri "https://api.powerbi.com/v1.0/myorg/groups?`$top=100&`$filter=type eq 'Workspace'" -Headers $hdrs
                    $wsList = @($wsResp.value | Sort-Object name)
                    $window.Dispatcher.Invoke([action]{
                        $comboWorkspace.DisplayMemberPath = "name"
                        $comboWorkspace.ItemsSource = $wsList
                    }.GetNewClosure())
                    bg_Log "Loaded $($wsList.Count) workspace(s). Select one to see its CDMs."
                } catch {
                    bg_Log "[WARN] Could not load workspaces: $_"
                }
            } else {
                bg_SetPbi $false "Login timeout"
                bg_Log "[WARN] Power BI login timed out. Restart the app to try again."
            }
        } catch {
            bg_SetPbi $false "Login failed"
            bg_Log "[WARN] Power BI login failed: $_"
        }

        # 2. Configure ADO remote and fetch
        bg_Log "Configuring Azure DevOps remote..."
        $remotes = git remote 2>$null
        if ($remotes -contains "azure") { git remote set-url azure $ADO_REMOTE_URL 2>&1 | Out-Null }
        else                            { git remote add azure $ADO_REMOTE_URL 2>&1 | Out-Null }

        bg_Log "Fetching branches from ADO (3011 - Distribution and Analytics)..."
        git fetch azure 2>&1 | Out-Null
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
