@echo off
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
<<<<<<< HEAD
  echo Install Node.js 24.x or 26.x before starting.
=======
  echo Install Node.js 24.x before starting.
>>>>>>> 2aef45882bd9ec54781d025e3620f1f2677a5c83
  pause
  exit /b 1
)
if not exist ".env" (
<<<<<<< HEAD
  echo Create .env using .env.example and enter your new database settings.
  echo Read START-HERE-ARCHIVE-DELETE.md for new database setup.
=======
  echo Copy your existing private .env into this folder first.
  echo Read UPDATE_INSTRUCTIONS.md for database migrations and setup.
>>>>>>> 2aef45882bd9ec54781d025e3620f1f2677a5c83
  pause
  exit /b 1
)
if not exist "node_modules" (
  call npm.cmd ci
  if errorlevel 1 exit /b 1
)
call npm.cmd run dev
pause
