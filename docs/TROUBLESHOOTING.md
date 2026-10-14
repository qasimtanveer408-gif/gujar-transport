# Troubleshooting

| Problem | Remedy |
|---|---|
| Environment not loaded | Start in package.json folder; hosting/process values override .env |
| Wrong Node / missing build | Use Node 24; npm ci; npm run build; check dist/server/index.js |
| Port occupied | Stop earlier process or update port/origin/proxy consistently |
| API 502 | Check startup logs, platform PORT/interface and missing configuration |
| API HTML / nested 404 | Deploy full Express app and proxy all routes to it, not static Vite only |
| CSRF/Origin denial | Exact scheme/host/port, matching origin, refresh token and cookies; do not disable protection |
| Missing Secure cookie | HTTPS required for live profiles; use trusted certificate |
| Auth login/profile failure | Confirm URL/key project pair, migrations and linked active app profile |
| Bootstrap existing email conflict | Intentional unrelated-account protection; inspect task/identity before authorized recovery |
| RLS/function denial | Check current permission/scope/session and grants; never use service key for ordinary reads |
| Schema cache mismatch | Compare migration history and selected project; reload cache appropriately, not destructive reset |
| Private file denied | Check source permissions, driver-document capability, exact bucket/path/state and MIME/size |
| Password recovery absent | Recovery UI/SMTP is separate; owner administration is current route |
| Version/duplicate conflict | Reload; inspect existing source/reference; do not delete canonical ledger rows |
| Closed period | Authorized reopen with reason; never falsify dates |
| Unexpected totals | Karachi dates, approval states, basis, cash versus expense and overhead |
| Alert lag | Check X-Alerts-Pending/job_runs/Cron history; reconcile same named job |
| CSV rejected | Correct row errors/duplicates and original facts; failed commit rolls back all rows |
| CLI missing | Install official OS-specific Supabase CLI on PATH |
| Browser suite launch failure | Install matching Playwright Chromium; optional executable path supported |

Share only sanitized request ID/code and action for diagnosis. Never share full environment dumps, passwords, tokens, keys, identity documents or private record payloads.
