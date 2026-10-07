# Environment variables

.env loads from the repository working directory; existing process/hosting variables win. No VITE_ secret variables exist. check:env prints only safe target/flag metadata, not credentials, and does not prove connectivity.

| Variable | Value/purpose |
|---|---|
| APP_ENV | development, local-live, production |
| NODE_ENV | development or production for deployed build |
| PORT | 5000 default; platform PORT wins |
| APP_URL | Exact app origin without path/query |
| ALLOWED_ORIGINS | Exact comma-separated origins including APP_URL |
| SUPABASE_URL | Chosen project HTTPS; local HTTP only in development |
| SUPABASE_PUBLISHABLE_KEY | Publishable or legacy anon, kept server-side here |
| SUPABASE_SECRET_KEY | Privileged server key; never client/public |
| SESSION_ENCRYPTION_KEY | 64 hex characters, 32 random bytes |
| ADMIN_BOOTSTRAP_ENABLED | False for web startup, true only during setup/reset |
| ADMIN_EMAIL / ADMIN_PASSWORD | Setup-only; delete password afterwards |
| ALLOW_LIVE_DATABASE_ACCESS | True required for local-live/production; forbidden in development |
| CURRENCY / BUSINESS_TIMEZONE | PKR / Asia/Karachi |
| TRUST_PROXY_HOPS | 0 direct; 1 for a confirmed single reverse proxy |
| LOG_LEVEL | info/error, with no secret-bearing request logs |

Development: http://localhost:5173 + dedicated development project + gbt_dev_session. Local-live: an approved HTTPS localhost origin + explicit live project + __Host-gbt_local_live. Production: actual HTTPS domain + production project + __Host-gbt_session.

The validator cannot know that an arbitrary URL is your production project: privately verify its identity. Generate the key with secrets:generate; keep its encrypted recovery copy and delete the temporary key file. Windows ACLs need user-only protection. Use the same protected encryption key across processes reading the same session store; changing it invalidates existing encrypted sessions.
