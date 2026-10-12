# Changes in the master review update

Reviewed and updated the supplied developed project. Existing modules, database identities, financial ledgers, formulas and driver transfer history are retained. No duplicate modules/tables were added. All 15 historical SQL migrations remain byte-identical; apply the new forward migration described in MASTER-UPDATE-START-HERE.md. No hosted customer data was accessed or changed.

Sessions now use 3 hours. Existing driver Remarks is editable in the exact form, requested labels are clearer, input/date checks are stronger, lightweight hover and reduced-motion feedback is complete, and loading/cache/asset handling is improved. Existing reference prints receive spacing, headers, footer and amount-wrapping fixes. Unconfirmed financial print rules remain visibly unavailable.

Validation: 74 automated tests, TypeScript/lint/build, local production HTTP checks and existing browser workflows passed. Responsive checks cover 20 screens at five widths from 360 to 1440 pixels. Five reference layouts and continuation PDF samples were rendered and inspected. Production dependency audit: 0 known vulnerabilities. See docs/MASTER_AUDIT.md and docs/MASTER_UPDATE_TEST_REPORT.md for evidence and limits.

Compiled production output was regenerated; obsolete fingerprinted bundles are replaced by the current build. Verification logs/JSON and TEST DATA ONLY report samples are included. Internal screenshots, private configuration and installed dependencies are excluded. MANIFEST.sha256 verifies the delivered file contents.

## Source and documentation changes

| Change | File |
|---|---|
| Updated | `FIELD_CONTRACT.md` |
| Added | `MASTER-UPDATE-START-HERE.md` |
| Updated | `README.md` |
| Updated | `REPORT_DATA_MAPPING.md` |
| Updated | `UPDATE_INSTRUCTIONS.md` |
| Updated | `UPGRADE-START-HERE.md` |
| Updated | `client/index.html` |
| Updated | `client/public/brand/favicon.png` |
| Updated | `client/public/brand/logo.png` |
| Updated | `client/src/api.ts` |
| Updated | `client/src/main.tsx` |
| Updated | `client/src/style.css` |
| Updated | `deploy/nginx-https.conf.example` |
| Updated | `deploy/nginx.conf.example` |
| Added | `docs/MASTER_AUDIT.md` |
| Added | `docs/MASTER_UPDATE_TEST_REPORT.md` |
| Updated | `docs/PROJECT_STATE.md` |
| Updated | `docs/SUPABASE_AUTH_AND_SESSIONS.md` |
| Updated | `docs/forms-reports/REFERENCE_IMAGE_MAPPING.md` |
| Updated | `package.json` |
| Added | `playwright-artifacts/dashboard-desktop.png` |
| Added | `playwright-artifacts/dashboard-mobile.png` |
| Added | `playwright-artifacts/imports-mobile.png` |
| Added | `playwright-artifacts/login-desktop.png` |
| Added | `playwright-artifacts/login-mobile.png` |
| Added | `playwright-artifacts/vehicle-dialog.png` |
| Updated | `scripts/form-docs.ts` |
| Updated | `scripts/forms-e2e.ts` |
| Added | `scripts/master-performance-e2e.mjs` |
| Updated | `scripts/ui-review-e2e.ts` |
| Updated | `server/app.ts` |
| Updated | `server/form-validation.ts` |
| Updated | `server/forms.ts` |
| Updated | `server/record-print.ts` |
| Updated | `server/reference-reports.ts` |
| Updated | `server/report-render.ts` |
| Updated | `server/reports.ts` |
| Updated | `server/session.ts` |
| Updated | `shared/form-contract.ts` |
| Updated | `shared/modules.ts` |
| Updated | `shared/report-contract.ts` |
| Added | `shared/session-policy.ts` |
| Added | `supabase/migrations/20261011160000_master_review.sql` |
| Added | `tests/master-review.test.ts` |
| Updated | `vite.config.ts` |
