@echo off
REM ============================================================================
REM  Install-ShadowDefender.cmd
REM  Double-click launcher for Install-ShadowDefender.ps1.
REM  Bypasses the PowerShell execution policy without modifying it system-wide.
REM  The PowerShell script handles UAC elevation itself.
REM ============================================================================

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-ShadowDefender.ps1" %*
