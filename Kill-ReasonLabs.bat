@echo off
REM =====================================================
REM  ReasonLabs Removal Tool - double-click launcher
REM  (auto-elevates to Administrator via PowerShell)
REM =====================================================

setlocal EnableDelayedExpansion

REM ---- Reliable Administrator check (fltmc works on every Windows SKU) ----
fltmc >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo Administrator privileges required. Relaunching elevated...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

REM ---- Move into the script's own folder ----
cd /d "%~dp0"

REM ---- Verify the PS1 actually exists ----
if not exist "%~dp0Remove-ReasonLabs.ps1" (
    echo ERROR: Remove-ReasonLabs.ps1 not found next to this .bat
    echo Expected at: %~dp0Remove-ReasonLabs.ps1
    pause
    exit /b 1
)

:menu
cls
echo.
echo ========================================
echo   ReasonLabs / RAV Endpoint Protection
echo   Deep Removal Tool
echo ========================================
echo.
echo Working dir : %CD%
echo Script path : %~dp0Remove-ReasonLabs.ps1
echo.
echo Mode:
echo   [1] DryRun  - simulate only, no deletion (run this first)
echo   [2] Execute - actually delete
echo   [Q] Quit
echo.

set "mode="
set /p "mode=Enter choice (1/2/Q): "

if /i "!mode!"=="Q" goto :end
if /i "!mode!"=="1" goto :dryrun
if /i "!mode!"=="2" goto :execute

echo.
echo Invalid choice: [!mode!]
pause
goto :menu

:dryrun
echo.
echo Running DryRun...
echo --------------------------------------------------
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Remove-ReasonLabs.ps1"
echo --------------------------------------------------
echo DryRun finished. Exit code: %errorlevel%
echo.
pause
goto :menu

:execute
echo.
echo *** WARNING: this will actually delete system files! ***
set "confirm="
set /p "confirm=Confirm real deletion? (y/yes to proceed, anything else to cancel): "
if /i "!confirm!"=="y"   goto :doexecute
if /i "!confirm!"=="yes" goto :doexecute
echo Cancelled.
pause
goto :menu

:doexecute
echo.
echo Running Execute mode...
echo --------------------------------------------------
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Remove-ReasonLabs.ps1" -Execute
echo --------------------------------------------------
echo Execute finished. Exit code: %errorlevel%
echo.
pause
goto :menu

:end
echo Bye.
timeout /t 2 >nul
endlocal
exit /b 0
