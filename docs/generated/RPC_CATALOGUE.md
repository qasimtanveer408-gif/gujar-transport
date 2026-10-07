# RPC catalogue

All functions have explicit grants and fixed search paths. Server-prefixed actions are privileged.

| Function | Arguments | Returns | Mode |
|---|---|---|---|
| accrue_earning | p_driver uuid, p_date date, p_kind text, p_amount numeric, p_rule text, p_key uuid | uuid | definer + explicit authorization |
| approve_booking | p_id uuid, p_version integer, p_key uuid | void | definer + explicit authorization |
| approve_maintenance | p_id uuid, p_version integer, p_key uuid | void | definer + explicit authorization |
| assign_driver | p_vehicle uuid, p_driver uuid, p_reason text | void | definer + explicit authorization |
| begin_user_provisioning | p_email text, p_name text, p_role uuid | jsonb | definer + explicit authorization |
| close_period | p_period uuid, p_version integer, p_reason text | void | definer + explicit authorization |
| commit_import | p_batch uuid | jsonb | definer + explicit authorization |
| complete_form_trip | p_id uuid, p_version integer | void | definer + explicit authorization |
| create_period | p_name text, p_start date, p_end date | uuid | definer + explicit authorization |
| dashboard | p_from date, p_to date, p_basis text DEFAULT 'measured'::text, p_min_distance numeric DEFAULT 100 | jsonb | caller RLS |
| delete_attachment_state | p_id uuid, p_finish boolean | jsonb | definer + explicit authorization |
| driver_statement | p_driver uuid | jsonb | caller RLS |
| expense_action | p_id uuid, p_action text, p_version integer, p_reason text, p_key uuid | void | definer + explicit authorization |
| export_records | p_resource text, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_vehicle uuid DEFAULT NULL::uuid, p_driver uuid DEFAULT NULL::uuid | jsonb | caller RLS |
| finalize_attachment | p_id uuid | void | definer + explicit authorization |
| form_export | p_resource text, p_from date, p_to date, p_vehicle uuid DEFAULT NULL::uuid, p_driver uuid DEFAULT NULL::uuid | jsonb | caller RLS |
| form_record | p_resource text, p_id uuid, p_from date, p_to date | jsonb | caller RLS |
| form_register | p_resource text, p_from date, p_to date, p_page integer DEFAULT 1, p_limit integer DEFAULT 25, p_search text DEFAULT ''::text, p_vehicle uuid DEFAULT NULL::uuid, p_driver uuid DEFAULT NULL::uuid | jsonb | caller RLS |
| list_records | p_resource text, p_search text DEFAULT ''::text, p_page integer DEFAULT 1, p_limit integer DEFAULT 25, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_vehicle uuid DEFAULT NULL::uuid, p_driver uuid DEFAULT NULL::uuid | jsonb | caller RLS |
| loan_transaction | p_loan uuid, p_driver uuid, p_date date, p_kind text, p_amount numeric, p_reference text, p_due date, p_key uuid | uuid | definer + explicit authorization |
| mark_notification_read | p_id uuid | void | definer + explicit authorization |
| monthly_accounts | p_from date, p_to date, p_basis text DEFAULT 'measured'::text | jsonb | caller RLS |
| my_access |  | jsonb | definer + explicit authorization |
| prepare_import | p_resource text, p_reference text, p_rows jsonb | uuid | definer + explicit authorization |
| reconcile_alerts |  | void | definer + explicit authorization |
| reference_dataset | p_kind text, p_from date, p_to date, p_vehicle uuid DEFAULT NULL::uuid, p_driver uuid DEFAULT NULL::uuid | jsonb | caller RLS |
| refresh_alerts_after_change |  | void | definer + explicit authorization |
| reopen_period | p_period uuid, p_version integer, p_reason text | void | definer + explicit authorization |
| reserve_attachment | p_resource text, p_record uuid, p_name text, p_mime text, p_size bigint | jsonb | definer + explicit authorization |
| revoke_my_sessions |  | void | definer + explicit authorization |
| save_alert_rule | p_code text, p_enabled boolean, p_threshold numeric, p_version integer | void | definer + explicit authorization |
| save_booking | p_data jsonb | uuid | definer + explicit authorization |
| save_business_settings | p_data jsonb, p_version integer | void | definer + explicit authorization |
| save_company | p_name text | uuid | definer + explicit authorization |
| save_driver | p_id uuid, p_version integer, p_data jsonb | uuid | definer + explicit authorization |
| save_driver_identity | p_driver uuid, p_version integer, p_data jsonb | void | definer + explicit authorization |
| save_form | p_resource text, p_id uuid, p_version integer, p_data jsonb, p_identity_version integer DEFAULT NULL::integer, p_assignment uuid DEFAULT NULL::uuid | uuid | definer + explicit authorization |
| save_maintenance | p_id uuid, p_version integer, p_data jsonb, p_items jsonb, p_oil jsonb | uuid | definer + explicit authorization |
| save_office_expense | p_id uuid, p_version integer, p_data jsonb | uuid | definer + explicit authorization |
| save_role | p_id uuid, p_name text, p_version integer, p_grants jsonb | uuid | definer + explicit authorization |
| save_trip | p_id uuid, p_version integer, p_data jsonb, p_lines jsonb | uuid | definer + explicit authorization |
| save_vehicle | p_id uuid, p_version integer, p_data jsonb | uuid | definer + explicit authorization |
| server_admin_reset | p_user uuid, p_email text, p_stage text | void | definer + explicit authorization |
| server_bootstrap_begin | p_email text | jsonb | definer + explicit authorization |
| server_orphan_candidates |  | jsonb | definer + explicit authorization |
| server_orphan_finish | p_id uuid | void | definer + explicit authorization |
| server_provision_finish | p_task uuid, p_user uuid | void | definer + explicit authorization |
| server_reconcile_alerts |  | void | definer + explicit authorization |
| server_session_claim | p_hash text, p_version integer, p_owner uuid | boolean | definer + explicit authorization |
| server_session_create | p_hash text, p_user uuid, p_auth_session uuid, p_credentials text | void | definer + explicit authorization |
| server_session_read | p_hash text | jsonb | definer + explicit authorization |
| server_session_revoke | p_hash text | void | definer + explicit authorization |
| server_session_rotate | p_hash text, p_version integer, p_owner uuid, p_credentials text | boolean | definer + explicit authorization |
| server_throttle | p_key text, p_limit integer, p_seconds integer | boolean | definer + explicit authorization |
| set_driver_duty | p_driver uuid, p_on_duty boolean | void | definer + explicit authorization |
| set_user_access | p_user uuid, p_active boolean, p_role uuid, p_version integer, p_reason text | void | definer + explicit authorization |
| set_vehicle_scope | p_user uuid, p_vehicle uuid, p_enabled boolean | void | definer + explicit authorization |
| settle_driver_payment | p_driver uuid, p_date date, p_reference text, p_allocations jsonb, p_key uuid | uuid | definer + explicit authorization |
| trip_action | p_trip uuid, p_action text, p_version integer, p_reason text, p_key uuid | void | definer + explicit authorization |
| trip_finance | p_trip uuid | jsonb | definer + explicit authorization |