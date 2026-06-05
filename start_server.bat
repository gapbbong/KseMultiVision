@echo off
chcp 65001 > nul
title 멀티비전 로컬 서버

:: 이미 포트 8080이 열려 있으면 중복 실행하지 않음
netstat -ano | findstr ":8080" > nul 2>&1
if %ERRORLEVEL% == 0 (
    echo [OK] 서버가 이미 실행 중입니다. (localhost:8080)
    timeout /t 2 > nul
    exit /b 0
)

echo [시작] 멀티비전 로컬 서버를 시작합니다...
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0server.ps1"
