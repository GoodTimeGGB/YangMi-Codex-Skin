[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$commonPath = Join-Path $root 'windows\common-yang-mi-skin.ps1'
$verifyPath = Join-Path $root 'windows\verify-yang-mi-skin.ps1'

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

function Assert-False {
  param([bool]$Condition, [string]$Message)
  if ($Condition) { throw $Message }
}

function Get-TestFileSnapshot {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return [pscustomobject]@{ Exists = $false; Bytes = $null; ModifiedTicks = $null } }
  $item = Get-Item -LiteralPath $Path
  return [pscustomobject]@{
    Exists = $true
    Bytes = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Path))
    ModifiedTicks = $item.LastWriteTimeUtc.Ticks
  }
}

function Assert-TestFileSnapshotEqual {
  param([object]$Before, [object]$After, [string]$Message)
  Assert-True ($Before.Exists -eq $After.Exists -and $Before.Bytes -ceq $After.Bytes -and
    $Before.ModifiedTicks -eq $After.ModifiedTicks) $Message
}

Assert-True (Test-Path -LiteralPath $commonPath) 'The Yang Mi common helper is missing.'
Assert-True (Test-Path -LiteralPath $verifyPath) 'The Yang Mi verifier is missing.'
. $commonPath

$autostartPowerShellPath = [System.IO.Path]::GetFullPath((Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'))
$autostartWatcherPath = 'C:\YangMi\watch-yang-mi-skin.ps1'
$autostartStateRoot = 'C:\YangMiCodexSkin'
$autostartAction = New-YangMiAutostartTaskAction -PowerShellPath $autostartPowerShellPath -WatcherPath $autostartWatcherPath -StateRoot $autostartStateRoot
$autostartPrincipal = Get-YangMiAutostartTaskPrincipalIdentity
$autostartTask = [pscustomobject]@{
  TaskName = $script:YangMiAutostartTaskName
  Actions = $autostartAction
  Principal = $autostartPrincipal
  Settings = [pscustomobject]@{ Enabled = $true; MultipleInstances = 'IgnoreNew'; StartWhenAvailable = $true }
  Triggers = @([pscustomobject]@{ Enabled = $true; UserId = $autostartPrincipal.UserId; CimClass = [pscustomobject]@{ CimClassName = 'MSFT_TaskLogonTrigger' } })
}
$autostartRunValue = [pscustomobject]@{
  Name = $script:YangMiAutostartRunValueName
  Kind = [Microsoft.Win32.RegistryValueKind]::String
  RawValue = New-YangMiAutostartRunCommand -PowerShellPath $autostartPowerShellPath -WatcherPath $autostartWatcherPath -StateRoot $autostartStateRoot
}
$taskSelection = Get-YangMiAutostartBackendSelection -Task $autostartTask -RunValue $autostartRunValue -PowerShellPath $autostartPowerShellPath -WatcherPath $autostartWatcherPath -StateRoot $autostartStateRoot
Assert-True ($taskSelection.backend -ceq 'scheduled-task') 'An exact Scheduled Task must be selected before an exact Run value.'
$runSelection = Get-YangMiAutostartBackendSelection -Task $null -RunValue $autostartRunValue -PowerShellPath $autostartPowerShellPath -WatcherPath $autostartWatcherPath -StateRoot $autostartStateRoot
Assert-True ($runSelection.backend -ceq 'hkcu-run') 'An exact HKCU Run value must be accepted when the Scheduled Task is absent.'
$mismatchedTask = [pscustomobject]@{
  TaskName = 'OtherTask'
  Actions = $autostartAction
  Principal = $autostartPrincipal
  Settings = $autostartTask.Settings
  Triggers = $autostartTask.Triggers
}
$mismatchSelection = Get-YangMiAutostartBackendSelection -Task $mismatchedTask -RunValue $autostartRunValue -PowerShellPath $autostartPowerShellPath -WatcherPath $autostartWatcherPath -StateRoot $autostartStateRoot
Assert-True ($null -eq $mismatchSelection.backend -and $mismatchSelection.failure -ceq 'scheduled-task-mismatch') 'A mismatched Scheduled Task must not fall through to the Run fallback.'
$badRunSelection = Get-YangMiAutostartBackendSelection -Task $null -RunValue ([pscustomobject]@{ Name = $script:YangMiAutostartRunValueName; Kind = [Microsoft.Win32.RegistryValueKind]::ExpandString; RawValue = $autostartRunValue.RawValue }) -PowerShellPath $autostartPowerShellPath -WatcherPath $autostartWatcherPath -StateRoot $autostartStateRoot
Assert-True ($null -eq $badRunSelection.backend -and $badRunSelection.failure -ceq 'hkcu-run-mismatch') 'A non-REG_SZ Run fallback must not be accepted.'

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "yang-mi-verify-test-$([guid]::NewGuid().ToString('N'))"
try {
  $paths = Get-YangMiSkinPaths -StateRoot $tempRoot
  $settings = New-YangMiSkinSettings -ThemeId 'floral-retro' -PreferredPort 9447 -Enabled $true
  $session = New-YangMiSkinSession -Status 'active'
  $session.watcherPid = 101
  $session.watcherStartedAt = [datetime]::UtcNow.ToString('o')
  $session.watcherScriptPath = Join-Path $root 'windows\watch-yang-mi-skin.ps1'
  $session.powershellPath = [System.IO.Path]::GetFullPath((Join-Path $PSHOME 'powershell.exe'))
  $session.injectorPid = 102
  $session.injectorStartedAt = [datetime]::UtcNow.ToString('o')
  $session.injectorPath = Join-Path $root 'shared\injector.mjs'
  $session.nodePath = 'C:\Program Files\nodejs\node.exe'
  $session.port = 9447
  $session.browserId = 'browser-1'
  Write-YangMiSkinSettings -Path $paths.SettingsPath -Settings $settings
  Write-YangMiSkinSession -Path $paths.SessionPath -Session $session
  $settingsBefore = Get-TestFileSnapshot -Path $paths.SettingsPath
  $sessionBefore = Get-TestFileSnapshot -Path $paths.SessionPath
  $injectorPath = Join-Path $root 'shared\injector.mjs'
  $injectorBefore = @(Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue | Where-Object {
    "$($_.CommandLine)" -match [regex]::Escape($injectorPath)
  } | Select-Object -ExpandProperty ProcessId)

  $whatIfJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $verifyPath -WhatIf -StateRoot $tempRoot
  if ($LASTEXITCODE -ne 0) { throw 'Verifier -WhatIf failed.' }
  $whatIf = $whatIfJson | ConvertFrom-Json
  Assert-True ($whatIf.whatIf -eq $true) 'Verifier -WhatIf must identify itself as a dry run.'
  Assert-True ($whatIf.themeId -ceq 'floral-retro') 'Verifier -WhatIf selected the wrong theme.'
  Assert-True ($whatIf.autostart.scheduledTask.name -ceq $script:YangMiAutostartTaskName) 'Verifier -WhatIf reported the wrong task identity.'
  Assert-True ($whatIf.autostart.scheduledTask.exists -eq $false) 'Verification requires no scheduled task.'
  Assert-True ($whatIf.autostart.hkcuRun.valueName -ceq $script:YangMiAutostartRunValueName) 'Verifier -WhatIf reported the wrong HKCU Run identity.'
  Assert-True ($whatIf.autostart.hkcuRun.exists -eq $false) 'Verification requires no HKCU Run value.'
  Assert-True ($whatIf.autostart.pass -eq $true) 'Absent startup backends must pass verification.'
  Assert-True ($whatIf.watcher.pid -eq 101) 'Verifier -WhatIf reported the wrong watcher identity.'
  Assert-True ($whatIf.injector.pid -eq 102) 'Verifier -WhatIf reported the wrong injector identity.'
  Assert-True ($whatIf.cdp.port -eq 9447 -and $whatIf.cdp.browserId -ceq 'browser-1') 'Verifier -WhatIf reported the wrong CDP identity.'
  Assert-True ($whatIf.renderer.verification -ceq 'not-run') 'Verifier -WhatIf must not run Node renderer verification.'
  Assert-TestFileSnapshotEqual $settingsBefore (Get-TestFileSnapshot -Path $paths.SettingsPath) 'Verifier -WhatIf changed settings state.'
  Assert-TestFileSnapshotEqual $sessionBefore (Get-TestFileSnapshot -Path $paths.SessionPath) 'Verifier -WhatIf changed session state.'
  $injectorAfter = @(Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue | Where-Object {
    "$($_.CommandLine)" -match [regex]::Escape($injectorPath)
  } | Select-Object -ExpandProperty ProcessId)
  Assert-True ((Compare-Object $injectorBefore $injectorAfter).Count -eq 0) 'Verifier -WhatIf started or stopped a Yang Mi injector.'

  $disabled = New-YangMiSkinSettings -ThemeId 'floral-retro' -PreferredPort 9447 -Enabled $false
  Write-YangMiSkinSettings -Path $paths.SettingsPath -Settings $disabled
  $disabledJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $verifyPath -WhatIf -StateRoot $tempRoot
  Assert-True ($LASTEXITCODE -ne 0) 'Verifier must reject disabled settings even during -WhatIf.'
  $disabledReport = $disabledJson | ConvertFrom-Json
  Assert-False ([bool]$disabledReport.pass) 'Disabled settings must not produce a passing verification report.'
  Assert-True (@($disabledReport.errors | Where-Object { "$_" -match 'disabled' }).Count -gt 0) 'Disabled settings must be reported as a verification failure.'
} finally {
  if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

$verifyText = [System.IO.File]::ReadAllText($verifyPath)
Assert-True ($verifyText -match '\[switch\]\$WhatIf') 'Verifier must offer -WhatIf.'
Assert-True ($verifyText -match 'Read-YangMiSkinSettings') 'Verifier must validate settings.'
Assert-True ($verifyText -match 'Read-YangMiSkinSession') 'Verifier must validate session state.'
Assert-False ($verifyText -match 'Get-YangMiAutostartBackendSelection') 'Verifier must not accept any installed autostart backend.'
Assert-False ($verifyText -match 'Get-ScheduledTask') 'Verifier must not depend on the Scheduler PowerShell API.'
Assert-True ($verifyText -match 'schtasks\.exe[\s\S]*/Query') 'Verifier must use the bounded system task query for exact absence checks.'
Assert-True ($verifyText -match 'Get-YangMiAutostartRunValue') 'Verifier must read the exact HKCU Run value to require its absence.'
Assert-True ($verifyText -match 'Test-YangMiSessionWatcher') 'Verifier must validate exact watcher identity.'
Assert-True ($verifyText -match 'Test-YangMiProcessIdentity') 'Verifier must validate exact injector identity.'
Assert-True ($verifyText -match 'Get-DreamSkinCodexInstall') 'Verifier must validate the Store Codex installation.'
Assert-True ($verifyText -match 'Get-DreamSkinVerifiedCdpIdentity') 'Verifier must validate verified CDP ownership.'
Assert-True ($verifyText -match '--verify\s+--theme') 'Verifier must invoke the Node renderer verification mode.'
Assert-True ($verifyText -match 'ConvertTo-Json') 'Verifier must emit a structured JSON report.'
$taskCheckIndex = $verifyText.IndexOf('schtasks.exe')
$watcherCheckIndex = $verifyText.IndexOf('Test-YangMiSessionWatcher')
$injectorCheckIndex = $verifyText.IndexOf('Test-YangMiProcessIdentity')
$cdpCheckIndex = $verifyText.IndexOf('Get-DreamSkinVerifiedCdpIdentity')
$nodeVerifyIndex = $verifyText.IndexOf('--verify')
Assert-True ($taskCheckIndex -ge 0 -and $watcherCheckIndex -gt $taskCheckIndex -and $injectorCheckIndex -gt $watcherCheckIndex -and
  $cdpCheckIndex -gt $injectorCheckIndex -and $nodeVerifyIndex -gt $cdpCheckIndex) 'Verifier safety ordering must validate autostart absence and processes before CDP and Node.'

$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($verifyPath, [ref]$tokens, [ref]$parseErrors)
Assert-True ($parseErrors.Count -eq 0) 'Verifier has PowerShell parser errors.'

Write-Host 'PASS: verify contract'
exit 0
