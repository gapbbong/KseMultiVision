@echo off
chcp 65001 > nul
title 멀티비전 소스코드 Vercel 자동 배포 도구
cd /d "%~dp0"

echo ====================================================
echo 🚀 멀티비전 소스코드 Vercel 자동 배포를 시작합니다.
echo ====================================================
echo.

echo 🔍 1. 변경된 파일 확인 및 스테이징 중...
git add .
echo [완료] 변경 사항을 준비 영역에 등록했습니다.
echo.

echo 💬 2. 커밋 메시지 작성
echo (메시지를 적지 않고 [Enter]만 누르면 "Update codebase"로 자동 지정됩니다.)
set /p commit_msg="커밋 메시지 입력: "

if "%commit_msg%"=="" (
    set commit_msg="Update codebase"
)

git commit -m "%commit_msg%"
echo.

echo 📤 3. 깃허브 원격 서버로 푸시 중 (Vercel 배포 트리거)...
git push origin main
echo.

echo ====================================================
echo 🎉 푸시 완료! 약 1분 후 Vercel 배포가 반영됩니다.
echo ====================================================
echo.
pause
