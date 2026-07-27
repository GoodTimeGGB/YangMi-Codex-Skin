[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$commonPath = Join-Path $root 'windows\common-yang-mi-skin.ps1'
$installPath = Join-Path $root 'windows\install-yang-mi-autostart.ps1'
$uninstallPath = Join-Path $root 'windows\uninstall-yang-mi-autostart.ps1'
$restorePath = Join-Path $root 'windows\restore-yang-mi-skin.ps1'
$applyPath = Join-Path $root 'windows\apply-yang-mi-skin.ps1'
$watcherPath = Join-Path $root 'windows\watch-yang-mi-skin.ps1'

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
  Assert-True ($Before.Exists -eq $After.Exists -and $Before.Bytes -ceq $After.Bytes -and $Before.ModifiedTicks -eq $After.ModifiedTicks) $Message
}

Assert-True (Test-Path -LiteralPath $commonPath) 'The common helper is missing.'
Assert-True (Test-Path -LiteralPath $installPath) 'The autostart installer is missing.'
Assert-True (Test-Path -LiteralPath $uninstallPath) 'The autostart uninstaller is missing.'
. $commonPath

if (-not ('YangMiSkin.AutostartContractHResultException' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.IO;
using Microsoft.Win32;
namespace YangMiSkin {
  public sealed class AutostartContractHResultException : Exception {
    public AutostartContractHResultException() { HResult = unchecked((int)0x80041003); }
    public int Code { get { return HResult; } }
  }
  public sealed class AutostartContractCimException : Exception {
    public AutostartContractCimException() { HResult = -2146233088; }
    public int Code { get { return HResult; } }
  }
  public sealed class AutostartContractDeletedRunKey {
    public RegistryValueKind GetValueKind(string name) { throw new IOException("Run key is marked for deletion.", 1018); }
  }
  public sealed class AutostartContractMissingRunKey {
    public RegistryValueKind GetValueKind(string name) { throw new IOException("The specified registry key does not exist.", 2); }
  }
  public sealed class AutostartContractMissingValueRunKey {
    public RegistryValueKind GetValueKind(string name) { throw new ArgumentException("Run value does not exist."); }
  }
  public sealed class AutostartContractGenericIoRunKey {
    public RegistryValueKind GetValueKind(string name) { throw new IOException("Generic registry IO failure."); }
  }
  public sealed class AutostartContractClosedRunKey {
    public RegistryValueKind GetValueKind(string name) { throw new ObjectDisposedException("Run key"); }
  }
}
'@
}
$wbemError = [System.Management.Automation.ErrorRecord]::new([YangMiSkin.AutostartContractHResultException]::new(), 'HRESULT 0x80041003,Get-ScheduledTask', [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
$registerError = [System.Management.Automation.ErrorRecord]::new([YangMiSkin.AutostartContractCimException]::new(), 'HRESULT 0x80070005,Register-ScheduledTask', [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
$unrelatedError = [System.Management.Automation.ErrorRecord]::new([System.InvalidOperationException]::new(), 'HRESULT 0x80004005,Register-ScheduledTask', [System.Management.Automation.ErrorCategory]::NotSpecified, $null)
Assert-True (Test-YangMiAutostartAccessDenied -Error $wbemError) 'WBEM_E_ACCESS_DENIED must be eligible for the restricted HKCU Run fallback.'
Assert-True (Test-YangMiAutostartAccessDenied -Error $registerError) 'A Scheduler ErrorRecord with exact HRESULT 0x80070005 must be eligible for the restricted HKCU Run fallback.'
Assert-False (Test-YangMiAutostartAccessDenied -Error $unrelatedError) 'Unrelated Scheduler ErrorRecord HRESULTs must not be eligible for the HKCU Run fallback.'

$taskName = 'YangMiCodexSkinWatcher'
$stateRoot = [System.IO.Path]::GetFullPath((Join-Path ([System.IO.Path]::GetTempPath()) 'yang-mi-autostart-contract'))
$powershellPath = [System.IO.Path]::GetFullPath((Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'))
$expectedAction = New-YangMiAutostartTaskAction -PowerShellPath $powershellPath -WatcherPath $watcherPath -StateRoot $stateRoot
$expectedPrincipal = Get-YangMiAutostartTaskPrincipalIdentity

Assert-True ($expectedAction.Execute -ceq $powershellPath) 'Autostart action must use an absolute powershell.exe path.'
Assert-True ([System.IO.Path]::IsPathRooted($expectedAction.Execute) -and [System.IO.Path]::IsPathRooted($watcherPath) -and [System.IO.Path]::IsPathRooted($stateRoot)) 'Autostart paths must be absolute.'
Assert-True ($expectedAction.Arguments -match '^-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File ') 'Autostart action must use a hidden noninteractive PowerShell invocation.'
Assert-True ($expectedAction.Arguments -match '-File\s+"' -and $expectedAction.Arguments -match '-StateRoot\s+"') 'Autostart watcher and state-root paths must be Windows-command-line quoted.'
Assert-True ($expectedAction.Arguments -match [regex]::Escape($watcherPath)) 'Autostart action must quote the absolute watcher path.'
Assert-True ($expectedAction.Arguments -match [regex]::Escape($stateRoot)) 'Autostart action must quote the absolute state root.'
Assert-True (Test-YangMiAutostartTaskIdentity -TaskName $taskName -TaskAction $expectedAction -TaskPrincipal $expectedPrincipal -PowerShellPath $powershellPath -WatcherPath $watcherPath -StateRoot $stateRoot) 'The exact autostart task identity should match.'
Assert-False (Test-YangMiAutostartTaskIdentity -TaskName 'OtherTask' -TaskAction $expectedAction -TaskPrincipal $expectedPrincipal -PowerShellPath $powershellPath -WatcherPath $watcherPath -StateRoot $stateRoot) 'A wrong task name must fail task identity validation.'
$wrongAction = [pscustomobject]@{ Execute = $powershellPath; Arguments = '-NoProfile -File C:\other.ps1 -StateRoot C:\other' }
Assert-False (Test-YangMiAutostartTaskIdentity -TaskName $taskName -TaskAction $wrongAction -TaskPrincipal $expectedPrincipal -PowerShellPath $powershellPath -WatcherPath $watcherPath -StateRoot $stateRoot) 'A wrong watcher action must fail task identity validation.'
$wrongPrincipal = [pscustomobject]@{ UserId = 'S-1-5-18'; LogonType = 'Interactive'; RunLevel = 'Limited' }
Assert-False (Test-YangMiAutostartTaskIdentity -TaskName $taskName -TaskAction $expectedAction -TaskPrincipal $wrongPrincipal -PowerShellPath $powershellPath -WatcherPath $watcherPath -StateRoot $stateRoot) 'A wrong task principal must fail task identity validation.'
$wrongArguments = [pscustomobject]@{ Execute = $powershellPath; Arguments = "$($expectedAction.Arguments) -NoProfile" }
Assert-False (Test-YangMiAutostartTaskIdentity -TaskName $taskName -TaskAction $wrongArguments -TaskPrincipal $expectedPrincipal -PowerShellPath $powershellPath -WatcherPath $watcherPath -StateRoot $stateRoot) 'Duplicate or extra task arguments must fail task identity validation.'

$runPowerShellPath = [System.IO.Path]::GetFullPath((Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'))
$runWatcherPath = 'C:\YangMi\watch-yang-mi-skin.ps1'
$runStateRoot = 'C:\YangMiCodexSkin'
$expectedRunCommand = New-YangMiAutostartRunCommand -PowerShellPath $runPowerShellPath -WatcherPath $runWatcherPath -StateRoot $runStateRoot
Assert-True ($expectedRunCommand -ceq ('"{0}" -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}" -StateRoot "{2}"' -f $runPowerShellPath, $runWatcherPath, $runStateRoot)) 'The Run fallback command must use the canonical hidden watcher invocation.'
Assert-True ($expectedRunCommand.Length -le 260) 'The canonical Run fallback command must fit the supported Run-value length.'
$exactRunValue = [pscustomobject]@{
  Name = $script:YangMiAutostartRunValueName
  Kind = [Microsoft.Win32.RegistryValueKind]::String
  RawValue = $expectedRunCommand
}
Assert-True (Test-YangMiAutostartRunValueIdentity -Value $exactRunValue -PowerShellPath $runPowerShellPath -WatcherPath $runWatcherPath -StateRoot $runStateRoot) 'The exact REG_SZ Run fallback value should match the watcher identity.'
Assert-False (Test-YangMiAutostartRunValueIdentity -Value ([pscustomobject]@{ Name = 'OtherValue'; Kind = [Microsoft.Win32.RegistryValueKind]::String; RawValue = $expectedRunCommand }) -PowerShellPath $runPowerShellPath -WatcherPath $runWatcherPath -StateRoot $runStateRoot) 'A Run value with the wrong name must not be treated as owned.'
Assert-False (Test-YangMiAutostartRunValueIdentity -Value ([pscustomobject]@{ Name = $script:YangMiAutostartRunValueName; Kind = [Microsoft.Win32.RegistryValueKind]::ExpandString; RawValue = $expectedRunCommand }) -PowerShellPath $runPowerShellPath -WatcherPath $runWatcherPath -StateRoot $runStateRoot) 'REG_EXPAND_SZ must not be treated as an owned Run fallback value.'
Assert-False (Test-YangMiAutostartRunValueIdentity -Value ([pscustomobject]@{ Name = $script:YangMiAutostartRunValueName; Kind = [Microsoft.Win32.RegistryValueKind]::String; RawValue = "$expectedRunCommand -NoProfile" }) -PowerShellPath $runPowerShellPath -WatcherPath $runWatcherPath -StateRoot $runStateRoot) 'Run fallback commands with extra arguments must be rejected.'
Assert-False (Test-YangMiAutostartRunValueIdentity -Value ([pscustomobject]@{ Name = $script:YangMiAutostartRunValueName; Kind = [Microsoft.Win32.RegistryValueKind]::String; RawValue = '"C:\broken' }) -PowerShellPath $runPowerShellPath -WatcherPath $runWatcherPath -StateRoot $runStateRoot) 'Malformed Run fallback commands must be rejected.'
Assert-False (Test-YangMiAutostartRunValueIdentity -Value ([pscustomobject]@{ Name = $script:YangMiAutostartRunValueName; Kind = [Microsoft.Win32.RegistryValueKind]::String; RawValue = ('x' * 261) }) -PowerShellPath $runPowerShellPath -WatcherPath $runWatcherPath -StateRoot $runStateRoot) 'Run fallback commands longer than 260 characters must be rejected.'
$deletedRunKey = [YangMiSkin.AutostartContractDeletedRunKey]::new()
Assert-True ($null -eq (Get-YangMiAutostartRunValue -RegistryKey $deletedRunKey)) 'An HKCU Run key marked for deletion must be treated as absent.'
$missingRunKey = [YangMiSkin.AutostartContractMissingRunKey]::new()
Assert-True ($null -eq (Get-YangMiAutostartRunValue -RegistryKey $missingRunKey)) 'A missing HKCU Run key must be treated as absent.'
$missingValueRunKey = [YangMiSkin.AutostartContractMissingValueRunKey]::new()
Assert-True ($null -eq (Get-YangMiAutostartRunValue -RegistryKey $missingValueRunKey)) 'A missing named HKCU Run value must be treated as absent.'
$genericRunReadFailed = $false
try { $null = Get-YangMiAutostartRunValue -RegistryKey ([YangMiSkin.AutostartContractGenericIoRunKey]::new()) } catch { $genericRunReadFailed = $true }
Assert-True $genericRunReadFailed 'Generic HKCU Run IO failures must not be treated as absent.'
$closedRunReadFailed = $false
try { $null = Get-YangMiAutostartRunValue -RegistryKey ([YangMiSkin.AutostartContractClosedRunKey]::new()) } catch { $closedRunReadFailed = $true }
Assert-True $closedRunReadFailed 'Closed HKCU Run keys must not be treated as absent.'

$installedStateRoot = [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'YangMiCodexSkin'))
$longDirectCommand = New-YangMiAutostartRunCommand -PowerShellPath $powershellPath -WatcherPath $watcherPath -StateRoot $installedStateRoot
Assert-True ($longDirectCommand.Length -gt 260) 'The real installed direct Run command must exercise the long-command fallback path.'
$launcherDefinition = New-YangMiAutostartRunDefinition -PowerShellPath $powershellPath -WatcherPath $watcherPath -StateRoot $installedStateRoot
Assert-True ($launcherDefinition.mode -ceq 'launcher') 'An oversized direct command must use the short watcher launcher.'
Assert-True ($launcherDefinition.command.Length -le 260) 'The watcher launcher Run command must fit the supported Run-value length.'
Assert-True ($launcherDefinition.launcherPath -ceq (Join-Path $installedStateRoot 'watcher-launch.ps1')) 'The launcher must be created at the stable StateRoot path.'
Assert-True ($launcherDefinition.launcherContent -match 'watch-yang-mi-skin\.ps1' -and $launcherDefinition.launcherContent -match '-StateRoot') 'The launcher must contain the canonical watcher invocation.'
$launcherRunValue = [pscustomobject]@{ Name = $script:YangMiAutostartRunValueName; Kind = [Microsoft.Win32.RegistryValueKind]::String; RawValue = $launcherDefinition.command }
Assert-True (Test-YangMiAutostartRunValueIdentity -Value $launcherRunValue -PowerShellPath $powershellPath -WatcherPath $watcherPath -StateRoot $installedStateRoot -LauncherContent $launcherDefinition.launcherContent) 'The exact launcher-backed REG_SZ Run fallback should match the watcher identity.'
$launcherArguments = @(ConvertFrom-YangMiWindowsCommandLine -CommandLine $launcherRunValue.RawValue)
Assert-True (Test-YangMiAutostartRunLauncherCommandArguments -Arguments $launcherArguments -PowerShellPath $powershellPath -LauncherPath $launcherDefinition.launcherPath) 'The launcher-backed Run command must parse to the exact hardened PowerShell argv.'
$mutatedLauncherArguments = @($launcherArguments)
$mutatedLauncherArguments[6] = 'Visible'
Assert-False (Test-YangMiAutostartRunLauncherCommandArguments -Arguments $mutatedLauncherArguments -PowerShellPath $powershellPath -LauncherPath $launcherDefinition.launcherPath) 'A mutated launcher-mode PowerShell argument must be rejected.'
Assert-False (Test-YangMiAutostartRunValueIdentity -Value $launcherRunValue -PowerShellPath $powershellPath -WatcherPath $watcherPath -StateRoot $installedStateRoot -LauncherContent "$($launcherDefinition.launcherContent)# altered") 'A launcher with altered content must not be treated as owned.'

$uninstallTask = [pscustomobject]@{
  TaskName = $taskName
  Actions = $expectedAction
  Principal = $expectedPrincipal
  Settings = [pscustomobject]@{ Enabled = $true; MultipleInstances = 'IgnoreNew'; StartWhenAvailable = $true }
  Triggers = @([pscustomobject]@{ Enabled = $true; UserId = $expectedPrincipal.UserId; CimClass = [pscustomobject]@{ CimClassName = 'MSFT_TaskLogonTrigger' } })
}
$unownedRunValue = [pscustomobject]@{ Name = $script:YangMiAutostartRunValueName; Kind = [Microsoft.Win32.RegistryValueKind]::ExpandString; RawValue = $expectedRunCommand }
$collisionPreflight = Get-YangMiAutostartUninstallPreflight -Task $uninstallTask -RunValue $unownedRunValue -PowerShellPath $powershellPath -WatcherPath $watcherPath -StateRoot $stateRoot
Assert-False $collisionPreflight.CanRemove 'An unowned HKCU Run collision must stop uninstall before the verified task is touched.'
Assert-True ($collisionPreflight.Failure -ceq 'hkcu-run-mismatch') 'An unowned HKCU Run collision must be reported as an identity mismatch.'

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "yang-mi-autostart-test-$([guid]::NewGuid().ToString('N'))"
try {
  [System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null
  $paths = Get-YangMiSkinPaths -StateRoot $tempRoot
  $settings = New-YangMiSkinSettings -ThemeId 'floral-retro' -Enabled $true
  Write-YangMiSkinSettings -Path $paths.SettingsPath -Settings $settings
  $settingsBefore = Get-TestFileSnapshot -Path $paths.SettingsPath
  $sessionBefore = Get-TestFileSnapshot -Path $paths.SessionPath
  $installerJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $installPath -WhatIf -StateRoot $tempRoot
  if ($LASTEXITCODE -ne 0) { throw 'Autostart installer -WhatIf failed.' }
  $installer = $installerJson | ConvertFrom-Json
  Assert-True ($installer.taskName -ceq $taskName) 'Installer -WhatIf reported the wrong task name.'
  Assert-True ($installer.action.execute -ceq $powershellPath) 'Installer -WhatIf reported the wrong action executable.'
  Assert-True ($installer.action.arguments -match [regex]::Escape($watcherPath)) 'Installer -WhatIf did not report the watcher action.'
  Assert-True ($installer.principal.userId -ceq $expectedPrincipal.UserId) 'Installer -WhatIf reported the wrong current-user principal.'
  Assert-True (@($installer.backends).Count -eq 2) 'Installer -WhatIf must report both planned autostart backends.'
  $plannedScheduler = @($installer.backends | Where-Object { $_.backend -ceq 'scheduled-task' })
  $plannedRun = @($installer.backends | Where-Object { $_.backend -ceq 'hkcu-run' })
  Assert-True ($plannedScheduler.Count -eq 1 -and $plannedScheduler[0].taskName -ceq $taskName) 'Installer -WhatIf must report the planned Task Scheduler backend.'
  Assert-True ($plannedRun.Count -eq 1 -and $plannedRun[0].registryPath -ceq $script:YangMiAutostartRunRegistryPath -and $plannedRun[0].valueName -ceq $script:YangMiAutostartRunValueName) 'Installer -WhatIf must report the named HKCU Run fallback value.'
  $expectedInstallRunDefinition = New-YangMiAutostartRunDefinition -PowerShellPath $powershellPath -WatcherPath $watcherPath -StateRoot $tempRoot
  Assert-True ($plannedRun[0].command -ceq $expectedInstallRunDefinition.command) 'Installer -WhatIf must report the exact canonical HKCU Run command.'
  Assert-True ($plannedRun[0].launcherPath -ceq $expectedInstallRunDefinition.launcherPath -and $plannedRun[0].launcherContent -ceq $expectedInstallRunDefinition.launcherContent) 'Installer -WhatIf must report the exact launcher identity when the direct command is too long.'
  Assert-TestFileSnapshotEqual $settingsBefore (Get-TestFileSnapshot -Path $paths.SettingsPath) 'Installer -WhatIf changed settings.'
  Assert-TestFileSnapshotEqual $sessionBefore (Get-TestFileSnapshot -Path $paths.SessionPath) 'Installer -WhatIf changed session state.'

  $uninstallJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $uninstallPath -WhatIf -StateRoot $tempRoot
  if ($LASTEXITCODE -ne 0) { throw 'Autostart uninstaller -WhatIf failed.' }
  $uninstall = $uninstallJson | ConvertFrom-Json
  Assert-True ($uninstall.whatIf -eq $true -and $uninstall.taskName -ceq $taskName) 'Uninstaller -WhatIf output is invalid.'
  Assert-True (@($uninstall.backends).Count -eq 2) 'Uninstaller -WhatIf must report both removable autostart backends.'
  $uninstallScheduler = @($uninstall.backends | Where-Object { $_.backend -ceq 'scheduled-task' })
  $uninstallRun = @($uninstall.backends | Where-Object { $_.backend -ceq 'hkcu-run' })
  Assert-True ($uninstallScheduler.Count -eq 1 -and $uninstallScheduler[0].taskName -ceq $taskName) 'Uninstaller -WhatIf must report Task Scheduler removal.'
  $expectedUninstallRunDefinition = New-YangMiAutostartRunDefinition -PowerShellPath $powershellPath -WatcherPath $watcherPath -StateRoot $tempRoot
  Assert-True ($uninstallRun.Count -eq 1 -and $uninstallRun[0].registryPath -ceq $script:YangMiAutostartRunRegistryPath -and $uninstallRun[0].valueName -ceq $script:YangMiAutostartRunValueName -and $uninstallRun[0].command -ceq $expectedUninstallRunDefinition.command) 'Uninstaller -WhatIf must report the exact HKCU Run removal identity.'
  Assert-TestFileSnapshotEqual $settingsBefore (Get-TestFileSnapshot -Path $paths.SettingsPath) 'Uninstaller -WhatIf changed settings.'
  Assert-TestFileSnapshotEqual $sessionBefore (Get-TestFileSnapshot -Path $paths.SessionPath) 'Uninstaller -WhatIf changed session state.'
} finally {
  if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

$commonText = [System.IO.File]::ReadAllText($commonPath)
$installText = [System.IO.File]::ReadAllText($installPath)
$uninstallText = [System.IO.File]::ReadAllText($uninstallPath)
$restoreText = [System.IO.File]::ReadAllText($restorePath)
$applyText = [System.IO.File]::ReadAllText($applyPath)
Assert-True ($installText -match 'New-ScheduledTaskTrigger\s+-AtLogOn') 'Autostart must use an interactive logon trigger.'
Assert-True ($installText -match 'MultipleInstances\s+IgnoreNew' -and $installText -match 'StartWhenAvailable') 'Autostart task settings are incomplete.'
Assert-False ($installText -match '(?:AtStartup|AtBoot|RunLevel\s+Highest|Register-ScheduledTask[\s\S]*Password)') 'Autostart must not use boot, elevation, or a password.'
Assert-True (($installText + $uninstallText) -match 'Get-ScheduledTask[^\r\n]*-ErrorAction\s+Stop') 'Scheduler reads must surface access failures for the explicit fallback gate.'
Assert-False (($installText + $uninstallText) -match 'Get-ScheduledTask[^\r\n]*-ErrorAction\s+SilentlyContinue') 'Scheduler reads must not silently treat arbitrary errors as a missing task.'
Assert-True (($installText + $uninstallText) -match 'Test-YangMiAutostartAccessDenied') 'Installer and uninstaller must gate fallback handling on an access-denied identity.'
Assert-True (($installText + $uninstallText) -match 'Test-YangMiAutostartAccessDenied\s+-Error\s+\$_') 'Installer and uninstaller must pass the full Scheduler ErrorRecord to the access-denied gate.'
Assert-False (($installText + $uninstallText) -match 'Test-YangMiAutostartAccessDenied\s+-Exception\s+\$_\.Exception') 'Installer and uninstaller must not discard Scheduler ErrorRecord identity details.'
Assert-True ($installText.LastIndexOf('New-YangMiAutostartRunDefinition') -gt $installText.IndexOf('Register-ScheduledTask')) 'Installer must construct the Run fallback only after Task Scheduler has failed with access denied.'
Assert-True ($commonText -match 'RegistryValueOptions\]::DoNotExpandEnvironmentNames') 'Run fallback identity must be read without expanding environment variables.'
Assert-True ($commonText -match 'RegistryValueKind\]::String') 'Run fallback identity must require REG_SZ.'
Assert-True ($uninstallText -match 'DeleteValue\(\$script:YangMiAutostartRunValueName') 'Uninstaller must remove only the named owned Run value.'
Assert-False (($installText + $uninstallText) -match 'Remove-Item[^\r\n]*YangMiAutostartRunRegistryPath') 'Autostart cleanup must not remove the HKCU Run key broadly.'
$runDeleteIndex = $uninstallText.IndexOf('DeleteValue($script:YangMiAutostartRunValueName')
$autostartOnlyIndex = $uninstallText.IndexOf('if ($AutostartOnly)')
Assert-True ($uninstallText -match '\[Alias\(''TaskOnly''\)\]\s*\[switch\]\$AutostartOnly') '-TaskOnly must remain a compatibility alias for broadened autostart cleanup.'
Assert-True ($runDeleteIndex -ge 0 -and $autostartOnlyIndex -gt $runDeleteIndex) '-AutostartOnly must run after both backends are cleaned up.'
$uninstallPreflightIndex = $uninstallText.IndexOf('Get-YangMiAutostartUninstallPreflight')
$disableTaskIndex = $uninstallText.IndexOf('Disable-ScheduledTask')
Assert-True ($uninstallPreflightIndex -ge 0 -and $disableTaskIndex -gt $uninstallPreflightIndex -and $runDeleteIndex -gt $uninstallPreflightIndex) 'Uninstaller must preflight both backend identities before removing either backend.'
Assert-False (($commonText + $uninstallText + $restoreText + $applyText) -match 'Stop-Process\s+-Id\s+\(\[int\]\)\$[^^\r\n]*\.(?:injectorPid|watcherPid)') 'Raw Stop-Process against a recorded state PID is forbidden.'
Assert-True ($restoreText -match 'Read-YangMiSkinSession[\s\S]*if\s*\(\$null\s+-ne\s*\$session\)') 'Restore must work without a session file.'
Assert-True ($restoreText -match '&\s+\$uninstaller\s+-AutostartOnly') 'Restore must invoke broadened verified autostart cleanup.'
Assert-False ($restoreText -match 'Start-DreamSkinCodex|Stop-DreamSkinCodex') 'Restore must not force-close or restart Codex.'
Assert-True ($restoreText -match 'function\s+Test-YangMiRestoreHasInjectorIdentity') 'Restore must distinguish an idle session from a partially recorded injector identity.'
Assert-True ($restoreText -match '\$hasInjectorIdentity\s+-and\s+-not\s+\(Test-YangMiRestoreSession') 'Restore must reject only partial injector identity, not a clean idle session.'
Assert-True ($restoreText -match 'if\s*\(\$hasInjectorIdentity\)[\s\S]*--remove[\s\S]*Stop-YangMiSessionInjectorAnyAllowedTheme') 'Renderer removal and injector termination must run only when a complete injector identity exists.'
Assert-True ($uninstallText -match 'orphanLauncherPath[\s\S]*Test-YangMiAutostartRunLauncherContentIdentity[\s\S]*Remove-Item\s+-LiteralPath\s+\$orphanLauncherPath') 'Autostart cleanup must remove an orphaned watcher launcher only after exact content identity verification.'
Assert-False ($applyText -match '\$autostartInstaller') 'Manual apply must not reference the autostart installer.'
Assert-False ($applyText -match 'install-yang-mi-autostart\.ps1') 'Manual apply must not install Windows startup persistence.'
Assert-False ($applyText -match '\$autostartInstallAttempted') 'Manual apply rollback must not manage autostart installation.'

foreach ($path in @($commonPath, $installPath, $uninstallPath, $restorePath, $applyPath)) {
  $tokens = $null
  $parseErrors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
  Assert-True ($parseErrors.Count -eq 0) "PowerShell parser errors in $path"
}

Write-Host 'PASS: autostart contract'
