[CmdletBinding()]
param(
  [switch]$WhatIf,
  [Alias('TaskOnly')]
  [switch]$AutostartOnly,
  [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'YangMiCodexSkin')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common-yang-mi-skin.ps1')

$watcherPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'watch-yang-mi-skin.ps1'))
$powerShellPath = [System.IO.Path]::GetFullPath((Join-Path $PSHOME 'powershell.exe'))
$fullStateRoot = [System.IO.Path]::GetFullPath($StateRoot)
$runDefinition = New-YangMiAutostartRunDefinition -PowerShellPath $powerShellPath -WatcherPath $watcherPath -StateRoot $fullStateRoot

if ($WhatIf) {
  [pscustomobject][ordered]@{
    whatIf = $true
    taskName = $script:YangMiAutostartTaskName
    stateRoot = $fullStateRoot
    backends = @(
      [pscustomobject][ordered]@{
        backend = 'scheduled-task'
        taskName = $script:YangMiAutostartTaskName
      },
      [pscustomobject][ordered]@{
        backend = 'hkcu-run'
        registryPath = $script:YangMiAutostartRunRegistryPath
        valueName = $script:YangMiAutostartRunValueName
        command = $runDefinition.Command
        mode = $runDefinition.Mode
        launcherPath = $runDefinition.LauncherPath
        launcherContent = $runDefinition.LauncherContent
      }
    )
  } | ConvertTo-Json -Compress
  return
}

$schedulerDenied = $false
try {
  $existing = Get-ScheduledTask -TaskName $script:YangMiAutostartTaskName -ErrorAction Stop
} catch {
  if (Test-YangMiAutostartAccessDenied -Error $_) {
    $schedulerDenied = $true
  } elseif ($_.CategoryInfo.Category -eq [System.Management.Automation.ErrorCategory]::ObjectNotFound) {
    $existing = $null
  } else {
    throw
  }
}
$removedRunValue = $false
$removeLauncherPath = $null
$runKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:YangMiAutostartRunRegistrySubKey, $true)
try {
  $existingRunValue = Get-YangMiAutostartRunValue -RegistryKey $runKey
  $launcherContent = if ($null -ne $existingRunValue -and $runDefinition.Mode -ceq 'launcher') { Read-YangMiAutostartRunLauncherContent -Path $runDefinition.LauncherPath } else { $null }
  $preflight = Get-YangMiAutostartUninstallPreflight -Task $existing -RunValue $existingRunValue -PowerShellPath $powerShellPath `
    -WatcherPath $watcherPath -StateRoot $fullStateRoot -LauncherContent $launcherContent -SchedulerDenied:$schedulerDenied
  if (-not $preflight.CanRemove) {
    if ($preflight.Failure -ceq 'scheduled-task-mismatch') {
      throw "Refused to disable or unregister '$($script:YangMiAutostartTaskName)' because it does not match the verified Yang Mi task identity."
    }
    if ($preflight.Failure -ceq 'hkcu-run-mismatch') {
      throw "Refused to remove '$($script:YangMiAutostartRunValueName)' because its HKCU Run value or launcher does not match the verified Yang Mi watcher identity."
    }
    throw 'Task Scheduler access was denied and no verified HKCU Run fallback value was available to remove.'
  }
  if (-not $schedulerDenied -and $null -ne $existing) {
    try {
      Disable-ScheduledTask -TaskName $script:YangMiAutostartTaskName -ErrorAction Stop | Out-Null
      Unregister-ScheduledTask -TaskName $script:YangMiAutostartTaskName -Confirm:$false -ErrorAction Stop
    } catch {
      if (-not (Test-YangMiAutostartAccessDenied -Error $_)) { throw }
      $schedulerDenied = $true
      if ($null -eq $existingRunValue) {
        throw 'Task Scheduler access was denied and no verified HKCU Run fallback value was available to remove.'
      }
    }
  }
  if ($null -ne $existingRunValue) {
    $runKey.DeleteValue($script:YangMiAutostartRunValueName, $false)
    $removedRunValue = $true
    if ($runDefinition.Mode -ceq 'launcher') { $removeLauncherPath = $runDefinition.LauncherPath }
  }
} finally {
  if ($null -ne $runKey) { $runKey.Dispose() }
}

if ($null -ne $removeLauncherPath) {
  $launcherContent = Read-YangMiAutostartRunLauncherContent -Path $removeLauncherPath
  if (Test-YangMiAutostartRunLauncherContentIdentity -Content $launcherContent -PowerShellPath $powerShellPath -WatcherPath $watcherPath -StateRoot $fullStateRoot) {
    Remove-Item -LiteralPath $removeLauncherPath -Force
  }
}
$orphanLauncherPath = if ($runDefinition.Mode -ceq 'launcher') { $runDefinition.LauncherPath } else { $null }
if ($null -ne $orphanLauncherPath -and (Test-Path -LiteralPath $orphanLauncherPath)) {
  $orphanLauncherContent = Read-YangMiAutostartRunLauncherContent -Path $orphanLauncherPath
  if (Test-YangMiAutostartRunLauncherContentIdentity -Content $orphanLauncherContent -PowerShellPath $powerShellPath -WatcherPath $watcherPath -StateRoot $fullStateRoot) {
    Remove-Item -LiteralPath $orphanLauncherPath -Force
  }
}
if ($AutostartOnly) { return }

$paths = Get-YangMiSkinPaths -StateRoot $fullStateRoot
$injectorPath = [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $PSScriptRoot) 'shared\injector.mjs'))
try {
  $session = Read-YangMiSkinSession -Path $paths.SessionPath
} catch {
  $null = Archive-YangMiSkinFile -Path $paths.SessionPath -Kind 'invalid'
  throw 'The Yang Mi session was invalid, so it was archived and no recorded process was stopped.'
}
if ($null -eq $session) { return }

$watcherStopped = Stop-YangMiSessionWatcher -Session $session -WatcherPath $watcherPath -StateRoot $fullStateRoot
$injectorStopped = Stop-YangMiSessionInjectorAnyAllowedTheme -Session $session -ExpectedInjectorPath $injectorPath
if (-not $watcherStopped -or -not $injectorStopped) {
  $archive = Archive-YangMiSkinFile -Path $paths.SessionPath -Kind 'identity-mismatch'
  throw "A recorded Yang Mi process did not match its saved full identity and was left untouched. Session preserved at: $archive"
}
