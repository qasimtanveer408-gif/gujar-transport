> Current full setup: [START-HERE-ARCHIVE-DELETE.md](../START-HERE-ARCHIVE-DELETE.md).

# Local setup — Windows

1. Use Node.js 24 through 26. Open a fresh PowerShell terminal and run node --version and npm --version. If execution policy blocks npm.ps1, use npm.cmd rather than changing the machine-wide policy.
2. Extract the ZIP. Open the gujjar-brother-transport folder containing package.json in your editor. Open a terminal there; Get-ChildItem package.json should find it.
3. Run npm ci. Copy-Item .env.example .env, then edit .env privately for a disposable development project. Follow SUPABASE_SETUP.md for migrations and first administrator.
4. Generate and securely copy the encryption key. Run check:env. Complete seed:admin interactively, remove ADMIN_PASSWORD and disable bootstrap.
5. Run npm run dev. Expected ports: frontend 5173, Express 5000. Open http://localhost:5173 and sign in. Ctrl+C stops both processes; data remains in Supabase.
6. Confirm Business settings/period convention, create a period, then a test vehicle/driver and assignment before a trip.

Verification: npm run typecheck; npm run lint; npm test; npm run build (run separately). For the built development app use APP_URL/ALLOWED_ORIGINS=http://localhost:5000, run npm start, and open port 5000. Do not confuse the development proxy origin with the built-server origin.

If a port is occupied, close the old process. If Node is not found, reopen the terminal. If login fails, verify the selected project, migration history and linked active profile before attempting a reset. No default password exists.
