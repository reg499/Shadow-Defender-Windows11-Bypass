# =============================================================================
#  Install-ShadowDefender.ps1
#  Shadow Defender installer bypass for Windows 11 24H2+
#
#  Problem: Microsoft blacklisted the Shadow Defender Setup.exe via apphelp.dll
#           starting with the October 2024 patch, blocking installation on all
#           Windows 10/11 versions.
#
#  Solution: Double-extract the installer with 7-Zip to reach the inner
#            setup.exe, then run it under a different filename so apphelp.dll
#            cannot match it against the blocklist.
#
#  Usage:
#    1. Place this script in the same folder as your Shadow Defender installer
#    2. Open PowerShell as Administrator
#    3. Set-ExecutionPolicy Bypass -Scope Process -Force
#    4. .\Install-ShadowDefender.ps1
#
#  Or pass the installer path directly:
#    .\Install-ShadowDefender.ps1 -InstallerPath "C:\path\to\SD_Setup.exe"
#
#  Requirements: 7-Zip (https://7-zip.org), Windows PowerShell 5.1+
# =============================================================================

param(
    [string]$InstallerPath = ""
)

# ---- Helpers ----------------------------------------------------------------

function Write-Green($msg)  { Write-Host $msg -ForegroundColor Green }
function Write-Yellow($msg) { Write-Host $msg -ForegroundColor Yellow }
function Write-Red($msg)    { Write-Host $msg -ForegroundColor Red }
function Write-Cyan($msg)   { Write-Host $msg -ForegroundColor Cyan }

function Write-Banner {
    Write-Cyan "--------------------------------------------------"
    Write-Cyan "  Shadow Defender - Windows 11 24H2 Install Bypass"
    Write-Cyan "  github.com/YOUR_USERNAME/sd-bypass"
    Write-Cyan "--------------------------------------------------"
    Write-Host ""
}

function Exit-Script($code) {
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit $code
}

# ---- Main -------------------------------------------------------------------

Write-Banner

# 1. Administrator check
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Red "ERROR: Please run this script as Administrator."
    Write-Yellow "Right-click PowerShell -> 'Run as administrator', then try again."
    Exit-Script 1
}
Write-Green "[OK] Running as Administrator"

# 2. Windows version info
$winVer = [System.Environment]::OSVersion.Version
$buildStr = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuild
Write-Green "[OK] Windows Build: $buildStr"

# 3. Locate 7-Zip
$7zipCandidates = @(
    "C:\Program Files\7-Zip\7z.exe",
    "C:\Program Files (x86)\7-Zip\7z.exe",
    (Get-Command "7z.exe" -ErrorAction SilentlyContinue)?.Source
)
$7zip = $null
foreach ($candidate in $7zipCandidates) {
    if ($candidate -and (Test-Path $candidate)) {
        $7zip = $candidate
        break
    }
}

if (-not $7zip) {
    Write-Red "ERROR: 7-Zip not found."
    Write-Yellow "Download and install 7-Zip from https://7-zip.org, then re-run this script."
    Exit-Script 1
}
Write-Green "[OK] 7-Zip found: $7zip"

# 4. Locate Shadow Defender installer
if (-not $InstallerPath) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $found = Get-ChildItem -Path $scriptDir -Filter "*.exe" |
             Where-Object { $_.Name -match "(?i)(shadow|ShadowDefender|SD\d)" } |
             Select-Object -First 1

    if ($found) {
        $InstallerPath = $found.FullName
        Write-Yellow "Auto-detected installer: $($found.Name)"
        $answer = Read-Host "Use this file? (Y/N)"
        if ($answer -notmatch "^[Yy]") {
            $InstallerPath = ""
        }
    }
}

if (-not $InstallerPath) {
    Write-Yellow "Enter the full path to the Shadow Defender installer:"
    $InstallerPath = (Read-Host "Path").Trim('"').Trim("'")
}

if (-not (Test-Path $InstallerPath)) {
    Write-Red "ERROR: File not found: $InstallerPath"
    Exit-Script 1
}
Write-Green "[OK] Installer: $InstallerPath"

# 5. Create temp working directory
$workDir = Join-Path $env:TEMP ("SD_Bypass_" + (Get-Random).ToString())
New-Item -ItemType Directory -Path $workDir -Force | Out-Null
Write-Green "[OK] Work directory: $workDir"
Write-Host ""

$success = $false

try {
    # Step 1/4 - Extract outer package
    Write-Cyan "[1/4] Extracting outer installer package..."
    $step1Dir = Join-Path $workDir "outer"
    New-Item -ItemType Directory -Path $step1Dir -Force | Out-Null
    & $7zip x "$InstallerPath" -o"$step1Dir" -y | Out-Null

    $innerSetup = Get-ChildItem -Path $step1Dir -Filter "Setup_x64.exe" | Select-Object -First 1
    if (-not $innerSetup) {
        $innerSetup = Get-ChildItem -Path $step1Dir -Filter "Setup_x86.exe" | Select-Object -First 1
    }
    if (-not $innerSetup) {
        Write-Red "ERROR: Could not find Setup_x64.exe inside the installer package."
        Write-Yellow "Make sure you are using an official Shadow Defender installer (e.g. SD1.5.0.726_Setup.exe)."
        Exit-Script 1
    }
    Write-Green "      Found inner package: $($innerSetup.Name)"

    # Step 2/4 - Extract inner package
    Write-Cyan "[2/4] Extracting inner installer package..."
    $step2Dir = Join-Path $workDir "inner"
    New-Item -ItemType Directory -Path $step2Dir -Force | Out-Null
    & $7zip x "$($innerSetup.FullName)" -o"$step2Dir" -y | Out-Null

    $setupExe = Get-ChildItem -Path $step2Dir -Filter "setup.exe" | Select-Object -First 1
    if (-not $setupExe) {
        $setupExe = Get-ChildItem -Path $step2Dir -Recurse -Filter "*.exe" | Select-Object -First 1
    }
    if (-not $setupExe) {
        Write-Red "ERROR: Could not find setup.exe in the inner package."
        Exit-Script 1
    }
    Write-Green "      Found inner setup: $($setupExe.Name)"

    # Step 3/4 - Rename to bypass blacklist
    Write-Cyan "[3/4] Renaming executable to bypass apphelp.dll blocklist..."
    $bypassExe = Join-Path $step2Dir "sdcore_installer.exe"
    Copy-Item -Path $setupExe.FullName -Destination $bypassExe -Force
    Write-Green "      Renamed to: sdcore_installer.exe"

    # Step 4/4 - Run installer
    Write-Cyan "[4/4] Launching installer..."
    Write-Yellow "      The installer window will open. Complete the setup normally."
    Write-Yellow "      Do NOT close this PowerShell window until installation finishes."
    Write-Host ""

    $proc = Start-Process -FilePath $bypassExe -WorkingDirectory $step2Dir -PassThru -Wait

    Write-Host ""
    if ($proc.ExitCode -eq 0) {
        Write-Green "[OK] Installation completed successfully. (Exit code: 0)"
        $success = $true
    } else {
        Write-Yellow "[??] Installer exited with code: $($proc.ExitCode)"
        Write-Yellow "     If the Shadow Defender UI appeared and you completed setup, this is likely fine."
        $success = $true
    }
}
catch {
    Write-Red "UNEXPECTED ERROR: $_"
}
finally {
    Write-Host ""
    Write-Cyan "Cleaning up temporary files..."
    Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Green "[OK] Cleanup done."
}

Write-Host ""
Write-Cyan "--------------------------------------------------"
if ($success) {
    Write-Green "  Done! Reboot your system to activate Shadow Defender."
} else {
    Write-Red "  Something went wrong. See the errors above."
    Write-Yellow "  Open an issue at: github.com/YOUR_USERNAME/sd-bypass"
}
Write-Cyan "--------------------------------------------------"
Write-Host ""
Exit-Script 0
