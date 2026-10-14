@echo off
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo Install Node.js 24.x or 26.x before starting.
  pause
  exit /b 1
)
if not exist ".env" (
  echo Create .env using .env.example and enter your new database settings.
  echo Read START-HERE-ARCHIVE-DELETE.md for new database setup.
  pause
  exit /b 1
)
if not exist "node_modules" (
  call npm.cmd ci
  if errorlevel 1 exit /b 1
)
call npm.cmd run dev
pause
