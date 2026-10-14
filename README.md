<<<<<<< HEAD
> **Latest release: archive / restore / permanent delete. Start with [START-HERE-ARCHIVE-DELETE.md](START-HERE-ARCHIVE-DELETE.md), including the new-database setup instructions.** The earlier release notes below remain as history.

=======
<<<<<<< HEAD
>>>>>>> d1a492683f98713288c02ce0dbffae1d235f6a40
=======
>>>>>>> 2aef45882bd9ec54781d025e3620f1f2677a5c83
>>>>>>> c44b1c5f20bc867d0d0ff98c100dd40351076c00
# Gujjar Brother Transport

This update improves the existing React/Vite, Express and Supabase application in place. It balances screen sizing, fixes dark-mode form readability and tablet layout, clarifies vehicle/driver selections, verifies the existing user search, and uses email/password staff login.

Latest master review: 3-hour sessions, completed driver Remarks, clear commission/reward labels, CSS feedback, optimized assets/page loading and print/security checks.

Start with [MASTER-UPDATE-START-HERE.md](MASTER-UPDATE-START-HERE.md). Copy your existing private `.env` into the extracted `Gujjar-Transport` folder. Existing accounts, permissions, database records, accounting formulas and operating workflows are retained.

## Windows / Antigravity

Open the folder containing `package.json` in Antigravity. Use Node.js 24.x and run these commands separately in its PowerShell terminal:

```powershell
npm.cmd ci
npm.cmd run check:env
npm.cmd run dev
```

Open `http://localhost:5173` and sign in with your existing email and password. `START-WINDOWS.cmd` also starts the configured development app.

## Features retained

The application includes fleet and driver management, dated vehicle-assignment history and transfers, arbitrary saved routes, trips and Driver cycle commission, Punjab Police expenses, maintenance/oil service, office expenses/bookings, loans/earnings/payments, accounting periods, private documents, CSV imports, reports and exports, signatures, notification bell/read states, dashboard charts and fuel ranking, user/role permissions, custom fields and bounded decimal formulas.

Cards, tables, dialogs and long pages retain independent scrolling. Light/dark themes, the existing branding, logo and welcome animation remain available. Desktop controls use normal professional sizing; phone controls keep suitable touch targets and input text remains 16px.

## Verification and deployment

Local automated verification uses isolated PostgreSQL migrations and application HTTP handlers, with remote Auth/Storage mocked. Browser tests cover password login, saved forms/calculations/prints, search, selections and responsive light/dark layouts. See [docs/ENHANCEMENT_TEST_REPORT.md](docs/ENHANCEMENT_TEST_REPORT.md) for final results and test boundaries.

Use Node.js 24 and `.env.production.example` for a hosted deployment. `npm run build` compiles the client/server; `npm start` serves both on `PORT`. Production requires HTTPS and environment origins matching the actual public URL. Private environment values stay outside the client assets.

| Command | Purpose |
| --- | --- |
| `npm run dev` | Vite frontend and Express development API |
| `npm run build` / `npm start` | Compile and serve the application |
| `npm run typecheck` / `npm run lint` | Static validation |
| `npm test` | Formula, HTTP, SQL, permissions and accounting regressions |
| `npm run test:e2e` | Password login, SQL-backed form workflows and UI review |
| `npm run test:production` | Smoke-test the compiled server locally without remote services |
| `npm run schema:snapshot` | Regenerate schema documentation/types locally |
| `npm run check:env` | Validate your private environment configuration |

The archive includes source, lockfile, ordered migrations, compiled output and setup guides. It excludes private `.env`, dependencies and live business data. Hosted database, printer and deployment acceptance require the configured installation. Unconfirmed inherited reference-report share/settlement mappings remain marked incomplete in `REPORT_DATA_MAPPING.md`.
