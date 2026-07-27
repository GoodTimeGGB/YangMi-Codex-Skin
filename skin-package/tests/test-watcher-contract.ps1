[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$commonPath = Join-Path $root 'windows\common-yang-mi-skin.ps1'
$watcherPath = Join-Path $root 'windows\watch-yang-mi-skin.ps1'
$applyPath = Join-Path $root 'windows\apply-yang-mi-skin.ps1'

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

function Assert-False {
  param([bool]$Condition, [string]$Message)
  if ($Condition) { throw $Message }
}

function Assert-Throws {
  param([scriptblock]$Operation, [string]$Message)
  try {
    & $Operation
  } catch {
    return
  }
  throw $Message
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
Assert-True (Test-Path -LiteralPath $watcherPath) 'The Yang Mi watcher is missing.'
. $commonPath

$syntheticNodeCandidates = @(
  [pscustomobject]@{ Path = 'C:\tools\node20\node.exe' },
  [pscustomobject]@{ Path = 'C:\Program Files\nodejs\node.exe' }
)
$syntheticNodeRuntime = Get-YangMiNodeRuntime -Candidates $syntheticNodeCandidates -VersionProbe {
  param([string]$Path)
  if ($Path -match 'node20') { return 'v20.19.0' }
  return 'v24.3.0'
}
Assert-True ($syntheticNodeRuntime.Path -ceq 'C:\Program Files\nodejs\node.exe' -and
  $syntheticNodeRuntime.Version -ceq '24.3.0' -and $syntheticNodeRuntime.Major -eq 24) 'The Yang Mi Node resolver must choose the verified Node 24 candidate over Node 20.'
Assert-Throws {
  Get-YangMiNodeRuntime -Candidates @([pscustomobject]@{ Path = 'C:\tools\node20\node.exe' }) -VersionProbe {
    param([string]$Path)
    return 'v20.19.0'
  }
} 'The Yang Mi Node resolver must reject a candidate set without Node.js 22 or newer.'
$actualNodeRuntime = Get-YangMiNodeRuntime
Assert-True ($actualNodeRuntime.Major -ge 22 -and $actualNodeRuntime.Path -and $actualNodeRuntime.Version) 'The Yang Mi Node resolver selected an invalid actual runtime.'

$now = [datetime]::UtcNow
$fresh = @(
  [pscustomobject]@{ ProcessId = 101; CreationDate = $now.AddSeconds(-2) },
  [pscustomobject]@{ ProcessId = 102; CreationDate = $now.AddSeconds(-2) }
)
$old = @(
  [pscustomobject]@{ ProcessId = 101; CreationDate = $now.AddSeconds(-2) },
  [pscustomobject]@{ ProcessId = 102; CreationDate = $now.AddSeconds(-9) }
)
Assert-True (Test-YangMiFreshLaunchGuard -Processes $fresh -Now $now -TakeoverWindowSeconds 8 -HasEstablishedSession:$false) 'All 2-second-old processes should be eligible for takeover.'
Assert-False (Test-YangMiFreshLaunchGuard -Processes $old -Now $now -TakeoverWindowSeconds 8 -HasEstablishedSession:$false) 'Any process older than the takeover window must block takeover.'
Assert-False (Test-YangMiFreshLaunchGuard -Processes $fresh -Now $now -TakeoverWindowSeconds 8 -HasEstablishedSession:$true) 'An established shell/session must block takeover.'
Assert-False (Test-YangMiFreshLaunchGuard -Processes @() -Now $now -TakeoverWindowSeconds 8 -HasEstablishedSession:$false) 'An empty process set must not trigger takeover.'
$activeSession = New-YangMiSkinSession -Status 'active'
$blockedDraftSession = New-YangMiSkinSession -Status 'blocked' -BlockedReason 'existing-session-may-contain-draft'
$ordinaryBlockedSession = New-YangMiSkinSession -Status 'blocked' -BlockedReason 'codex-launch-is-old-or-ambiguous'
$recoverySession = New-YangMiSkinSession -Status 'error' -BlockedReason 'recovery-relaunched-without-cdp'
Assert-True (Test-YangMiSessionProtectsDraft -Session $activeSession) 'An active session must protect a possible draft.'
Assert-True (Test-YangMiSessionProtectsDraft -Session $blockedDraftSession) 'Draft protection must persist across watcher polls.'
Assert-False (Test-YangMiSessionProtectsDraft -Session $ordinaryBlockedSession) 'An ordinary blocked launch must not masquerade as an established session.'
Assert-True (Test-YangMiSessionProtectsDraft -Session $recoverySession) 'A normal relaunch after CDP timeout must be protected from the next takeover poll.'
Assert-False (Test-YangMiFreshLaunchGuard -Processes $fresh -Now $now -TakeoverWindowSeconds 8 -HasEstablishedSession:(Test-YangMiSessionProtectsDraft -Session $recoverySession)) 'The protected normal recovery launch must not be eligible for takeover.'

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "yang-mi-watcher-test-$([guid]::NewGuid().ToString('N'))"
try {
  $paths = Get-YangMiSkinPaths -StateRoot $tempRoot
  $settings = New-YangMiSkinSettings -ThemeId 'floral-retro' -PreferredPort 9447 -TakeoverWindowSeconds 8 -Enabled $true
  Write-YangMiSkinSettings -Path $paths.SettingsPath -Settings $settings
  $roundTrip = Read-YangMiSkinSettings -Path $paths.SettingsPath
  Assert-True ($roundTrip.schemaVersion -eq 1) 'Settings schema did not round-trip.'
  Assert-True ($roundTrip.themeId -ceq 'floral-retro') 'Settings theme did not round-trip.'
  Assert-True ($roundTrip.preferredPort -eq 9447) 'Settings port did not round-trip.'
  $bytes = [System.IO.File]::ReadAllBytes($paths.SettingsPath)
  Assert-False ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) 'Settings must be strict UTF-8 without a BOM.'
  Assert-False ((Get-ChildItem -LiteralPath $tempRoot -Filter '*.tmp' -Force -ErrorAction SilentlyContinue).Count -gt 0) 'Atomic settings writes left a temporary file behind.'

  foreach ($invalid in @(
    [pscustomobject]@{ schemaVersion = 2; enabled = $true; themeId = 'floral-retro'; preferredPort = 9447; takeoverWindowSeconds = 8; updatedAt = $now.ToString('o') },
    [pscustomobject]@{ schemaVersion = 1; enabled = $true; themeId = 'unknown'; preferredPort = 9447; takeoverWindowSeconds = 8; updatedAt = $now.ToString('o') },
    [pscustomobject]@{ schemaVersion = 1; enabled = $true; themeId = 'floral-retro'; preferredPort = 80; takeoverWindowSeconds = 8; updatedAt = $now.ToString('o') },
    [pscustomobject]@{ schemaVersion = 1; enabled = 'true'; themeId = 'floral-retro'; preferredPort = 9447; takeoverWindowSeconds = 8; updatedAt = $now.ToString('o') },
    [pscustomobject]@{ schemaVersion = 1; enabled = $true; themeId = 'floral-retro'; preferredPort = 9447; takeoverWindowSeconds = 8; updatedAt = $now.ToString('o'); extra = 1 }
  )) {
    Assert-Throws { Assert-YangMiSkinSettings -Settings $invalid } 'Invalid settings were accepted.'
  }

  $session = New-YangMiSkinSession -Status 'active'
  $session.port = 9447
  $session.browserId = 'browser-1'
  Write-YangMiSkinSession -Path $paths.SessionPath -Session $session
  $sessionRoundTrip = Read-YangMiSkinSession -Path $paths.SessionPath
  Assert-True ($sessionRoundTrip.generationId -ceq $session.generationId) 'Session generation did not round-trip.'
  Assert-True ($sessionRoundTrip.status -ceq 'active') 'Session status did not round-trip.'
  Assert-True ($sessionRoundTrip.browserId -ceq 'browser-1') 'Session browser identity did not round-trip.'
  $sessionBytes = [System.IO.File]::ReadAllBytes($paths.SessionPath)
  Assert-False ($sessionBytes.Length -ge 3 -and $sessionBytes[0] -eq 0xEF -and $sessionBytes[1] -eq 0xBB -and $sessionBytes[2] -eq 0xBF) 'Session must be strict UTF-8 without a BOM.'
  Assert-False ((Get-ChildItem -LiteralPath $tempRoot -Filter '*.tmp' -Force -ErrorAction SilentlyContinue).Count -gt 0) 'Atomic session writes left a temporary file behind.'
  $invalidSession = New-YangMiSkinSession
  $invalidSession.schemaVersion = 2
  Assert-Throws { Assert-YangMiSkinSession -Session $invalidSession } 'Unsupported session schema was accepted.'
  $invalidSession = New-YangMiSkinSession
  $invalidSession | Add-Member -NotePropertyName extra -NotePropertyValue 1
  Assert-Throws { Assert-YangMiSkinSession -Session $invalidSession } 'Session with an extra property was accepted.'
  $invalidSessionPath = Join-Path $tempRoot 'invalid-session.json'
  Write-DreamSkinUtf8FileAtomically -Path $invalidSessionPath -Content "{`"schemaVersion`":1}`r`n"
  Assert-Throws { Read-YangMiSkinSession -Path $invalidSessionPath } 'Incomplete session JSON was accepted.'

  $scriptToken = Join-Path $root 'shared\injector.mjs'
  $nodePath = 'C:\Program Files\nodejs\node.exe'
  $startedAt = $now.AddSeconds(-3).ToString('o')
  $record = [pscustomobject]@{
    ProcessId = 777
    ExecutablePath = $nodePath
    CommandLine = "`"$nodePath`" `"$scriptToken`" --watch --theme floral-retro --port 9447 --browser-id browser-1"
    StartedAt = $startedAt
  }
  Assert-True (Test-YangMiProcessIdentity -ProcessInfo $record -RuntimeKind node -ExpectedPid 777 -ExpectedStartedAt $startedAt -ExpectedExecutablePath $nodePath -ScriptPath $scriptToken -RequiredArguments @{ '--watch' = $null; '--theme' = 'floral-retro'; '--port' = '9447'; '--browser-id' = 'browser-1' }) 'Exact synthetic injector identity should match.'
  Assert-False (Test-YangMiProcessIdentity -ProcessInfo $record -RuntimeKind node -ExpectedPid 777 -ExpectedStartedAt $startedAt -ExpectedExecutablePath $nodePath -ScriptPath $scriptToken -RequiredArguments @{ '--watch' = $null; '--theme' = 'noir-silver'; '--port' = '9447'; '--browser-id' = 'browser-1' }) 'A mismatched theme argument must fail identity validation.'
  Assert-False (Test-YangMiProcessIdentity -ProcessInfo $record -RuntimeKind node -ExpectedPid 778 -ExpectedStartedAt $startedAt -ExpectedExecutablePath $nodePath -ScriptPath $scriptToken -RequiredArguments @{ '--watch' = $null }) 'A mismatched PID must fail identity validation.'
  $duplicateThemeRecord = $record.PSObject.Copy()
  $duplicateThemeRecord.CommandLine = "`"$nodePath`" `"$scriptToken`" --watch --theme floral-retro --theme noir-silver --port 9447 --browser-id browser-1"
  Assert-False (Test-YangMiProcessIdentity -ProcessInfo $duplicateThemeRecord -RuntimeKind node -ExpectedPid 777 -ExpectedStartedAt $startedAt -ExpectedExecutablePath $nodePath -ScriptPath $scriptToken -RequiredArguments @{ '--watch' = $null; '--theme' = 'floral-retro'; '--port' = '9447'; '--browser-id' = 'browser-1' }) 'A duplicate overriding theme argument must fail identity validation.'
  $duplicatePortRecord = $record.PSObject.Copy()
  $duplicatePortRecord.CommandLine = "`"$nodePath`" `"$scriptToken`" --watch --theme floral-retro --port 9447 --port 9555 --browser-id browser-1"
  Assert-False (Test-YangMiProcessIdentity -ProcessInfo $duplicatePortRecord -RuntimeKind node -ExpectedPid 777 -ExpectedStartedAt $startedAt -ExpectedExecutablePath $nodePath -ScriptPath $scriptToken -RequiredArguments @{ '--watch' = $null; '--theme' = 'floral-retro'; '--port' = '9447'; '--browser-id' = 'browser-1' }) 'A duplicate overriding port argument must fail identity validation.'
  $alternateModeRecord = $record.PSObject.Copy()
  $alternateModeRecord.CommandLine = "`"$nodePath`" `"$scriptToken`" --watch --remove --theme floral-retro --port 9447 --browser-id browser-1"
  Assert-False (Test-YangMiProcessIdentity -ProcessInfo $alternateModeRecord -RuntimeKind node -ExpectedPid 777 -ExpectedStartedAt $startedAt -ExpectedExecutablePath $nodePath -ScriptPath $scriptToken -RequiredArguments @{ '--watch' = $null; '--theme' = 'floral-retro'; '--port' = '9447'; '--browser-id' = 'browser-1' }) 'An alternate overriding injector mode must fail identity validation.'
  $missingBrowserRecord = $record.PSObject.Copy()
  $missingBrowserRecord.CommandLine = "`"$nodePath`" `"$scriptToken`" --watch --theme floral-retro --port 9447"
  Assert-False (Test-YangMiProcessIdentity -ProcessInfo $missingBrowserRecord -RuntimeKind node -ExpectedPid 777 -ExpectedStartedAt $startedAt -ExpectedExecutablePath $nodePath -ScriptPath $scriptToken -RequiredArguments @{ '--watch' = $null; '--theme' = 'floral-retro'; '--port' = '9447'; '--browser-id' = 'browser-1' }) 'A missing controlled argument must fail identity validation.'
  Assert-False (Test-YangMiProcessIdentity -ProcessInfo $record -RuntimeKind node -ExpectedPid 777 -ExpectedStartedAt $startedAt -ExpectedExecutablePath $nodePath -ScriptPath $scriptToken -RequiredArguments @{ '--watch' = $null }) 'Unaccounted controlled injector arguments must fail identity validation.'
  $unknownInjectorFlag = $record.PSObject.Copy()
  $unknownInjectorFlag.CommandLine = "`"$nodePath`" `"$scriptToken`" --watch --theme floral-retro --port 9447 --browser-id browser-1 --diagnostic"
  Assert-False (Test-YangMiProcessIdentity -ProcessInfo $unknownInjectorFlag -RuntimeKind node -ExpectedPid 777 -ExpectedStartedAt $startedAt -ExpectedExecutablePath $nodePath -ScriptPath $scriptToken -RequiredArguments @{ '--watch' = $null; '--theme' = 'floral-retro'; '--port' = '9447'; '--browser-id' = 'browser-1' }) 'An extra unknown injector flag must fail exact identity validation.'
  $extraInjectorPositional = $record.PSObject.Copy()
  $extraInjectorPositional.CommandLine = "`"$nodePath`" `"$scriptToken`" --watch --theme floral-retro --port 9447 --browser-id browser-1 C:\Temp\unexpected"
  Assert-False (Test-YangMiProcessIdentity -ProcessInfo $extraInjectorPositional -RuntimeKind node -ExpectedPid 777 -ExpectedStartedAt $startedAt -ExpectedExecutablePath $nodePath -ScriptPath $scriptToken -RequiredArguments @{ '--watch' = $null; '--theme' = 'floral-retro'; '--port' = '9447'; '--browser-id' = 'browser-1' }) 'An extra injector positional argument must fail exact identity validation.'
  $nodeRuntimeFlag = $record.PSObject.Copy()
  $nodeRuntimeFlag.CommandLine = "`"$nodePath`" --trace-warnings `"$scriptToken`" --watch --theme floral-retro --port 9447 --browser-id browser-1"
  Assert-False (Test-YangMiProcessIdentity -ProcessInfo $nodeRuntimeFlag -RuntimeKind node -ExpectedPid 777 -ExpectedStartedAt $startedAt -ExpectedExecutablePath $nodePath -ScriptPath $scriptToken -RequiredArguments @{ '--watch' = $null; '--theme' = 'floral-retro'; '--port' = '9447'; '--browser-id' = 'browser-1' }) 'A Node runtime flag must fail exact injector identity validation.'
  $extraInjectorMode = $record.PSObject.Copy()
  $extraInjectorMode.CommandLine = "`"$nodePath`" `"$scriptToken`" --watch --once --theme floral-retro --port 9447 --browser-id browser-1"
  Assert-False (Test-YangMiProcessIdentity -ProcessInfo $extraInjectorMode -RuntimeKind node -ExpectedPid 777 -ExpectedStartedAt $startedAt -ExpectedExecutablePath $nodePath -ScriptPath $scriptToken -RequiredArguments @{ '--watch' = $null; '--theme' = 'floral-retro'; '--port' = '9447'; '--browser-id' = 'browser-1' }) 'An extra injector mode must fail exact identity validation.'
  Assert-Throws { Test-YangMiProcessIdentity -ProcessInfo $record -ExpectedPid 777 -ExpectedStartedAt $startedAt -ExpectedExecutablePath $nodePath -ScriptPath $scriptToken -RequiredArguments @{ '--watch' = $null } } 'RuntimeKind must be explicit for process identity validation.'
  Assert-Throws { Stop-YangMiRecordedProcess -ProcessInfo $record -ExpectedPid 799 -ExpectedStartedAt $startedAt -ExpectedExecutablePath $nodePath -ScriptPath $scriptToken -RequiredArguments @{ '--watch' = $null } } 'RuntimeKind must be explicit for recorded-process termination.'

  Assert-True (Test-YangMiProcessIdentity -ProcessInfo $record -RuntimeKind node -ExpectedPid 777 -ExpectedStartedAt $startedAt -ExpectedExecutablePath $nodePath -ScriptPath $scriptToken -RequiredArguments @{ '--watch' = $null; '--theme' = 'floral-retro'; '--port' = '9447'; '--browser-id' = 'browser-1' }) 'Node identity must require injector.mjs as the positional script argument.'
  $nodePositionalSpoof = $record.PSObject.Copy()
  $nodePositionalSpoof.CommandLine = "`"$nodePath`" --inspect `"$scriptToken`" --watch --theme floral-retro --port 9447 --browser-id browser-1"
  Assert-False (Test-YangMiProcessIdentity -ProcessInfo $nodePositionalSpoof -RuntimeKind node -ExpectedPid 777 -ExpectedStartedAt $startedAt -ExpectedExecutablePath $nodePath -ScriptPath $scriptToken -RequiredArguments @{ '--watch' = $null; '--theme' = 'floral-retro'; '--port' = '9447'; '--browser-id' = 'browser-1' }) 'Injector script supplied as a non-positional Node argument must be rejected.'
  $nodeDuplicateScript = $record.PSObject.Copy()
  $nodeDuplicateScript.CommandLine = "`"$nodePath`" `"$scriptToken`" --watch --theme floral-retro --port 9447 --browser-id browser-1 `"$scriptToken`""
  Assert-False (Test-YangMiProcessIdentity -ProcessInfo $nodeDuplicateScript -RuntimeKind node -ExpectedPid 777 -ExpectedStartedAt $startedAt -ExpectedExecutablePath $nodePath -ScriptPath $scriptToken -RequiredArguments @{ '--watch' = $null; '--theme' = 'floral-retro'; '--port' = '9447'; '--browser-id' = 'browser-1' }) 'Duplicate injector script arguments must be rejected.'
  $nodeMalformedQuote = $record.PSObject.Copy()
  $nodeMalformedQuote.CommandLine = "`"$nodePath`" `"$scriptToken --watch --theme floral-retro --port 9447 --browser-id browser-1"
  Assert-False (Test-YangMiProcessIdentity -ProcessInfo $nodeMalformedQuote -RuntimeKind node -ExpectedPid 777 -ExpectedStartedAt $startedAt -ExpectedExecutablePath $nodePath -ScriptPath $scriptToken -RequiredArguments @{ '--watch' = $null; '--theme' = 'floral-retro'; '--port' = '9447'; '--browser-id' = 'browser-1' }) 'Malformed quoted Node command lines must be rejected.'

  $powershellPath = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
  $watcherStartedAt = $now.AddSeconds(-2).ToString('o')
  $watcherRecord = [pscustomobject]@{
    ProcessId = 779
    ExecutablePath = $powershellPath
    CommandLine = "`"$powershellPath`" -NoProfile -File `"$watcherPath`" -StateRoot C:\Temp\yang-mi"
    StartedAt = $watcherStartedAt
  }
  Assert-True (Test-YangMiProcessIdentity -ProcessInfo $watcherRecord -RuntimeKind powershell -ExpectedPid 779 -ExpectedStartedAt $watcherStartedAt -ExpectedExecutablePath $powershellPath -ScriptPath $watcherPath -RequiredArguments @{ '-File' = $watcherPath; '-StateRoot' = 'C:\Temp\yang-mi' }) 'Watcher identity must require the script immediately after a unique -File.'
  $watcherPositionalSpoof = $watcherRecord.PSObject.Copy()
  $watcherPositionalSpoof.CommandLine = "`"$powershellPath`" `"$watcherPath`" -File C:\Temp\other.ps1 -StateRoot C:\Temp\yang-mi"
  Assert-False (Test-YangMiProcessIdentity -ProcessInfo $watcherPositionalSpoof -RuntimeKind powershell -ExpectedPid 779 -ExpectedStartedAt $watcherStartedAt -ExpectedExecutablePath $powershellPath -ScriptPath $watcherPath -RequiredArguments @{ '-File' = $watcherPath; '-StateRoot' = 'C:\Temp\yang-mi' }) 'Watcher script outside the unique -File position must be rejected.'
  $watcherDuplicateScript = $watcherRecord.PSObject.Copy()
  $watcherDuplicateScript.CommandLine = "`"$powershellPath`" -File `"$watcherPath`" -StateRoot C:\Temp\yang-mi `"$watcherPath`""
  Assert-False (Test-YangMiProcessIdentity -ProcessInfo $watcherDuplicateScript -RuntimeKind powershell -ExpectedPid 779 -ExpectedStartedAt $watcherStartedAt -ExpectedExecutablePath $powershellPath -ScriptPath $watcherPath -RequiredArguments @{ '-File' = $watcherPath; '-StateRoot' = 'C:\Temp\yang-mi' }) 'Duplicate watcher script arguments must be rejected.'
  $watcherMalformedQuote = $watcherRecord.PSObject.Copy()
  $watcherMalformedQuote.CommandLine = "`"$powershellPath`" -File `"$watcherPath -StateRoot C:\Temp\yang-mi"
  Assert-False (Test-YangMiProcessIdentity -ProcessInfo $watcherMalformedQuote -RuntimeKind powershell -ExpectedPid 779 -ExpectedStartedAt $watcherStartedAt -ExpectedExecutablePath $powershellPath -ScriptPath $watcherPath -RequiredArguments @{ '-File' = $watcherPath; '-StateRoot' = 'C:\Temp\yang-mi' }) 'Malformed quoted watcher command lines must be rejected.'

  $oldBrowserRecord = [pscustomobject]@{
    ProcessId = 778
    ExecutablePath = $nodePath
    CommandLine = "`"$nodePath`" `"$scriptToken`" --watch --theme noir-silver --port 9555 --browser-id browser-old"
    StartedAt = $now.AddSeconds(-4).ToString('o')
  }
  $exactInjectors = @(Find-YangMiExactInjectors -Processes @($record, $oldBrowserRecord, $duplicatePortRecord) -NodePath $nodePath -InjectorPath $scriptToken)
  Assert-True ($exactInjectors.Count -eq 2) 'Exact injector discovery must include current and old browser/port identities while rejecting duplicates.'
  Assert-True (@($exactInjectors | Where-Object { $_.BrowserId -ceq 'browser-old' -and $_.Port -eq 9555 -and $_.ThemeId -ceq 'noir-silver' }).Count -eq 1) 'Cross-browser injector discovery lost the old exact identity.'

  $recordedExactInjectorStops = @()
  function Stop-YangMiRecordedProcess {
    param([object]$ProcessInfo, [int]$ExpectedPid)
    $script:recordedExactInjectorStops += $ExpectedPid
    return $true
  }
  Assert-True (Stop-YangMiExactInjectors -ExactInjectors @($exactInjectors[0]) -InjectorPath $scriptToken) 'Exact injector cleanup must invoke the validated stop path for a synthetic injector.'
  Assert-True ($recordedExactInjectorStops.Count -eq 1 -and $recordedExactInjectorStops[0] -eq 777) 'Exact injector cleanup must forward the synthetic process ID without assigning PowerShell automatic $PID.'

  $oldNvmNodePath = 'C:\Users\Test\.nvm\v20.18.0\node.exe'
  $currentNodePath = 'C:\Program Files\nodejs\node.exe'
  Assert-False (Test-Path -LiteralPath $paths.LegacyStatePath) 'Cross-runtime injector discovery must not depend on a legacy state file.'
  $legacyInjectorRecord = [pscustomobject]@{
    ProcessId = 780
    ExecutablePath = $oldNvmNodePath
    CommandLine = "`"$oldNvmNodePath`" `"$scriptToken`" --watch --theme bridal-moonlight --port 9666 --browser-id browser-legacy"
    StartedAt = $now.AddSeconds(-5).ToString('o')
  }
  $currentInjectorRecord = [pscustomobject]@{
    ProcessId = 781
    ExecutablePath = $currentNodePath
    CommandLine = "`"$currentNodePath`" `"$scriptToken`" --watch --theme floral-retro --port 9447 --browser-id browser-current"
    StartedAt = $now.AddSeconds(-1).ToString('o')
  }
  $candidateNodePaths = @(Get-YangMiInjectorCandidateNodePaths -Processes @($legacyInjectorRecord, $currentInjectorRecord) -NodePaths @($currentNodePath))
  Assert-True ($candidateNodePaths.Count -eq 2 -and $candidateNodePaths -contains $oldNvmNodePath -and $candidateNodePaths -contains $currentNodePath) 'Injector candidate discovery must retain a live legacy NVM Node path alongside the selected runtime.'
  $allCandidateInjectors = @(Find-YangMiExactInjectorsAcrossNodePaths -Processes @($legacyInjectorRecord, $currentInjectorRecord) -NodePaths @($currentNodePath) -InjectorPath $scriptToken)
  Assert-True ($allCandidateInjectors.Count -eq 2) 'Cross-runtime injector discovery must find both legacy and current exact injectors.'
  Assert-True (@($allCandidateInjectors | Where-Object { $_.NodePath -ceq $oldNvmNodePath -and $_.BrowserId -ceq 'browser-legacy' }).Count -eq 1) 'Cross-runtime injector discovery lost the legacy NVM injector identity.'

  $injectorBefore = @(Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue | Where-Object {
    "$($_.CommandLine)" -match [regex]::Escape($scriptToken)
  } | Select-Object -ExpandProperty ProcessId)
  $settingsBeforeWhatIf = Get-TestFileSnapshot -Path $paths.SettingsPath
  $sessionBeforeWhatIf = Get-TestFileSnapshot -Path $paths.SessionPath
  $whatIfJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $watcherPath -WhatIf -Once -StateRoot $tempRoot
  if ($LASTEXITCODE -ne 0) { throw 'Watcher -WhatIf failed.' }
  $whatIf = $whatIfJson | ConvertFrom-Json
  Assert-True ([bool]$whatIf.watcherReady) 'Watcher -WhatIf did not report watcher readiness.'
  Assert-True ($whatIf.themeId -ceq 'floral-retro') 'Watcher -WhatIf selected the wrong theme.'
  Assert-True ($whatIf.preferredPort -eq 9447) 'Watcher -WhatIf selected the wrong port.'
  Assert-True ($whatIf.takeoverWindowSeconds -eq 8) 'Watcher -WhatIf selected the wrong takeover window.'
  Assert-True ($whatIf.settingsPath -ceq $paths.SettingsPath) 'Watcher -WhatIf reported the wrong settings path.'
  Assert-TestFileSnapshotEqual $settingsBeforeWhatIf (Get-TestFileSnapshot -Path $paths.SettingsPath) 'Watcher -WhatIf changed settings state.'
  Assert-TestFileSnapshotEqual $sessionBeforeWhatIf (Get-TestFileSnapshot -Path $paths.SessionPath) 'Watcher -WhatIf changed session state.'
  $injectorAfterWhatIf = @(Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue | Where-Object {
    "$($_.CommandLine)" -match [regex]::Escape($scriptToken)
  } | Select-Object -ExpandProperty ProcessId)
  Assert-True ((Compare-Object $injectorBefore $injectorAfterWhatIf).Count -eq 0) 'Watcher -WhatIf started or stopped a Yang Mi injector.'

  $settingsBeforeDryRun = Get-TestFileSnapshot -Path $paths.SettingsPath
  $sessionBeforeDryRun = Get-TestFileSnapshot -Path $paths.SessionPath
  $dryRunJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $applyPath -ThemeId 'noir-silver' -DryRun -StateRoot $tempRoot
  if ($LASTEXITCODE -ne 0) { throw 'Apply -DryRun failed.' }
  $dryRun = $dryRunJson | ConvertFrom-Json
  Assert-True ([bool]$dryRun.dryRun -and $dryRun.themeId -ceq 'noir-silver') 'Apply -DryRun output is invalid.'
  Assert-TestFileSnapshotEqual $settingsBeforeDryRun (Get-TestFileSnapshot -Path $paths.SettingsPath) 'Apply -DryRun changed settings state.'
  Assert-TestFileSnapshotEqual $sessionBeforeDryRun (Get-TestFileSnapshot -Path $paths.SessionPath) 'Apply -DryRun changed session state.'
  $injectorAfterDryRun = @(Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue | Where-Object {
    "$($_.CommandLine)" -match [regex]::Escape($scriptToken)
  } | Select-Object -ExpandProperty ProcessId)
  Assert-True ((Compare-Object $injectorBefore $injectorAfterDryRun).Count -eq 0) 'Apply -DryRun started or stopped a Yang Mi injector.'
} finally {
  if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

$commonText = [System.IO.File]::ReadAllText($commonPath)
$watcherText = [System.IO.File]::ReadAllText($watcherPath)
$applyText = [System.IO.File]::ReadAllText($applyPath)
Assert-True ($applyText -match 'Get-YangMiNodeRuntime\s+-MinimumMajor\s+22') 'Manual apply must require Node.js 22 or newer.'
Assert-False (($commonText + $watcherText + $applyText) -match 'Get-DreamSkinNodeRuntime\s+-MinimumMajor\s+22') 'Yang Mi execution paths must not use the PATH-only Node resolver.'
Assert-True (($applyText + $watcherText) -match '--remote-debugging-address=127\.0\.0\.1') 'Loopback CDP address argument is missing.'
Assert-True (($applyText + $watcherText) -match '--remote-debugging-port') 'CDP port argument is missing.'
Assert-False (($commonText + $watcherText + $applyText) -match 'Stop-Process\s+-Id\s+\(\[int\]\)\$[^\r\n]*\.(?:injectorPid|watcherPid)') 'Raw Stop-Process against a recorded state PID is forbidden.'
Assert-True ($watcherText -match 'function\s+Stop-YangMiInjectorForTransition[\s\S]*Archive-YangMiSkinFile[\s\S]*identity-mismatch') 'Idle and disabled transitions must archive mismatched injector state.'
Assert-True ($watcherText -match 'foreach\s*\(\s*\$otherTheme\s+in\s+\$script:YangMiSkinThemeIds\s*\)') 'Watcher must reconcile exact injectors from the previous allowed theme.'
Assert-True ($watcherText -match 'Find-YangMiExactInjectorsAcrossNodePaths[\s\S]*BrowserId[\s\S]*Port[\s\S]*Stop-YangMiExactInjectors') 'Watcher must reconcile exact injectors across old browser IDs and ports.'
Assert-True (($applyText + $watcherText) -match 'Find-YangMiExactInjectorsAcrossNodePaths') 'Apply and watcher must discover exact injectors across all candidate Node paths.'
Assert-True ($commonText -match 'function\s+Stop-YangMiExactInjectors[\s\S]*Stop-YangMiRecordedProcess') 'Exact injector cleanup must terminate only through full live identity validation.'
Assert-False ($commonText -match 'function\s+Stop-YangMiExactInjectors[\s\S]*Stop-Process\s+-Id') 'Exact injector cleanup must not raw-stop a discovered Node PID.'
Assert-True ($applyText -match '-not\s+\$session\.injectorPid\s+-and\s+\(Test-YangMiInjectorSessionIdentityComplete\s+-Session\s+\$legacy\)') 'Legacy state without a complete immutable injector identity must not be adopted as a session PID.'
Assert-True ($applyText -match 'if\s*\(\$session\.injectorPid\)[\s\S]*Stop-YangMiSessionInjectorAnyAllowedTheme') 'Apply must validate a recorded legacy injector against every allowed theme before replacement cleanup.'
$applyPreStartDiscoveryIndex = $applyText.IndexOf('Find-YangMiExactInjectorsAcrossNodePaths')
$applyStartIndex = $applyText.IndexOf('Start-YangMiInjector')
Assert-True ($applyPreStartDiscoveryIndex -ge 0 -and $applyPreStartDiscoveryIndex -lt $applyStartIndex) 'Apply must remove exact legacy injectors across candidate Node paths before starting a replacement.'
$watcherTokens = $null
$watcherParseErrors = $null
$watcherAst = [System.Management.Automation.Language.Parser]::ParseFile($watcherPath, [ref]$watcherTokens, [ref]$watcherParseErrors)
Assert-True ($watcherParseErrors.Count -eq 0) 'Watcher source did not parse for AST contract checks.'
$ensureInjectorFunction = $watcherAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Ensure-YangMiInjector' }, $true)
Assert-True ($null -ne $ensureInjectorFunction) 'Watcher must define injector reconciliation.'
$ensureInjectorText = $ensureInjectorFunction.Extent.Text
$nodeTransitionPredicate = '-not (Test-DreamSkinPathEqual -Left $Session.nodePath -Right $node.Path)'
$nodeTransitionPredicateIndex = $ensureInjectorText.IndexOf($nodeTransitionPredicate)
$nodeTransitionStopIndex = $ensureInjectorText.IndexOf('Stop-YangMiSessionInjectorAnyAllowedTheme')
$nodeTransitionClearIndex = $ensureInjectorText.IndexOf('Clear-YangMiInjectorIdentity')
$nodeTransitionDiscoveryIndex = $ensureInjectorText.IndexOf('Find-YangMiExactInjectors')
Assert-True ($nodeTransitionPredicateIndex -ge 0 -and $ensureInjectorText.IndexOf('$identityChanged =') -lt $nodeTransitionPredicateIndex) 'Injector reconciliation must treat a recorded Node path change as an identity change.'
Assert-True ($nodeTransitionStopIndex -gt $nodeTransitionPredicateIndex -and $nodeTransitionClearIndex -gt $nodeTransitionStopIndex -and
  $nodeTransitionDiscoveryIndex -gt $nodeTransitionClearIndex) 'A recorded injector on a different Node path must be stopped and cleared before current-runtime discovery can retain or spawn another injector.'
foreach ($forbidden in @(
  'Stop-YangMiFreshCodexSnapshot',
  'Stop-YangMiCapturedCodexSnapshot',
  'Wait-YangMiLaunchedCodexSnapshot',
  'Start-DreamSkinCodex'
)) {
  Assert-False ($watcherText -match [regex]::Escape($forbidden)) "Watcher must not contain Codex takeover path: $forbidden"
}
Assert-False ($watcherText -match 'Stop-Process') 'Watcher must not terminate Codex or any other process directly.'
Assert-True ($watcherText -match 'if\s*\(\s*\$codexProcesses\.Count\s+-eq\s+0\s*\)\s*\{[\s\S]*?Set-YangMiSkinSessionStatus[\s\S]*?idle[\s\S]*?return\s+\$false') 'Watcher must become idle and end its current session when Codex is absent.'
Assert-True ($watcherText -match '\$keepWatching\s*=\s*Reconcile-YangMiSkin[\s\S]*if\s*\(\s*-not\s+\$keepWatching\s*\)\s*\{\s*break\s*\}') 'Watcher loop must stop after the current Codex session ends.'
Assert-False ($watcherText -match 'if\s*\(\s*\$codexProcesses\.Count\s+-eq\s+0\s*\)\s*\{[^}]*(?:Start-DreamSkinCodex|Start-Process)') 'Watcher must not launch Codex when the user has closed it.'
$verificationIndex = $applyText.IndexOf('& $node.Path $injector --verify')
$settingsWriteIndex = $applyText.IndexOf('Write-YangMiSkinSettings')
Assert-True ($verificationIndex -ge 0 -and $settingsWriteIndex -gt $verificationIndex) 'Apply must persist candidate settings only after injector verification succeeds.'
Assert-True ($applyText -match '\$verificationDeadline\s*=\s*\(Get-Date\)\.AddSeconds\(') 'Apply must use a bounded live renderer verification deadline.'
Assert-True ($applyText -match 'do\s*\{[\s\S]*--verify\s+--theme[\s\S]*Start-Sleep[\s\S]*\}\s*while\s*\([^\r\n]*\$verificationDeadline') 'Apply must retry renderer verification until the bounded deadline.'
Assert-True ($applyText -match 'Restore-YangMiSkinStateSnapshot[\s\S]*catch') 'Apply must roll back settings and session state when watcher startup fails.'

Write-Host 'PASS: watcher contract'
