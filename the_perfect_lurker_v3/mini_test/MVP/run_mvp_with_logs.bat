@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem MVP launcher:
rem - If no argument is provided, auto-pick freshest valid EXE+PCK pair.
rem - Enforce matching .pck sidecar + timestamp safety checks.
rem - Delegate execution + tee logging to ..\run_with_logs.bat.

set "SCRIPT_DIR=%~dp0"
set "RUNNER=%SCRIPT_DIR%..\run_with_logs.bat"

if not exist "%RUNNER%" (
    echo Could not find runner: %RUNNER%
    pause
    exit /b 1
)

if "%~1"=="" (
    rem No argument: runner auto-selects freshest valid pair (MVP + mini_test root).
    call "%RUNNER%"
) else (
    rem Pass-through mode: caller specifies EXE path/args.
    call "%RUNNER%" %*
)
