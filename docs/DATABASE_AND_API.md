# Database and API

Every listed path begins with /api. GET health is process liveness and explicitly does not claim service connectivity. Authenticated GET connection verifies caller data access. Unknown API paths return JSON (authentication may precede 404); browser routes fall back to React.

| Family | Function |
|---|---|
| auth/csrf, auth/login, auth/me, auth/logout, auth/logout-all | CSRF, login, safe profile and revocation |
| settings | Business settings/versioned edit |
| users, roles, permissions, roles/:id/grants | Provisioning, access and role matrix |
| users/:id/vehicle-scope(s) | Assigned vehicle scopes |
| lookup; records/:resource | Allowlisted scoped lookups/listing/create/edit |
| records/:resource/:id/action | Submit, approve, reject, void, close/reopen as supported |
| trips/:id/finance; maintenance/:id/details | Restricted source details |
| drivers/:id/identity, duty, statement | Identity, duty and money statement |
| vehicles/:id/assignment(s) | Audited assignment/history |
| loans/:id/repay | Principal repayment |
| documents/upload, documents, documents/:id/link, delete | Private file lifecycle |
| dashboard; reports | SQL totals and scoped CSV/XLSX/print reporting |
| alerts; alert-rules; alerts/reconcile | Reminders/rules |
| imports/template, imports/preview, imports/:id/commit, imports | Reviewed operational CSV import |
| audit | Read-only audit history |

JSON bodies are limited to 256 KB; uploads 10 MB. Normal lists paginate 25, lookups 25. Exports gather a consistent scoped SQL snapshot and explicitly reject above 50,000 rows instead of truncating silently. SQL identifiers/resources/columns are allowlisted. Financial action keys bind actor, source, action and payload. Reload on a version conflict instead of blindly replaying stale forms. See generated/RPC_CATALOGUE.md for exact SQL parameters.
