$ErrorActionPreference = 'Stop'

$dreamSkinCommon = Join-Path $HOME '.codex\skills\windows\scripts\common-windows.ps1'
if (-not (Test-Path -LiteralPath $dreamSkinCommon)) {
  throw "The vetted Windows Dream Skin helper is missing: $dreamSkinCommon"
}
. $dreamSkinCommon

function Get-YangMiNodeRuntime {
  param(
    [int]$MinimumMajor = 22,
    [AllowNull()][object[]]$Candidates = $null,
    [AllowNull()][scriptblock]$VersionProbe = $null
  )

  $injectedCandidates = $PSBoundParameters.ContainsKey('Candidates')
  if (-not $injectedCandidates) {
    $Candidates = @()
    foreach ($command in @(Get-Command node.exe -All -ErrorAction SilentlyContinue)) {
      $candidatePath = if ($command.Path) { "$($command.Path)" } else { "$($command.Source)" }
      if ($candidatePath) { $Candidates += [pscustomobject]@{ Path = $candidatePath } }
    }
    $programFilesNode = Join-Path $env:ProgramFiles 'nodejs\node.exe'
    if (Test-Path -LiteralPath $programFilesNode) {
      $Candidates += [pscustomobject]@{ Path = $programFilesNode }
    }
  }

  $verified = @()
  $seen = @{}
  foreach ($candidate in @($Candidates)) {
    $candidatePath = if ($candidate -is [string]) { $candidate } elseif ($candidate.PSObject.Properties.Name -contains 'Path') { "$($candidate.Path)" } elseif ($candidate.PSObject.Properties.Name -contains 'Source') { "$($candidate.Source)" } else { $null }
    if (-not $candidatePath) { continue }
    try { $candidatePath = [System.IO.Path]::GetFullPath($candidatePath) } catch { continue }
    if ($seen.ContainsKey($candidatePath)) { continue }
    $seen[$candidatePath] = $true
    if (-not $injectedCandidates -and -not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) { continue }

    try {
      if ($VersionProbe) {
        $versionOutput = @(& $VersionProbe $candidatePath)
      } else {
        $versionOutput = @(& $candidatePath --version 2>$null)
        if ($LASTEXITCODE -ne 0) { continue }
      }
      $version = (@($versionOutput | ForEach-Object { "$_" } | Where-Object { $_ } | Select-Object -First 1) -join '').Trim()
      $match = [regex]::Match($version, '^v?(\d+)\.\d+\.\d+(?:[-+].*)?$')
      if (-not $match.Success) { continue }
      $major = 0
      if (-not [int]::TryParse($match.Groups[1].Value, [ref]$major) -or $major -lt $MinimumMajor) { continue }
      $verified += [pscustomobject]@{ Path = $candidatePath; Version = ($version -replace '^v', ''); Major = $major }
    } catch {}
  }

  if ($verified.Count -eq 0) { throw "Node.js $MinimumMajor or newer is required; no verified eligible runtime was found." }
  return @($verified | Sort-Object -Property @(
    @{ Expression = 'Major'; Descending = $true },
    @{ Expression = 'Version'; Descending = $true }
  ) | Select-Object -First 1)[0]
}

$script:YangMiSkinSchemaVersion = 1
$script:YangMiSkinThemeIds = @('floral-retro', 'woodland-white', 'bridal-moonlight', 'noir-silver')
$script:YangMiAutostartTaskName = 'YangMiCodexSkinWatcher'
$script:YangMiAutostartRunValueName = 'YangMiCodexSkinWatcher'
$script:YangMiAutostartRunRegistryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$script:YangMiAutostartRunRegistrySubKey = 'Software\Microsoft\Windows\CurrentVersion\Run'
$script:YangMiAutostartRunMaximumCommandLength = 260
$script:YangMiSettingsProperties = @('schemaVersion', 'enabled', 'themeId', 'preferredPort', 'takeoverWindowSeconds', 'updatedAt')
$script:YangMiSessionProperties = @(
  'schemaVersion', 'generationId', 'status', 'blockedReason',
  'watcherPid', 'watcherStartedAt', 'watcherScriptPath', 'powershellPath',
  'injectorPid', 'injectorStartedAt', 'injectorPath', 'nodePath',
  'port', 'browserId', 'codexExe', 'codexPackageRoot', 'codexPackageFullName',
  'codexPackageFamilyName', 'codexVersion', 'updatedAt'
)

function Get-YangMiSkinPaths {
  param([string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'YangMiCodexSkin'))
  $fullRoot = [System.IO.Path]::GetFullPath($StateRoot)
  return [pscustomobject]@{
    StateRoot = $fullRoot
    SettingsPath = Join-Path $fullRoot 'settings.json'
    SessionPath = Join-Path $fullRoot 'session.json'
    LegacyStatePath = Join-Path $fullRoot 'state.json'
    WatcherLogPath = Join-Path $fullRoot 'watcher.log'
    WatcherErrorLogPath = Join-Path $fullRoot 'watcher-error.log'
    InjectorLogPath = Join-Path $fullRoot 'injector.log'
    InjectorErrorLogPath = Join-Path $fullRoot 'injector-error.log'
  }
}

function Assert-YangMiExactProperties {
  param([object]$Value, [string[]]$Allowed, [string]$Kind)
  if ($null -eq $Value -or $Value -is [string] -or $Value -is [array]) { throw "$Kind must be a JSON object." }
  $actual = @($Value.PSObject.Properties.Name)
  foreach ($name in $actual) {
    if ($name -notin $Allowed) { throw "$Kind contains an unsupported field: $name" }
  }
  foreach ($name in $Allowed) {
    if ($name -notin $actual) { throw "$Kind is missing required field: $name" }
  }
}

function Test-YangMiIsoTimestamp {
  param([AllowNull()][object]$Value)
  if ($Value -isnot [string] -or -not $Value) { return $false }
  $parsed = [datetimeoffset]::MinValue
  return [datetimeoffset]::TryParseExact(
    $Value,
    'o',
    [System.Globalization.CultureInfo]::InvariantCulture,
    [System.Globalization.DateTimeStyles]::RoundtripKind,
    [ref]$parsed
  )
}

function Assert-YangMiSkinSettings {
  param([Parameter(Mandatory = $true)][object]$Settings)
  Assert-YangMiExactProperties -Value $Settings -Allowed $script:YangMiSettingsProperties -Kind 'Yang Mi settings'
  if ($Settings.schemaVersion -isnot [int] -or $Settings.schemaVersion -ne $script:YangMiSkinSchemaVersion) { throw 'Yang Mi settings schema is not supported.' }
  if ($Settings.enabled -isnot [bool]) { throw 'Yang Mi settings enabled must be Boolean.' }
  if ($Settings.themeId -isnot [string] -or $Settings.themeId -cnotin $script:YangMiSkinThemeIds) { throw 'Yang Mi settings themeId is invalid.' }
  if ($Settings.preferredPort -isnot [int]) { throw 'Yang Mi settings preferredPort must be an integer.' }
  Assert-DreamSkinPort -Port $Settings.preferredPort
  if ($Settings.takeoverWindowSeconds -isnot [int] -or $Settings.takeoverWindowSeconds -lt 1 -or $Settings.takeoverWindowSeconds -gt 30) {
    throw 'Yang Mi settings takeoverWindowSeconds must be between 1 and 30.'
  }
  if (-not (Test-YangMiIsoTimestamp -Value $Settings.updatedAt)) { throw 'Yang Mi settings updatedAt is invalid.' }
  return $Settings
}

function New-YangMiSkinSettings {
  param(
    [Parameter(Mandatory = $true)][string]$ThemeId,
    [int]$PreferredPort = 9447,
    [int]$TakeoverWindowSeconds = 8,
    [bool]$Enabled = $true
  )
  $settings = [pscustomobject][ordered]@{
    schemaVersion = 1
    enabled = $Enabled
    themeId = $ThemeId
    preferredPort = $PreferredPort
    takeoverWindowSeconds = $TakeoverWindowSeconds
    updatedAt = [datetime]::UtcNow.ToString('o')
  }
  return (Assert-YangMiSkinSettings -Settings $settings)
}

function Read-YangMiSkinSettings {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  try {
    $settings = Read-DreamSkinUtf8File -Path $Path | ConvertFrom-Json -ErrorAction Stop
    return (Assert-YangMiSkinSettings -Settings $settings)
  } catch {
    throw "Yang Mi settings are invalid and were preserved for inspection: $Path. $($_.Exception.Message)"
  }
}

function Write-YangMiSkinSettings {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Settings)
  $null = Assert-YangMiSkinSettings -Settings $Settings
  Write-DreamSkinUtf8FileAtomically -Path $Path -Content (($Settings | ConvertTo-Json -Depth 4) + "`r`n")
}

function New-YangMiSkinSession {
  param([string]$GenerationId = ([guid]::NewGuid().ToString('N')), [string]$Status = 'idle', [AllowNull()][string]$BlockedReason = $null)
  return [pscustomobject][ordered]@{
    schemaVersion = 1
    generationId = $GenerationId
    status = $Status
    blockedReason = $BlockedReason
    watcherPid = $null
    watcherStartedAt = $null
    watcherScriptPath = $null
    powershellPath = $null
    injectorPid = $null
    injectorStartedAt = $null
    injectorPath = $null
    nodePath = $null
    port = $null
    browserId = $null
    codexExe = $null
    codexPackageRoot = $null
    codexPackageFullName = $null
    codexPackageFamilyName = $null
    codexVersion = $null
    updatedAt = [datetime]::UtcNow.ToString('o')
  }
}

function Assert-YangMiNullableString {
  param([AllowNull()][object]$Value, [string]$Name)
  if ($null -ne $Value -and $Value -isnot [string]) { throw "Yang Mi session $Name must be a string or null." }
}

function Assert-YangMiNullablePositiveInt {
  param([AllowNull()][object]$Value, [string]$Name)
  if ($null -ne $Value -and ($Value -isnot [int] -or $Value -le 0)) { throw "Yang Mi session $Name must be a positive integer or null." }
}

function Assert-YangMiSkinSession {
  param([Parameter(Mandatory = $true)][object]$Session)
  Assert-YangMiExactProperties -Value $Session -Allowed $script:YangMiSessionProperties -Kind 'Yang Mi session'
  if ($Session.schemaVersion -isnot [int] -or $Session.schemaVersion -ne 1) { throw 'Yang Mi session schema is not supported.' }
  if ($Session.generationId -isnot [string] -or $Session.generationId -cnotmatch '^[a-f0-9]{32}$') { throw 'Yang Mi session generationId is invalid.' }
  if ($Session.status -isnot [string] -or $Session.status -cnotin @('idle', 'starting', 'ready', 'active', 'blocked', 'disabled', 'error')) { throw 'Yang Mi session status is invalid.' }
  foreach ($name in @('blockedReason', 'watcherStartedAt', 'watcherScriptPath', 'powershellPath', 'injectorStartedAt', 'injectorPath', 'nodePath', 'browserId', 'codexExe', 'codexPackageRoot', 'codexPackageFullName', 'codexPackageFamilyName', 'codexVersion')) {
    Assert-YangMiNullableString -Value $Session.$name -Name $name
  }
  Assert-YangMiNullablePositiveInt -Value $Session.watcherPid -Name 'watcherPid'
  Assert-YangMiNullablePositiveInt -Value $Session.injectorPid -Name 'injectorPid'
  if ($null -ne $Session.port) {
    if ($Session.port -isnot [int]) { throw 'Yang Mi session port must be an integer or null.' }
    Assert-DreamSkinPort -Port $Session.port
  }
  foreach ($name in @('watcherStartedAt', 'injectorStartedAt')) {
    if ($Session.$name -and -not (Test-YangMiIsoTimestamp -Value $Session.$name)) { throw "Yang Mi session $name is invalid." }
  }
  if ($Session.browserId -and -not (Test-DreamSkinBrowserId -Value $Session.browserId)) { throw 'Yang Mi session browserId is invalid.' }
  if (-not (Test-YangMiIsoTimestamp -Value $Session.updatedAt)) { throw 'Yang Mi session updatedAt is invalid.' }
  return $Session
}

function Read-YangMiSkinSession {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  try {
    $session = Read-DreamSkinUtf8File -Path $Path | ConvertFrom-Json -ErrorAction Stop
    return (Assert-YangMiSkinSession -Session $session)
  } catch {
    throw "Yang Mi session is invalid and was preserved for inspection: $Path. $($_.Exception.Message)"
  }
}

function Write-YangMiSkinSession {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Session)
  $Session.updatedAt = [datetime]::UtcNow.ToString('o')
  $null = Assert-YangMiSkinSession -Session $Session
  Write-DreamSkinUtf8FileAtomically -Path $Path -Content (($Session | ConvertTo-Json -Depth 5) + "`r`n")
}

function Set-YangMiSkinSessionStatus {
  param([Parameter(Mandatory = $true)][object]$Session, [Parameter(Mandatory = $true)][string]$Status, [AllowNull()][string]$BlockedReason = $null)
  $Session.status = $Status
  $Session.blockedReason = $BlockedReason
  return $Session
}

function Set-YangMiSkinSessionPackage {
  param([Parameter(Mandatory = $true)][object]$Session, [Parameter(Mandatory = $true)][object]$Codex)
  $Session.codexExe = "$($Codex.Executable)"
  $Session.codexPackageRoot = "$($Codex.PackageRoot)"
  $Session.codexPackageFullName = "$($Codex.PackageFullName)"
  $Session.codexPackageFamilyName = "$($Codex.PackageFamilyName)"
  $Session.codexVersion = "$($Codex.Version)"
  return $Session
}

function Archive-YangMiSkinFile {
  param([Parameter(Mandatory = $true)][string]$Path, [string]$Kind = 'stale')
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  $directory = Split-Path -Parent ([System.IO.Path]::GetFullPath($Path))
  $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
  $archive = Join-Path $directory "$name.$Kind-$((Get-Date).ToString('yyyyMMdd-HHmmss-fff'))-$([guid]::NewGuid().ToString('N')).json"
  Move-Item -LiteralPath $Path -Destination $archive -ErrorAction Stop
  return $archive
}

function ConvertTo-YangMiCreationTime {
  param([AllowNull()][object]$Value)
  if ($null -eq $Value) { return $null }
  if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
  try { return ([System.Management.ManagementDateTimeConverter]::ToDateTime("$Value")).ToUniversalTime() } catch {}
  try { return ([datetimeoffset]::Parse("$Value")).UtcDateTime } catch { return $null }
}

function Test-YangMiFreshLaunchGuard {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Processes,
    [datetime]$Now = ([datetime]::UtcNow),
    [int]$TakeoverWindowSeconds = 8,
    [switch]$HasEstablishedSession
  )
  if ($HasEstablishedSession -or $Processes.Count -eq 0) { return $false }
  $utcNow = $Now.ToUniversalTime()
  foreach ($process in $Processes) {
    $created = ConvertTo-YangMiCreationTime -Value $process.CreationDate
    if ($null -eq $created) { return $false }
    $age = ($utcNow - $created).TotalSeconds
    if ($age -lt -1 -or $age -gt $TakeoverWindowSeconds) { return $false }
  }
  return $true
}

function Test-YangMiSessionProtectsDraft {
  param([AllowNull()][object]$Session)
  if ($null -eq $Session) { return $false }
  return $Session.status -cin @('ready', 'active') -or
    ($Session.status -ceq 'blocked' -and $Session.blockedReason -ceq 'existing-session-may-contain-draft') -or
    ($Session.status -ceq 'error' -and $Session.blockedReason -ceq 'recovery-relaunched-without-cdp')
}

function Get-YangMiProcessStartedAtFromInfo {
  param([Parameter(Mandatory = $true)][object]$ProcessInfo)
  if ($ProcessInfo.PSObject.Properties.Name -contains 'StartedAt' -and $ProcessInfo.StartedAt) { return "$($ProcessInfo.StartedAt)" }
  $created = ConvertTo-YangMiCreationTime -Value $ProcessInfo.CreationDate
  if ($null -eq $created) { return $null }
  return $created.ToString('o')
}

function Test-YangMiWindowsCommandLineQuoteSyntax {
  param([string]$CommandLine)
  if (-not $CommandLine) { return $false }
  $insideQuote = $false
  $backslashCount = 0
  foreach ($character in $CommandLine.ToCharArray()) {
    if ($character -eq '\') { $backslashCount++; continue }
    if ($character -eq '"') {
      if (($backslashCount % 2) -eq 0) { $insideQuote = -not $insideQuote }
    }
    $backslashCount = 0
  }
  return -not $insideQuote
}

function ConvertFrom-YangMiWindowsCommandLine {
  param([string]$CommandLine)
  if (-not (Test-YangMiWindowsCommandLineQuoteSyntax -CommandLine $CommandLine)) { return $null }
  if (-not ('YangMiSkin.NativeCommandLine' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace YangMiSkin {
  public static class NativeCommandLine {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr CommandLineToArgvW(string commandLine, out int argumentCount);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr LocalFree(IntPtr memory);
  }
}
'@
  }
  $argumentCount = 0
  $memory = [YangMiSkin.NativeCommandLine]::CommandLineToArgvW($CommandLine, [ref]$argumentCount)
  if ($memory -eq [IntPtr]::Zero -or $argumentCount -lt 1) { return $null }
  try {
    $arguments = @()
    for ($index = 0; $index -lt $argumentCount; $index++) {
      $itemPointer = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($memory, $index * [IntPtr]::Size)
      $arguments += [System.Runtime.InteropServices.Marshal]::PtrToStringUni($itemPointer)
    }
    return $arguments
  } finally {
    [void][YangMiSkin.NativeCommandLine]::LocalFree($memory)
  }
}

function Get-YangMiCommandArgumentIndexes {
  param([string[]]$Arguments, [string]$Name)
  $indexes = @()
  for ($index = 0; $index -lt $Arguments.Count; $index++) {
    if ($Arguments[$index] -ieq $Name) { $indexes += $index }
  }
  return $indexes
}

function Test-YangMiCommandArgument {
  param([string[]]$Arguments, [string]$Name, [AllowNull()][object]$Value)
  $indexes = @(Get-YangMiCommandArgumentIndexes -Arguments $Arguments -Name $Name)
  if ($indexes.Count -ne 1) { return $false }
  if ($null -eq $Value) { return $true }
  $valueIndex = [int]$indexes[0] + 1
  return $valueIndex -lt $Arguments.Count -and $Arguments[$valueIndex] -ceq "$Value"
}

function Get-YangMiSingleCommandArgumentValue {
  param([string[]]$Arguments, [string]$Name)
  $indexes = @(Get-YangMiCommandArgumentIndexes -Arguments $Arguments -Name $Name)
  if ($indexes.Count -ne 1) { return $null }
  $valueIndex = [int]$indexes[0] + 1
  if ($valueIndex -ge $Arguments.Count) { return $null }
  return $Arguments[$valueIndex]
}

function Test-YangMiRuntimeScriptPosition {
  param([string[]]$Arguments, [ValidateSet('node', 'powershell')][string]$RuntimeKind, [string]$ScriptPath)
  if ($Arguments.Count -lt 2) { return $false }
  $scriptIndexes = @()
  for ($index = 0; $index -lt $Arguments.Count; $index++) {
    if (Test-DreamSkinPathEqual -Left $Arguments[$index] -Right $ScriptPath) { $scriptIndexes += $index }
  }
  if ($scriptIndexes.Count -ne 1) { return $false }
  if ($RuntimeKind -eq 'node') { return $scriptIndexes[0] -eq 1 }
  $fileIndexes = @(Get-YangMiCommandArgumentIndexes -Arguments $Arguments -Name '-File')
  return $fileIndexes.Count -eq 1 -and $fileIndexes[0] + 1 -eq $scriptIndexes[0]
}

function ConvertFrom-YangMiInjectorCommandLine {
  param([string]$CommandLine)
  $arguments = @(ConvertFrom-YangMiWindowsCommandLine -CommandLine $CommandLine)
  if ($arguments.Count -lt 2 -or -not (Test-YangMiCommandArgument -Arguments $arguments -Name '--watch' -Value $null)) { return $null }
  $themeId = Get-YangMiSingleCommandArgumentValue -Arguments $arguments -Name '--theme'
  $portText = Get-YangMiSingleCommandArgumentValue -Arguments $arguments -Name '--port'
  $browserId = Get-YangMiSingleCommandArgumentValue -Arguments $arguments -Name '--browser-id'
  $port = 0
  if ($themeId -cnotin $script:YangMiSkinThemeIds -or
    -not [int]::TryParse($portText, [ref]$port) -or $port -lt 1024 -or $port -gt 65535 -or
    -not (Test-DreamSkinBrowserId -Value $browserId)) { return $null }
  return [pscustomobject]@{ ThemeId = $themeId; Port = $port; BrowserId = $browserId }
}

function Test-YangMiProcessIdentity {
  param(
    [Parameter(Mandatory = $true)][object]$ProcessInfo,
    [Parameter(Mandatory = $true)][ValidateSet('node', 'powershell')][string]$RuntimeKind,
    [Parameter(Mandatory = $true)][int]$ExpectedPid,
    [Parameter(Mandatory = $true)][string]$ExpectedStartedAt,
    [Parameter(Mandatory = $true)][string]$ExpectedExecutablePath,
    [Parameter(Mandatory = $true)][string]$ScriptPath,
    [hashtable]$RequiredArguments = @{}
  )
  $actualPid = if ($ProcessInfo.PSObject.Properties.Name -contains 'ProcessId') { [int]$ProcessInfo.ProcessId } else { [int]$ProcessInfo.Id }
  if ($actualPid -ne $ExpectedPid) { return $false }
  $actualPath = Get-DreamSkinProcessExecutablePath -ProcessInfo $ProcessInfo
  if (-not (Test-DreamSkinPathEqual -Left $actualPath -Right $ExpectedExecutablePath)) { return $false }
  $actualStartedAt = Get-YangMiProcessStartedAtFromInfo -ProcessInfo $ProcessInfo
  try {
    $actualStart = ([datetimeoffset]::Parse($actualStartedAt)).UtcDateTime
    $expectedStart = ([datetimeoffset]::Parse($ExpectedStartedAt)).UtcDateTime
    if ([math]::Abs(($actualStart - $expectedStart).TotalMilliseconds) -gt 10) { return $false }
  } catch { return $false }
  $commandLine = "$($ProcessInfo.CommandLine)"
  $arguments = @(ConvertFrom-YangMiWindowsCommandLine -CommandLine $commandLine)
  if ($arguments.Count -lt 2 -or -not (Test-DreamSkinPathEqual -Left $arguments[0] -Right $ExpectedExecutablePath) -or
    -not (Test-YangMiRuntimeScriptPosition -Arguments $arguments -RuntimeKind $RuntimeKind -ScriptPath $ScriptPath)) { return $false }
  if ($RuntimeKind -eq 'node') {
    $expectedNames = @('--watch', '--theme', '--port', '--browser-id')
    if ($RequiredArguments.Count -ne $expectedNames.Count) { return $false }
    foreach ($name in $expectedNames) {
      if (-not $RequiredArguments.ContainsKey($name)) { return $false }
    }
    if ($null -ne $RequiredArguments['--watch']) { return $false }
    $expectedArguments = @(
      $ExpectedExecutablePath, $ScriptPath, '--watch', '--theme', "$($RequiredArguments['--theme'])",
      '--port', "$($RequiredArguments['--port'])", '--browser-id', "$($RequiredArguments['--browser-id'])"
    )
    if ($arguments.Count -ne $expectedArguments.Count) { return $false }
    for ($index = 0; $index -lt $expectedArguments.Count; $index++) {
      if ($index -in @(0, 1)) {
        if (-not (Test-DreamSkinPathEqual -Left $arguments[$index] -Right $expectedArguments[$index])) { return $false }
      } elseif ($arguments[$index] -cne $expectedArguments[$index]) { return $false }
    }
  }
  foreach ($controlledName in @(
    '--watch', '--once', '--verify', '--remove', '--check-payload', '--self-test',
    '--theme', '--port', '--browser-id'
  )) {
    if (-not $RequiredArguments.ContainsKey($controlledName) -and
      (Get-YangMiCommandArgumentIndexes -Arguments $arguments -Name $controlledName).Count -ne 0) { return $false }
  }
  foreach ($argument in $RequiredArguments.GetEnumerator()) {
    if (-not (Test-YangMiCommandArgument -Arguments $arguments -Name "$($argument.Key)" -Value $argument.Value)) { return $false }
  }
  return $true
}

function Get-YangMiProcessInfo {
  param([int]$ProcessId)
  return Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue
}

function Stop-YangMiRecordedProcess {
  param(
    [AllowNull()][object]$ProcessInfo,
    [Parameter(Mandatory = $true)][int]$ExpectedPid,
    [Parameter(Mandatory = $true)][string]$ExpectedStartedAt,
    [Parameter(Mandatory = $true)][string]$ExpectedExecutablePath,
    [Parameter(Mandatory = $true)][string]$ScriptPath,
    [Parameter(Mandatory = $true)][ValidateSet('node', 'powershell')][string]$RuntimeKind,
    [hashtable]$RequiredArguments = @{}
  )
  $currentProcessInfo = Get-YangMiProcessInfo -ProcessId $ExpectedPid
  if ($null -eq $currentProcessInfo) { return $true }
  if (-not (Test-YangMiProcessIdentity -ProcessInfo $currentProcessInfo -RuntimeKind $RuntimeKind -ExpectedPid $ExpectedPid -ExpectedStartedAt $ExpectedStartedAt -ExpectedExecutablePath $ExpectedExecutablePath -ScriptPath $ScriptPath -RequiredArguments $RequiredArguments)) {
    Write-Warning "Skipped PID $ExpectedPid because its full process identity does not match the saved Yang Mi session."
    return $false
  }
  Stop-Process -Id $ExpectedPid -Force -ErrorAction Stop
  try { Wait-Process -Id $ExpectedPid -Timeout 5 -ErrorAction Stop } catch {}
  return $null -eq (Get-Process -Id $ExpectedPid -ErrorAction SilentlyContinue)
}

function Stop-YangMiSessionInjector {
  param([AllowNull()][object]$Session, [Parameter(Mandatory = $true)][string]$ThemeId)
  if ($null -eq $Session -or -not $Session.injectorPid) { return $true }
  $processInfo = Get-YangMiProcessInfo -ProcessId ([int]$Session.injectorPid)
  if ($null -eq $processInfo) { return $true }
  if (-not $Session.injectorStartedAt -or -not $Session.injectorPath -or -not $Session.nodePath -or -not $Session.port -or -not $Session.browserId) { return $false }
  return Stop-YangMiRecordedProcess -ProcessInfo $processInfo -ExpectedPid ([int]$Session.injectorPid) `
    -ExpectedStartedAt $Session.injectorStartedAt -ExpectedExecutablePath $Session.nodePath -ScriptPath $Session.injectorPath `
    -RuntimeKind node -RequiredArguments @{ '--watch' = $null; '--theme' = $ThemeId; '--port' = "$($Session.port)"; '--browser-id' = $Session.browserId }
}

function Stop-YangMiSessionInjectorAnyAllowedTheme {
  param([AllowNull()][object]$Session, [string]$ExpectedInjectorPath)
  if ($null -eq $Session -or -not $Session.injectorPid) { return $true }
  $processInfo = Get-YangMiProcessInfo -ProcessId ([int]$Session.injectorPid)
  if ($null -eq $processInfo) { return $true }
  if (-not $Session.injectorStartedAt -or -not $Session.injectorPath -or -not $Session.nodePath -or -not $Session.port -or -not $Session.browserId) { return $false }
  if ($ExpectedInjectorPath -and -not (Test-DreamSkinPathEqual -Left $Session.injectorPath -Right $ExpectedInjectorPath)) { return $false }
  foreach ($themeId in $script:YangMiSkinThemeIds) {
    $arguments = @{ '--watch' = $null; '--theme' = $themeId; '--port' = "$($Session.port)"; '--browser-id' = $Session.browserId }
    if (Test-YangMiProcessIdentity -ProcessInfo $processInfo -RuntimeKind node -ExpectedPid ([int]$Session.injectorPid) `
      -ExpectedStartedAt $Session.injectorStartedAt -ExpectedExecutablePath $Session.nodePath -ScriptPath $Session.injectorPath `
      -RequiredArguments $arguments) {
      return Stop-YangMiRecordedProcess -ProcessInfo $processInfo -ExpectedPid ([int]$Session.injectorPid) `
        -ExpectedStartedAt $Session.injectorStartedAt -ExpectedExecutablePath $Session.nodePath -ScriptPath $Session.injectorPath `
        -RuntimeKind node -RequiredArguments $arguments
    }
  }
  return $false
}

function Test-YangMiInjectorSessionIdentityComplete {
  param([AllowNull()][object]$Session)
  if ($null -eq $Session -or -not $Session.injectorPid -or -not $Session.injectorStartedAt -or
    -not $Session.injectorPath -or -not $Session.nodePath -or -not $Session.port -or -not $Session.browserId) { return $false }
  if ($Session.injectorPid -isnot [int] -or $Session.injectorPid -le 0 -or
    -not (Test-YangMiIsoTimestamp -Value $Session.injectorStartedAt) -or
    $Session.injectorPath -isnot [string] -or $Session.nodePath -isnot [string] -or
    $Session.port -isnot [int] -or $Session.browserId -isnot [string]) { return $false }
  try { Assert-DreamSkinPort -Port $Session.port } catch { return $false }
  return Test-DreamSkinBrowserId -Value $Session.browserId
}

function Get-YangMiInjectorCandidateNodePaths {
  param(
    [AllowNull()][object[]]$Processes,
    [AllowNull()][string[]]$NodePaths = @()
  )
  if (-not $PSBoundParameters.ContainsKey('Processes')) {
    $Processes = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq 'node.exe' })
  }
  $paths = @()
  foreach ($candidatePath in @($NodePaths)) {
    if ($candidatePath) { $paths += "$candidatePath" }
  }
  foreach ($process in @($Processes)) {
    $path = Get-DreamSkinProcessExecutablePath -ProcessInfo $process
    if ($path) { $paths += "$path" }
  }
  $unique = @()
  foreach ($path in $paths) {
    if (-not (@($unique | Where-Object { Test-DreamSkinPathEqual -Left $_ -Right $path }).Count)) { $unique += $path }
  }
  return $unique
}

function Find-YangMiExactInjectors {
  param(
    [AllowNull()][object[]]$Processes,
    [string]$NodePath,
    [string]$InjectorPath
  )
  if (-not $PSBoundParameters.ContainsKey('Processes')) {
    $Processes = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq 'node.exe' })
  }
  $matches = @()
  foreach ($process in @($Processes)) {
    $arguments = ConvertFrom-YangMiInjectorCommandLine -CommandLine "$($process.CommandLine)"
    if ($null -eq $arguments) { continue }
    $startedAt = Get-YangMiProcessStartedAtFromInfo -ProcessInfo $process
    if (-not $startedAt) { continue }
    if (Test-YangMiProcessIdentity -ProcessInfo $process -RuntimeKind node -ExpectedPid ([int]$process.ProcessId) -ExpectedStartedAt $startedAt `
      -ExpectedExecutablePath $NodePath -ScriptPath $InjectorPath `
      -RequiredArguments @{ '--watch' = $null; '--theme' = $arguments.ThemeId; '--port' = "$($arguments.Port)"; '--browser-id' = $arguments.BrowserId }) {
      $matches += [pscustomobject]@{
        Process = $process
        StartedAt = $startedAt
        NodePath = $NodePath
        ThemeId = $arguments.ThemeId
        Port = $arguments.Port
        BrowserId = $arguments.BrowserId
      }
    }
  }
  return $matches
}

function Find-YangMiExactInjectorsAcrossNodePaths {
  param(
    [AllowNull()][object[]]$Processes,
    [AllowNull()][string[]]$NodePaths = @(),
    [Parameter(Mandatory = $true)][string]$InjectorPath
  )
  $hasProcesses = $PSBoundParameters.ContainsKey('Processes')
  if (-not $hasProcesses) {
    $Processes = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq 'node.exe' })
  }
  $matches = @()
  foreach ($nodePath in @(Get-YangMiInjectorCandidateNodePaths -Processes $Processes -NodePaths $NodePaths)) {
    $matches += @(Find-YangMiExactInjectors -Processes $Processes -NodePath $nodePath -InjectorPath $InjectorPath)
  }
  return $matches
}

function Stop-YangMiExactInjectors {
  param(
    [AllowNull()][object[]]$ExactInjectors,
    [Parameter(Mandatory = $true)][string]$InjectorPath
  )
  foreach ($injector in @($ExactInjectors)) {
    if ($null -eq $injector -or -not $injector.Process -or -not $injector.StartedAt -or -not $injector.NodePath -or
      $injector.ThemeId -cnotin $script:YangMiSkinThemeIds -or -not $injector.Port -or -not $injector.BrowserId) { return $false }
    $processId = if ($injector.Process.PSObject.Properties.Name -contains 'ProcessId') { [int]$injector.Process.ProcessId } else { [int]$injector.Process.Id }
    if (-not (Stop-YangMiRecordedProcess -ProcessInfo $injector.Process -ExpectedPid $processId -ExpectedStartedAt $injector.StartedAt `
      -ExpectedExecutablePath $injector.NodePath -ScriptPath $InjectorPath -RuntimeKind node `
      -RequiredArguments @{ '--watch' = $null; '--theme' = $injector.ThemeId; '--port' = "$($injector.Port)"; '--browser-id' = $injector.BrowserId })) { return $false }
  }
  return $true
}

function Find-YangMiMatchingInjectors {
  param([string]$NodePath, [string]$InjectorPath, [string]$ThemeId, [int]$Port, [string]$BrowserId)
  return @(Find-YangMiExactInjectors -NodePath $NodePath -InjectorPath $InjectorPath | Where-Object {
    $_.ThemeId -ceq $ThemeId -and $_.Port -eq $Port -and $_.BrowserId -ceq $BrowserId
  })
}

function Start-YangMiInjector {
  param(
    [string]$NodePath, [string]$InjectorPath, [string]$ThemeId, [int]$Port, [string]$BrowserId,
    [string]$StandardOutputPath, [string]$StandardErrorPath
  )
  $process = Start-Process -FilePath $NodePath -ArgumentList @(
    (ConvertTo-DreamSkinProcessArgument -Value $InjectorPath), '--watch', '--theme', $ThemeId,
    '--port', "$Port", '--browser-id', $BrowserId
  ) -WindowStyle Hidden -PassThru -RedirectStandardOutput $StandardOutputPath -RedirectStandardError $StandardErrorPath
  Start-Sleep -Milliseconds 750
  if ($process.HasExited) { throw "Yang Mi injector exited. See $StandardErrorPath" }
  return [pscustomobject]@{ Process = $process; StartedAt = $process.StartTime.ToUniversalTime().ToString('o') }
}

function Enter-YangMiWatcherMutex {
  $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $mutex = [System.Threading.Mutex]::new($false, "Local\YangMiCodexSkin.$sid.Watcher")
  $acquired = $false
  try { $acquired = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $acquired = $true }
  if (-not $acquired) { $mutex.Dispose(); return $null }
  return $mutex
}

function Exit-YangMiWatcherMutex {
  param([AllowNull()][System.Threading.Mutex]$Mutex)
  if ($null -eq $Mutex) { return }
  try { $Mutex.ReleaseMutex() } finally { $Mutex.Dispose() }
}

function Start-YangMiWatcher {
  param([string]$PowerShellPath, [string]$WatcherPath, [string]$StateRoot, [string]$StandardOutputPath, [string]$StandardErrorPath)
  $process = Start-Process -FilePath $PowerShellPath -ArgumentList @(
    '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', (ConvertTo-DreamSkinProcessArgument -Value $WatcherPath),
    '-StateRoot', (ConvertTo-DreamSkinProcessArgument -Value $StateRoot)
  ) -WindowStyle Hidden -PassThru -RedirectStandardOutput $StandardOutputPath -RedirectStandardError $StandardErrorPath
  Start-Sleep -Milliseconds 250
  if ($process.HasExited) { throw "Yang Mi watcher exited. See $StandardErrorPath" }
  return [pscustomobject]@{ Process = $process; StartedAt = $process.StartTime.ToUniversalTime().ToString('o') }
}

function Test-YangMiSessionWatcher {
  param([AllowNull()][object]$Session, [string]$WatcherPath, [string]$StateRoot)
  if ($null -eq $Session -or -not $Session.watcherPid -or -not $Session.watcherStartedAt -or
    -not $Session.watcherScriptPath -or -not $Session.powershellPath) { return $false }
  if (-not (Test-DreamSkinPathEqual -Left $Session.watcherScriptPath -Right $WatcherPath)) { return $false }
  $processInfo = Get-YangMiProcessInfo -ProcessId ([int]$Session.watcherPid)
  if ($null -eq $processInfo) { return $false }
  return Test-YangMiWatcherProcessIdentity -ProcessInfo $processInfo -ExpectedPid ([int]$Session.watcherPid) `
    -ExpectedStartedAt $Session.watcherStartedAt -PowerShellPath $Session.powershellPath -WatcherPath $WatcherPath -StateRoot $StateRoot
}

function ConvertTo-YangMiQuotedWindowsArgument {
  param([Parameter(Mandatory = $true)][string]$Value)
  if ($Value.Contains('"')) { throw 'Windows command arguments cannot contain a quote character.' }
  $escaped = if ($Value.EndsWith('\')) { "$Value\" } else { $Value }
  return "`"$escaped`""
}

function Get-YangMiAutostartTaskPrincipalIdentity {
  $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
  if ($null -eq $identity.User) { throw 'Unable to determine the current user SID for the Yang Mi autostart task.' }
  return [pscustomobject][ordered]@{
    UserId = $identity.User.Value
    LogonType = 'Interactive'
    RunLevel = 'Limited'
  }
}

function New-YangMiAutostartTaskAction {
  param(
    [Parameter(Mandatory = $true)][string]$PowerShellPath,
    [Parameter(Mandatory = $true)][string]$WatcherPath,
    [Parameter(Mandatory = $true)][string]$StateRoot
  )
  $powerShellFullPath = [System.IO.Path]::GetFullPath($PowerShellPath)
  $watcherFullPath = [System.IO.Path]::GetFullPath($WatcherPath)
  $stateRootFullPath = [System.IO.Path]::GetFullPath($StateRoot)
  return [pscustomobject][ordered]@{
    Execute = $powerShellFullPath
    Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File {0} -StateRoot {1}' -f `
      (ConvertTo-YangMiQuotedWindowsArgument -Value $watcherFullPath), (ConvertTo-YangMiQuotedWindowsArgument -Value $stateRootFullPath)
  }
}

function New-YangMiAutostartRunCommand {
  param(
    [Parameter(Mandatory = $true)][string]$PowerShellPath,
    [Parameter(Mandatory = $true)][string]$WatcherPath,
    [Parameter(Mandatory = $true)][string]$StateRoot
  )
  $powerShellFullPath = [System.IO.Path]::GetFullPath($PowerShellPath)
  $watcherFullPath = [System.IO.Path]::GetFullPath($WatcherPath)
  $stateRootFullPath = [System.IO.Path]::GetFullPath($StateRoot)
  return '{0} -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File {1} -StateRoot {2}' -f `
    (ConvertTo-YangMiQuotedWindowsArgument -Value $powerShellFullPath),
    (ConvertTo-YangMiQuotedWindowsArgument -Value $watcherFullPath),
    (ConvertTo-YangMiQuotedWindowsArgument -Value $stateRootFullPath)
}

function ConvertTo-YangMiSingleQuotedPowerShellString {
  param([Parameter(Mandatory = $true)][string]$Value)
  return "'$($Value.Replace("'", "''"))'"
}

function New-YangMiAutostartRunLauncherCommand {
  param(
    [Parameter(Mandatory = $true)][string]$PowerShellPath,
    [Parameter(Mandatory = $true)][string]$LauncherPath
  )
  $powerShellFullPath = [System.IO.Path]::GetFullPath($PowerShellPath)
  $launcherFullPath = [System.IO.Path]::GetFullPath($LauncherPath)
  return '{0} -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File {1}' -f `
    (ConvertTo-YangMiQuotedWindowsArgument -Value $powerShellFullPath),
    (ConvertTo-YangMiQuotedWindowsArgument -Value $launcherFullPath)
}

function New-YangMiAutostartRunLauncherContent {
  param(
    [Parameter(Mandatory = $true)][string]$PowerShellPath,
    [Parameter(Mandatory = $true)][string]$WatcherPath,
    [Parameter(Mandatory = $true)][string]$StateRoot
  )
  $powerShellFullPath = [System.IO.Path]::GetFullPath($PowerShellPath)
  $watcherFullPath = [System.IO.Path]::GetFullPath($WatcherPath)
  $stateRootFullPath = [System.IO.Path]::GetFullPath($StateRoot)
  return ('& {0} -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File {1} -StateRoot {2}' -f `
    (ConvertTo-YangMiSingleQuotedPowerShellString -Value $powerShellFullPath),
    (ConvertTo-YangMiSingleQuotedPowerShellString -Value $watcherFullPath),
    (ConvertTo-YangMiSingleQuotedPowerShellString -Value $stateRootFullPath)) + "`r`n"
}

function Test-YangMiAutostartRunLauncherCommandArguments {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [Parameter(Mandatory = $true)][string]$PowerShellPath,
    [Parameter(Mandatory = $true)][string]$LauncherPath
  )
  $expected = @(
    $PowerShellPath, '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
    '-File', $LauncherPath
  )
  if ($Arguments.Count -ne $expected.Count) { return $false }
  for ($index = 0; $index -lt $expected.Count; $index++) {
    if ($index -in @(0, 8)) {
      if (-not (Test-DreamSkinPathEqual -Left $Arguments[$index] -Right $expected[$index])) { return $false }
    } elseif ($Arguments[$index] -cne $expected[$index]) { return $false }
  }
  return $true
}

function New-YangMiAutostartRunDefinition {
  param(
    [Parameter(Mandatory = $true)][string]$PowerShellPath,
    [Parameter(Mandatory = $true)][string]$WatcherPath,
    [Parameter(Mandatory = $true)][string]$StateRoot
  )
  $powerShellFullPath = [System.IO.Path]::GetFullPath($PowerShellPath)
  $watcherFullPath = [System.IO.Path]::GetFullPath($WatcherPath)
  $stateRootFullPath = [System.IO.Path]::GetFullPath($StateRoot)
  $directCommand = New-YangMiAutostartRunCommand -PowerShellPath $powerShellFullPath -WatcherPath $watcherFullPath -StateRoot $stateRootFullPath
  if ($directCommand.Length -le $script:YangMiAutostartRunMaximumCommandLength) {
    return [pscustomobject][ordered]@{
      Mode = 'direct'
      Command = $directCommand
      LauncherPath = $null
      LauncherContent = $null
    }
  }
  $launcherPath = Join-Path $stateRootFullPath 'watcher-launch.ps1'
  $launcherCommand = New-YangMiAutostartRunLauncherCommand -PowerShellPath $powerShellFullPath -LauncherPath $launcherPath
  if ($launcherCommand.Length -gt $script:YangMiAutostartRunMaximumCommandLength) {
    throw "The HKCU Run fallback cannot fit within $($script:YangMiAutostartRunMaximumCommandLength) characters, even with the watcher launcher."
  }
  return [pscustomobject][ordered]@{
    Mode = 'launcher'
    Command = $launcherCommand
    LauncherPath = $launcherPath
    LauncherContent = New-YangMiAutostartRunLauncherContent -PowerShellPath $powerShellFullPath -WatcherPath $watcherFullPath -StateRoot $stateRootFullPath
  }
}

function Read-YangMiAutostartRunLauncherContent {
  param([Parameter(Mandatory = $true)][string]$Path)
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { return $null }
  return [System.IO.File]::ReadAllText($fullPath, [System.Text.Encoding]::UTF8)
}

function Test-YangMiAutostartRunLauncherContentIdentity {
  param(
    [AllowNull()][string]$Content,
    [Parameter(Mandatory = $true)][string]$PowerShellPath,
    [Parameter(Mandatory = $true)][string]$WatcherPath,
    [Parameter(Mandatory = $true)][string]$StateRoot
  )
  $expectedContent = New-YangMiAutostartRunLauncherContent -PowerShellPath $PowerShellPath -WatcherPath $WatcherPath -StateRoot $StateRoot
  if ($Content -cne $expectedContent) { return $false }
  $arguments = @(ConvertFrom-YangMiWindowsCommandLine -CommandLine (New-YangMiAutostartRunCommand -PowerShellPath $PowerShellPath -WatcherPath $WatcherPath -StateRoot $StateRoot))
  return Test-YangMiWatcherCommandArguments -Arguments $arguments -PowerShellPath $PowerShellPath -WatcherPath $WatcherPath -StateRoot $StateRoot
}

function Get-YangMiAutostartRunValue {
  param([AllowNull()][object]$RegistryKey)
  if ($null -eq $RegistryKey) { return $null }
  try {
    $kind = $RegistryKey.GetValueKind($script:YangMiAutostartRunValueName)
    $rawValue = $RegistryKey.GetValue(
      $script:YangMiAutostartRunValueName,
      $null,
      [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
    )
  } catch [System.ArgumentException] {
    return $null
  } catch {
    if (Test-YangMiRegistryKeyDeletedError -Error $_) { return $null }
    throw
  }
  return [pscustomobject][ordered]@{
    Name = $script:YangMiAutostartRunValueName
    Kind = $kind
    RawValue = $rawValue
  }
}

function Test-YangMiRegistryKeyDeletedError {
  param([AllowNull()][object]$Error)
  if ($null -eq $Error) { return $false }
  $exception = if ($Error -is [System.Exception]) {
    $Error
  } elseif ($Error.PSObject.Properties.Name -contains 'Exception' -and $Error.Exception -is [System.Exception]) {
    $Error.Exception
  } else {
    $null
  }
  for ($current = $exception; $null -ne $current; $current = $current.InnerException) {
    if ($current -is [System.IO.IOException] -and @(2, 1018) -contains [int]$current.HResult) { return $true }
  }
  return $false
}

function Test-YangMiAutostartRunValueIdentity {
  param(
    [AllowNull()][object]$Value,
    [Parameter(Mandatory = $true)][string]$PowerShellPath,
    [Parameter(Mandatory = $true)][string]$WatcherPath,
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [AllowNull()][string]$LauncherContent = $null
  )
  if ($null -eq $Value -or
    $Value.PSObject.Properties.Name -notcontains 'Name' -or
    $Value.PSObject.Properties.Name -notcontains 'Kind' -or
    $Value.PSObject.Properties.Name -notcontains 'RawValue' -or
    "$($Value.Name)" -cne $script:YangMiAutostartRunValueName -or
    $Value.Kind -ne [Microsoft.Win32.RegistryValueKind]::String -or
    $Value.RawValue -isnot [string] -or
    $Value.RawValue.Length -gt $script:YangMiAutostartRunMaximumCommandLength) { return $false }
  $definition = New-YangMiAutostartRunDefinition -PowerShellPath $PowerShellPath -WatcherPath $WatcherPath -StateRoot $StateRoot
  if ($Value.RawValue -cne $definition.Command) { return $false }
  if ($definition.Mode -ceq 'launcher') {
    $arguments = @(ConvertFrom-YangMiWindowsCommandLine -CommandLine $Value.RawValue)
    if (-not (Test-YangMiAutostartRunLauncherCommandArguments -Arguments $arguments -PowerShellPath $PowerShellPath -LauncherPath $definition.LauncherPath)) { return $false }
    return Test-YangMiAutostartRunLauncherContentIdentity -Content $LauncherContent -PowerShellPath $PowerShellPath -WatcherPath $WatcherPath -StateRoot $StateRoot
  }
  $arguments = @(ConvertFrom-YangMiWindowsCommandLine -CommandLine $Value.RawValue)
  return Test-YangMiWatcherCommandArguments -Arguments $arguments -PowerShellPath $PowerShellPath -WatcherPath $WatcherPath -StateRoot $StateRoot
}

function Get-YangMiAutostartBackendSelection {
  param(
    [AllowNull()][object]$Task,
    [AllowNull()][object]$RunValue,
    [Parameter(Mandatory = $true)][string]$PowerShellPath,
    [Parameter(Mandatory = $true)][string]$WatcherPath,
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [AllowNull()][string]$LauncherContent = $null
  )
  if ($null -ne $Task) {
    if (Test-YangMiAutostartTaskDefinition -Task $Task -PowerShellPath $PowerShellPath -WatcherPath $WatcherPath -StateRoot $StateRoot) {
      return [pscustomobject][ordered]@{ Backend = 'scheduled-task'; Failure = $null }
    }
    return [pscustomobject][ordered]@{ Backend = $null; Failure = 'scheduled-task-mismatch' }
  }
  if ($null -ne $RunValue) {
    if (Test-YangMiAutostartRunValueIdentity -Value $RunValue -PowerShellPath $PowerShellPath -WatcherPath $WatcherPath -StateRoot $StateRoot -LauncherContent $LauncherContent) {
      return [pscustomobject][ordered]@{ Backend = 'hkcu-run'; Failure = $null }
    }
    return [pscustomobject][ordered]@{ Backend = $null; Failure = 'hkcu-run-mismatch' }
  }
  return [pscustomobject][ordered]@{ Backend = $null; Failure = 'missing' }
}

function Get-YangMiAutostartUninstallPreflight {
  param(
    [AllowNull()][object]$Task,
    [AllowNull()][object]$RunValue,
    [Parameter(Mandatory = $true)][string]$PowerShellPath,
    [Parameter(Mandatory = $true)][string]$WatcherPath,
    [Parameter(Mandatory = $true)][string]$StateRoot,
    [AllowNull()][string]$LauncherContent = $null,
    [switch]$SchedulerDenied
  )
  if ($null -ne $Task -and -not (Test-YangMiAutostartTaskDefinition -Task $Task -PowerShellPath $PowerShellPath -WatcherPath $WatcherPath -StateRoot $StateRoot)) {
    return [pscustomobject][ordered]@{ CanRemove = $false; Failure = 'scheduled-task-mismatch' }
  }
  if ($null -ne $RunValue -and -not (Test-YangMiAutostartRunValueIdentity -Value $RunValue -PowerShellPath $PowerShellPath -WatcherPath $WatcherPath -StateRoot $StateRoot -LauncherContent $LauncherContent)) {
    return [pscustomobject][ordered]@{ CanRemove = $false; Failure = 'hkcu-run-mismatch' }
  }
  if ($SchedulerDenied -and $null -eq $RunValue) {
    return [pscustomobject][ordered]@{ CanRemove = $false; Failure = 'hkcu-run-missing' }
  }
  return [pscustomobject][ordered]@{ CanRemove = $true; Failure = $null }
}

function Test-YangMiAutostartAccessDenied {
  param([Alias('Exception')][AllowNull()][object]$Error)
  if ($null -eq $Error) { return $false }
  $fullyQualifiedErrorId = if ($Error.PSObject.Properties.Name -contains 'FullyQualifiedErrorId') { "$($Error.FullyQualifiedErrorId)" } else { $null }
  if ($fullyQualifiedErrorId -match '^HRESULT 0x(?:80070005|80041003)(?:,|$)') { return $true }
  $exception = if ($Error -is [System.Exception]) {
    $Error
  } elseif ($Error.PSObject.Properties.Name -contains 'Exception' -and $Error.Exception -is [System.Exception]) {
    $Error.Exception
  } else {
    $null
  }
  for ($current = $exception; $null -ne $current; $current = $current.InnerException) {
    if ($current -is [System.UnauthorizedAccessException]) { return $true }
    try {
      if ([int]$current.HResult -in @(-2147024891, -2147217405)) { return $true }
    } catch {}
  }
  return $false
}

function Test-YangMiWatcherCommandArguments {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [Parameter(Mandatory = $true)][string]$PowerShellPath,
    [Parameter(Mandatory = $true)][string]$WatcherPath,
    [Parameter(Mandatory = $true)][string]$StateRoot
  )
  $expected = @(
    $PowerShellPath, '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
    '-File', $WatcherPath, '-StateRoot', $StateRoot
  )
  if ($Arguments.Count -ne $expected.Count) { return $false }
  for ($index = 0; $index -lt $expected.Count; $index++) {
    if ($index -in @(0, 8, 10)) {
      if (-not (Test-DreamSkinPathEqual -Left $Arguments[$index] -Right $expected[$index])) { return $false }
    } elseif ($Arguments[$index] -cne $expected[$index]) { return $false }
  }
  return $true
}

function Test-YangMiAutostartTaskIdentity {
  param(
    [Parameter(Mandatory = $true)][string]$TaskName,
    [Parameter(Mandatory = $true)][object]$TaskAction,
    [Parameter(Mandatory = $true)][object]$TaskPrincipal,
    [Parameter(Mandatory = $true)][string]$PowerShellPath,
    [Parameter(Mandatory = $true)][string]$WatcherPath,
    [Parameter(Mandatory = $true)][string]$StateRoot
  )
  if ($TaskName -cne $script:YangMiAutostartTaskName -or $null -eq $TaskAction -or $null -eq $TaskPrincipal) { return $false }
  $actions = @($TaskAction)
  if ($actions.Count -ne 1 -or -not (Test-DreamSkinPathEqual -Left "$($actions[0].Execute)" -Right $PowerShellPath)) { return $false }
  $expectedAction = New-YangMiAutostartTaskAction -PowerShellPath $PowerShellPath -WatcherPath $WatcherPath -StateRoot $StateRoot
  if ("$($actions[0].Arguments)" -cne $expectedAction.Arguments) { return $false }
  $arguments = @(ConvertFrom-YangMiWindowsCommandLine -CommandLine "`"$PowerShellPath`" $($actions[0].Arguments)")
  if (-not (Test-YangMiWatcherCommandArguments -Arguments $arguments -PowerShellPath $PowerShellPath -WatcherPath $WatcherPath -StateRoot $StateRoot)) { return $false }
  $expectedPrincipal = Get-YangMiAutostartTaskPrincipalIdentity
  return "$($TaskPrincipal.UserId)" -ceq $expectedPrincipal.UserId -and
    "$($TaskPrincipal.LogonType)" -ceq $expectedPrincipal.LogonType -and
    "$($TaskPrincipal.RunLevel)" -ceq $expectedPrincipal.RunLevel
}

function Test-YangMiAutostartTaskDefinition {
  param(
    [Parameter(Mandatory = $true)][object]$Task,
    [Parameter(Mandatory = $true)][string]$PowerShellPath,
    [Parameter(Mandatory = $true)][string]$WatcherPath,
    [Parameter(Mandatory = $true)][string]$StateRoot
  )
  if (-not (Test-YangMiAutostartTaskIdentity -TaskName "$($Task.TaskName)" -TaskAction $Task.Actions -TaskPrincipal $Task.Principal `
    -PowerShellPath $PowerShellPath -WatcherPath $WatcherPath -StateRoot $StateRoot)) { return $false }
  if ($null -eq $Task.Settings -or $Task.Settings.Enabled -isnot [bool] -or -not $Task.Settings.Enabled -or
    "$($Task.Settings.MultipleInstances)" -cne 'IgnoreNew' -or $Task.Settings.StartWhenAvailable -isnot [bool] -or
    -not $Task.Settings.StartWhenAvailable) { return $false }
  $triggers = @($Task.Triggers)
  if ($triggers.Count -ne 1 -or $triggers[0].Enabled -isnot [bool] -or -not $triggers[0].Enabled) { return $false }
  $triggerClass = if ($triggers[0].PSObject.Properties.Name -contains 'CimClass') { "$($triggers[0].CimClass.CimClassName)" } else { $triggers[0].GetType().Name }
  return $triggerClass -match 'Logon' -and "$($triggers[0].UserId)" -ceq (Get-YangMiAutostartTaskPrincipalIdentity).UserId
}

function Test-YangMiWatcherProcessIdentity {
  param(
    [Parameter(Mandatory = $true)][object]$ProcessInfo,
    [Parameter(Mandatory = $true)][int]$ExpectedPid,
    [Parameter(Mandatory = $true)][string]$ExpectedStartedAt,
    [Parameter(Mandatory = $true)][string]$PowerShellPath,
    [Parameter(Mandatory = $true)][string]$WatcherPath,
    [Parameter(Mandatory = $true)][string]$StateRoot
  )
  if (-not (Test-YangMiProcessIdentity -ProcessInfo $ProcessInfo -RuntimeKind powershell -ExpectedPid $ExpectedPid `
    -ExpectedStartedAt $ExpectedStartedAt -ExpectedExecutablePath $PowerShellPath -ScriptPath $WatcherPath `
    -RequiredArguments @{ '-NoProfile' = $null; '-NonInteractive' = $null; '-ExecutionPolicy' = 'Bypass'; '-WindowStyle' = 'Hidden'; '-File' = $WatcherPath; '-StateRoot' = $StateRoot })) { return $false }
  $arguments = @(ConvertFrom-YangMiWindowsCommandLine -CommandLine "$($ProcessInfo.CommandLine)")
  return Test-YangMiWatcherCommandArguments -Arguments $arguments -PowerShellPath $PowerShellPath -WatcherPath $WatcherPath -StateRoot $StateRoot
}

function Stop-YangMiSessionWatcher {
  param([AllowNull()][object]$Session, [Parameter(Mandatory = $true)][string]$WatcherPath, [Parameter(Mandatory = $true)][string]$StateRoot)
  if ($null -eq $Session -or -not $Session.watcherPid) { return $true }
  $processInfo = Get-YangMiProcessInfo -ProcessId ([int]$Session.watcherPid)
  if ($null -eq $processInfo) { return $true }
  if (-not $Session.watcherStartedAt -or -not $Session.watcherScriptPath -or -not $Session.powershellPath -or
    -not (Test-DreamSkinPathEqual -Left $Session.watcherScriptPath -Right $WatcherPath)) { return $false }
  if (-not (Test-YangMiWatcherProcessIdentity -ProcessInfo $processInfo -ExpectedPid ([int]$Session.watcherPid) `
    -ExpectedStartedAt $Session.watcherStartedAt -PowerShellPath $Session.powershellPath -WatcherPath $WatcherPath -StateRoot $StateRoot)) { return $false }
  return Stop-YangMiRecordedProcess -ProcessInfo $processInfo -ExpectedPid ([int]$Session.watcherPid) `
    -ExpectedStartedAt $Session.watcherStartedAt -ExpectedExecutablePath $Session.powershellPath -ScriptPath $WatcherPath `
    -RuntimeKind powershell -RequiredArguments @{ '-NoProfile' = $null; '-NonInteractive' = $null; '-ExecutionPolicy' = 'Bypass'; '-WindowStyle' = 'Hidden'; '-File' = $WatcherPath; '-StateRoot' = $StateRoot }
}
