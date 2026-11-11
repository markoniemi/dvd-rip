# ==============================================================================
# Checks that the documentation holds together. No parameters, so no
# comment-based help of its own - see docs/Configuration.md for the layout
# this enforces:
#
#   1. every script with a param() block has .SYNOPSIS,
#   2. every parameter it declares has a .PARAMETER entry,
#   3. every such script has docs/<Script>.md beside it,
#   4. every relative link in a markdown file resolves to something.
#
# Exits 1 when anything fails, so it can gate a commit.
# ==============================================================================

$ErrorActionPreference = "Stop"

$repoRoot  = Split-Path $PSScriptRoot -Parent
$docsDir   = Join-Path $repoRoot "docs"
$failures  = New-Object System.Collections.Generic.List[string]
$checked   = 0

function Add-Failure($message) { $failures.Add($message) | Out-Null }

# PowerShell adds these to anything with [CmdletBinding()]; they are not ours
# to document.
$commonParams = @(
    [System.Management.Automation.PSCmdlet]::CommonParameters +
    [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
)

# --- 1-3: help and markdown per script -----------------------------------
foreach ($script in Get-ChildItem (Join-Path $repoRoot "Scripts") -Filter *.ps1 | Sort-Object Name) {
    $declared = @((Get-Command $script.FullName).Parameters.Keys |
                  Where-Object { $commonParams -notcontains $_ })

    # A script with no parameters (Config.ps1, this one) needs no help block
    # and no markdown file of its own.
    if ($declared.Count -eq 0) { continue }

    $checked++
    $help = Get-Help $script.FullName -Full

    # With no .SYNOPSIS, Get-Help invents one out of the syntax line, which
    # begins with the script's own file name.
    $synopsis = "$($help.Synopsis)".Trim()
    if (-not $synopsis -or $synopsis.StartsWith($script.Name)) {
        Add-Failure "$($script.Name): no .SYNOPSIS"
    }

    # Get-Help lists every declared parameter whether or not it was written
    # about, so the name being there proves nothing - the description is what
    # a .PARAMETER entry actually adds.
    $documented = @{}
    foreach ($p in $help.parameters.parameter) {
        $documented[$p.name] = "$(($p.description | ForEach-Object { $_.Text }) -join ' ')".Trim()
    }
    foreach ($param in $declared) {
        if (-not $documented[$param]) {
            Add-Failure "$($script.Name): -$param has no .PARAMETER entry"
        }
    }

    $mdPath = Join-Path $docsDir ([System.IO.Path]::ChangeExtension($script.Name, "md"))
    if (-not (Test-Path -LiteralPath $mdPath)) {
        Add-Failure "$($script.Name): docs/$([System.IO.Path]::ChangeExtension($script.Name, 'md')) is missing"
    }
}

# --- 4: relative markdown links ------------------------------------------
$markdown = @(Get-ChildItem $repoRoot -Filter *.md) +
            @(Get-ChildItem $docsDir -Filter *.md -Recurse)
$linkCount = 0

foreach ($file in $markdown) {
    $text = Get-Content -LiteralPath $file.FullName -Raw
    foreach ($match in [regex]::Matches($text, '\[[^\]]*\]\(([^)\s]+)\)')) {
        $target = $match.Groups[1].Value

        # External links and bare anchors are not ours to resolve.
        if ($target -match '^(https?:|mailto:|#)') { continue }

        $linkCount++
        $path = ($target -split '#')[0]
        if (-not $path) { continue }

        $resolved = Join-Path (Split-Path $file.FullName -Parent) $path
        if (-not (Test-Path -LiteralPath $resolved)) {
            $relative = $file.FullName.Substring($repoRoot.Length + 1)
            Add-Failure "$relative -> $target does not exist"
        }
    }
}

# --- report ---------------------------------------------------------------
Write-Host "checked $checked script(s) with parameters, $($markdown.Count) markdown file(s), $linkCount relative link(s)"

if ($failures.Count -gt 0) {
    Write-Host ""
    foreach ($failure in $failures) { Write-Host "  FAIL  $failure" }
    Write-Host ""
    Write-Host "$($failures.Count) problem(s)"
    exit 1
}

Write-Host "all good"
exit 0
