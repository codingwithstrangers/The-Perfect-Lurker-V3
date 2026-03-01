@echo off
setlocal EnableDelayedExpansion

rem Generic EXE launcher with runtime log capture.
rem - Discovers EXEs (or accepts one as argument)
rem - Supports --mvp-only to only list EXEs in .\MVP
rem - Requires matching Godot .pck sidecar + close timestamps
rem - Pipes stdout/stderr to logs\exe_runtime_YYYYMMDD_HHMMSS.log

set "MVP_ONLY=0"
if /I "%~1"=="--mvp-only" (
    set "MVP_ONLY=1"
    shift
)

set "BASE_DIR=%~dp0"
set "LOG_DIR=%BASE_DIR%logs"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "STAMP=%%i"
set "LOG_FILE=%LOG_DIR%\exe_runtime_%STAMP%.log"

if "%~1"=="" (
    set /a EXE_COUNT=0

    rem First: search MVP folder EXEs
    for %%F in ("%BASE_DIR%MVP\*.exe") do (
        if exist "%%~fF" (
            set /a EXE_COUNT+=1
            set "EXE_!EXE_COUNT!=%%~fF"
        )
    )

    rem Second: search mini_test root EXEs (unless MVP-only mode requested)
    if "%MVP_ONLY%"=="0" (
        for %%F in ("%BASE_DIR%*.exe") do (
            if exist "%%~fF" (
                set /a EXE_COUNT+=1
                set "EXE_!EXE_COUNT!=%%~fF"
            )
        )
    )

    if !EXE_COUNT! EQU 0 (
        echo No EXE found in:
        echo   %BASE_DIR%MVP
        if "%MVP_ONLY%"=="0" echo   %BASE_DIR%
        echo Usage: run_with_logs.bat "C:\path\to\your.exe"
        pause
        exit /b 1
    )

    if !EXE_COUNT! EQU 1 (
        set "EXE_PATH=!EXE_1!"
    ) else (
        echo Found !EXE_COUNT! EXEs. Choose one to run with logging:
        for /L %%I in (1,1,!EXE_COUNT!) do (
            echo   %%I^) !EXE_%%I!
        )
        set "EXE_CHOICE="
        set /p EXE_CHOICE=Enter number ^(1-!EXE_COUNT!^): 

        for /f "delims=0123456789" %%A in ("!EXE_CHOICE!") do set "EXE_CHOICE="
        if "!EXE_CHOICE!"=="" (
            echo Invalid selection.
            pause
            exit /b 1
        )
        if !EXE_CHOICE! LSS 1 (
            echo Invalid selection.
            pause
            exit /b 1
        )
        if !EXE_CHOICE! GTR !EXE_COUNT! (
            echo Invalid selection.
            pause
            exit /b 1
        )

        call set "EXE_PATH=%%EXE_!EXE_CHOICE!%%"
    )
) else (
    set "EXE_PATH=%~1"
    if not exist "%EXE_PATH%" (
        if exist "%BASE_DIR%MVP\%~1" set "EXE_PATH=%BASE_DIR%MVP\%~1"
        if not exist "%EXE_PATH%" if "%MVP_ONLY%"=="0" (
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
