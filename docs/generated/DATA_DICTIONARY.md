# Data dictionary

Generated from applied migrations. API financial RPCs cast numeric values to decimal strings.

| Table | Column | SQL type | Nullable |
|---|---|---|---|
| accounting_periods | id | uuid | NO |
| accounting_periods | name | text | NO |
| accounting_periods | start_date | date | NO |
| accounting_periods | end_date | date | NO |
| accounting_periods | status | text | NO |
| accounting_periods | version | integer | NO |
| alert_rules | code | text | NO |
| alert_rules | threshold | numeric | NO |
| alert_rules | enabled | boolean | NO |
| alert_rules | version | integer | NO |
| app_users | id | uuid | NO |
| app_users | email | text | NO |
| app_users | display_name | text | NO |
| app_users | active | boolean | NO |
| app_users | version | integer | NO |
| app_users | created_at | timestamp with time zone | NO |
| app_users | updated_at | timestamp with time zone | NO |
| attachments | id | uuid | NO |
| attachments | vehicle_id | uuid | YES |
| attachments | driver_id | uuid | YES |
| attachments | trip_id | uuid | YES |
| attachments | maintenance_id | uuid | YES |
| attachments | office_expense_id | uuid | YES |
| attachments | bucket_id | text | NO |
| attachments | object_path | text | NO |
| attachments | original_name | text | NO |
| attachments | mime_type | text | NO |
| attachments | size_bytes | bigint | NO |
| attachments | state | text | NO |
| attachments | created_by | uuid | NO |
| attachments | created_at | timestamp with time zone | NO |
| attachments | updated_at | timestamp with time zone | NO |
| audit_logs | id | bigint | NO |
| audit_logs | actor_id | uuid | YES |
| audit_logs | action | text | NO |
| audit_logs | record_type | text | NO |
| audit_logs | record_id | text | YES |
| audit_logs | summary | text | NO |
| audit_logs | created_at | timestamp with time zone | NO |
| business_settings | id | boolean | NO |
| business_settings | business_name | text | NO |
| business_settings | contact_email | text | NO |
| business_settings | phone_1 | text | NO |
| business_settings | phone_2 | text | NO |
| business_settings | phone_3 | text | NO |
| business_settings | address | text | YES |
| business_settings | currency | text | NO |
| business_settings | timezone | text | NO |
| business_settings | period_start_day | integer | NO |
| business_settings | period_confirmed | boolean | NO |
| business_settings | refresh_seconds | integer | NO |
| business_settings | version | integer | NO |
| cash_transactions | id | uuid | NO |
| cash_transactions | business_date | date | NO |
| cash_transactions | direction | text | NO |
| cash_transactions | amount | numeric | NO |
| cash_transactions | reference | text | NO |
| cash_transactions | loan_transaction_id | uuid | YES |
| cash_transactions | driver_payment_id | uuid | YES |
| cash_transactions | created_by | uuid | NO |
| companies | id | uuid | NO |
| companies | name | text | NO |
| companies | created_by | uuid | YES |
| companies | version | integer | NO |
| driver_duty_sessions | id | uuid | NO |
| driver_duty_sessions | driver_id | uuid | NO |
| driver_duty_sessions | started_at | timestamp with time zone | NO |
| driver_duty_sessions | ended_at | timestamp with time zone | YES |
| driver_duty_sessions | created_by | uuid | NO |
| driver_earnings | id | uuid | NO |
| driver_earnings | driver_id | uuid | NO |
| driver_earnings | business_date | date | NO |
| driver_earnings | kind | text | NO |
| driver_earnings | amount | numeric | NO |
| driver_earnings | state | text | NO |
| driver_earnings | trip_line_id | uuid | YES |
| driver_earnings | rule_snapshot | text | NO |
| driver_earnings | created_by | uuid | NO |
| driver_identity_details | driver_id | uuid | NO |
| driver_identity_details | father_name | text | YES |
| driver_identity_details | cnic | text | YES |
| driver_identity_details | licence_number | text | YES |
| driver_identity_details | address | text | YES |
| driver_identity_details | emergency_contact | text | YES |
| driver_identity_details | version | integer | NO |
| driver_loan_transactions | id | uuid | NO |
| driver_loan_transactions | loan_id | uuid | NO |
| driver_loan_transactions | business_date | date | NO |
| driver_loan_transactions | kind | text | NO |
| driver_loan_transactions | amount | numeric | NO |
| driver_loan_transactions | reference | text | NO |
| driver_loan_transactions | created_by | uuid | NO |
| driver_loan_transactions | created_at | timestamp with time zone | NO |
| driver_loans | id | uuid | NO |
| driver_loans | driver_id | uuid | NO |
| driver_loans | reference | text | NO |
| driver_loans | due_date | date | YES |
| driver_loans | created_by | uuid | NO |
| driver_payment_allocations | payment_id | uuid | NO |
| driver_payment_allocations | earning_id | uuid | NO |
| driver_payment_allocations | amount | numeric | NO |
| driver_payments | id | uuid | NO |
| driver_payments | driver_id | uuid | NO |
| driver_payments | business_date | date | NO |
| driver_payments | amount | numeric | NO |
| driver_payments | reference | text | NO |
| driver_payments | created_by | uuid | NO |
| driver_payments | created_at | timestamp with time zone | NO |
| drivers | id | uuid | NO |
| drivers | full_name | text | NO |
| drivers | mobile | text | NO |
| drivers | joining_date | date | YES |
| drivers | leaving_date | date | YES |
| drivers | licence_expiry | date | YES |
| drivers | employment_status | text | NO |
| drivers | remarks | text | YES |
| drivers | created_by | uuid | NO |
| drivers | created_at | timestamp with time zone | NO |
| drivers | version | integer | NO |
| expense_categories | code | text | NO |
| expense_categories | label | text | NO |
| expense_categories | active | boolean | NO |
| expense_entries | id | uuid | NO |
| expense_entries | business_date | date | NO |
| expense_entries | amount | numeric | NO |
| expense_entries | category | text | NO |
| expense_entries | vehicle_id | uuid | YES |
| expense_entries | driver_id | uuid | YES |
| expense_entries | trip_id | uuid | YES |
| expense_entries | trip_line_id | uuid | YES |
| expense_entries | maintenance_item_id | uuid | YES |
| expense_entries | office_expense_id | uuid | YES |
| expense_entries | earning_id | uuid | YES |
| expense_entries | reversal_of | uuid | YES |
| expense_entries | created_by | uuid | NO |
| expense_entries | created_at | timestamp with time zone | NO |
| idempotency_keys | key | uuid | NO |
| idempotency_keys | actor_id | uuid | NO |
| idempotency_keys | action | text | NO |
| idempotency_keys | record_id | uuid | NO |
| idempotency_keys | payload_hash | text | NO |
| idempotency_keys | created_at | timestamp with time zone | NO |
| import_batches | id | uuid | NO |
| import_batches | resource | text | NO |
| import_batches | original_reference | text | NO |
| import_batches | state | text | NO |
| import_batches | created_by | uuid | NO |
| import_batches | created_at | timestamp with time zone | NO |
| import_batches | committed_at | timestamp with time zone | YES |
| import_rows | batch_id | uuid | NO |
| import_rows | row_number | integer | NO |
| import_rows | data | jsonb | NO |
| import_rows | record_id | uuid | YES |
| job_runs | job_name | text | NO |
| job_runs | last_completed_at | timestamp with time zone | YES |
| job_runs | run_count | bigint | NO |
| maintenance_categories | code | text | NO |
| maintenance_categories | label | text | NO |
| maintenance_components | maintenance_id | uuid | NO |
| maintenance_components | category | text | NO |
| maintenance_components | work_detail | text | NO |
| maintenance_items | id | uuid | NO |
| maintenance_items | maintenance_id | uuid | NO |
| maintenance_items | kind | text | NO |
| maintenance_items | description | text | NO |
| maintenance_items | amount | numeric | NO |
| maintenance_items | part_identifier | text | YES |
| maintenance_items | tyre_position | text | YES |
| maintenance_items | warranty_until | date | YES |
| maintenance_records | id | uuid | NO |
| maintenance_records | vehicle_id | uuid | NO |
| maintenance_records | driver_id | uuid | YES |
| maintenance_records | trip_id | uuid | YES |
| maintenance_records | business_date | date | YES |
| maintenance_records | odometer | numeric | YES |
| maintenance_records | category | text | YES |
| maintenance_records | description | text | YES |
| maintenance_records | supplier | text | YES |
| maintenance_records | next_service_date | date | YES |
| maintenance_records | next_service_odometer | numeric | YES |
| maintenance_records | remarks | text | YES |
| maintenance_records | state | text | NO |
| maintenance_records | created_by | uuid | NO |
| maintenance_records | created_at | timestamp with time zone | NO |
| maintenance_records | version | integer | NO |
| notification_reads | notification_id | uuid | NO |
| notification_reads | user_id | uuid | NO |
| notification_reads | read_at | timestamp with time zone | NO |
| notifications | id | uuid | NO |
| notifications | dedup_key | text | NO |
| notifications | type | text | NO |
| notifications | message | text | NO |
| notifications | vehicle_id | uuid | YES |
| notifications | driver_id | uuid | YES |
| notifications | trip_id | uuid | YES |
| notifications | action_link | text | NO |
| notifications | created_at | timestamp with time zone | NO |
| notifications | resolved_at | timestamp with time zone | YES |
| office_bookings | id | uuid | NO |
| office_bookings | business_date | date | NO |
| office_bookings | trip_id | uuid | YES |
| office_bookings | external_vehicle | text | YES |
| office_bookings | driver_contact | text | YES |
| office_bookings | cargo | text | YES |
| office_bookings | origin | text | NO |
| office_bookings | destination | text | NO |
| office_bookings | quoted_freight | numeric | NO |
| office_bookings | commission | numeric | NO |
| office_bookings | description | text | YES |
| office_bookings | state | text | NO |
| office_bookings | created_by | uuid | NO |
| office_bookings | version | integer | NO |
| office_expenses | id | uuid | NO |
| office_expenses | business_date | date | NO |
| office_expenses | category | text | NO |
| office_expenses | description | text | NO |
| office_expenses | amount | numeric | NO |
| office_expenses | vehicle_id | uuid | YES |
| office_expenses | driver_id | uuid | YES |
| office_expenses | payment_method | text | NO |
| office_expenses | remarks | text | YES |
| office_expenses | state | text | NO |
| office_expenses | created_by | uuid | NO |
| office_expenses | version | integer | NO |
| oil_changes | maintenance_id | uuid | NO |
| oil_changes | specification | text | NO |
| oil_changes | quantity_litres | numeric | NO |
| oil_changes | previous_date | date | YES |
| oil_changes | previous_odometer | numeric | YES |
| oil_changes | next_due_odometer | numeric | YES |
| period_close_snapshots | id | uuid | NO |
| period_close_snapshots | period_id | uuid | NO |
| period_close_snapshots | close_version | integer | NO |
| period_close_snapshots | summary | jsonb | NO |
| period_close_snapshots | closed_by | uuid | NO |
| period_close_snapshots | closed_at | timestamp with time zone | NO |
| permissions | code | text | NO |
| permissions | description | text | NO |
| revenue_entries | id | uuid | NO |
| revenue_entries | business_date | date | NO |
| revenue_entries | amount | numeric | NO |
| revenue_entries | kind | text | NO |
| revenue_entries | vehicle_id | uuid | YES |
| revenue_entries | driver_id | uuid | YES |
| revenue_entries | trip_id | uuid | YES |
| revenue_entries | booking_id | uuid | YES |
| revenue_entries | reversal_of | uuid | YES |
| revenue_entries | created_by | uuid | NO |
| revenue_entries | created_at | timestamp with time zone | NO |
| role_permissions | role_id | uuid | NO |
| role_permissions | permission_code | text | NO |
| role_permissions | scope | text | NO |
| roles | id | uuid | NO |
| roles | name | text | NO |
| roles | reserved | boolean | NO |
| roles | version | integer | NO |
| settlement_allocations | id | uuid | NO |
| settlement_allocations | cash_transaction_id | uuid | NO |
| settlement_allocations | revenue_entry_id | uuid | YES |
| settlement_allocations | expense_entry_id | uuid | YES |
| settlement_allocations | amount | numeric | NO |
| trip_expense_lines | id | uuid | NO |
| trip_expense_lines | trip_id | uuid | NO |
| trip_expense_lines | category | text | NO |
| trip_expense_lines | business_date | date | NO |
| trip_expense_lines | amount | numeric | NO |
| trip_expense_lines | description | text | NO |
| trip_financials | trip_id | uuid | NO |
| trip_financials | fare | numeric | NO |
| trip_status_history | id | bigint | NO |
| trip_status_history | trip_id | uuid | NO |
| trip_status_history | state | text | NO |
| trip_status_history | reason | text | YES |
| trip_status_history | actor_id | uuid | NO |
| trip_status_history | created_at | timestamp with time zone | NO |
| trips | id | uuid | NO |
| trips | trip_number | text | NO |
| trips | business_date | date | NO |
| trips | vehicle_id | uuid | NO |
| trips | driver_id | uuid | NO |
| trips | cycle_number | text | NO |
| trips | origin | text | YES |
| trips | destination | text | YES |
| trips | route_description | text | YES |
| trips | cargo | text | YES |
| trips | customer_reference | text | YES |
| trips | operational_state | text | NO |
| trips | financial_state | text | NO |
| trips | start_odometer | numeric | NO |
| trips | end_odometer | numeric | YES |
| trips | fuel_litres | numeric | YES |
| trips | fuel_basis | text | NO |
| trips | weight | numeric | YES |
| trips | weight_unit | text | NO |
| trips | remarks | text | YES |
| trips | created_by | uuid | NO |
| trips | created_at | timestamp with time zone | NO |
| trips | version | integer | NO |
| user_roles | user_id | uuid | NO |
| user_roles | role_id | uuid | NO |
| user_vehicle_scopes | user_id | uuid | NO |
| user_vehicle_scopes | vehicle_id | uuid | NO |
| vehicle_driver_assignments | id | uuid | NO |
| vehicle_driver_assignments | vehicle_id | uuid | NO |
| vehicle_driver_assignments | driver_id | uuid | NO |
| vehicle_driver_assignments | started_at | timestamp with time zone | NO |
| vehicle_driver_assignments | ended_at | timestamp with time zone | YES |
| vehicle_driver_assignments | remarks | text | YES |
| vehicle_driver_assignments | created_by | uuid | NO |
| vehicle_financials | vehicle_id | uuid | NO |
| vehicle_financials | purchase_price | numeric | YES |
| vehicles | id | uuid | NO |
| vehicles | registration | text | NO |
| vehicles | manufacturer | text | YES |
| vehicles | model | text | YES |
| vehicles | owner_company_id | uuid | YES |
| vehicles | vehicle_class | text | YES |
| vehicles | purchase_date | date | YES |
| vehicles | opening_odometer | numeric | NO |
| vehicles | current_odometer | numeric | NO |
| vehicles | status | text | NO |
| vehicles | service_interval_km | numeric | YES |
| vehicles | fuel_target | numeric | YES |
| vehicles | document_expiry | date | YES |
| vehicles | remarks | text | YES |
| vehicles | created_by | uuid | NO |
| vehicles | created_at | timestamp with time zone | NO |
| vehicles | updated_at | timestamp with time zone | NO |
| vehicles | version | integer | NO |
| vehicles | purchase_year | integer | YES |
| vehicles | major_maintenance_work | text | YES |