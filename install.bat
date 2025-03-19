@echo off
setlocal enabledelayedexpansion

REM --- Install Perl dependencies using cpanm if available ---
where cpanm > nul 2>&1
if %errorlevel% neq 0 (
    echo Error: cpanm is not installed. Please install it before continuing.
    exit /b 1
)

echo Installing required Perl modules...
cpanm JSON LWP::UserAgent Term::ReadKey Curses::UI Git::Repository DateTime::Format::ISO8601
if %errorlevel% neq 0 (
    echo Error: Failed to install required Perl modules.
    exit /b 1
)

REM --- Set installation paths ---
set GKM_LIB_DIR=C:\gkm-cli\lib
set GKM_BIN_DIR=C:\gkm-cli\bin

REM --- Create installation directories ---
if not exist "%GKM_LIB_DIR%" (
    mkdir "%GKM_LIB_DIR%" || (
        echo Error: Failed to create directory %GKM_LIB_DIR%
        exit /b 1
    )
)

if not exist "%GKM_BIN_DIR%" (
    mkdir "%GKM_BIN_DIR%" || (
        echo Error: Failed to create directory %GKM_BIN_DIR%
        exit /b 1
    )
)

REM --- Copy files to target directories ---
echo Copying library files...
xcopy /E /I /Q "lib\*" "%GKM_LIB_DIR%" > nul
if %errorlevel% neq 0 (
    echo Error: Failed to copy library files.
    exit /b 1
)

echo Copying gkm-cli.pl to binary directory...
copy /Y "bin\gkm-cli.pl" "%GKM_BIN_DIR%\gkm-cli.pl" > nul
if %errorlevel% neq 0 (
    echo Error: Failed to copy gkm-cli.pl to binary directory.
    exit /b 1
)

REM --- Create gkm-cli.bat for easier execution ---
set GKM_CLI_BAT=%GKM_BIN_DIR%\gkm-cli.bat
(
    echo @echo off
    echo setlocal
    echo perl -I "%GKM_LIB_DIR%" "%GKM_BIN_DIR%\gkm-cli.pl" %%*
) > "%GKM_CLI_BAT%"

REM --- Add gkm-cli to PATH if not already added ---
set PATH_EXISTS=0
for %%I in ("%GKM_BIN_DIR%") do (
    if "%%~dp$PATH:I" neq "" (
        set PATH_EXISTS=1
    )
)

if !PATH_EXISTS! == 0 (
    echo Adding %GKM_BIN_DIR% to system PATH...
    setx PATH "%PATH%;%GKM_BIN_DIR%" /M > nul
    if %errorlevel% neq 0 (
        echo Error: Failed to update system PATH. Please add "%GKM_BIN_DIR%" manually.
    )
) else (
    echo gkm-cli is already in the system PATH.
)

REM --- Add shebang and library path to gkm-cli.pl ---
echo Updating shebang in gkm-cli.pl...
(
    echo #!C:\Perl\bin\perl.exe
    echo use lib "%GKM_LIB_DIR%";
    type "%GKM_BIN_DIR%\gkm-cli.pl"
) > "%GKM_BIN_DIR%\gkm-cli.pl.tmp"

move /Y "%GKM_BIN_DIR%\gkm-cli.pl.tmp" "%GKM_BIN_DIR%\gkm-cli.pl" > nul

REM --- Set executable permissions ---
icacls "%GKM_BIN_DIR%\gkm-cli.pl" /grant Everyone:F > nul

echo gkm-cli installed successfully!
exit /b 0
