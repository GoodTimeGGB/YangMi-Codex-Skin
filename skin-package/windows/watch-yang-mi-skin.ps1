[CmdletBinding()]
param(
  [switch]$WhatIf,
  [switch]$Once,
  [ValidateRange(100, 60000)][int]$PollMilliseconds = 1500,
  [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'YangMiCodexSkin')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$injectorPath = Join-Path $root 'shared\injector.mjs'
$watcherPath = $MyInvocation.MyCommand.Path
. (Join-Path $PSScriptRoot 'common-yang-mi-skin.ps1')

$paths = Get-YangMiSkinPaths -StateRoot $StateRoot
$settings = Read-YangMiSkinSettings -Path $paths.SettingsPath
if ($null -eq $settings) { throw "Yang Mi settings do not exist: $($paths.SettingsPath)" }

if ($WhatIf) {
  [pscustomobject][ordered]@{
    watcherReady = $true
    enabled = $settings.enabled
    themeId = $settings.themeId
    preferredPort = $settings.preferredPort
    takeoverWindowSeconds = $settings.takeoverWindowSeconds
    stateRoot = $paths.StateRoot
    settingsPath = $paths.SettingsPath
    sessionPath = $paths.SessionPath
    injectorPath = $injectorPath
    watcherPath = $watcherPath
  } | ConvertTo-Json -Compress
  return
}

function Get-YangMiWatcherSession {
  try {
    $session = Read-YangMiSkinSession -Path $paths.SessionPath
  } catch {
    $null = Archive-YangMiSkinFile -Path $paths.SessionPath -Kind 'invalid'
    $session = $null
  }
  if ($null -eq $session) { $session = New-YangMiSkinSession }
  $session.watcherPid = $PID
  $session.watcherStartedAt = (Get-Process -Id $PID -ErrorAction Stop).StartTime.ToUniversalTime().ToString('o')
  $session.watcherScriptPath = $watcherPath
  $session.powershellPath = (Get-Process -Id $PID -ErrorAction Stop).Path
  return $session
}

function Save-YangMiWatcherSession {
  param([Parameter(Mandatory = $true)][object]$Session)
  Write-YangMiSkinSession -Path $paths.SessionPath -Session $Session
}

function Clear-YangMiInjectorIdentity {
  param([Parameter(Mandatory = $true)][object]$Session)
  $Session.injectorPid = $null
  $Session.injectorStartedAt = $null
  $Session.injectorPath = $null
  $Session.nodePath = $null
  $Session.port = $null
  $Session.browserId = $null
  return $Session
}

function Get-YangMiVerifiedIdentity {
  param([object]$Codex, [object]$Session, [int]$PreferredPort)
  $ports = @($PreferredPort)
  if ($Session.port -and [int]$Session.port -ne $PreferredPort) { $ports += [int]$Session.port }
  foreach ($candidate in $ports | Select-Object -Unique) {
    $identity = Get-DreamSkinVerifiedCdpIdentity -Port $candidate -Codex $Codex
    if ($null -ne $identity) { return [pscustomobject]@{ Port = [int]$candidate; Identity = $identity } }
  }
  return $null
}

function Stop-YangMiInjectorForTransition {
  param([object]$Session, [string]$Status)
  if ($Session.injectorPid) {
    $stopped = Stop-YangMiSessionInjectorAnyAllowedTheme -Session $Session
    if (-not $stopped) {
      $null = Archive-YangMiSkinFile -Path $paths.SessionPath -Kind 'identity-mismatch'
      $Session = Get-YangMiWatcherSession
    }
  }
  $Session = Clear-YangMiInjectorIdentity -Session $Session
  return Set-YangMiSkinSessionStatus -Session $Session -Status $Status
}

function Ensure-YangMiInjector {
  param([object]$Session, [object]$Settings, [object]$Codex, [int]$Port, [object]$Identity)
  $node = Get-YangMiNodeRuntime -MinimumMajor 22
  $identityChanged = $Session.browserId -cne $Identity.BrowserId -or $Session.port -ne $Port -or
    -not (Test-DreamSkinPathEqual -Left $Session.nodePath -Right $node.Path)
  if ($Session.injectorPid -and ($identityChanged -or
    -not (Test-DreamSkinPathEqual -Left $Session.injectorPath -Right $injectorPath))) {
    $stopped = Stop-YangMiSessionInjectorAnyAllowedTheme -Session $Session
    if (-not $stopped) {
      $null = Archive-YangMiSkinFile -Path $paths.SessionPath -Kind 'identity-mismatch'
      $Session = Get-YangMiWatcherSession
    } else {
      $Session = Clear-YangMiInjectorIdentity -Session $Session
    }
  }

  $candidateNodePaths = @($node.Path)
  if ($Session.nodePath) { $candidateNodePaths += $Session.nodePath }
  $exactInjectors = @(Find-YangMiExactInjectorsAcrossNodePaths -NodePaths $candidateNodePaths -InjectorPath $injectorPath)
  $matching = @($exactInjectors | Where-Object {
    $_.ThemeId -ceq $Settings.themeId -and $_.Port -eq $Port -and $_.BrowserId -ceq $Identity.BrowserId
  } | Sort-Object { [int]$_.Process.ProcessId })
  $keeper = if ($matching.Count -gt 0) { $matching[0] } else { $null }

  $injectorsToStop = @()
  foreach ($otherTheme in $script:YangMiSkinThemeIds) {
    if ($otherTheme -ceq $Settings.themeId) { continue }
    $injectorsToStop += @($exactInjectors | Where-Object { $_.ThemeId -ceq $otherTheme })
  }

  $injectorsToStop += @($exactInjectors | Where-Object {
    $_.ThemeId -ceq $Settings.themeId -and ($_.Port -ne $Port -or $_.BrowserId -cne $Identity.BrowserId)
  })

  if ($matching.Count -gt 1) {
    $injectorsToStop += @($matching | Select-Object -Skip 1)
  }
  if ($injectorsToStop.Count -gt 0 -and -not (Stop-YangMiExactInjectors -ExactInjectors $injectorsToStop -InjectorPath $injectorPath)) {
    $null = Archive-YangMiSkinFile -Path $paths.SessionPath -Kind 'identity-mismatch'
    throw 'An exact Yang Mi injector changed identity before it could be stopped. The session was archived and no replacement injector was started.'
  }
  if ($null -eq $keeper) {
    $started = Start-YangMiInjector -NodePath $node.Path -InjectorPath $injectorPath -ThemeId $Settings.themeId `
      -Port $Port -BrowserId $Identity.BrowserId -StandardOutputPath $paths.InjectorLogPath -StandardErrorPath $paths.InjectorErrorLogPath
    $Session.injectorPid = $started.Process.Id
    $Session.injectorStartedAt = $started.StartedAt
  } else {
    $Session.injectorPid = [int]$keeper.Process.ProcessId
    $Session.injectorStartedAt = $keeper.StartedAt
  }
  $Session.injectorPath = $injectorPath
  $Session.nodePath = if ($keeper) { $keeper.NodePath } else { $node.Path }
  $Session.port = $Port
  $Session.browserId = $Identity.BrowserId
  if ($identityChanged) { $Session.generationId = [guid]::NewGuid().ToString('N') }
  $Session = Set-YangMiSkinSessionPackage -Session $Session -Codex $Codex
  $Session = Set-YangMiSkinSessionStatus -Session $Session -Status 'active'
  return $Session
}

function Reconcile-YangMiSkin {
  $settingsNow = Read-YangMiSkinSettings -Path $paths.SettingsPath
  if ($null -eq $settingsNow) { return $false }
  $session = Get-YangMiWatcherSession

  if (-not $settingsNow.enabled) {
    $session = Stop-YangMiInjectorForTransition -Session $session -Status 'disabled'
    $session.watcherPid = $null
    $session.watcherStartedAt = $null
    $session.watcherScriptPath = $null
    $session.powershellPath = $null
    Save-YangMiWatcherSession -Session $session
    return $false
  }

  try { $codex = Get-DreamSkinCodexInstall } catch {
    $session = Set-YangMiSkinSessionStatus -Session $session -Status 'blocked' -BlockedReason 'verified-codex-package-unavailable'
    Save-YangMiWatcherSession -Session $session
    return $true
  }
  $allCodexProcesses = @(Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" -ErrorAction SilentlyContinue)
  $codexProcesses = @(Get-DreamSkinCodexProcesses -Codex $codex)
  if ($codexProcesses.Count -eq 0) {
    $session = Set-YangMiSkinSessionStatus -Session $session -Status 'idle'
    $session = Stop-YangMiInjectorForTransition -Session $session -Status 'idle'
    $session.watcherPid = $null
    $session.watcherStartedAt = $null
    $session.watcherScriptPath = $null
    $session.powershellPath = $null
    Save-YangMiWatcherSession -Session $session
    return $false
  }
  if ($allCodexProcesses.Count -ne $codexProcesses.Count) {
    $session = Set-YangMiSkinSessionStatus -Session $session -Status 'blocked' -BlockedReason 'ambiguous-codex-executable-identity'
    Save-YangMiWatcherSession -Session $session
    return $true
  }

  $verified = Get-YangMiVerifiedIdentity -Codex $codex -Session $session -PreferredPort $settingsNow.preferredPort
  if ($null -ne $verified) {
    $session = Ensure-YangMiInjector -Session $session -Settings $settingsNow -Codex $codex -Port $verified.Port -Identity $verified.Identity
    Save-YangMiWatcherSession -Session $session
    return $true
  }

  $session = Set-YangMiSkinSessionStatus -Session $session -Status 'blocked' -BlockedReason 'verified-loopback-cdp-unavailable'
  Save-YangMiWatcherSession -Session $session
  return $true
}

$watcherMutex = Enter-YangMiWatcherMutex
if ($null -eq $watcherMutex) { return }
try {
  do {
    $keepWatching = $true
    $operationMutex = $null
    try {
      $operationMutex = Enter-DreamSkinOperationLock
    } catch {
      if ($Once) { throw }
    }
    if ($null -ne $operationMutex) {
      try {
        $keepWatching = Reconcile-YangMiSkin
      } catch {
        try {
          $failedSession = Get-YangMiWatcherSession
          $failedSession = Set-YangMiSkinSessionStatus -Session $failedSession -Status 'error' -BlockedReason $_.Exception.Message
          Save-YangMiWatcherSession -Session $failedSession
        } catch {}
        if ($Once) { throw }
      } finally {
        Exit-DreamSkinOperationLock -Mutex $operationMutex
      }
    }
    if (-not $keepWatching) { break }
    if (-not $Once) { Start-Sleep -Milliseconds $PollMilliseconds }
  } while (-not $Once)
} finally {
  Exit-YangMiWatcherMutex -Mutex $watcherMutex
}
