@echo off
setlocal EnableDelayedExpansion

rem Generic EXE launcher with runtime log capture.
rem - Discovers EXEs (or accepts one as argument)
rem - Auto-selects freshest valid EXE build when no arg is provided
rem - Uses matching Godot .pck sidecar if present, but supports EXE-only builds
rem - Pipes stdout/stderr to logs\exe_runtime_YYYYMMDD_HHMMSS.log

set "BASE_DIR=%~dp0"
set "LOG_DIR=%BASE_DIR%logs"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "STAMP=%%i"
set "LOG_FILE=%LOG_DIR%\exe_runtime_%STAMP%.log"

if "%~1"=="" (
    rem Collect all EXE builds for each track, keeping the latest build per track.
    set "EXE_COUNT=0"
    
    for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "$base='%BASE_DIR%'; $dirs=@((Join-Path $base 'MVP'), $base); $pairs = foreach($d in $dirs){ if(Test-Path $d){ Get-ChildItem -Path $d -Filter *.exe -File | ForEach-Object { $pck=[System.IO.Path]::ChangeExtension($_.FullName,'.pck'); $trackMatch=[regex]::Match($_.Name,'track(\d+)'); if($trackMatch.Success){ $track=[int]$trackMatch.Groups[1].Value; [pscustomobject]@{ Exe=$_.FullName; ExeTime=$_.LastWriteTimeUtc; Pck=$pck; PckExists=Test-Path $pck; PairAge = if(Test-Path $pck){ $p=Get-Item -LiteralPath $pck; [math]::Abs(($_.LastWriteTimeUtc-$p.LastWriteTimeUtc).TotalSeconds) } else { -1 }; TrackNum = $track } } } } }; $valid=$pairs | Where-Object { $_.TrackNum -gt 0 } | Group-Object TrackNum | ForEach-Object { $_.Group | Sort-Object ExeTime -Descending | Select-Object -First 1 } | Sort-Object TrackNum; $valid | ForEach-Object { $_.Exe } "`) do (
        set /a "EXE_COUNT+=1"
        set "EXE_!EXE_COUNT!=%%~I"
    )

    if !EXE_COUNT! equ 0 (
        echo No valid EXE found in:
        echo   %BASE_DIR%MVP
        echo   %BASE_DIR%
        echo Usage: run_with_logs.bat "C:\path\to\your.exe"
        pause
        exit /b 1
    )

    if !EXE_COUNT! equ 1 (
        set "EXE_PATH=!EXE_1!"
        echo Auto-selected only valid EXE: !EXE_PATH!
    ) else (
        echo Multiple tracks available. Choose one:
        for /L %%N in (1,1,!EXE_COUNT!) do call echo %%N. %%EXE_%%N%%
        set /p "CHOICE=Enter selection (1-!EXE_COUNT!): "
        if "!CHOICE!"=="" set "CHOICE=1"
        call set "EXE_PATH=%%EXE_!CHOICE!%%"
        if not defined EXE_PATH (
            echo Invalid choice. Defaulting to the first option.
            set "EXE_PATH=!EXE_1!"
        )
        echo Selected: !EXE_PATH!
    )
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

rem Validate matching .pck sidecar if it exists; allow EXE-only builds.
for %%A in ("%EXE_PATH%") do (
    set "EXPECTED_PCK=%%~dpA%%~nA.pck"
)
if exist "!EXPECTED_PCK!" (
    echo Sidecar found: !EXPECTED_PCK!
    for /f %%i in ('powershell -NoProfile -Command "$e=Get-Item -LiteralPath ''%EXE_PATH%''; $p=Get-Item -LiteralPath ''!EXPECTED_PCK!''; [int][math]::Abs(($e.LastWriteTimeUtc-$p.LastWriteTimeUtc).TotalSeconds)"') do set "PAIR_AGE_SEC=%%i"
    if not defined PAIR_AGE_SEC set "PAIR_AGE_SEC=999999"
    if !PAIR_AGE_SEC! GTR 600 (
        echo Warning: EXE/PCK timestamps differ by !PAIR_AGE_SEC! seconds.
        echo This may be a stale leftover PCK, but the launcher will continue.
    )
) else (
    echo No matching PCK sidecar found: !EXPECTED_PCK!
    echo Assuming single-file EXE build.
    set "PAIR_AGE_SEC=0"
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
