# ==============================================================================
# Shared config loader - dot-source this from other scripts.
#
# Each script defines its own defaults as a hashtable and calls Get-RipConfig
# with them. If config.json exists next to the scripts, matching keys there
# override the defaults; anything config.json doesn't mention keeps its
# default. config.json is optional - skip it and everything just uses
# defaults as before.
#
# config.json is shared across all scripts, so it can hold keys a given
# script doesn't use (e.g. RipDisc.ps1 ignores ConvertNext.ps1's keys) -
# that's expected, not an error.
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
            # Keys this script doesn't declare belong to another script -
            # config.json is shared, so silently skip them.
            if (-not $Defaults.ContainsKey($prop.Name)) { continue }
            $config[$prop.Name] = $prop.Value
        }
    }

    return $config
}
