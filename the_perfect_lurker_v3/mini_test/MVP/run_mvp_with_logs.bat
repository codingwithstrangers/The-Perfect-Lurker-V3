@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "RUNNER=%SCRIPT_DIR%..\run_with_logs.bat"
set "DEFAULT_EXE=%SCRIPT_DIR%track5mvp.exe"
set "DEFAULT_PCK=%SCRIPT_DIR%track5mvp.pck"

if not exist "%RUNNER%" (
    echo Could not find runner: %RUNNER%
    pause
    exit /b 1
)

if "%~1"=="" (
    if not exist "%DEFAULT_EXE%" (
        echo Could not find default MVP EXE: %DEFAULT_EXE%
        pause
        exit /b 1
    )
    if not exist "%DEFAULT_PCK%" (
        echo Warning: matching PCK not found: %DEFAULT_PCK%
    )
    call "%RUNNER%" "%DEFAULT_EXE%"
) else (
    call "%RUNNER%" %*
)
