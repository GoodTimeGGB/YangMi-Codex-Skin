[CmdletBinding()]
param(
  [switch]$WhatIf,
  [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'YangMiCodexSkin')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$injectorPath = [System.IO.Path]::GetFullPath((Join-Path $root 'shared\injector.mjs'))
$watcherPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'watch-yang-mi-skin.ps1'))
. (Join-Path $PSScriptRoot 'common-yang-mi-skin.ps1')

function New-YangMiVerifyReport {
  param([AllowNull()][object]$Settings, [AllowNull()][object]$Session, [bool]$DryRun)
  return [ordered]@{
    pass = $false
    whatIf = $DryRun
    themeId = if ($null -ne $Settings) { $Settings.themeId } else { $null }
    autostart = [ordered]@{
      pass = $false
      scheduledTask = [ordered]@{ name = $script:YangMiAutostartTaskName; exists = $null; state = 'not-checked' }
      hkcuRun = [ordered]@{
        registryPath = $script:YangMiAutostartRunRegistryPath
        valueName = $script:YangMiAutostartRunValueName
        exists = $null
        state = 'not-checked'
      }
    }
    watcher = [ordered]@{ pid = if ($null -ne $Session) { $Session.watcherPid } else { $null }; identity = if ($DryRun) { 'expected' } else { 'not-checked' }; path = $watcherPath }
    injector = [ordered]@{ pid = if ($null -ne $Session) { $Session.injectorPid } else { $null }; identity = if ($DryRun) { 'expected' } else { 'not-checked' }; path = $injectorPath }
    cdp = [ordered]@{ port = if ($null -ne $Session) { $Session.port } else { $null }; browserId = if ($null -ne $Session) { $Session.browserId } else { $null }; ownership = if ($DryRun) { 'not-checked' } else { 'not-checked' } }
    renderer = [ordered]@{ verification = 'not-run'; exitCode = $null; nodeResult = $null }
    errors = @()
  }
}

function Invoke-YangMiScheduledTaskQuery {
  param([Parameter(Mandatory = $true)][string]$Arguments)
  $taskQueryPath = Join-Path $env:WINDIR 'System32\schtasks.exe'
  $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $taskQueryPath
  $startInfo.Arguments = $Arguments
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  try {
    if (-not $process.Start()) { throw 'Unable to start the scheduled-task query.' }
    if (-not $process.WaitForExit(5000)) {
      try { $process.Kill() } catch {}
      throw 'Scheduled-task absence query timed out.'
    }
    $output = @($process.StandardOutput.ReadToEnd(), $process.StandardError.ReadToEnd()) -join "`n"
    return [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $output.Trim() }
  } finally {
    $process.Dispose()
  }
}

function Get-YangMiScheduledTaskPresence {
  $exact = Invoke-YangMiScheduledTaskQuery -Arguments "/Query /TN `"$script:YangMiAutostartTaskName`" /FO LIST"
  if ($exact.ExitCode -eq 0) {
    return [pscustomobject]@{ Exists = $true; State = 'present' }
  }
  $taskFile = Join-Path $env:WINDIR "System32\Tasks\$script:YangMiAutostartTaskName"
  try {
    $null = Get-Item -LiteralPath $taskFile -ErrorAction Stop
    return [pscustomobject]@{ Exists = $true; State = 'present' }
  } catch [System.Management.Automation.ItemNotFoundException] {
    return [pscustomobject]@{ Exists = $false; State = 'absent' }
  } catch {
    throw "Scheduled-task absence could not be verified: $($_.Exception.Message)"
  }
}

function Complete-YangMiVerifyReport {
  param([Parameter(Mandatory = $true)][hashtable]$Report, [int]$ExitCode = 0)
  $Report.pass = @($Report.errors).Count -eq 0 -and $ExitCode -eq 0
  $Report | ConvertTo-Json -Depth 6 -Compress
  exit $(if ($Report.pass) { 0 } else { 1 })
}

$paths = Get-YangMiSkinPaths -StateRoot $StateRoot
$settings = $null
$session = $null
$stateErrors = @()
try {
  $settings = Read-YangMiSkinSettings -Path $paths.SettingsPath
  if ($null -eq $settings) { $stateErrors += "Yang Mi settings do not exist: $($paths.SettingsPath)" }
} catch {
  $stateErrors += $_.Exception.Message
}
try {
  $session = Read-YangMiSkinSession -Path $paths.SessionPath
  if ($null -eq $session) { $stateErrors += "Yang Mi session does not exist: $($paths.SessionPath)" }
} catch {
  $stateErrors += $_.Exception.Message
}

$report = New-YangMiVerifyReport -Settings $settings -Session $session -DryRun:$WhatIf
$report.errors = @($stateErrors)
if ($null -ne $settings -and -not $settings.enabled) {
  $report.errors += 'Yang Mi settings are disabled.'
}
if ($null -ne $session -and $session.status -cne 'active') {
  $report.errors += "Yang Mi session is not active: $($session.status)"
}

$autostartErrors = @()
try {
  $taskPresence = Get-YangMiScheduledTaskPresence
  $report.autostart.scheduledTask.exists = $taskPresence.Exists
  $report.autostart.scheduledTask.state = $taskPresence.State
  if ($taskPresence.Exists) { $autostartErrors += 'Legacy Yang Mi scheduled-task autostart is still present.' }
} catch {
  $report.autostart.scheduledTask.state = 'unknown'
  $autostartErrors += $_.Exception.Message
}

$runKey = $null
try {
  $runKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:YangMiAutostartRunRegistrySubKey, $false)
  $runValue = Get-YangMiAutostartRunValue -RegistryKey $runKey
  $report.autostart.hkcuRun.exists = $null -ne $runValue
  $report.autostart.hkcuRun.state = if ($null -eq $runValue) { 'absent' } else { 'present' }
  if ($null -ne $runValue) { $autostartErrors += 'Legacy Yang Mi HKCU Run autostart is still present.' }
} catch {
  $report.autostart.hkcuRun.state = 'unknown'
  $autostartErrors += $_.Exception.Message
} finally {
  if ($null -ne $runKey) { $runKey.Dispose() }
}
$report.autostart.pass = $autostartErrors.Count -eq 0
$report.errors += $autostartErrors

if ($WhatIf) {
  Complete-YangMiVerifyReport -Report $report
}
if ($report.errors.Count -gt 0) {
  Complete-YangMiVerifyReport -Report $report
}

if (-not (Test-YangMiSessionWatcher -Session $session -WatcherPath $watcherPath -StateRoot $paths.StateRoot)) {
  $report.errors += 'Yang Mi watcher is absent or does not match the recorded full process identity.'
} else {
  $report.watcher.identity = 'verified'
}
if ($report.errors.Count -gt 0) {
  Complete-YangMiVerifyReport -Report $report
}

try {
  $node = Get-YangMiNodeRuntime -MinimumMajor 22
  if (-not (Test-DreamSkinPathEqual -Left $session.nodePath -Right $node.Path)) {
    throw 'Recorded Node runtime does not match the verified Node.js 22 runtime.'
  }
} catch {
  $report.errors += $_.Exception.Message
}
if ($report.errors.Count -gt 0) {
  Complete-YangMiVerifyReport -Report $report
}

if (-not (Test-DreamSkinPathEqual -Left $session.injectorPath -Right $injectorPath)) {
  $report.errors += 'Yang Mi injector path does not match this skin package.'
} else {
  $injectorProcess = Get-YangMiProcessInfo -ProcessId ([int]$session.injectorPid)
  $expectedInjectorArguments = @{ '--watch' = $null; '--theme' = $settings.themeId; '--port' = "$($session.port)"; '--browser-id' = $session.browserId }
  if ($null -eq $injectorProcess -or -not (Test-YangMiProcessIdentity -ProcessInfo $injectorProcess -RuntimeKind node `
    -ExpectedPid ([int]$session.injectorPid) -ExpectedStartedAt $session.injectorStartedAt -ExpectedExecutablePath $node.Path `
    -ScriptPath $injectorPath -RequiredArguments $expectedInjectorArguments)) {
    $report.errors += 'Yang Mi injector is absent or does not match the recorded full process identity.'
  } else {
    $report.injector.identity = 'verified'
  }
}
if ($report.errors.Count -gt 0) {
  Complete-YangMiVerifyReport -Report $report
}

try {
  $codex = Get-DreamSkinCodexInstall
  if (-not (Test-DreamSkinPathEqual -Left $session.codexExe -Right $codex.Executable) -or
    $session.codexPackageFullName -cne "$($codex.PackageFullName)" -or
    $session.codexPackageFamilyName -cne "$($codex.PackageFamilyName)") {
    throw 'Recorded Store Codex package identity does not match the installed package.'
  }
  $identity = Get-DreamSkinVerifiedCdpIdentity -Port ([int]$session.port) -Codex $codex
  if ($null -eq $identity -or $identity.BrowserId -cne $session.browserId) {
    throw 'Loopback CDP does not belong to the recorded Store Codex browser identity.'
  }
  $report.cdp.ownership = 'verified'
} catch {
  $report.errors += $_.Exception.Message
}
if ($report.errors.Count -gt 0) {
  Complete-YangMiVerifyReport -Report $report
}

try {
  $rendererOutput = @(& $node.Path $injectorPath --verify --theme $settings.themeId --port ([int]$session.port) --browser-id $session.browserId 2>&1)
  $report.renderer.exitCode = $LASTEXITCODE
  if ($LASTEXITCODE -ne 0) { throw "Node renderer verification exited with code $LASTEXITCODE." }
  $rendererJson = @($rendererOutput | ForEach-Object { "$_" } | Where-Object { $_ -match '^\{.*\}$' } | Select-Object -Last 1)
  if ($rendererJson.Count -ne 1) { throw 'Node renderer verification did not return a structured result.' }
  $report.renderer.nodeResult = $rendererJson[0] | ConvertFrom-Json -ErrorAction Stop
  if (-not $report.renderer.nodeResult.pass -or $report.renderer.nodeResult.theme -cne $settings.themeId) {
    throw 'Node renderer verification did not confirm the selected theme.'
  }
  $report.renderer.verification = 'passed'
} catch {
  $report.renderer.verification = 'failed'
  if ($null -eq $report.renderer.exitCode) { $report.renderer.exitCode = 1 }
  $report.errors += $_.Exception.Message
}

Complete-YangMiVerifyReport -Report $report
