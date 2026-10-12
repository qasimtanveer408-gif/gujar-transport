@echo off
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo Install Node.js 24.x before starting.
  pause
  exit /b 1
)
if not exist ".env" (
  echo Copy your existing private .env into this folder first.
  echo Read UPDATE_INSTRUCTIONS.md for database migrations and setup.
  pause
  exit /b 1
)
if not exist "node_modules" (
  call npm.cmd ci
  if errorlevel 1 exit /b 1
)
call npm.cmd run dev
pause
