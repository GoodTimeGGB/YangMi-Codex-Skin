[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $packageRoot 'yangmi-green-bee'
$destination = Join-Path $HOME '.codex\pets\yangmi-green-bee'

if (-not (Test-Path -LiteralPath (Join-Path $source 'pet.json'))) {
  throw "Pet package is incomplete: $source"
}

New-Item -ItemType Directory -Path $destination -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $source 'pet.json') -Destination (Join-Path $destination 'pet.json') -Force
Copy-Item -LiteralPath (Join-Path $source 'spritesheet.webp') -Destination (Join-Path $destination 'spritesheet.webp') -Force

Write-Host 'Yang Mi Green Bee has been installed.' -ForegroundColor Green
Write-Host 'Restart Codex, then select the pet in Codex settings.'
