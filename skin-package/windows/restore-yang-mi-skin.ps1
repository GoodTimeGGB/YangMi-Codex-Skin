[CmdletBinding()]
param(
  [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'YangMiCodexSkin')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$injector = [System.IO.Path]::GetFullPath((Join-Path $root 'shared\injector.mjs'))
$uninstaller = Join-Path $PSScriptRoot 'uninstall-yang-mi-autostart.ps1'
. (Join-Path $PSScriptRoot 'common-yang-mi-skin.ps1')

function Set-YangMiRestoreSettingsDisabled {
  param([Parameter(Mandatory = $true)][object]$Paths)
  try {
    $settings = Read-YangMiSkinSettings -Path $Paths.SettingsPath
  } catch {
    $null = Archive-YangMiSkinFile -Path $Paths.SettingsPath -Kind 'invalid'
    throw 'The Yang Mi settings were invalid, so they were archived instead of being overwritten.'
  }
  if ($null -ne $settings) {
    $settings.enabled = $false
    Write-YangMiSkinSettings -Path $Paths.SettingsPath -Settings $settings
  }
}

function Test-YangMiRestoreSession {
  param([Parameter(Mandatory = $true)][object]$Session, [Parameter(Mandatory = $true)][string]$InjectorPath)
  return $Session.injectorPid -and $Session.injectorStartedAt -and $Session.injectorPath -and $Session.nodePath -and
    $Session.port -and $Session.browserId -and (Test-DreamSkinPathEqual -Left $Session.injectorPath -Right $InjectorPath)
}

function Test-YangMiRestoreHasInjectorIdentity {
  param([Parameter(Mandatory = $true)][object]$Session)
  return [bool]($Session.injectorPid -or $Session.injectorStartedAt -or $Session.injectorPath -or $Session.nodePath -or
    $Session.port -or $Session.browserId)
}

$mutex = Enter-DreamSkinOperationLock
try {
  $paths = Get-YangMiSkinPaths -StateRoot $StateRoot
  Set-YangMiRestoreSettingsDisabled -Paths $paths

  # Autostart cleanup is isolated so restore can remove the injected marker before ending a verified injector.
  & $uninstaller -AutostartOnly -StateRoot $paths.StateRoot
  if (-not $?) { throw 'The Yang Mi autostart registration could not be safely uninstalled.' }

  try {
    $session = Read-YangMiSkinSession -Path $paths.SessionPath
  } catch {
    $archive = Archive-YangMiSkinFile -Path $paths.SessionPath -Kind 'invalid'
    throw "The Yang Mi session was invalid and was preserved at: $archive"
  }

  if ($null -ne $session) {
    $hasInjectorIdentity = Test-YangMiRestoreHasInjectorIdentity -Session $session
    if ($hasInjectorIdentity -and -not (Test-YangMiRestoreSession -Session $session -InjectorPath $injector)) {
      $archive = Archive-YangMiSkinFile -Path $paths.SessionPath -Kind 'identity-mismatch'
      throw "The Yang Mi session cannot safely identify its injector and was preserved at: $archive"
    }

    $watcherStopped = Stop-YangMiSessionWatcher -Session $session -WatcherPath (Join-Path $PSScriptRoot 'watch-yang-mi-skin.ps1') -StateRoot $paths.StateRoot
    if (-not $watcherStopped) {
      $archive = Archive-YangMiSkinFile -Path $paths.SessionPath -Kind 'identity-mismatch'
      throw "The recorded watcher identity did not match a live process and was left untouched. Session preserved at: $archive"
    }

    if ($hasInjectorIdentity) {
      $node = Get-YangMiNodeRuntime -MinimumMajor 22
      if (-not (Test-DreamSkinPathEqual -Left $session.nodePath -Right $node.Path)) {
        $archive = Archive-YangMiSkinFile -Path $paths.SessionPath -Kind 'identity-mismatch'
        throw "The recorded injector runtime did not match the current Node runtime and was left untouched. Session preserved at: $archive"
      }
      & $node.Path $injector --remove --port ([int]$session.port) --browser-id $session.browserId
      if ($LASTEXITCODE -ne 0) { throw 'The verified Yang Mi marker could not be removed from the live Codex session.' }

      $injectorStopped = Stop-YangMiSessionInjectorAnyAllowedTheme -Session $session -ExpectedInjectorPath $injector
      if (-not $injectorStopped) {
        $archive = Archive-YangMiSkinFile -Path $paths.SessionPath -Kind 'identity-mismatch'
        throw "The recorded injector identity did not match a live process and was left untouched. Session preserved at: $archive"
      }
    }
  }

  if (Test-Path -LiteralPath $paths.SettingsPath) { Remove-Item -LiteralPath $paths.SettingsPath -Force }
  if (Test-Path -LiteralPath $paths.SessionPath) { Remove-Item -LiteralPath $paths.SessionPath -Force }
  Write-Host 'Yang Mi skin removed. Codex was left running.'
} finally {
  Exit-DreamSkinOperationLock -Mutex $mutex
}
