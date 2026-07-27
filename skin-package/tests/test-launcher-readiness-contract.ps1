[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$applyPath = Join-Path $root 'windows\apply-yang-mi-skin.ps1'

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

function Assert-False {
  param([bool]$Condition, [string]$Message)
  if ($Condition) { throw $Message }
}

$source = [System.IO.File]::ReadAllText($applyPath)

Assert-True ($source -match '\$verificationOutput\s*=\s*@\(&\s*\$node\.Path\s+\$injector\s+--verify') 'Launcher must poll the exact renderer verification.'
Assert-True ($source -match 'Start-Sleep -Milliseconds 500') 'Launcher must wait between renderer checks.'
Assert-True ($source -match '\$verificationPending\s*=\s*-not\s+\$verificationPassed') 'Launcher must preserve a nonfatal pending state.'
Assert-False ($source -match 'Theme verification failed before the deadline') 'Launcher must not emit a transient verification failure.'
Assert-True ($source -match '\$remainingExactInjectors\s*=\s*@\(Find-YangMiExactInjectorsAcrossNodePaths') 'Launcher must re-scan after an injector identity race.'
Assert-True ($source -match 'if \(\$remainingExactInjectors\.Count -gt 0\)') 'Launcher must stop only when an exact injector remains after the re-scan.'
Assert-True ($source -match 'function Enter-YangMiApplyOperationLock') 'Launcher must wait for the watcher-owned operation lock.'
Assert-True ($source -match 'Start-Sleep -Milliseconds 200') 'Launcher must retry after the watcher releases the operation lock.'
Assert-True ($source -match 'function Stop-YangMiWatcherForApply') 'Launcher must stop its own verified watcher before acquiring the shared operation lock.'
Assert-True ($source -match 'Stop-YangMiSessionWatcher -Session \$session -WatcherPath \$watcher -StateRoot \$paths\.StateRoot') 'Launcher must stop only the session-recorded watcher with complete identity validation.'

$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($applyPath, [ref]$tokens, [ref]$parseErrors)
Assert-True ($parseErrors.Count -eq 0) 'Launcher has PowerShell parser errors.'

Write-Host 'PASS: launcher waits for watcher-driven exact renderer readiness.'
