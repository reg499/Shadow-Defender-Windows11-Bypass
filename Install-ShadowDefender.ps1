# =============================================================================
#  Install-ShadowDefender.ps1                                            v2.0.0
#  Shadow Defender installer bypass for Windows 11 24H2+
#
#  v2.0 - Fully automated. The user only has to run the script. It will:
#    * Self-elevate to Administrator (UAC prompt)
#    * Install 7-Zip if missing (winget, with direct-MSI fallback)
#    * Download the official Shadow Defender installer if not present
#    * Double-extract and rename to bypass the apphelp.dll blocklist
#    * Run the installer and clean up after itself
#
#  Problem: Microsoft blacklisted the Shadow Defender Setup.exe via apphelp.dll
#           starting with the October 2024 cumulative update, blocking
#           installation on all Windows 10/11 versions.
#
#  Solution: Double-extract the installer with 7-Zip to reach the inner
#            setup.exe, then run it under a different filename so apphelp.dll
#            cannot match it against the blocklist.
#
#  Usage (recommended):
#    Right-click Install-ShadowDefender.cmd -> Run
#    or
#    powershell -ExecutionPolicy Bypass -File .\Install-ShadowDefender.ps1
#
#  Optional parameters:
#    -InstallerPath  Use a specific installer file (skip auto-download).
#    -NoDownload     Don't download; fail if no local installer is found.
#
#  Requirements: Windows PowerShell 5.1+ (built into Windows 10/11).
# =============================================================================

[CmdletBinding()]
param(
    [string]$InstallerPath = "",
    [switch]$NoDownload
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'  # Massively speeds up Invoke-WebRequest

# Force TLS 1.2 - older Windows 10 PS 5.1 defaults to TLS 1.0/1.1 which modern
# HTTPS endpoints (including 7-zip.org and shadowdefender.com) reject.
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

# ---- Helpers ----------------------------------------------------------------

function Write-Green ($msg) { Write-Host $msg -ForegroundColor Green  }
function Write-Yellow($msg) { Write-Host $msg -ForegroundColor Yellow }
function Write-Red   ($msg) { Write-Host $msg -ForegroundColor Red    }
function Write-Cyan  ($msg) { Write-Host $msg -ForegroundColor Cyan   }

function Write-Banner {
    Write-Cyan "--------------------------------------------------"
    Write-Cyan "  Shadow Defender - Windows 11 24H2 Install Bypass"
    Write-Cyan "  v2.0.0 - Fully Automated"
    Write-Cyan "--------------------------------------------------"
    Write-Host ""
}

function Exit-Script($code) {
    Write-Host ""
    try { Read-Host "Press Enter to exit" | Out-Null } catch { }
    exit $code
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

# ---- 1. Self-elevate -------------------------------------------------------

if (-not (Test-IsAdmin)) {
    Write-Yellow "Administrator privileges required. Requesting UAC elevation..."

    $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
    if (-not $scriptPath) {
        Write-Red "ERROR: Could not determine script path for self-elevation."
        Read-Host "Press Enter to exit" | Out-Null
        exit 1
    }

    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$scriptPath`"")
    if ($InstallerPath) { $argList += @('-InstallerPath', "`"$InstallerPath`"") }
    if ($NoDownload)    { $argList += '-NoDownload' }

    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs | Out-Null
    } catch {
        Write-Red "UAC prompt was declined or failed: $_"
        Read-Host "Press Enter to exit" | Out-Null
        exit 1
    }
    exit 0
}

# ---- Now running elevated ---------------------------------------------------

Write-Banner
Write-Green "[OK] Running as Administrator"

$buildStr = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuild
Write-Green "[OK] Windows Build: $buildStr"

# ---- 2. Ensure 7-Zip is installed ------------------------------------------

function Find-7Zip {
    $candidates = @(
        "$env:ProgramFiles\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
    )
    $cmd = Get-Command '7z.exe' -ErrorAction SilentlyContinue
    if ($cmd) { $candidates += $cmd.Source }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    return $null
}

function Install-7ZipViaWinget {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) { return $false }
    Write-Yellow "      Trying winget..."
    try {
        $proc = Start-Process -FilePath 'winget' -ArgumentList @(
            'install','--id','7zip.7zip','-e','--silent',
            '--accept-package-agreements','--accept-source-agreements'
        ) -Wait -PassThru -NoNewWindow
        return ($proc.ExitCode -eq 0)
    } catch { return $false }
}

function Get-7ZipMsiUrl {
    try {
        $html = Invoke-WebRequest -Uri 'https://www.7-zip.org/download.html' -UseBasicParsing
        # Match the latest x64 MSI link, e.g. a/7z2409-x64.msi
        $match = [regex]::Match($html.Content, 'href="(a/7z[\d.]+-x64\.msi)"')
        if ($match.Success) { return 'https://www.7-zip.org/' + $match.Groups[1].Value }
    } catch { }
    return $null
}

function Install-7ZipDirect {
    $url = Get-7ZipMsiUrl
    if (-not $url) {
        Write-Red "      Could not locate 7-Zip MSI download URL on 7-zip.org."
        return $false
    }
    $msi = Join-Path $env:TEMP '7zip-setup.msi'
    Write-Yellow "      Downloading: $url"
    try {
        Invoke-WebRequest -Uri $url -OutFile $msi -UseBasicParsing
    } catch {
        Write-Red "      Download failed: $_"
        return $false
    }
    Write-Yellow "      Installing silently via msiexec..."
    $proc = Start-Process -FilePath 'msiexec.exe' `
        -ArgumentList @('/i', "`"$msi`"", '/qn', '/norestart') -Wait -PassThru
    Remove-Item $msi -Force -ErrorAction SilentlyContinue
    return ($proc.ExitCode -eq 0)
}

$7zip = Find-7Zip
if (-not $7zip) {
    Write-Yellow "[!]  7-Zip not found - installing automatically..."
    $ok = Install-7ZipViaWinget
    if (-not $ok) {
        Write-Yellow "      winget unavailable or failed, falling back to direct download..."
        $ok = Install-7ZipDirect
    }
    if (-not $ok) {
        Write-Red "ERROR: Could not install 7-Zip automatically."
        Write-Yellow "       Please install it manually from https://7-zip.org and re-run this script."
        Exit-Script 1
    }
    $7zip = Find-7Zip
    if (-not $7zip) {
        Write-Red "ERROR: 7-Zip was installed but the executable could not be found."
        Write-Yellow "       Restart PowerShell and try again."
        Exit-Script 1
    }
}
Write-Green "[OK] 7-Zip: $7zip"

# ---- 3. Locate or download the Shadow Defender installer -------------------

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}

function Find-LocalInstaller {
    Get-ChildItem -Path $scriptDir -Filter '*.exe' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(?i)(shadow|SD\d|SD_Setup)' } |
        Select-Object -First 1
}

function Get-ShadowDefenderInstaller {
    # Official installer URL - stable since 2014, last version is 1.5.0.726.
    $url = 'https://www.shadowdefender.com/sd/SD1.5.0.726_Setup.exe'
    $dst = Join-Path $env:TEMP 'SD1.5.0.726_Setup.exe'

    Write-Yellow "      Downloading: $url"
    try {
        Invoke-WebRequest -Uri $url -OutFile $dst -UseBasicParsing -UserAgent 'Mozilla/5.0'
    } catch {
        Write-Red "      Download failed: $_"
        return $null
    }

    # Sanity check - the real installer is ~5 MB. A tiny file means we got
    # a redirect/error page instead.
    if (-not (Test-Path $dst) -or (Get-Item $dst).Length -lt 1MB) {
        Write-Red "      Downloaded file looks invalid (too small)."
        Remove-Item $dst -Force -ErrorAction SilentlyContinue
        return $null
    }
    return $dst
}

$installerWasDownloaded = $false

if (-not $InstallerPath) {
    $local = Find-LocalInstaller
    if ($local) {
        $InstallerPath = $local.FullName
        Write-Green "[OK] Found local installer: $($local.Name)"
    }
    elseif (-not $NoDownload) {
        Write-Yellow "[!]  No local installer found - downloading from shadowdefender.com..."
        $InstallerPath = Get-ShadowDefenderInstaller
        if (-not $InstallerPath) {
            Write-Red "ERROR: Could not download Shadow Defender automatically."
            Write-Yellow "       Download SD1.5.0.726_Setup.exe manually from"
            Write-Yellow "       https://www.shadowdefender.com, place it next to this script,"
            Write-Yellow "       and re-run."
            Exit-Script 1
        }
        $installerWasDownloaded = $true
        Write-Green "[OK] Downloaded to: $InstallerPath"
    }
    else {
        Write-Red "ERROR: No installer found and -NoDownload was specified."
        Exit-Script 1
    }
}

if (-not (Test-Path $InstallerPath)) {
    Write-Red "ERROR: File not found: $InstallerPath"
    Exit-Script 1
}
Write-Green "[OK] Installer: $InstallerPath"

# ---- 4. Work directory -----------------------------------------------------

$workDir = Join-Path $env:TEMP ('SD_Bypass_' + (Get-Random).ToString())
New-Item -ItemType Directory -Path $workDir -Force | Out-Null
Write-Green "[OK] Work directory: $workDir"
Write-Host ""

$success = $false

try {
    # Step 1/4 - Extract outer package
    Write-Cyan "[1/4] Extracting outer installer package..."
    $step1Dir = Join-Path $workDir 'outer'
    New-Item -ItemType Directory -Path $step1Dir -Force | Out-Null
    & $7zip x "$InstallerPath" -o"$step1Dir" -y | Out-Null

    $innerSetup = Get-ChildItem -Path $step1Dir -Filter 'Setup_x64.exe' | Select-Object -First 1
    if (-not $innerSetup) {
        $innerSetup = Get-ChildItem -Path $step1Dir -Filter 'Setup_x86.exe' | Select-Object -First 1
    }
    if (-not $innerSetup) {
        Write-Red "ERROR: Could not find Setup_x64.exe inside the installer package."
        Write-Yellow "       Make sure you are using an official Shadow Defender installer"
        Write-Yellow "       (e.g. SD1.5.0.726_Setup.exe)."
        Exit-Script 1
    }
    Write-Green "      Found inner package: $($innerSetup.Name)"

    # Step 2/4 - Extract inner package
    Write-Cyan "[2/4] Extracting inner installer package..."
    $step2Dir = Join-Path $workDir 'inner'
    New-Item -ItemType Directory -Path $step2Dir -Force | Out-Null
    & $7zip x "$($innerSetup.FullName)" -o"$step2Dir" -y | Out-Null

    $setupExe = Get-ChildItem -Path $step2Dir -Filter 'setup.exe' | Select-Object -First 1
    if (-not $setupExe) {
        $setupExe = Get-ChildItem -Path $step2Dir -Recurse -Filter '*.exe' | Select-Object -First 1
    }
    if (-not $setupExe) {
        Write-Red "ERROR: Could not find setup.exe in the inner package."
        Exit-Script 1
    }
    Write-Green "      Found inner setup: $($setupExe.Name)"

    # Step 3/4 - Rename to bypass blacklist
    Write-Cyan "[3/4] Renaming executable to bypass apphelp.dll blocklist..."
    $bypassExe = Join-Path $step2Dir 'sdcore_installer.exe'
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
    } else {
        Write-Yellow "[??] Installer exited with code: $($proc.ExitCode)"
        Write-Yellow "     If the Shadow Defender UI appeared and you completed setup, this is likely fine."
    }
    $success = $true
}
catch {
    Write-Red "UNEXPECTED ERROR: $_"
}
finally {
    Write-Host ""
    Write-Cyan "Cleaning up temporary files..."
    Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
    if ($installerWasDownloaded -and $InstallerPath -and (Test-Path $InstallerPath)) {
        Remove-Item -Path $InstallerPath -Force -ErrorAction SilentlyContinue
    }
    Write-Green "[OK] Cleanup done."
}

Write-Host ""
Write-Cyan "--------------------------------------------------"
if ($success) {
    Write-Green "  Done! Reboot your system to activate Shadow Defender."
} else {
    Write-Red   "  Something went wrong. See the errors above."
}
Write-Cyan "--------------------------------------------------"
Write-Host ""
Exit-Script 0
