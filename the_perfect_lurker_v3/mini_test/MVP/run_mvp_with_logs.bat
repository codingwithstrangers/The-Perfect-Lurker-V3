@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem MVP launcher:
rem - If no argument is provided, auto-select the newest EXE in this MVP folder.
rem - Validate matching .pck sidecar for that EXE.
rem - Delegate execution + tee logging to ..\run_with_logs.bat.

set "SCRIPT_DIR=%~dp0"
set "RUNNER=%SCRIPT_DIR%..\run_with_logs.bat"

if not exist "%RUNNER%" (
    echo Could not find runner: %RUNNER%
    pause
    exit /b 1
)

if "%~1"=="" (
    rem Find newest EXE by last-modified time.
    set "DEFAULT_EXE="
    for /f "delims=" %%F in ('dir /b /a:-d /o-d "%SCRIPT_DIR%*.exe" 2^>nul') do (
        if not defined DEFAULT_EXE set "DEFAULT_EXE=%SCRIPT_DIR%%%F"
    )

    if not defined DEFAULT_EXE (
        echo Could not find any MVP EXE in: %SCRIPT_DIR%
        pause
        exit /b 1
    )

    for %%A in ("!DEFAULT_EXE!") do (
        set "DEFAULT_PCK=%%~dpA%%~nA.pck"
    )

    if not exist "!DEFAULT_PCK!" (
        echo Warning: matching PCK not found: !DEFAULT_PCK!
        echo Available PCK files in MVP folder:
        dir /b "%SCRIPT_DIR%*.pck" 2>nul
    )

    echo Launching newest MVP build: !DEFAULT_EXE!
    call "%RUNNER%" "!DEFAULT_EXE!"
) else (
    rem Pass-through mode: caller specifies EXE path/args.
    call "%RUNNER%" %*
)
