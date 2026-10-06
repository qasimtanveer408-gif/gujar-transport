# Roles and permissions

| Role | Seeded intent |
|---|---|
| Super Admin | Every capability; reserved and immutable; last active owner protected |
| Admin | Most business modules/user creation; excludes role management, role assignment and restricted identity/documents |
| Operations Manager | Fleet, drivers, duty, assignments and trip entry/submission; no company financial ledger |
| Accountant | Financial review, loans, earnings/payments, accounts and exports |
| Data Entry | Own trip drafts/submission/finance and operational lookups |
| Maintenance Manager | Maintenance/documents for explicitly scoped vehicles |
| Viewer | Operational fleet/driver/trip reads; no financial or identity data |

Each grant has all, assigned or own scope. Assigned uses user_vehicle_scopes; driver access follows active vehicle assignment. Own compares the real creator, not a caller-supplied owner. Some global actions intentionally require all scope. The exact matrix follows below from applied migrations.

The role editor cannot modify Super Admin. Delegation cannot exceed the caller's rights. Disable/access changes revoke application sessions; current grants are also checked on every SQL action. UI hiding is not the security boundary. Disable signup in the Supabase project as well as omitting a signup UI.

Provisioning creates a real Auth account with a task marker before linking the profile/role. An unrelated existing email is never adopted or reset. Rerunning completed bootstrap does not change credentials.

## Exact seeded grants

| Permission | Accountant | Admin | Data Entry | Maintenance Manager | Operations Manager | Super Admin | Viewer |
|---|---|---|---|---|---|---|---|
| accounts.close | all | all | — | — | — | all | — |
| accounts.create | all | all | — | — | — | all | — |
| accounts.reopen | all | all | — | — | — | all | — |
| accounts.view | all | all | — | — | — | all | — |
| alerts.view | all | all | — | — | all | all | — |
| assignments.manage | — | all | — | — | all | all | — |
| audit.view | — | all | — | — | — | all | — |
| bookings.approve | all | all | — | — | — | all | — |
| bookings.create | all | all | — | — | — | all | — |
| bookings.view | all | all | — | — | — | all | — |
| documents.delete | — | all | — | — | — | all | — |
| documents.upload | — | all | all | assigned | — | all | — |
| documents.view | — | all | own | assigned | — | all | — |
| drivers.create | — | all | — | — | all | all | — |
| drivers.documents.view | — | — | — | — | — | all | — |
| drivers.identity.manage | — | — | — | — | — | all | — |
| drivers.identity.view | — | — | — | — | — | all | — |
| drivers.update | — | all | — | — | all | all | — |
| drivers.view | all | all | all | — | all | all | all |
| duty.manage | — | all | — | — | all | all | — |
| expenses.approve | all | all | — | — | — | all | — |
| expenses.create | all | all | — | — | — | all | — |
| expenses.view | all | all | — | — | — | all | — |
| expenses.void | all | all | — | — | — | all | — |
| imports.manage | — | all | — | — | — | all | — |
| loans.issue | all | all | — | — | — | all | — |
| loans.repay | all | all | — | — | — | all | — |
| loans.view | all | all | — | — | — | all | — |
| maintenance.approve | all | all | — | — | — | all | — |
| maintenance.create | — | all | — | assigned | — | all | — |
| maintenance.view | all | all | — | assigned | all | all | — |
| payments.approve | all | all | — | — | — | all | — |
| payments.create | all | all | — | — | — | all | — |
| payments.view | all | all | — | — | — | all | — |
| reports.export | all | all | — | — | — | all | — |
| reports.financial.view | all | all | — | — | — | all | — |
| reports.operational.view | all | all | — | — | all | all | all |
| roles.manage | — | — | — | — | — | all | — |
| roles.view | — | all | — | — | — | all | — |
| settings.manage | — | all | — | — | — | all | — |
| settings.view | — | all | — | — | — | all | — |
| trips.approve | all | all | — | — | — | all | — |
| trips.create | — | all | own | — | all | all | — |
| trips.finance.view | all | all | own | — | — | all | — |
| trips.reject | all | all | — | — | — | all | — |
| trips.submit | — | all | own | — | all | all | — |
| trips.update | — | all | — | — | all | all | — |
| trips.update_own_draft | — | all | own | — | — | all | — |
| trips.view | all | all | own | — | all | all | all |
| trips.void | all | all | — | — | — | all | — |
| users.create | — | all | — | — | — | all | — |
| users.disable | — | all | — | — | — | all | — |
| users.roles | — | — | — | — | — | all | — |
| users.view | — | all | — | — | — | all | — |
| vehicles.archive | — | all | — | — | — | all | — |
| vehicles.create | — | all | — | — | all | all | — |
| vehicles.update | — | all | — | — | all | all | — |
| vehicles.view | all | all | all | assigned | all | all | all |
