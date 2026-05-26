# Shadow Defender Bypass

**A PowerShell script that bypasses the Windows 11 24H2 installation block for Shadow Defender.**

---

## Background

Shadow Defender is a lightweight "shadow mode" tool that virtualizes your system drive — every change made while shadow mode is active is discarded on reboot. It's popular for safe browsing, malware testing, and keeping lab machines clean between sessions.

Starting with the **October 2024 Windows cumulative update**, Microsoft added Shadow Defender's official `Setup.exe` to the `apphelp.dll` application compatibility blocklist. This causes Windows to display:

> *"This app can't run on this device — Shadow Defender causes security or performance issues on Windows."*

The block affects **all versions of Windows 10 and 11** patched after October 2024. Shadow Defender itself has not been updated to address this.

---

## How the bypass works

The official installer is a nested package:

```
SD_Setup.exe
 └── Setup_x64.exe   (inner package, also an archive)
      └── setup.exe  (actual installer binary)
```

Windows blocks execution based on the **filename** matched by `apphelp.dll`. By:

1. Extracting the outer package with 7-Zip
2. Extracting the inner `Setup_x64.exe` with 7-Zip
3. Copying the inner `setup.exe` under a different filename
4. Running that renamed copy

...the blocklist check never fires, and installation proceeds normally.

> **Note:** This script does **not** modify, rename, or disable `apphelp.dll` or any system file.

---

## Requirements

| Requirement | Details |
|---|---|
| **OS** | Windows 10 or Windows 11 (any version, including 24H2 / 25H2) |
| **PowerShell** | 5.1 or later (built into Windows) |
| **Internet** | Needed only the first time (to fetch 7-Zip and the installer) |

> Everything else — 7-Zip, the Shadow Defender installer itself, and the Administrator elevation — is handled by the script. **As of v2.0 you do not need to install anything before running it.**

---

## Usage

### Option A — One click (recommended)

1. Download this repo (or just `Install-ShadowDefender.cmd` and `Install-ShadowDefender.ps1`).
2. **Double-click `Install-ShadowDefender.cmd`**.
3. Click **Yes** on the UAC prompt.
4. Complete the Shadow Defender setup wizard when it appears.

That's it. The script will, in order:

- Re-launch itself as Administrator.
- Install 7-Zip silently if it isn't present (via `winget`, or by downloading the official MSI).
- Download `SD1.5.0.726_Setup.exe` from `shadowdefender.com` if it isn't already next to the script.
- Perform the double-extract + rename bypass and launch the installer.
- Clean up every temporary file it created.

### Option B — From PowerShell

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-ShadowDefender.ps1
```

### Option C — Use an installer you already have

If you've already downloaded the Shadow Defender installer, drop the `.exe` next to the script (it will be auto-detected) or pass the path explicitly:

```powershell
.\Install-ShadowDefender.ps1 -InstallerPath "C:\Users\You\Downloads\SD1.5.0.726_Setup.exe"
```

Add `-NoDownload` if you want to make sure the script never reaches the internet for the installer:

```powershell
.\Install-ShadowDefender.ps1 -NoDownload
```

### After installation

Reboot your system. Shadow Defender should appear in your system tray and Start menu.

---

## What the script does — step by step

```
[0]   Self-elevates via UAC if not already Administrator
[0]   Installs 7-Zip (winget or direct MSI) if it isn't present
[0]   Downloads the official installer if no local copy is found
[1/4] Extracts the outer installer  →  finds Setup_x64.exe
[2/4] Extracts Setup_x64.exe        →  finds the real setup.exe inside
[3/4] Copies setup.exe as sdcore_installer.exe  (bypasses the blocklist)
[4/4] Runs sdcore_installer.exe     →  normal installation UI appears
      Cleans up all temp files (and any auto-downloaded installer)
```

---

## Tested on

| Windows Version | Build | Status |
|---|---|---|
| Windows 11 25H2 | 26200.xxxx | Works |
| Windows 11 24H2 | 26100.xxxx | Works |
| Windows 11 23H2 | 22631.xxxx | Works |
| Windows 10 22H2 | 19045.xxxx | Works |

> If you've tested on a version not listed here, please open an issue or PR to update the table.

---

## Known limitations

- Shadow Defender is **abandonware** — it has not been updated since version 1.5.0.726. Use at your own risk on production machines.
- This bypass installs the program, but future Windows updates may re-block it at the driver level.
- Not tested with ARM64 Windows.

---

## Alternatives

If Shadow Defender no longer meets your needs, consider:

| Tool | Description |
|---|---|
| [Sandboxie-Plus](https://github.com/sandboxie-plus/Sandboxie) | Free, open-source, actively maintained sandbox |
| Windows Sandbox | Built into Windows 11 Pro — no install needed |
| Hyper-V / VMware | Full VM for isolated testing |
| Unified Write Filter (UWF) | Built into Windows 11 Enterprise |

---

## Contributing

Pull requests are welcome. If you find a version or build where this stops working, please open an issue with your Windows build number (`winver`) and the exact error message.

---

## Disclaimer

This project is provided for educational and research purposes. Shadow Defender is third-party software; this repository has no affiliation with its developers. You are responsible for complying with your organization's software policies. The bypass technique does not circumvent any security enforcement — it only avoids a compatibility metadata check.

---

## License

MIT — see [LICENSE](LICENSE)
