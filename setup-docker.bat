@echo off
setlocal EnableDelayedExpansion

REM ========================================
REM  One-click Docker install + Epay run
REM  Right-click -> Run as Administrator
REM ========================================

:: Check if Docker is already installed and responsive
docker version >nul 2>&1
if %errorlevel% == 0 (
    echo [OK] Docker is already running.
    goto RUN_PROJECT
)

:: Check for administrator rights
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [INFO] Administrator rights required. Relaunching as admin...
    powershell -Command "Start-Process '%~f0' -Verb runAs"
    exit /b
)

echo [INFO] Enabling WSL and Virtual Machine Platform...
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart

echo [INFO] Installing WSL2 (if not already present)...
wsl --install --no-distribution 2>nul || echo [WARN] WSL install may require a reboot after this script finishes.

echo [INFO] Downloading Docker Desktop installer...
set INSTALLER=%TEMP%\DockerDesktopInstaller.exe
powershell -Command "Invoke-WebRequest -Uri 'https://desktop.docker.com/win/main/amd64/Docker%%20Desktop%%20Installer.exe' -OutFile '%INSTALLER%' -UseBasicParsing"
if not exist "%INSTALLER%" (
    echo [ERROR] Failed to download Docker Desktop installer. Please check your internet connection.
    pause
    exit /b 1
)

echo [INFO] Installing Docker Desktop silently (this may take 5-15 minutes)...
"%INSTALLER%" install --quiet
if %errorlevel% neq 0 (
    echo [ERROR] Docker Desktop installation failed. You may need to reboot and run this script again.
    pause
    exit /b 1
)

echo [INFO] Starting Docker Desktop...
start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe"

echo [INFO] Waiting for Docker engine to start...
:WAIT_DOCKER
timeout /t 8 /nobreak >nul
docker version >nul 2>&1
if errorlevel 1 goto WAIT_DOCKER
echo [OK] Docker engine is ready!

:RUN_PROJECT
cd /d "%~dp0"
if not exist ".env" (
    copy ".env.example" ".env" >nul
    echo [INFO] Created .env from .env.example
)

echo [INFO] Stopping any previous Epay containers...
docker compose down --volumes --remove-orphans 2>nul

echo [INFO] Pre-pulling base images via China mirrors to bypass Docker Hub timeout...
call :PULL_IMAGE mysql 8.0 library/mysql
if %errorlevel% neq 0 (
    pause
    exit /b 1
)
call :PULL_IMAGE php 8.0-fpm library/php
if %errorlevel% neq 0 (
    pause
    exit /b 1
)
call :PULL_IMAGE composer 2 library/composer
if %errorlevel% neq 0 (
    pause
    exit /b 1
)

echo [INFO] Building and starting Epay services...
docker compose up --build -d
if %errorlevel% neq 0 (
    echo [ERROR] docker compose up failed.
    pause
    exit /b 1
)

echo [INFO] Waiting for services to initialize (MySQL + App)...
timeout /t 20 /nobreak >nul

echo [INFO] Current container status:
docker compose ps

echo.
echo ========================================
echo   Epay Docker Deployment Complete!
echo   Access URL: http://localhost:8080
echo ========================================
echo.
echo If you see a 502 error, wait another 30s
echo for the database to finish initializing.
echo.
pause
goto :EOF

REM ========================================
REM  Subroutine: Pull image via mirror registry
REM ========================================
:PULL_IMAGE
set "IMG_NAME=%~1"
set "IMG_TAG=%~2"
set "REMOTE_PATH=%~3"

:: Check if already exists locally
docker image inspect %IMG_NAME%:%IMG_TAG% >nul 2>&1
if %errorlevel% == 0 (
    echo [OK] %IMG_NAME%:%IMG_TAG% already exists locally.
    exit /b 0
)

for %%M in (docker.m.daocloud.io docker.1panel.live hub.rat.dev) do (
    echo [INFO] Trying %%M/%REMOTE_PATH%:%IMG_TAG% ...
    docker pull %%M/%REMOTE_PATH%:%IMG_TAG%
    if !errorlevel! == 0 (
        docker tag %%M/%REMOTE_PATH%:%IMG_TAG% %IMG_NAME%:%IMG_TAG%
        echo [OK] Tagged %IMG_NAME%:%IMG_TAG% from %%M
        exit /b 0
    )
)
echo [ERROR] Failed to pull %IMG_NAME%:%IMG_TAG% from all mirrors. Check your network or configure a proxy.
exit /b 1
