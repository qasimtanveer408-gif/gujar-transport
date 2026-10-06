# Gujjar Brother Transport — v0.1.0

Runnable cumulative source checkpoint, **not the complete requested production system**. React/Vite + Express; Supabase PostgreSQL, Auth and private Storage own all runtime persistence. PKR and Asia/Karachi are enforced. The supplied logo and template assets are integrated.

Start with [Windows local setup](docs/LOCAL_SETUP_WINDOWS.md), then [Supabase setup](docs/SUPABASE_SETUP.md). Read [Project state](docs/PROJECT_STATE.md), [traceability](docs/REQUIREMENTS_TRACEABILITY.md) and [test report](docs/TEST_REPORT.md) before adoption. No real Supabase or Hostinger account was connected.

## Quick start

1. Extract this ZIP and open the folder containing package.json in a terminal.
2. Install Node.js 24; run `node --version`, then `npm ci`.
3. Copy `.env.example` to `.env`; privately configure a disposable development Supabase project, apply migrations and explicitly provision the administrator as documented.
4. Remove the setup password and disable bootstrap. Run `npm run check:env`, then `npm run dev`. Open http://localhost:5173.
5. Production compilation: `npm run build`. The actual server entry is `dist/server/index.js`; Express also serves `dist/client`. Start from the repository root with `npm start`.

There is no default password or fake production login. Missing configuration deliberately prevents startup. The browser never receives Supabase access/refresh tokens.

| Command | Purpose |
|---|---|
| npm run dev | Vite + Express development |
| npm run build / npm start | Compile / serve full application |
| npm run typecheck / npm run lint | Static checks |
| npm test | Unit, mocked-Auth HTTP and isolated PostgreSQL tests |
| npm run test:sql | Apply all SQL to disposable isolated PostgreSQL |
| npm run schema:snapshot | Generate schema types/data dictionary locally |
| npm run test:e2e | Browser UI tests using explicit HTTP fixtures |
| npm run seed:admin / npm run reset:admin | Explicit interactive owner setup/recovery |
| npm run secrets:generate | Write a random encryption key privately |
| npm run db:migrate / npm run db:types | Confirmed linked-project schema/types via official CLI |
| npm run db:test -- --local | Supplied pgTAP against disposable local Supabase |

All production data remains in Supabase across process restarts. Source includes no live credentials, records, node_modules or built distribution. Build from the included lockfile.
