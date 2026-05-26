# Changelog

All notable changes to this project will be documented here.

## [2.0.0] - 2026-05-26

### Added
- **Self-elevation**: script now requests UAC automatically — no need to open PowerShell as Administrator first.
- **Automatic 7-Zip installation**: if 7-Zip is missing, the script installs it via `winget` and falls back to a silent MSI download from 7-zip.org.
- **Automatic Shadow Defender download**: if no installer is found in the script's folder, `SD1.5.0.726_Setup.exe` is downloaded from the official site (`shadowdefender.com`).
- `Install-ShadowDefender.cmd` companion launcher — double-click to run, no PowerShell knowledge required.
- `-NoDownload` switch to disable auto-download (only use local installers).
- TLS 1.2 is now explicitly enabled for downloads (fixes failures on older Windows 10 builds).
- Auto-downloaded installers are cleaned up after a successful run.

### Changed
- Banner now shows `v2.0.0 - Fully Automated`.
- README rewritten around the one-step "double-click and go" workflow.

## [1.0.0] - 2025-05-26

### Added
- Initial release
- Double-extraction bypass for `apphelp.dll` blocklist
- Auto-detection of installer in the same directory
- `-InstallerPath` parameter for manual path input
- 7-Zip presence check with helpful error message
- Administrator privilege check
- Automatic cleanup of temp files
- Tested on Windows 11 24H2, 23H2 and Windows 10 22H2
