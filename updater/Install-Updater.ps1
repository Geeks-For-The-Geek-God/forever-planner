<#
  Forever Planner updater: one-time setup.
  1. Finds your WoW Forever AddOns folder (or asks for it).
  2. Copies the updater to %LOCALAPPDATA%\ForeverPlanner.
  3. Creates a scheduled task that checks for updates every 3 hours, and soon after you
     log in. It runs hidden, needs no admin rights, and only ever writes the
     Interface\AddOns\ForeverPlanner folder.
  4. Runs one update check straight away.
#>
$ErrorActionPreference = 'Stop'
$TaskName = 'Forever Planner updater'
$AddonName = 'ForeverPlanner'
$DataDir = Join-Path $env:LOCALAPPDATA 'ForeverPlanner'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Say([string]$Text, [string]$Color = 'Gray') { Write-Host $Text -ForegroundColor $Color }

function Test-AddOnsFolder([string]$Path) {
  return ($Path -and (Test-Path -LiteralPath $Path -PathType Container) -and ((Split-Path -Leaf $Path) -eq 'AddOns'))
}

function Find-AddOnsFolder {
  $roots = New-Object System.Collections.Generic.List[string]
  foreach ($key in 'HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft',
                   'HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft') {
    try {
      $p = (Get-ItemProperty -Path $key -ErrorAction Stop).InstallPath
      if ($p) { $roots.Add((Split-Path -Parent ($p.TrimEnd('\')))) }   # InstallPath points at a flavour folder
    } catch {}
  }
  foreach ($drive in Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue) {
    foreach ($sub in 'Program Files (x86)\World of Warcraft', 'Program Files\World of Warcraft', 'World of Warcraft',
                     'Games\World of Warcraft', 'Battle.net\World of Warcraft', 'Blizzard\World of Warcraft') {
      $roots.Add((Join-Path $drive.Root $sub))
    }
  }
  $found = New-Object System.Collections.Generic.List[string]
  foreach ($root in ($roots | Select-Object -Unique)) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    $forever = Join-Path $root '_forever_\Interface\AddOns'
    if (Test-Path -LiteralPath $forever) { $found.Add($forever) }
    # Any other flavour folder that already holds Forever Planner.
    foreach ($flavour in Get-ChildItem -LiteralPath $root -Directory -Filter '_*_' -ErrorAction SilentlyContinue) {
      $a = Join-Path $flavour.FullName 'Interface\AddOns'
      if ((Test-Path -LiteralPath (Join-Path $a "$AddonName\$AddonName.toc")) -and -not $found.Contains($a)) { $found.Add($a) }
    }
  }
  return $found
}

try {
  Say ''
  Say 'Forever Planner updater setup' 'Cyan'
  Say '-----------------------------' 'Cyan'

  # 1. AddOns folder
  $candidates = @(Find-AddOnsFolder)
  $addOns = $null
  if ($candidates.Count -eq 1) {
    $addOns = $candidates[0]
    Say "Found your AddOns folder: $addOns"
    $ok = Read-Host 'Is this your WoW Forever AddOns folder? (Y/N)'
    if ($ok -notmatch '^[Yy]') { $addOns = $null }
  } elseif ($candidates.Count -gt 1) {
    Say 'Found more than one AddOns folder:'
    for ($i = 0; $i -lt $candidates.Count; $i++) { Say ("  {0}. {1}" -f ($i + 1), $candidates[$i]) }
    $pick = Read-Host 'Type the number of your WoW Forever one (or press Enter to type a path)'
    if ($pick -match '^\d+$' -and [int]$pick -ge 1 -and [int]$pick -le $candidates.Count) { $addOns = $candidates[[int]$pick - 1] }
  }
  while (-not (Test-AddOnsFolder $addOns)) {
    Say ''
    Say 'Please paste the full path of your WoW Forever AddOns folder.' 'Yellow'
    Say 'It ends in \Interface\AddOns and is the folder that holds Questie and ForeverPlanner.'
    Say 'Example: C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns'
    $addOns = (Read-Host 'AddOns folder').Trim().Trim('"')
    if (-not (Test-AddOnsFolder $addOns)) { Say "That folder doesn't exist or doesn't end in AddOns. Try again." 'Red' }
  }

  # Check we can write there without admin rights.
  $probe = Join-Path $addOns ('.fp-write-test-' + [guid]::NewGuid().ToString('N'))
  try { New-Item -ItemType File -Path $probe -Force | Out-Null; Remove-Item -LiteralPath $probe -Force }
  catch { throw "Windows won't let this account write to $addOns. Tell Claude this message." }

  # 2. Copy the updater and save the folder
  if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir | Out-Null }
  Copy-Item -Path (Join-Path $Here 'Update-ForeverPlanner.ps1') -Destination $DataDir -Force
  Copy-Item -Path (Join-Path $Here 'Update-Now.cmd') -Destination $DataDir -Force
  @{ AddOnsPath = $addOns } | ConvertTo-Json | Set-Content -Path (Join-Path $DataDir 'config.json') -Encoding UTF8
  Get-ChildItem -Path $DataDir -File | Unblock-File -ErrorAction SilentlyContinue
  $script = Join-Path $DataDir 'Update-ForeverPlanner.ps1'
  Say "Updater copied to $DataDir"

  # 3. Scheduled task: hidden (conhost --headless), every 3 hours, catches up after sleep or logon.
  $psArgs = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$script`""
  $hidden = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument "--headless powershell.exe $psArgs"
  $fallback = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-WindowStyle Hidden $psArgs"
  $repeat = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(5)) -RepetitionInterval (New-TimeSpan -Hours 3) -RepetitionDuration (New-TimeSpan -Days 3650)
  $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -MultipleInstances IgnoreNew
  $desc = 'Checks GitHub for a new Forever Planner release and installs it into your WoW Forever AddOns folder.'

  function Register-Updater($Action) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    try {
      $logon = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
      $logon.Delay = 'PT2M'
      Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger @($repeat, $logon) -Settings $settings -Description $desc | Out-Null
    } catch {
      # Some PCs need admin rights for a logon trigger; the 3-hourly check still catches up after logon.
      Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $repeat -Settings $settings -Description $desc | Out-Null
    }
  }

  function Test-TaskRun {
    $log = Join-Path $DataDir 'updater.log'
    $before = if (Test-Path $log) { (Get-Item $log).LastWriteTime } else { [datetime]::MinValue }
    Start-ScheduledTask -TaskName $TaskName
    for ($i = 0; $i -lt 45; $i++) {
      Start-Sleep -Seconds 1
      if ((Test-Path $log) -and (Get-Item $log).LastWriteTime -gt $before) { return $true }
    }
    return $false
  }

  Say 'Creating the scheduled task and running a first check...'
  Register-Updater $hidden
  $ran = Test-TaskRun
  if (-not $ran) {
    Register-Updater $fallback
    $ran = Test-TaskRun
  }
  if (-not $ran) { throw "The scheduled task didn't run. Tell Claude this message." }

  Say ''
  Say 'Done. Last update check:' 'Green'
  Get-Content -Path (Join-Path $DataDir 'updater.log') -Tail 1 | ForEach-Object { Say "  $_" 'Green' }
  Say ''
  Say 'From now on Forever Planner updates itself every few hours. When one lands while'
  Say 'you are playing, type /reload. To check right now, double-click Update-Now.cmd in'
  Say "$DataDir"
}
catch {
  Say ''
  Say "Setup stopped: $($_.Exception.Message)" 'Red'
}
Say ''
Read-Host 'Press Enter to close'
