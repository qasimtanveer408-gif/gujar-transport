@echo off
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
<<<<<<< HEAD
<<<<<<< HEAD
  echo Install Node.js 24.x or 26.x before starting.
=======
  echo Install Node.js 24.x before starting.
>>>>>>> d1a492683f98713288c02ce0dbffae1d235f6a40
=======
  echo Install Node.js 24.x or 26.x before starting.
>>>>>>> c44b1c5f20bc867d0d0ff98c100dd40351076c00
  pause
  exit /b 1
)
if not exist ".env" (
<<<<<<< HEAD
<<<<<<< HEAD
  echo Create .env using .env.example and enter your new database settings.
  echo Read START-HERE-ARCHIVE-DELETE.md for new database setup.
=======
  echo Copy your existing private .env into this folder first.
  echo Read UPDATE_INSTRUCTIONS.md for database migrations and setup.
>>>>>>> d1a492683f98713288c02ce0dbffae1d235f6a40
=======
  echo Create .env using .env.example and enter your new database settings.
  echo Read START-HERE-ARCHIVE-DELETE.md for new database setup.
>>>>>>> c44b1c5f20bc867d0d0ff98c100dd40351076c00
  pause
  exit /b 1
)
if not exist "node_modules" (
  call npm.cmd ci
  if errorlevel 1 exit /b 1
)
call npm.cmd run dev
pause
