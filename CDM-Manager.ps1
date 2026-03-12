# CDM-Manager.ps1
# Production CDM Workflow Manager - v1.5

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# Hard-coded service endpoints
$ADO_REMOTE_URL  = "https://dev.azure.com/bigroupairliquide/_git/3011%20-%20Distribution%20and%20Analytics"
$DEFAULT_PBIX    = "H:\GitRepos\Airgas\Power BI Workflow\Production CDM.pbix"

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Production CDM - Workflow Manager" Height="900" Width="1000" Background="#1E1E1E">
    <Window.Resources>
        <Style TargetType="ComboBox">
            <Setter Property="Background" Value="White"/>
            <Setter Property="Foreground" Value="Black"/>
        </Style>
    </Window.Resources>
    <Grid Margin="20">
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

        <!-- PBIX Configuration Section -->
        <Border Grid.Row="2" Background="#2D2D30" CornerRadius="8" Padding="15" Margin="0,0,0,10">
            <StackPanel>
                <TextBlock Text="Local PBIX Configuration" FontSize="16" Foreground="White" Margin="0,0,0,5"/>
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBox x:Name="PbixPathText" Grid.Column="0" Height="25" VerticalContentAlignment="Center"
                             Background="#3E3E42" Foreground="White" BorderThickness="0" Padding="5"
                             Text="H:\GitRepos\Airgas\Power BI Workflow\Production CDM.pbix"/>
                    <Button x:Name="BtnBrowsePbix" Grid.Column="1" Content="Browse..." Width="80" Height="25" Margin="10,0,0,0"
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
                        <ComboBox x:Name="ComboTopBranch" Height="30"/>
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
            <Border Background="#2D2D30" CornerRadius="8" Margin="5" Padding="15">
                <StackPanel>
                    <TextBlock Text="Manual Operations" FontSize="16" Foreground="White" Margin="0,0,0,10"/>
                    <Button x:Name="BtnDeployDev" Content="Deploy Current to DEV" Height="30" Background="#007ACC" Foreground="White" Margin="0,5"/>
                    <StackPanel Orientation="Horizontal" Margin="0,2">
                        <CheckBox x:Name="ChkLiveConnect" Content="Live Connect to Prod Dataset (Dev Only)" Foreground="#AAAAAA" VerticalAlignment="Center"/>
                    </StackPanel>
                    <Button x:Name="BtnCreateLocalLive" Content="Create Local Live Report" Height="30" Background="#673AB7" Foreground="White" Margin="0,5"/>
                    <Button x:Name="BtnDeployProd" Content="Deploy to PROD (Main Only)" Height="30" Background="#D32F2F" Foreground="White" Margin="0,5"/>
                    <CheckBox x:Name="ChkCloudBackup" Content="Include Cloud Backup" Foreground="#AAAAAA" Margin="0,5,0,0"/>
                </StackPanel>
            </Border>

            <!-- Sync Card -->
            <Border Background="#2D2D30" CornerRadius="8" Margin="5" Padding="15">
                <StackPanel>
                    <TextBlock Text="Cloud &amp; Git" FontSize="16" Foreground="White" Margin="0,0,0,10"/>
                    <Button x:Name="BtnGithubSync" Content="Sync to GitHub" Height="30" Background="#333333" Foreground="White" Margin="0,5"/>
                    <Button x:Name="BtnCloudBackupOnly" Content="Manual Cloud Backup" Height="30" Background="#43A047" Foreground="White" Margin="0,5"/>
                </StackPanel>
            </Border>
        </UniformGrid>

        <!-- Console Log -->
        <Border Grid.Row="5" Background="Black" CornerRadius="5" Padding="10">
            <ScrollViewer x:Name="LogScroller" VerticalScrollBarVisibility="Auto">
                <TextBox x:Name="ConsoleLog" TextWrapping="Wrap" FontFamily="Consolas" Foreground="#00FF00" FontSize="12"
                         Background="Black" BorderThickness="0" IsReadOnly="True" Text="[SYSTEM] Dashboard v1.5 Ready..."
                         VerticalScrollBarVisibility="Disabled"/>
            </ScrollViewer>
        </Border>

        <!-- Footer -->
        <TextBlock Grid.Row="6" Text="Professional Power BI Workflow Manager" Foreground="#555555" HorizontalAlignment="Right" Margin="0,10,0,0"/>
    </Grid>
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
$btnCreateLocalLive = $window.FindName("BtnCreateLocalLive")
$chkCloudBackup     = $window.FindName("ChkCloudBackup")
$chkLiveConnect     = $window.FindName("ChkLiveConnect")
$pbiStatusDot       = $window.FindName("PbiStatusDot")
$pbiStatusText      = $window.FindName("PbiStatusText")
$adoStatusDot       = $window.FindName("AdoStatusDot")
$adoStatusText      = $window.FindName("AdoStatusText")

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
    # Strip remotes/azure/, remotes/origin/, azure/, origin/ prefixes
    return ($fullName -replace "remotes/azure/|remotes/origin/|^azure/|^origin/", "").Trim("* ").Trim()
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
                # Display: drop the [TopBranch] segment → "feature/MM-TEST04" instead of "feature/Production-Main/MM-TEST04"
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

    # Clean names stored — strips azure/ so dropdown shows "Production-Main" not "azure/Production-Main"
    $topBranches = @(git branch -r 2>$null |
        ForEach-Object { Get-CleanBranchName $_ } |
        Where-Object { $_ -notmatch "->|HEAD|^feature/|^hotfix/" -and ($_ -like "*Main*" -or $_ -match "^main$|^master$") } |
        Select-Object -Unique)
    $comboTopBranch.ItemsSource = $topBranches
    Refresh-SubBranches
}

# --- Events ---

$comboTopBranch.Add_SelectionChanged({ Refresh-SubBranches })
$radioFeature.Add_Click({ $lblNewBranch.Text = "New Feature Name" })
$radioHotfix.Add_Click({  $lblNewBranch.Text = "New Hotfix Name"  })

# --- Button Handlers ---

$btnBrowsePbix.Add_Click({
    $fd = New-Object System.Windows.Forms.OpenFileDialog
    $fd.Filter = "Power BI Files (*.pbix)|*.pbix"
    if ($fd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $pbixPathText.Text = $fd.FileName
        Write-Log "Selected PBIX: $($fd.FileName)"
    }
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
    $liveParam   = if ($chkLiveConnect.IsChecked)  { "-LiveConnect" } else { "" }
    $output = powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ".\deploy-pbi.ps1 -TargetEnv Dev -BranchName '$name' -PbixPath '$selectedPbix' $backupParam $liveParam *>&1"
    Write-Log ($output -join "`n")

    Refresh-UI
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
    $liveParam   = if ($chkLiveConnect.IsChecked)  { "-LiveConnect" } else { "" }
    $output = powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ".\deploy-pbi.ps1 -TargetEnv Dev -BranchName '$cleanName' -PbixPath '$selectedPbix' $backupParam $liveParam *>&1"
    Write-Log ($output -join "`n")
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
        $output = powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ".\deploy-pbi.ps1 -TargetEnv Prod -BranchName '$branch' -PbixPath '$selectedPbix' -CloudBackup *>&1"
        Write-Log ($output -join "`n")
    }
})

$btnCreateLocalLive.Add_Click({
    $repoRoot    = Split-Path $pbixPathText.Text -Parent
    $targetDir   = Join-Path $repoRoot "Live Connections"
    $reportName  = "Production CDM - Live"
    $reportFolder = Join-Path $targetDir "$reportName.Report"
    $pbipPath    = Join-Path $targetDir "$reportName.pbip"
    $targetGuid  = "10ad1784-d53f-4877-b9f0-f77641efbff4"

    Write-Log "Creating local Live Connection report..."
    try {
        if (-not (Test-Path $reportFolder)) { New-Item -ItemType Directory -Path $reportFolder -Force | Out-Null }

        @"
{
  "version": "1.0",
  "datasetReference": {
    "byConnection": {
      "connectionString": "Data Source=pbiazure://api.powerbi.com;Initial Catalog=$targetGuid;Identity Provider=\"https://login.microsoftonline.com/common, https://analysis.windows.net/powerbi/api, 7f67af8a-fedc-4b08-8b4e-37c4d127b6cf\";Integrated Security=ClaimsToken",
      "pbiServiceModelId": "12763409",
      "pbiModelVirtualServerName": "sobe_wowvirtualserver",
      "pbiModelDatabaseName": "$targetGuid",
      "name": "EntityDataSource",
      "connectionType": "pbiServiceLive"
    }
  }
}
"@ | Set-Content -Path (Join-Path $reportFolder "definition.pbir") -Force

        @"
{
  "version": "1.0",
  "artifacts": [{ "report": { "path": "$reportName.Report" } }]
}
"@ | Set-Content -Path $pbipPath -Force

        $rj = Join-Path $reportFolder "report.json"
        if (-not (Test-Path $rj)) { "{}" | Set-Content -Path $rj -Force }

        Write-Log "[SUCCESS] Live report created at: $pbipPath"
    } catch {
        Write-Log "[ERROR] Failed to create live report: $_"
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
