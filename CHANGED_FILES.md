# Changed files

Compared byte-for-byte with the supplied source ZIP. Authentication/provisioning files and all nine pre-existing SQL migrations are unchanged. Replace the complete source as a new release; keep your own environment file separately.

| Status | File |
|---|---|
| New | `FIELD_CONTRACT.md` |
| Changed | `MANIFEST.sha256` |
| Changed | `README.md` |
| New | `REPORT_DATA_MAPPING.md` |
| New | `UPDATE_INSTRUCTIONS.md` |
| New | `client/public/fonts/OFL.txt` |
| New | `client/public/fonts/OpenSans-Bold.ttf` |
| New | `client/public/fonts/OpenSans-Regular.ttf` |
| New | `client/src/ExactFormsPage.tsx` |
| Changed | `client/src/ReportsPage.tsx` |
| Changed | `client/src/ResourcePage.tsx` |
| Changed | `client/src/components.tsx` |
| Changed | `client/src/main.tsx` |
| Changed | `client/src/style.css` |
| Changed | `docs/TEST_REPORT.md` |
| New | `docs/forms-reports/GAP_MATRIX.md` |
| New | `docs/forms-reports/REFERENCE_IMAGE_MAPPING.md` |
| New | `docs/forms-reports/REMAINING_QUESTIONS.md` |
| New | `docs/forms-reports/TEST_RESULTS.md` |
| Changed | `docs/generated/DATA_DICTIONARY.md` |
| Changed | `docs/generated/RPC_CATALOGUE.md` |
| Changed | `docs/generated/schema.json` |
| Changed | `package-lock.json` |
| Changed | `package.json` |
| New | `scripts/before-screenshots.mjs` |
| Changed | `scripts/e2e.mjs` |
| New | `scripts/form-docs.ts` |
| New | `scripts/forms-e2e.ts` |
| New | `scripts/render-workbooks.mjs` |
| New | `scripts/report-samples.ts` |
| Changed | `server/app.ts` |
| Changed | `server/domain.ts` |
| New | `server/form-validation.ts` |
| New | `server/forms.ts` |
| New | `server/reference-reports.ts` |
| New | `server/register-export.ts` |
| New | `server/report-render.ts` |
| Changed | `server/reports.ts` |
| New | `shared/form-contract.ts` |
| Changed | `shared/generated/schema.ts` |
| New | `shared/report-contract.ts` |
| New | `supabase/migrations/20261006135132_exact_forms.sql` |
| New | `supabase/migrations/20261006140546_reference_reports.sql` |
| New | `tests/forms.test.ts` |
| New | `tests/helpers/form-fixture.ts` |
| New | `tests/helpers/report-fixture.ts` |
| New | `tests/reference-reports.test.ts` |
| Changed | `tests/reports.test.ts` |

Additional evidence: `verification/screenshots/`, `verification/report-samples/`, `verification/rendered/`, and `verification/logs/`. These contain only synthetic TEST data and validation output. Generated dependency/build folders and actual secrets are excluded.
