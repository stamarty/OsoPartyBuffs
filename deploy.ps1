# Copies the addon into the WoW AddOns folder, replacing any previous copy.
# Usage: .\deploy.ps1 [-AddOnsPath <path to Interface\AddOns>]
param(
    [string]$AddOnsPath = "D:\ProgramFiles\World of Warcraft\_classic_era_\Interface\AddOns"
)

$ErrorActionPreference = "Stop"
$name = "OsoPartyBuffs"
$source = $PSScriptRoot
$toc = Join-Path $source "$name.toc"

if (-not (Test-Path $AddOnsPath)) {
    throw "AddOns folder not found: $AddOnsPath"
}

# Ship the .toc plus every file it lists, nothing else (no .git, README, scripts)
$files = @("$name.toc") + (Get-Content $toc | Where-Object { $_ -match '^\s*[^#\s].*\.(lua|xml)\s*$' } | ForEach-Object { $_.Trim() })

$dest = Join-Path $AddOnsPath $name
if (Test-Path $dest) {
    $item = Get-Item $dest -Force
    if ($item.LinkType) {
        # Remove only the link itself, never what it points at
        [System.IO.Directory]::Delete($dest)
    } else {
        Remove-Item $dest -Recurse -Force
    }
}
New-Item -ItemType Directory -Path $dest | Out-Null

foreach ($file in $files) {
    $from = Join-Path $source $file
    $to = Join-Path $dest $file
    New-Item -ItemType Directory -Path (Split-Path $to) -Force | Out-Null
    Copy-Item $from $to
}

Write-Host "Deployed $($files.Count) files to $dest"
$files | ForEach-Object { Write-Host "  $_" }
Write-Host "Restart WoW if the addon is new or the .toc changed; otherwise /reload in game."
