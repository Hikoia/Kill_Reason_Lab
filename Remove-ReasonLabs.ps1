<#
.SYNOPSIS
    Deep removal of ReasonLabs / RAV Endpoint Protection.

.DESCRIPTION
    Aggregates the complete cleanup procedure compiled from multiple community
    and vendor sources:
      1. Disable and delete scheduled tasks (uses takeown + icacls to break
         inheritance first, avoiding Access Denied)
      2. Force-kill every RAV / rs* process (including kernel-protected ones)
      3. Stop, disable, and delete all ReasonLabs services
      4. Invoke the official Uninstall.exe if it still exists
      5. Force-delete install dirs, ProgramData, and per-user AppData leftovers
      6. Purge registry keys (HKLM / HKCU / WOW6432Node / Uninstall list)
      7. Re-scan and report any remaining artifacts for manual review

    Defaults to DryRun (lists what WOULD be done without touching anything).
    Pass -Execute only after reviewing the dry-run log.

.PARAMETER Execute
    Required to perform real deletions. Without it, the script only simulates.

.PARAMETER LogPath
    Log file path. Defaults to ReasonLabs-Removal-<timestamp>.log next to the script.

.EXAMPLE
    # 1. Preview what will happen (recommended first run):
    .\Remove-ReasonLabs.ps1

    # 2. Actually remove after reviewing the log:
    .\Remove-ReasonLabs.ps1 -Execute

.NOTES
    Must be run as Administrator.
    Recommended before running:
      - Close all browsers and Office apps
      - Booting into Safe Mode works best (RAV's kernel driver does not load there)
    After running, reboot and run -Execute again to clear anything that respawned.
#>

[CmdletBinding()]
param(
    [switch]$Execute,
    [string]$LogPath
)

# Resolve script directory robustly (covers $PSScriptRoot empty, dot-sourcing, ISE, etc.)
$ScriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ScriptDir)) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path -ErrorAction SilentlyContinue
}
if ([string]::IsNullOrWhiteSpace($ScriptDir)) {
    $ScriptDir = (Get-Location).Path
}

if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $LogPath = Join-Path $ScriptDir ("ReasonLabs-Removal-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
}

# ---------- Helpers ----------
function Write-Log {
    param([string]$Msg, [string]$Level = "INFO")
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "HH:mm:ss"), $Level, $Msg
    Write-Host $line -ForegroundColor $(switch ($Level) {
        "ERROR" { "Red" }
        "WARN"  { "Yellow" }
        "OK"    { "Green" }
        "DRY"   { "Cyan" }
        default { "Gray" }
    })
    Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
}

function Invoke-Action {
    param([string]$Description, [scriptblock]$Action)
    if ($Execute) {
        try {
            & $Action
            Write-Log $Description "OK"
        } catch {
            Write-Log "$Description  FAILED: $($_.Exception.Message)" "ERROR"
        }
    } else {
        Write-Log "[DryRun] $Description" "DRY"
    }
}

# ---------- Require Administrator ----------
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Please run PowerShell as Administrator." -ForegroundColor Red
    exit 1
}

Write-Log "=== ReasonLabs deep removal script started ===" "INFO"
Write-Log "Mode: $(if ($Execute) { 'EXECUTE (real deletion)' } else { 'DRY-RUN (simulation only)' })" "WARN"
Write-Log "Log file: $LogPath" "INFO"

# ---------- Target lists (compiled from multiple sources) ----------
$ServiceNames = @(
    'rsEngineSvc',          # Reason Security Engine Service
    'rsClientSvc',
    'rsHelper',
    'rsHelperSvc',
    'RAVBg9Svc',
    'ReasonLabs Update',
    'ReasonLabsUpdate',
    'ReasonLabsVPN',
    'RAVUpdate',
    'EPProtectedService',
    'rsLitmus',
    'rsRemediation'
)

$ProcessNames = @(
    'rsEngineSvc', 'rsClientSvc', 'rsHelper', 'rsAssistant',
    'rsExtensionHost', 'rsLitmus.A', 'rsLitmus.S', 'rsRemediation',
    'rsWSC', 'rsAppUI', 'EPP', 'RAV', 'RAVBg9',
    'ravmond', 'ravapi', 'ravservice', 'ReasonLabs',
    'rsTrayManager', 'rsSyncSvc', 'rsAccountSvc'
)

$Folders = @(
    "$env:ProgramFiles\ReasonLabs",
    "${env:ProgramFiles(x86)}\ReasonLabs",
    "${env:ProgramFiles(x86)}\ReasonLab",
    "$env:ProgramFiles\RAVAntivirus",
    "$env:ProgramData\ReasonLabs",
    "$env:ProgramData\RAVAntivirus",
    "$env:LOCALAPPDATA\ReasonLabs",
    "$env:APPDATA\ReasonLabs"
)

# Add per-user AppData leftovers
Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $Folders += "$($_.FullName)\AppData\Local\ReasonLabs"
    $Folders += "$($_.FullName)\AppData\Roaming\ReasonLabs"
}

$RegistryKeys = @(
    'HKLM:\SOFTWARE\ReasonLabs',
    'HKLM:\SOFTWARE\WOW6432Node\ReasonLabs',
    'HKCU:\SOFTWARE\ReasonLabs',
    'HKLM:\SOFTWARE\Reason Cybersecurity',
    'HKLM:\SOFTWARE\WOW6432Node\Reason Cybersecurity'
)

# ---------- Step 1: Scheduled tasks ----------
Write-Log "" "INFO"
Write-Log "-- Step 1: Removing scheduled tasks --" "INFO"

$tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
    $_.TaskName -match 'Reason|RAV|rsEngine|rsClient|rsHelper' -or
    $_.TaskPath -match 'Reason|RAV'
}

if (-not $tasks) {
    Write-Log "No ReasonLabs/RAV scheduled tasks found." "OK"
} else {
    foreach ($t in $tasks) {
        $fullName = "$($t.TaskPath)$($t.TaskName)"
        Write-Log "Found scheduled task: $fullName" "WARN"

        # Fix the task XML ACL (the Reddit "Disable Inheritance" trick, scripted)
        $taskFile = Join-Path "$env:WINDIR\System32\Tasks" ($fullName.TrimStart('\'))
        if (Test-Path $taskFile) {
            Invoke-Action "Take ownership and reset ACL on $taskFile" {
                & takeown.exe /F $taskFile /A 2>&1 | Out-Null
                & icacls.exe $taskFile /inheritance:d 2>&1 | Out-Null
                & icacls.exe $taskFile /grant Administrators:F /T 2>&1 | Out-Null
            }
        }

        Invoke-Action "Disable scheduled task $fullName" {
            Disable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction Stop | Out-Null
        }
        Invoke-Action "Delete scheduled task $fullName" {
            Unregister-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -Confirm:$false -ErrorAction Stop
        }
    }
}

# ---------- Step 2: Kill processes ----------
Write-Log "" "INFO"
Write-Log "-- Step 2: Force-killing ReasonLabs/RAV processes --" "INFO"

foreach ($p in $ProcessNames) {
    $running = Get-Process -Name $p -ErrorAction SilentlyContinue
    if ($running) {
        Write-Log "Process running: $p (PID=$($running.Id -join ','))" "WARN"
        Invoke-Action "Stop process $p" {
            Stop-Process -Name $p -Force -ErrorAction Stop
        }
    }
}

# ---------- Step 3: Disable + delete services ----------
Write-Log "" "INFO"
Write-Log "-- Step 3: Disabling and deleting services --" "INFO"

foreach ($svc in $ServiceNames) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if (-not $service) { continue }
    Write-Log "Found service: $svc (status $($service.Status))" "WARN"

    Invoke-Action "Stop service $svc" {
        Stop-Service -Name $svc -Force -ErrorAction Stop
    }
    Invoke-Action "Set service $svc to Disabled" {
        Set-Service -Name $svc -StartupType Disabled -ErrorAction Stop
    }
    Invoke-Action "Delete service $svc (sc.exe delete)" {
        $r = & sc.exe delete $svc 2>&1
        if ($LASTEXITCODE -ne 0) { throw $r }
    }
}

# ---------- Step 4: Run official uninstaller if present ----------
Write-Log "" "INFO"
Write-Log "-- Step 4: Trying official Uninstall.exe --" "INFO"

$officialUninstallers = @(
    "$env:ProgramFiles\ReasonLabs\EPP\Uninstall.exe",
    "${env:ProgramFiles(x86)}\ReasonLabs\EPP\Uninstall.exe",
    "$env:ProgramFiles\ReasonLabs\Uninstall.exe"
) | Where-Object { Test-Path $_ }

foreach ($u in $officialUninstallers) {
    Invoke-Action "Run $u /S (silent uninstall)" {
        Start-Process -FilePath $u -ArgumentList '/S' -Wait -ErrorAction Stop
    }
}

# ---------- Step 5: Delete folders ----------
Write-Log "" "INFO"
Write-Log "-- Step 5: Deleting install folders --" "INFO"

foreach ($f in $Folders | Select-Object -Unique) {
    if (-not (Test-Path $f)) { continue }
    Write-Log "Found leftover folder: $f" "WARN"

    Invoke-Action "Take ownership and grant access on $f" {
        & takeown.exe /F $f /R /D Y 2>&1 | Out-Null
        & icacls.exe $f /grant Administrators:F /T /C 2>&1 | Out-Null
    }
    Invoke-Action "Delete folder $f" {
        Remove-Item -Path $f -Recurse -Force -ErrorAction Stop
    }
}

# ---------- Step 6: Clean registry ----------
Write-Log "" "INFO"
Write-Log "-- Step 6: Removing registry keys --" "INFO"

foreach ($k in $RegistryKeys) {
    if (Test-Path $k) {
        Write-Log "Found registry key: $k" "WARN"
        Invoke-Action "Delete $k" {
            Remove-Item -Path $k -Recurse -Force -ErrorAction Stop
        }
    }
}

# Also purge entries in the Uninstall list whose DisplayName matches
$uninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
)
foreach ($root in $uninstallRoots) {
    Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
        $dn = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DisplayName
        if ($dn -match 'RAV|ReasonLabs|Reason Cybersecurity') {
            Write-Log "Found Uninstall entry: $dn @ $($_.PSPath)" "WARN"
            Invoke-Action "Delete Uninstall entry $dn" {
                Remove-Item -Path $_.PSPath -Recurse -Force -ErrorAction Stop
            }
        }
    }
}

# ---------- Step 6.5: Remove UWP / AppX packages ----------
Write-Log "" "INFO"
Write-Log "-- Step 6.5: Removing AppX / UWP packages --" "INFO"

$appxMatch = { $_.Name -match 'ReasonLabs|RAV|Reason' -or $_.Publisher -match 'Reason' }

$installedAppx = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object $appxMatch
if (-not $installedAppx) {
    Write-Log "No installed AppX packages match ReasonLabs/RAV." "OK"
} else {
    foreach ($pkg in $installedAppx) {
        Write-Log "Found AppX: $($pkg.PackageFullName)" "WARN"
        $pfn = $pkg.PackageFullName
        Invoke-Action "Remove-AppxPackage $pfn (-AllUsers)" {
            Remove-AppxPackage -Package $pfn -AllUsers -ErrorAction Stop
        }
    }
}

$provAppxMatch = { $_.DisplayName -match 'ReasonLabs|RAV|Reason' -or $_.PublisherId -match 'Reason' }
$provisionedAppx = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object $provAppxMatch
if (-not $provisionedAppx) {
    Write-Log "No provisioned AppX packages match ReasonLabs/RAV." "OK"
} else {
    foreach ($pkg in $provisionedAppx) {
        Write-Log "Found provisioned AppX: $($pkg.DisplayName) ($($pkg.PackageName))" "WARN"
        $pn = $pkg.PackageName
        Invoke-Action "Remove-AppxProvisionedPackage $pn" {
            Remove-AppxProvisionedPackage -Online -PackageName $pn -ErrorAction Stop | Out-Null
        }
    }
}

# ---------- Step 7: Leftover scan ----------
Write-Log "" "INFO"
Write-Log "-- Step 7: Leftover check --" "INFO"

$leftFolders = $Folders | Where-Object { Test-Path $_ }
$leftServices = $ServiceNames | Where-Object { Get-Service -Name $_ -ErrorAction SilentlyContinue }
$leftTasks    = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
    $_.TaskName -match 'Reason|RAV|rsEngine'
}
$leftKeys = $RegistryKeys | Where-Object { Test-Path $_ }
$leftAppx = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object $appxMatch
$leftProvAppx = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object $provAppxMatch

if ($leftFolders -or $leftServices -or $leftTasks -or $leftKeys -or $leftAppx -or $leftProvAppx) {
    Write-Log "Leftovers detected. Consider rerunning in Safe Mode:" "WARN"
    $leftFolders  | ForEach-Object { Write-Log "  Folder:   $_"  "WARN" }
    $leftServices | ForEach-Object { Write-Log "  Service:  $_"    "WARN" }
    $leftTasks    | ForEach-Object { Write-Log "  Task:     $($_.TaskPath)$($_.TaskName)" "WARN" }
    $leftKeys     | ForEach-Object { Write-Log "  RegKey:   $_"    "WARN" }
    $leftAppx     | ForEach-Object { Write-Log "  AppX:     $($_.PackageFullName)" "WARN" }
    $leftProvAppx | ForEach-Object { Write-Log "  ProvAppX: $($_.DisplayName) ($($_.PackageName))" "WARN" }
} else {
    Write-Log "No ReasonLabs leftovers detected." "OK"
}

Write-Log "" "INFO"
Write-Log "=== Done. Reboot now and rerun with -Execute to confirm clean. ===" "OK"
if (-not $Execute) {
    Write-Host ""
    Write-Host "This was a dry run. Once the log looks correct, rerun:" -ForegroundColor Yellow
    Write-Host "    .\Remove-ReasonLabs.ps1 -Execute" -ForegroundColor Cyan
}
