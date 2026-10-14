# Architecture

Browser → same-origin Express `/api` → verified caller Supabase client → PostgreSQL RLS and protected action functions. Auth and private Storage are also Supabase services. The frontend imports no server credentials.

Express stores a random opaque handle in an HttpOnly cookie; its hash identifies encrypted credentials in private.app_sessions. Every request verifies Auth and current SQL permissions. Ordinary queries use the caller JWT. The separate privileged client is restricted to session/rate bookkeeping, explicit provisioning/recovery and trusted system actions.

Sensitive identity and financial fields are separate tables. Business writes use reviewed SQL RPCs, optimistic versions and exact scopes. Financial writes and period closure share an advisory lock before row locks; source indexes and idempotency keys prevent duplicate posting. Reports run as invoker under RLS.

PGlite is a dev-only isolated PostgreSQL test runtime with mock auth/storage schemas, never application persistence. Production uses Supabase exclusively. Vite is development-only; one compiled Express server serves React and API. PDF reports use browser Print/Save PDF and do not require Chromium on Hostinger.
