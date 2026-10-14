# Hostinger managed Node.js

No subscription/domain/account access was supplied. Account-side deployment remains pending.

Official guidance checked 2026-10-05 lists managed Node on Business and Cloud plans, with Node 24 available. Confirm your subscription, capacity and current billing in your account. In Hostinger dashboard choose Websites → Create Website → Web App, then Import Git Repository or Upload your website files. Use a private source repository or this ZIP.

| Setting | This project |
|---|---|
| Project root | Folder containing package.json |
| Framework | Express or Other server application |
| Node | 24 |
| Install | npm ci, including build dev dependencies |
| Build | npm run build |
| Output | dist |
| Entry | dist/server/index.js |
| Start | npm start, from project root |

Express serves dist/client and /api, listens on 0.0.0.0 and respects platform PORT. Do not select frontend-only Vite hosting. Configure secrets as server environment values; APP_ENV=production, NODE_ENV=production, explicit live access, actual HTTPS origin and bootstrap false. Leave ADMIN_PASSWORD unset. Never use VITE_ for credentials.

Apply migrations and administrator setup from a trusted machine against the confirmed project. Do not assume interactive managed SSH npm access, expose a bootstrap route, or provision an administrator during build. Configure your actual domain/DNS/SSL and update exact origins; no domain is invented.

Use deployment logs and the server-app Running → Restart control. Test health, login/connection, permission denial, safe CRUD, files, export, nested refresh and restart persistence in staging. Preserve a known-good source release. Code rollback must not undo financial data or schema blindly. No hosting/email/backup capacity is promised permanently free.

Source: [Hostinger deployment](https://www.hostinger.com/support/how-to-deploy-a-nodejs-website-in-hostinger/). Confirm evolving UI fields in your account.
