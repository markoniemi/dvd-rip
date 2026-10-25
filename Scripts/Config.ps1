# ==============================================================================
# Shared config loader - dot-source this from other scripts.
#
# Each script defines its own defaults as a hashtable and calls Get-RipConfig
# with them. If config.json exists next to the scripts, matching keys there
# override the defaults; anything config.json doesn't mention keeps its
# default. config.json is optional - skip it and everything just uses
# defaults as before.
#
# Usage (in another script):
#   . (Join-Path $PSScriptRoot "Config.ps1")
#   $cfg = Get-RipConfig @{
#       VideoRoot = "I:\Video"
#       MinLengthSeconds = 3600
#   }
#   $VideoRoot = $cfg.VideoRoot
# ==============================================================================

function Get-RipConfig([hashtable]$Defaults) {
    $config = $Defaults.Clone()
    $configPath = Join-Path $PSScriptRoot "config.json"

    if (Test-Path $configPath) {
        $overrides = Get-Content $configPath -Raw | ConvertFrom-Json
        foreach ($prop in $overrides.PSObject.Properties) {
            if (-not $Defaults.ContainsKey($prop.Name)) {
                Write-Host " config.json: ignoring unknown key '$($prop.Name)'"
                continue
            }
            $config[$prop.Name] = $prop.Value
        }
    }

    return $config
}
