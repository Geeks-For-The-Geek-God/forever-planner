<#
  Forever Planner updater.
  Checks GitHub for the newest Forever Planner release and, if it is newer than the
  copy in your AddOns folder, installs it. Your progress lives in WTF\SavedVariables,
  which this script never touches. In game, /reload picks up the new version.

  Run by the "Forever Planner updater" scheduled task, or by double-clicking Update-Now.cmd.
#>
[CmdletBinding()]
param(
  [string]$AddOnsPath,                 # overrides the path saved by the installer
  [string]$DataDir = $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'ForeverPlanner' } else { Join-Path $HOME '.foreverplanner' }),
  [string]$Repo = 'Geeks-For-The-Geek-God/forever-planner',
  [switch]$Force                       # reinstall even if already up to date
)

$ErrorActionPreference = 'Stop'
$AddonName = 'ForeverPlanner'
if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir -Force | Out-Null }
$LogFile = Join-Path $DataDir 'updater.log'

function Write-Log([string]$Message) {
  $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
  Add-Content -Path $LogFile -Value $line -Encoding UTF8
  Write-Host $line
}

function Get-TocVersion([string]$TocPath) {
  if (-not (Test-Path $TocPath)) { return $null }
  foreach ($line in Get-Content -Path $TocPath -Encoding UTF8) {
    if ($line -match '^##\s*Version:\s*(\S+)') { return $Matches[1] }
  }
  return $null
}

function ConvertTo-Version([string]$Text) {
  $v = $null
  if ($Text -and [version]::TryParse(($Text -replace '^v', ''), [ref]$v)) { return $v }
  return $null
}

# Keep the log short: last 300 lines.
if (Test-Path $LogFile) {
  $old = Get-Content -Path $LogFile -Encoding UTF8
  if ($old.Count -gt 300) { $old | Select-Object -Last 300 | Set-Content -Path $LogFile -Encoding UTF8 }
}

$work = $null
try {
  if (-not $AddOnsPath) {
    $configFile = Join-Path $DataDir 'config.json'
    if (-not (Test-Path $configFile)) { throw "No AddOns folder configured. Run Install.cmd again." }
    $AddOnsPath = (Get-Content -Path $configFile -Raw -Encoding UTF8 | ConvertFrom-Json).AddOnsPath
  }
  if (-not (Test-Path $AddOnsPath)) { throw "AddOns folder not found: $AddOnsPath" }

  $target = Join-Path $AddOnsPath $AddonName
  $installed = Get-TocVersion (Join-Path $target "$AddonName.toc")

  # Ask GitHub for the newest release (public repository, no sign-in needed).
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  $headers = @{ 'User-Agent' = 'ForeverPlanner-Updater'; 'Accept' = 'application/vnd.github+json' }
  $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers $headers -TimeoutSec 30
  $latest = $release.tag_name -replace '^v', ''

  $vLatest = ConvertTo-Version $latest
  $vInstalled = ConvertTo-Version $installed
  if (-not $vLatest) { throw "Couldn't read the release version '$($release.tag_name)'." }
  if (-not $Force -and $vInstalled -and $vInstalled -ge $vLatest) {
    Write-Log "Up to date ($installed)."
    exit 0
  }

  $asset = $release.assets | Where-Object { $_.name -like "$AddonName-*.zip" } | Select-Object -First 1
  if (-not $asset) { throw "Release $($release.tag_name) has no $AddonName zip." }

  # Download and unpack into a private temp folder.
  $work = Join-Path ([IO.Path]::GetTempPath()) ("fp-update-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $work | Out-Null
  $zip = Join-Path $work $asset.name
  Invoke-WebRequest -Uri $asset.browser_download_url -Headers @{ 'User-Agent' = 'ForeverPlanner-Updater' } -OutFile $zip -UseBasicParsing -TimeoutSec 120

  # Integrity check: GitHub publishes a SHA-256 for each release file.
  if ($asset.digest -and $asset.digest -like 'sha256:*') {
    $expected = $asset.digest.Substring(7).ToLowerInvariant()
    $actual = (Get-FileHash -Path $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($expected -ne $actual) { throw "Download check failed (SHA-256 mismatch). Nothing was changed." }
  }

  $unpacked = Join-Path $work 'unpacked'
  Expand-Archive -Path $zip -DestinationPath $unpacked -Force
  $newAddon = Join-Path $unpacked $AddonName
  $newVersion = Get-TocVersion (Join-Path $newAddon "$AddonName.toc")
  if (-not $newVersion) { throw "The download doesn't contain $AddonName\$AddonName.toc. Nothing was changed." }

  # Swap folders, keeping a backup outside AddOns so the game never sees it.
  $backupRoot = Join-Path $DataDir 'backup'
  $backup = Join-Path $backupRoot $AddonName
  if (Test-Path $target) {
    if (Test-Path $backupRoot) { Remove-Item -Path $backupRoot -Recurse -Force }
    New-Item -ItemType Directory -Path $backupRoot | Out-Null
    Copy-Item -Path $target -Destination $backupRoot -Recurse -Force
  }
  try {
    if (Test-Path $target) { Remove-Item -Path $target -Recurse -Force }
    Copy-Item -Path $newAddon -Destination $AddOnsPath -Recurse -Force
    if ((Get-TocVersion (Join-Path $target "$AddonName.toc")) -ne $newVersion) { throw "Copy didn't complete." }
  } catch {
    if (Test-Path $backup) {
      if (Test-Path $target) { Remove-Item -Path $target -Recurse -Force -ErrorAction SilentlyContinue }
      Copy-Item -Path $backup -Destination $AddOnsPath -Recurse -Force
      throw "Install failed and the previous version was restored: $($_.Exception.Message)"
    }
    throw
  }

  $from = if ($installed) { $installed } else { 'not installed' }
  Write-Log "Updated Forever Planner: $from -> $newVersion. Type /reload in game."
  exit 0
}
catch {
  Write-Log "ERROR: $($_.Exception.Message)"
  exit 1
}
finally {
  if ($work -and (Test-Path $work)) { Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue }
}
