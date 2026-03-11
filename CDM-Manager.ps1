# CDM-Manager.ps1
# A "No-Server" Desktop Dashboard for Production CDM Workflow - v1.2

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Production CDM - Workflow Manager" Height="800" Width="1000" Background="#1E1E1E">
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <StackPanel Grid.Row="0" Margin="0,0,0,20">
            <TextBlock Text="Production CDM Manager" FontSize="28" Foreground="#007ACC" FontWeight="Bold"/>
            <TextBlock x:Name="CurrentBranchText" Text="Current Branch: Loading..." FontSize="14" Foreground="#AAAAAA" Margin="0,5,0,0"/>
        </StackPanel>

        <!-- PBIX Configuration Section -->
        <Border Grid.Row="1" Background="#2D2D30" CornerRadius="8" Padding="15" Margin="0,0,0,10">
            <StackPanel>
                <TextBlock Text="📂 Local PBIX Configuration" FontSize="16" Foreground="White" Margin="0,0,0,5"/>
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBox x:Name="PbixPathText" Grid.Column="0" Height="25" VerticalContentAlignment="Center" 
                             Background="#3E3E42" Foreground="White" BorderThickness="0" Padding="5"
                             Text="D:\GitHubRepos\ProductionCDM\Production CDM.pbix"/>
                    <Button x:Name="BtnBrowsePbix" Grid.Column="1" Content="Browse..." Width="80" Height="25" Margin="10,0,0,0"
                            Background="#3E3E42" Foreground="White"/>
                </Grid>
            </StackPanel>
        </Border>

        <!-- Branch Management Section -->
        <Border Grid.Row="2" Background="#2D2D30" CornerRadius="8" Padding="15" Margin="0,0,0,10">
            <StackPanel>
                <TextBlock Text="🌿 Branch Management" FontSize="16" Foreground="White" Margin="0,0,0,10"/>
                <UniformGrid Columns="3">
                    <StackPanel Margin="5">
                        <TextBlock Text="Top Branch (Main)" Foreground="#AAAAAA" FontSize="12"/>
                        <ComboBox x:Name="ComboTopBranch" Height="30" Background="#3E3E42" Foreground="White"/>
                    </StackPanel>
                    <StackPanel Margin="5">
                        <TextBlock Text="Sub-Branch (Feature)" Foreground="#AAAAAA" FontSize="12"/>
                        <ComboBox x:Name="ComboSubBranch" Height="30" Background="#3E3E42" Foreground="White"/>
                    </StackPanel>
                    <StackPanel Margin="5">
                        <TextBlock Text="New Feature Name" Foreground="#AAAAAA" FontSize="12"/>
                        <TextBox x:Name="TxtNewFeature" Height="30" VerticalContentAlignment="Center" Background="#3E3E42" Foreground="White" BorderThickness="0" Padding="5"/>
                    </StackPanel>
                </UniformGrid>
                <UniformGrid Columns="2" Margin="0,10,0,0">
                    <Button x:Name="BtnSwitchBranch" Content="Switch to Selected Branch" Height="30" Background="#007ACC" Foreground="White" Margin="5"/>
                    <Button x:Name="BtnCreateFeature" Content="Create &amp; Deploy New Feature" Height="30" Background="#43A047" Foreground="White" Margin="5"/>
                </UniformGrid>
            </StackPanel>
        </Border>

        <!-- Actions Section -->
        <UniformGrid Grid.Row="3" Columns="2" Margin="0,0,0,10">
            <!-- Deployment Card -->
            <Border Background="#2D2D30" CornerRadius="8" Margin="5" Padding="15">
                <StackPanel>
                    <TextBlock Text="🚀 Manual Operations" FontSize="16" Foreground="White" Margin="0,0,0,10"/>
                    <Button x:Name="BtnDeployDev" Content="Deploy Current to DEV" Height="30" Background="#007ACC" Foreground="White" Margin="0,5"/>
                    <Button x:Name="BtnDeployProd" Content="Deploy to PROD (Main Only)" Height="30" Background="#D32F2F" Foreground="White" Margin="0,5"/>
                    <CheckBox x:Name="ChkCloudBackup" Content="Include Cloud Backup" Foreground="#AAAAAA" Margin="0,5,0,0"/>
                </StackPanel>
            </Border>

            <!-- Sync Card -->
            <Border Background="#2D2D30" CornerRadius="8" Margin="5" Padding="15">
                <StackPanel>
                    <TextBlock Text="🔄 Cloud &amp; Git" FontSize="16" Foreground="White" Margin="0,0,0,10"/>
                    <Button x:Name="BtnGithubSync" Content="Sync to GitHub" Height="30" Background="#333333" Foreground="White" Margin="0,5"/>
                    <Button x:Name="BtnCloudBackupOnly" Content="Manual Cloud Backup" Height="30" Background="#43A047" Foreground="White" Margin="0,5"/>
                </StackPanel>
            </Border>
        </UniformGrid>

        <!-- Console Log -->
        <Border Grid.Row="4" Background="Black" CornerRadius="5" Padding="10">
            <ScrollViewer x:Name="LogScroller" VerticalScrollBarVisibility="Auto">
                <TextBlock x:Name="ConsoleLog" TextWrapping="Wrap" FontFamily="Consolas" Foreground="#00FF00" FontSize="12" Text="[SYSTEM] Dashboard v1.2 Ready..."/>
            </ScrollViewer>
        </Border>

        <!-- Footer -->
        <TextBlock Grid.Row="5" Text="Professional Power BI Workflow Manager" Foreground="#555555" HorizontalAlignment="Right" Margin="0,10,0,0"/>
    </Grid>
</Window>
"@

# Load XAML
$reader = [XML.XmlReader]::Create([IO.StringReader]($xaml))
$window = [Windows.Markup.XamlReader]::Load($reader)

# Map Elements
$currentBranchText = $window.FindName("CurrentBranchText")
$consoleLog = $window.FindName("ConsoleLog")
$logScroller = $window.FindName("LogScroller")
$pbixPathText = $window.FindName("PbixPathText")
$btnBrowsePbix = $window.FindName("BtnBrowsePbix")
$comboTopBranch = $window.FindName("ComboTopBranch")
$comboSubBranch = $window.FindName("ComboSubBranch")
$txtNewFeature = $window.FindName("TxtNewFeature")
$btnSwitchBranch = $window.FindName("BtnSwitchBranch")
$btnCreateFeature = $window.FindName("BtnCreateFeature")
$btnDeployDev = $window.FindName("BtnDeployDev")
$btnDeployProd = $window.FindName("BtnDeployProd")
$btnGithubSync = $window.FindName("BtnGithubSync")
$btnCloudBackupOnly = $window.FindName("BtnCloudBackupOnly")
$chkCloudBackup = $window.FindName("ChkCloudBackup")

# Helper Functions
function Write-Log ($Message) {
    $timestamp = Get-Date -Format "HH:mm:ss"
    $consoleLog.Text += "`n[$timestamp] $Message"
    $logScroller.ScrollToEnd()
}

function Refresh-UI {
    $branch = git branch --show-current
    $currentBranchText.Text = "Current Branch: $branch"
    
    # Update Top Branches (Main branches usually have specific patterns)
    $allRemotes = git branch -r | ForEach-Object { $_.Trim() }
    $topBranches = $allRemotes | Where-Object { $_ -like "*Main*" -or $_ -match "main|master" }
    $comboTopBranch.ItemsSource = $topBranches
    
    # Update Sub Branches
    $subBranches = git branch -a | ForEach-Object { $_.Trim().Replace("* ", "") }
    $comboSubBranch.ItemsSource = $subBranches
}

# Button Actions
$btnBrowsePbix.Add_Click({
    $fd = New-Object System.Windows.Forms.OpenFileDialog
    $fd.InitialDirectory = "D:\GitHubRepos\ProductionCDM"
    $fd.Filter = "Power BI Files (*.pbix)|*.pbix"
    if ($fd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $pbixPathText.Text = $fd.FileName
        Write-Log "Selected PBIX: $($fd.FileName)"
    }
})

$btnSwitchBranch.Add_Click({
    $selected = $comboSubBranch.SelectedItem
    if ($selected) {
        Write-Log "Switching to $selected..."
        git checkout $selected.Replace("remotes/azure/", "").Replace("remotes/origin/", "")
        Refresh-UI
    }
})

$btnCreateFeature.Add_Click({
    $top = $comboTopBranch.SelectedItem
    $feat = $txtNewFeature.Text
    if (-not $top -or -not $feat) {
        Write-Log "[ERROR] Please select a Top Branch and enter a Feature Name."
        return
    }
    
    $cleanTop = $top.Replace("remotes/azure/", "").Replace("remotes/origin/", "")
    $featBranch = "feature/$feat"
    
    Write-Log "1. Checking out $cleanTop..."
    git checkout $cleanTop
    git pull azure $cleanTop
    
    Write-Log "2. Creating $featBranch..."
    git checkout -b $featBranch
    
    Write-Log "3. Pushing to ADO..."
    git push azure $featBranch -u
    
    Write-Log "4. Triggering Automatic Dev Deployment..."
    $backupParam = if ($chkCloudBackup.IsChecked) { "-CloudBackup" } else { "" }
    $output = powershell.exe -NoProfile -Command ".\deploy-pbi.ps1 -TargetEnv Dev -BranchName '$feat' $backupParam"
    Write-Log $output
    
    Refresh-UI
    Write-Log "[SUCCESS] Feature '$feat' created and deployed to Dev workspace."
})

$btnDeployDev.Add_Click({
    $branch = git branch --show-current
    $cleanName = $branch.Replace("feature/", "")
    Write-Log "Starting Deployment to DEV for '$cleanName'..."
    $backupParam = if ($chkCloudBackup.IsChecked) { "-CloudBackup" } else { "" }
    $output = powershell.exe -NoProfile -Command ".\deploy-pbi.ps1 -TargetEnv Dev -BranchName '$cleanName' $backupParam"
    Write-Log $output
})

$btnDeployProd.Add_Click({
    $branch = git branch --show-current
    if ($branch -notlike "*Main*") {
        Write-Log "[ERROR] Production deployments only allowed from Main branches."
        return
    }
    $result = [System.Windows.MessageBox]::Show("Are you sure you want to deploy to PRODUCTION?", "Safety Check", "YesNo", "Warning")
    if ($result -eq "Yes") {
        Write-Log "Starting Deployment to PROD..."
        $output = powershell.exe -NoProfile -Command ".\deploy-pbi.ps1 -TargetEnv Prod -BranchName '$branch' -CloudBackup"
        Write-Log $output
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
git checkout -f feature/advanced-costing
"@
    $output = powershell.exe -NoProfile -Command $commands
    Write-Log "GitHub Sync Complete."
})

$btnCloudBackupOnly.Add_Click({
    $timestamp = Get-Date -Format "yyyyMMdd_HHmm"
    $pbixPath = $pbixPathText.Text
    Write-Log "Creating Manual Cloud Backup..."
    $output = az storage blob upload --account-name aleaus2bigprodadlame01 --container-name dal3011 --name "Common Data Models/Production CDM/Production CDM_$timestamp.pbix" --file "$pbixPath" --auth-mode login
    Write-Log "Cloud Backup Saved."
})

# Initialize
Refresh-UI
$window.ShowDialog() | Out-Null
