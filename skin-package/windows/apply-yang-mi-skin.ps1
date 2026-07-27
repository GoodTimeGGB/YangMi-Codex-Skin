[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$ThemeId,
  [int]$Port = 9447,
  [switch]$RestartExisting,
  [switch]$DryRun,
  [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'YangMiCodexSkin')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$injector = Join-Path $root 'shared\injector.mjs'
$watcher = Join-Path $PSScriptRoot 'watch-yang-mi-skin.ps1'
. (Join-Path $PSScriptRoot 'common-yang-mi-skin.ps1')
$paths = Get-YangMiSkinPaths -StateRoot $StateRoot
$settings = New-YangMiSkinSettings -ThemeId $ThemeId -PreferredPort $Port -TakeoverWindowSeconds 8 -Enabled $true

function Enter-YangMiApplyOperationLock {
  param([ValidateRange(1, 30)][int]$WaitSeconds = 8)

  $deadline = (Get-Date).AddSeconds($WaitSeconds)
  do {
    try {
      return Enter-DreamSkinOperationLock
    } catch {
      $lockError = $_
      if ((Get-Date) -ge $deadline) { throw $lockError }
      Start-Sleep -Milliseconds 200
    }
  } while ($true)
}

function Stop-YangMiWatcherForApply {
  $session = Read-YangMiSkinSession -Path $paths.SessionPath
  if ($null -eq $session -or -not $session.watcherPid) { return }
  if (-not (Stop-YangMiSessionWatcher -Session $session -WatcherPath $watcher -StateRoot $paths.StateRoot)) {
    throw 'The recorded Yang Mi watcher identity did not match the live process. It was left untouched.'
  }
  $session.watcherPid = $null
  $session.watcherStartedAt = $null
  $session.watcherScriptPath = $null
  $session.powershellPath = $null
  Write-YangMiSkinSession -Path $paths.SessionPath -Session $session
}

if ($DryRun) {
  [pscustomobject][ordered]@{
    dryRun = $true
    themeId = $settings.themeId
    preferredPort = $settings.preferredPort
    takeoverWindowSeconds = $settings.takeoverWindowSeconds
    settingsPath = $paths.SettingsPath
    sessionPath = $paths.SessionPath
    injectorPath = $injector
    watcherPath = $watcher
  } | ConvertTo-Json -Compress
  return
}

function Get-YangMiSkinFileSnapshot {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    return [pscustomobject]@{ Path = $Path; Exists = $false; Bytes = $null }
  }
  return [pscustomobject]@{ Path = $Path; Exists = $true; Bytes = [System.IO.File]::ReadAllBytes($Path) }
}

function Get-YangMiSkinStateSnapshot {
  return [pscustomobject]@{
    Settings = Get-YangMiSkinFileSnapshot -Path $paths.SettingsPath
    Session = Get-YangMiSkinFileSnapshot -Path $paths.SessionPath
  }
}

function Restore-YangMiSkinFileSnapshot {
  param([Parameter(Mandatory = $true)][object]$Snapshot)
  if ($Snapshot.Exists) {
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $Snapshot.Path)) | Out-Null
    [System.IO.File]::WriteAllBytes($Snapshot.Path, [byte[]]$Snapshot.Bytes)
  } elseif (Test-Path -LiteralPath $Snapshot.Path) {
    Remove-Item -LiteralPath $Snapshot.Path -Force
  }
}

function Restore-YangMiSkinStateSnapshot {
  param([Parameter(Mandatory = $true)][object]$Snapshot)
  Restore-YangMiSkinFileSnapshot -Snapshot $Snapshot.Settings
  Restore-YangMiSkinFileSnapshot -Snapshot $Snapshot.Session
}

Stop-YangMiWatcherForApply
$mutex = Enter-YangMiApplyOperationLock
try {
  Assert-DreamSkinPort -Port $Port
  $node = Get-YangMiNodeRuntime -MinimumMajor 22
  $payloadCheck = @(& $node.Path $injector --theme $ThemeId --check-payload 2>&1)
  if ($LASTEXITCODE -ne 0) { throw ($payloadCheck -join "`n") }
  $existingSettings = Read-YangMiSkinSettings -Path $paths.SettingsPath
  if ($existingSettings) {
    $settings.takeoverWindowSeconds = $existingSettings.takeoverWindowSeconds
    $settings.updatedAt = [datetime]::UtcNow.ToString('o')
  }

  try { $session = Read-YangMiSkinSession -Path $paths.SessionPath } catch {
    $null = Archive-YangMiSkinFile -Path $paths.SessionPath -Kind 'invalid'
    $session = $null
  }
  if ($null -eq $session) { $session = New-YangMiSkinSession }
  $legacyCandidateNodePaths = @()
  if (Test-Path -LiteralPath $paths.LegacyStatePath) {
    try {
      $legacy = Read-DreamSkinState -Path $paths.LegacyStatePath
      if ($legacy -and $legacy.PSObject.Properties.Name -contains 'nodePath' -and $legacy.nodePath -is [string] -and $legacy.nodePath) {
        $legacyCandidateNodePaths += $legacy.nodePath
      }
      if ($legacy -and -not $session.injectorPid -and (Test-YangMiInjectorSessionIdentityComplete -Session $legacy)) {
        foreach ($mapping in @{
          injectorPid = 'injectorPid'; injectorStartedAt = 'injectorStartedAt'; injectorPath = 'injectorPath';
          nodePath = 'nodePath'; port = 'port'; browserId = 'browserId'; codexExe = 'codexExe';
          codexPackageRoot = 'codexPackageRoot'; codexPackageFullName = 'codexPackageFullName';
          codexPackageFamilyName = 'codexPackageFamilyName'; codexVersion = 'codexVersion'
        }.GetEnumerator()) {
          if ($legacy.PSObject.Properties.Name -contains $mapping.Value) { $session.($mapping.Key) = $legacy.($mapping.Value) }
        }
      } elseif ($legacy -and $legacy.PSObject.Properties.Name -contains 'injectorPid' -and $legacy.injectorPid) {
        Write-Warning 'Legacy Yang Mi injector state did not contain a complete immutable identity and was not adopted.'
      }
      $null = Archive-YangMiSkinFile -Path $paths.LegacyStatePath -Kind 'migrated'
    } catch {
      $null = Archive-YangMiSkinFile -Path $paths.LegacyStatePath -Kind 'invalid'
    }
  }

  $codex = Get-DreamSkinCodexInstall
  $identity = Get-DreamSkinVerifiedCdpIdentity -Port $Port -Codex $codex
  if ($null -eq $identity) {
    $running = @(Get-DreamSkinCodexProcesses -Codex $codex)
    if ($running.Count -gt 0) {
      if (-not $RestartExisting) { throw 'Codex is running without the local skin endpoint. Re-run with -RestartExisting after saving any draft.' }
      Stop-DreamSkinCodex -Codex $codex -AllowForce
    }
    if (-not (Test-DreamSkinPortAvailable -Port $Port)) { $Port = Select-DreamSkinPort -PreferredPort $Port }
    Start-DreamSkinCodex -Codex $codex -Arguments @('--remote-debugging-address=127.0.0.1', "--remote-debugging-port=$Port")
    $deadline = (Get-Date).AddSeconds(45)
    do { Start-Sleep -Milliseconds 350; $identity = Get-DreamSkinVerifiedCdpIdentity -Port $Port -Codex $codex } while ($null -eq $identity -and (Get-Date) -lt $deadline)
    if ($null -eq $identity) { throw "Codex did not expose a verified loopback endpoint on port $Port." }
  }

  if ($session.injectorPid) {
    $stopped = Stop-YangMiSessionInjectorAnyAllowedTheme -Session $session -ExpectedInjectorPath $injector
    if (-not $stopped) {
      $null = Archive-YangMiSkinFile -Path $paths.SessionPath -Kind 'identity-mismatch'
      throw 'The recorded injector identity did not match the live process. It was left untouched and the session was archived.'
    }
  }
  $candidateNodePaths = @($node.Path) + $legacyCandidateNodePaths
  if ($session.nodePath) { $candidateNodePaths += $session.nodePath }
  $exactInjectors = @(Find-YangMiExactInjectorsAcrossNodePaths -NodePaths $candidateNodePaths -InjectorPath $injector)
  if ($exactInjectors.Count -gt 0 -and -not (Stop-YangMiExactInjectors -ExactInjectors $exactInjectors -InjectorPath $injector)) {
    $remainingExactInjectors = @(Find-YangMiExactInjectorsAcrossNodePaths -NodePaths $candidateNodePaths -InjectorPath $injector)
    if ($remainingExactInjectors.Count -gt 0) {
      $null = Archive-YangMiSkinFile -Path $paths.SessionPath -Kind 'identity-mismatch'
      throw 'An exact Yang Mi injector could not be stopped. The session was archived and no replacement injector was started.'
    }
    Write-Warning 'A stale Yang Mi injector changed identity during replacement and was left untouched.'
  }
  $started = Start-YangMiInjector -NodePath $node.Path -InjectorPath $injector -ThemeId $ThemeId -Port $Port `
    -BrowserId $identity.BrowserId -StandardOutputPath $paths.InjectorLogPath -StandardErrorPath $paths.InjectorErrorLogPath
  $verificationDeadline = (Get-Date).AddSeconds(30)
  $verificationPassed = $false
  do {
    $verificationOutput = @(& $node.Path $injector --verify --theme $ThemeId --port $Port --browser-id $identity.BrowserId 2>&1)
    $verificationExitCode = $LASTEXITCODE
    if ($verificationExitCode -eq 0) {
      $verificationPassed = $true
      break
    }
    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $verificationDeadline -and -not $started.Process.HasExited)
  $verificationPending = -not $verificationPassed

  $session.generationId = [guid]::NewGuid().ToString('N')
  $session.status = 'active'
  $session.blockedReason = $null
  $session.injectorPid = $started.Process.Id
  $session.injectorStartedAt = $started.StartedAt
  $session.injectorPath = $injector
  $session.nodePath = $node.Path
  $session.port = $Port
  $session.browserId = $identity.BrowserId
  $session = Set-YangMiSkinSessionPackage -Session $session -Codex $codex

  $stateSnapshot = Get-YangMiSkinStateSnapshot
  $watcherProcess = $null
  try {
    # A live injector can complete its next watch cycle after the shell finishes loading.
    Write-YangMiSkinSettings -Path $paths.SettingsPath -Settings $settings
    if (-not (Test-YangMiSessionWatcher -Session $session -WatcherPath $watcher -StateRoot $paths.StateRoot)) {
      if ($session.watcherPid -and (Get-YangMiProcessInfo -ProcessId ([int]$session.watcherPid))) {
        $null = Archive-YangMiSkinFile -Path $paths.SessionPath -Kind 'watcher-identity-mismatch'
        throw 'The recorded watcher PID is live but its full identity does not match. It was left untouched.'
      }
      $powershellPath = (Get-Process -Id $PID -ErrorAction Stop).Path
      $watcherProcess = Start-YangMiWatcher -PowerShellPath $powershellPath -WatcherPath $watcher -StateRoot $paths.StateRoot `
        -StandardOutputPath $paths.WatcherLogPath -StandardErrorPath $paths.WatcherErrorLogPath
      $session.watcherPid = $watcherProcess.Process.Id
      $session.watcherStartedAt = $watcherProcess.StartedAt
      $session.watcherScriptPath = $watcher
      $session.powershellPath = $powershellPath
    }
    Write-YangMiSkinSession -Path $paths.SessionPath -Session $session
  } catch {
    $transactionError = $_
    $processInfo = Get-YangMiProcessInfo -ProcessId $started.Process.Id
    $null = Stop-YangMiRecordedProcess -ProcessInfo $processInfo -ExpectedPid $started.Process.Id -ExpectedStartedAt $started.StartedAt `
      -ExpectedExecutablePath $node.Path -ScriptPath $injector `
      -RuntimeKind node -RequiredArguments @{ '--watch' = $null; '--theme' = $ThemeId; '--port' = "$Port"; '--browser-id' = $identity.BrowserId }
    if ($null -ne $watcherProcess) {
      $watcherInfo = Get-YangMiProcessInfo -ProcessId $watcherProcess.Process.Id
      $null = Stop-YangMiRecordedProcess -ProcessInfo $watcherInfo -ExpectedPid $watcherProcess.Process.Id -ExpectedStartedAt $watcherProcess.StartedAt `
        -ExpectedExecutablePath $powershellPath -ScriptPath $watcher -RuntimeKind powershell `
        -RequiredArguments @{ '-File' = $watcher; '-StateRoot' = $paths.StateRoot }
    }
    Restore-YangMiSkinStateSnapshot -Snapshot $stateSnapshot
    try {
      $rolledBackSession = Read-YangMiSkinSession -Path $paths.SessionPath
      if ($null -eq $rolledBackSession) { $rolledBackSession = New-YangMiSkinSession }
      $rolledBackSession.status = 'error'
      $rolledBackSession.blockedReason = 'apply-transaction-rolled-back'
      $rolledBackSession.injectorPid = $null
      $rolledBackSession.injectorStartedAt = $null
      $rolledBackSession.injectorPath = $null
      $rolledBackSession.nodePath = $null
      $rolledBackSession.port = $null
      $rolledBackSession.browserId = $null
      if ($null -ne $watcherProcess) {
        $rolledBackSession.watcherPid = $null
        $rolledBackSession.watcherStartedAt = $null
        $rolledBackSession.watcherScriptPath = $null
        $rolledBackSession.powershellPath = $null
      }
      Write-YangMiSkinSession -Path $paths.SessionPath -Session $rolledBackSession
    } catch {}
    throw $transactionError
  }
  Write-Host "Yang Mi skin '$ThemeId' is active."
} finally { Exit-DreamSkinOperationLock -Mutex $mutex }
