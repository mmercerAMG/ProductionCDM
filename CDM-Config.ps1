# CDM-Config.ps1
# Configuration constants and config.json loader for CDM-Manager.
# Dot-sourced by CDM-Manager.ps1 - all variables land in the caller's scope.

# Default service endpoints (overridable via config.json)
$ADO_REMOTE_URL   = "https://dev.azure.com/bigroupairliquide/_git/3011%20-%20Distribution%20and%20Analytics"
$SCRIPT_DIR       = $PSScriptRoot
$LOCAL_PBIX_DIR   = Split-Path -Parent $PSScriptRoot
$DEV_WORKSPACE_ID = "2696b15d-427e-437b-ba5a-ca8d4fb188dd"

# Load config.json if present - overrides compiled-in defaults without requiring script edits
$configFile = Join-Path $PSScriptRoot "config.json"
if (Test-Path $configFile) {
    try {
        $cfg = Get-Content $configFile -Raw | ConvertFrom-Json
        if ($cfg.ado_remote_url)    { $ADO_REMOTE_URL   = $cfg.ado_remote_url }
        if ($cfg.dev_workspace_id)  { $DEV_WORKSPACE_ID = $cfg.dev_workspace_id }
    } catch { Write-Warning "config.json found but could not be parsed: $_" }
}
