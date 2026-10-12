# Auth and sessions

Real signInWithPassword happens server-side. The returned token is verified with Auth before its session claim is used. AES-256-GCM encrypts access/refresh credentials with the session hash as authenticated associated data. The browser receives a random 32-byte handle; only its SHA-256 hash is stored. Absolute app session lifetime is 3 hours (10,800 seconds). Cookie and server expiry agree; Auth token refresh does not extend the application session. Existing sessions are capped by the forward review migration. The UI returns to sign-in at expiry, and protected APIs clear expired cookies.

Cookies are HttpOnly, SameSite=Strict, path /. Local-live/production use Secure __Host- names, distinct from development. Tokens are not stored in browser localStorage/sessionStorage. Per-request Auth verification and live RLS rights prevent stale permission caches authorizing writes.

Refresh uses a database lease, owner and compare-and-swap version, so overlapping requests wait for one owner. Abandoned refresh claims fail closed. Logout revokes the application session before provider sign-out. Logout-all revokes application sessions; it does not promise to invalidate unrelated provider JWT usage instantly.

Writes require an exact allowed Origin and CSRF token. Login has a signed pre-login token and persisted IP/email rate counters. Server logs omit passwords, tokens, headers and request bodies. Administrator seed/reset requires an explicit interactive CLI confirmation and is not run during build/start.

Ordinary-user recovery UI and live provider refresh/recovery acceptance remain pending. Source: [Supabase sessions](https://supabase.com/docs/guides/auth/sessions).
