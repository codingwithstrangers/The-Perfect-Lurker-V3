@echo off
setlocal EnableDelayedExpansion

rem Generic EXE launcher with runtime log capture.
rem - Discovers EXEs (or accepts one as argument)
rem - Auto-selects freshest valid EXE+PCK pair when no arg is provided
rem - Requires matching Godot .pck sidecar + close timestamps
rem - Pipes stdout/stderr to logs\exe_runtime_YYYYMMDD_HHMMSS.log

set "BASE_DIR=%~dp0"
set "LOG_DIR=%BASE_DIR%logs"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "STAMP=%%i"
set "LOG_FILE=%LOG_DIR%\exe_runtime_%STAMP%.log"

if "%~1"=="" (
    rem Pick freshest EXE that has a matching PCK within 10 minutes.
    set "EXE_PATH="
    for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "$base='%BASE_DIR%'; $dirs=@((Join-Path $base 'MVP'), $base); $pairs = foreach($d in $dirs){ if(Test-Path $d){ Get-ChildItem -Path $d -Filter *.exe -File | ForEach-Object { $pck=[System.IO.Path]::ChangeExtension($_.FullName,'.pck'); if(Test-Path $pck){ $p=Get-Item -LiteralPath $pck; [pscustomobject]@{ Exe=$_.FullName; ExeTime=$_.LastWriteTimeUtc; PairAge=[math]::Abs(($_.LastWriteTimeUtc-$p.LastWriteTimeUtc).TotalSeconds) } } } } }; $valid=$pairs | Where-Object { $_.PairAge -le 600 } | Sort-Object ExeTime -Descending; if($valid.Count -gt 0){ $valid[0].Exe }"`) do (
        set "EXE_PATH=%%~I"
    )

    if not defined EXE_PATH (
        echo No valid EXE+PCK pair found in:
        echo   %BASE_DIR%MVP
        echo   %BASE_DIR%
        echo Requirement: matching .pck and EXE/PCK timestamps within 600 seconds.
        echo Usage: run_with_logs.bat "C:\path\to\your.exe"
        pause
        exit /b 1
    )
    echo Auto-selected freshest valid pair: %EXE_PATH%
) else (
    set "EXE_PATH=%~1"
    if not exist "%EXE_PATH%" (
        if exist "%BASE_DIR%MVP\%~1" set "EXE_PATH=%BASE_DIR%MVP\%~1"
        if not exist "%EXE_PATH%" (
            if exist "%BASE_DIR%%~1" set "EXE_PATH=%BASE_DIR%%~1"
        )
    )
)

:found_exe
if not exist "%EXE_PATH%" (
    echo EXE does not exist: %EXE_PATH%
    pause
    exit /b 1
)

for %%A in ("%EXE_PATH%") do (
    set "EXE_BASENAME=%%~nA"
)
set "LOG_FILE=%LOG_DIR%\exe_runtime_!EXE_BASENAME!_%STAMP%.log"

rem Validate matching .pck sidecar commonly required by Godot exports.
for %%A in ("%EXE_PATH%") do (
    set "EXPECTED_PCK=%%~dpA%%~nA.pck"
)
if exist "!EXPECTED_PCK!" (
    echo Sidecar found: !EXPECTED_PCK!
) else (
    echo Error: matching PCK not found: !EXPECTED_PCK!
    echo Aborting launch to prevent mismatched build/runtime data.
    pause
    exit /b 1
)

rem Ensure EXE and PCK look like the same build generation (close write times).
for /f %%i in ('powershell -NoProfile -Command "$e=Get-Item -LiteralPath ''%EXE_PATH%''; $p=Get-Item -LiteralPath ''!EXPECTED_PCK!''; [int][math]::Abs(($e.LastWriteTimeUtc-$p.LastWriteTimeUtc).TotalSeconds)"') do set "PAIR_AGE_SEC=%%i"
if not defined PAIR_AGE_SEC set "PAIR_AGE_SEC=999999"
if !PAIR_AGE_SEC! GTR 600 (
    echo Error: EXE/PCK timestamps differ by !PAIR_AGE_SEC! seconds.
    echo This usually means you are launching a stale or mismatched build pair.
    echo EXE: %EXE_PATH%
    echo PCK: !EXPECTED_PCK!
    pause
    exit /b 1
)

echo Running: %EXE_PATH%
echo Logging to: %LOG_FILE%
echo ----------------------------------------

powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%EXE_PATH%' 2>&1 | ForEach-Object { '[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') + '] ' + $_ } | Tee-Object -FilePath '%LOG_FILE%'"
set "EXIT_CODE=%ERRORLEVEL%"

echo ----------------------------------------
echo EXE exited with code %EXIT_CODE%
echo Log file: %LOG_FILE%
pause
exit /b %EXIT_CODE%
