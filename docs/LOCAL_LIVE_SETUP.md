# Local-live setup

This profile uses the same approved Supabase records as Hostinger. Select the project explicitly and use a separate checkout/environment from development. Never run sample seeding/destructive tests on this target.

Build with npm ci and npm run build. Set APP_ENV=local-live, NODE_ENV=production, ALLOW_LIVE_DATABASE_ACCESS=true and the confirmed live Supabase URL/keys. Configure an approved local HTTPS reverse proxy to the built Express server and trusted localhost certificate; use that exact HTTPS origin for APP_URL/ALLOWED_ORIGINS and the correct TRUST_PROXY_HOPS. This checkpoint does not include automatic local certificate installation. Keep certificate private keys outside the repository.

Start npm start and open the trusted HTTPS origin. Verify the LIVE DATA banner and Secure local-live cookie. Do not disable certificate verification or weaken cookie/Origin checks. Browser sessions remain distinct from the hosted origin.

Read the same authorized UUID/version in local-live and hosted clients; after an explicitly authorized safe change, refetch both and verify equality. Verify revocation and restart persistence. These checks remain pending; no real live records were changed here.
