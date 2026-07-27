[CmdletBinding()]
param(
  [switch]$WhatIf,
  [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'YangMiCodexSkin')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common-yang-mi-skin.ps1')

$watcherPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'watch-yang-mi-skin.ps1'))
$powerShellPath = [System.IO.Path]::GetFullPath((Join-Path $PSHOME 'powershell.exe'))
$fullStateRoot = [System.IO.Path]::GetFullPath($StateRoot)
$principalIdentity = Get-YangMiAutostartTaskPrincipalIdentity
$actionIdentity = New-YangMiAutostartTaskAction -PowerShellPath $powerShellPath -WatcherPath $watcherPath -StateRoot $fullStateRoot
$runDefinition = $null

if ($WhatIf) {
  $runDefinition = New-YangMiAutostartRunDefinition -PowerShellPath $powerShellPath -WatcherPath $watcherPath -StateRoot $fullStateRoot
  [pscustomobject][ordered]@{
    whatIf = $true
    taskName = $script:YangMiAutostartTaskName
    action = [pscustomobject][ordered]@{ execute = $actionIdentity.Execute; arguments = $actionIdentity.Arguments }
    principal = [pscustomobject][ordered]@{ userId = $principalIdentity.UserId; logonType = $principalIdentity.LogonType; runLevel = $principalIdentity.RunLevel }
    backends = @(
      [pscustomobject][ordered]@{
        backend = 'scheduled-task'
        taskName = $script:YangMiAutostartTaskName
        action = [pscustomobject][ordered]@{ execute = $actionIdentity.Execute; arguments = $actionIdentity.Arguments }
        principal = [pscustomobject][ordered]@{ userId = $principalIdentity.UserId; logonType = $principalIdentity.LogonType; runLevel = $principalIdentity.RunLevel }
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

if (-not (Test-Path -LiteralPath $watcherPath -PathType Leaf)) { throw "The Yang Mi watcher is missing: $watcherPath" }
if (-not (Test-Path -LiteralPath $powerShellPath -PathType Leaf)) { throw "The Windows PowerShell executable is missing: $powerShellPath" }

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
if (-not $schedulerDenied -and $null -ne $existing -and -not (Test-YangMiAutostartTaskDefinition -Task $existing -PowerShellPath $powerShellPath -WatcherPath $watcherPath -StateRoot $fullStateRoot)) {
  throw "Refused to replace '$($script:YangMiAutostartTaskName)' because its action, principal, trigger, or settings are not the verified Yang Mi task identity."
}
if (-not $schedulerDenied) {
  try {
    $action = New-ScheduledTaskAction -Execute $actionIdentity.Execute -Argument $actionIdentity.Arguments
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $principalIdentity.UserId
    $principal = New-ScheduledTaskPrincipal -UserId $principalIdentity.UserId -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable
    Register-ScheduledTask -TaskName $script:YangMiAutostartTaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
    Write-Host "Installed per-user autostart task '$($script:YangMiAutostartTaskName)' using backend scheduled-task."
    return
  } catch {
    if (-not (Test-YangMiAutostartAccessDenied -Error $_)) { throw }
    $schedulerDenied = $true
  }
}

$runDefinition = New-YangMiAutostartRunDefinition -PowerShellPath $powerShellPath -WatcherPath $watcherPath -StateRoot $fullStateRoot
if ($runDefinition.Command.Length -gt $script:YangMiAutostartRunMaximumCommandLength) {
  throw "Refused to create '$($script:YangMiAutostartRunValueName)' because its command exceeds $($script:YangMiAutostartRunMaximumCommandLength) characters."
}
$launcherCreated = $false
$runKey = $null
try {
  if ($runDefinition.Mode -ceq 'launcher') {
    $existingLauncherContent = Read-YangMiAutostartRunLauncherContent -Path $runDefinition.LauncherPath
    if ($null -eq $existingLauncherContent) {
      Write-DreamSkinUtf8FileAtomically -Path $runDefinition.LauncherPath -Content $runDefinition.LauncherContent
      $launcherCreated = $true
    } elseif (-not (Test-YangMiAutostartRunLauncherContentIdentity -Content $existingLauncherContent -PowerShellPath $powerShellPath -WatcherPath $watcherPath -StateRoot $fullStateRoot)) {
      throw "Refused to replace '$($runDefinition.LauncherPath)' because its launcher content does not match the verified Yang Mi watcher identity."
    }
  }
  $runKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($script:YangMiAutostartRunRegistrySubKey, $true)
  if ($null -eq $runKey) { throw "Unable to open $($script:YangMiAutostartRunRegistryPath) for the Yang Mi autostart fallback." }
  $existingRunValue = Get-YangMiAutostartRunValue -RegistryKey $runKey
  $launcherContent = if ($runDefinition.Mode -ceq 'launcher') { Read-YangMiAutostartRunLauncherContent -Path $runDefinition.LauncherPath } else { $null }
  if ($null -ne $existingRunValue -and -not (Test-YangMiAutostartRunValueIdentity -Value $existingRunValue -PowerShellPath $powerShellPath -WatcherPath $watcherPath -StateRoot $fullStateRoot -LauncherContent $launcherContent)) {
    throw "Refused to replace '$($script:YangMiAutostartRunValueName)' because its HKCU Run value does not match the verified Yang Mi watcher identity."
  }
  if ($null -eq $existingRunValue) {
    $runKey.SetValue($script:YangMiAutostartRunValueName, $runDefinition.Command, [Microsoft.Win32.RegistryValueKind]::String)
  }
} catch {
  if ($launcherCreated) {
    try {
      $launcherContent = Read-YangMiAutostartRunLauncherContent -Path $runDefinition.LauncherPath
      if (Test-YangMiAutostartRunLauncherContentIdentity -Content $launcherContent -PowerShellPath $powerShellPath -WatcherPath $watcherPath -StateRoot $fullStateRoot) {
        Remove-Item -LiteralPath $runDefinition.LauncherPath -Force
      }
    } catch {}
  }
  throw
} finally {
  if ($null -ne $runKey) { $runKey.Dispose() }
}

Write-Host "Installed per-user autostart fallback '$($script:YangMiAutostartRunValueName)' using backend hkcu-run."
