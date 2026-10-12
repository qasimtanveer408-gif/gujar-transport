// Generated from applied migrations in isolated PostgreSQL; not a hosted Supabase verification.
export interface SqlRows {
"accounting_periods": {
"id": string;
"name": string;
"start_date": string;
"end_date": string;
"status": string;
"version": number;
};
"alert_rules": {
"code": string;
"threshold": number;
"enabled": boolean;
"version": number;
};
"app_users": {
"id": string;
"email": string;
"display_name": string;
"active": boolean;
"version": number;
"created_at": string;
"updated_at": string;
"avatar_url": string | null;
"auth_provider": string;
};
"attachments": {
"id": string;
"vehicle_id": string | null;
"driver_id": string | null;
"trip_id": string | null;
"maintenance_id": string | null;
"office_expense_id": string | null;
"bucket_id": string;
"object_path": string;
"original_name": string;
"mime_type": string;
"size_bytes": string;
"state": string;
"created_by": string;
"created_at": string;
"updated_at": string;
};
"audit_logs": {
"id": string;
"actor_id": string | null;
"action": string;
"record_type": string;
"record_id": string | null;
"summary": string;
"created_at": string;
};
"business_settings": {
"id": boolean;
"business_name": string;
"contact_email": string;
"phone_1": string;
"phone_2": string;
"phone_3": string;
"address": string | null;
"currency": string;
"timezone": string;
"period_start_day": number;
"period_confirmed": boolean;
"refresh_seconds": number;
"version": number;
};
"cash_transactions": {
"id": string;
"business_date": string;
"direction": string;
"amount": number;
"reference": string;
"loan_transaction_id": string | null;
"driver_payment_id": string | null;
"created_by": string;
};
"companies": {
"id": string;
"name": string;
"created_by": string | null;
"version": number;
};
"custom_field_definitions": {
"id": string;
"resource": string;
"key": string;
"label": string;
"type": string;
"default_value": unknown | null;
"required": boolean;
"display_order": number;
"show_form": boolean;
"show_card": boolean;
"show_table": boolean;
"show_print": boolean;
"hidden": boolean;
"archived": boolean;
"restricted": boolean;
"options": string;
"formula": string;
"ast": unknown | null;
"dependencies": string;
"required_permissions": string;
"version": number;
"created_by": string;
"created_at": string;
};
"custom_field_values": {
"resource": string;
"record_id": string;
"field_id": string;
"value": unknown | null;
"updated_at": string;
};
"driver_duty_sessions": {
"id": string;
"driver_id": string;
"started_at": string;
"ended_at": string | null;
"created_by": string;
};
"driver_earnings": {
"id": string;
"driver_id": string;
"business_date": string;
"kind": string;
"amount": number;
"state": string;
"trip_line_id": string | null;
"rule_snapshot": string;
"created_by": string;
};
"driver_identity_details": {
"driver_id": string;
"father_name": string | null;
"cnic": string | null;
"licence_number": string | null;
"address": string | null;
"emergency_contact": string | null;
"version": number;
};
"driver_loan_transactions": {
"id": string;
"loan_id": string;
"business_date": string;
"kind": string;
"amount": number;
"reference": string;
"created_by": string;
"created_at": string;
};
"driver_loans": {
"id": string;
"driver_id": string;
"reference": string;
"due_date": string | null;
"created_by": string;
};
"driver_payment_allocations": {
"payment_id": string;
"earning_id": string;
"amount": number;
};
"driver_payments": {
"id": string;
"driver_id": string;
"business_date": string;
"amount": number;
"reference": string;
"created_by": string;
"created_at": string;
};
"drivers": {
"id": string;
"full_name": string;
"mobile": string;
"joining_date": string | null;
"leaving_date": string | null;
"licence_expiry": string | null;
"employment_status": string;
"remarks": string | null;
"created_by": string;
"created_at": string;
"version": number;
"photo_attachment_id": string | null;
};
"expense_categories": {
"code": string;
"label": string;
"active": boolean;
};
"expense_entries": {
"id": string;
"business_date": string;
"amount": number;
"category": string;
"vehicle_id": string | null;
"driver_id": string | null;
"trip_id": string | null;
"trip_line_id": string | null;
"maintenance_item_id": string | null;
"office_expense_id": string | null;
"earning_id": string | null;
"reversal_of": string | null;
"created_by": string;
"created_at": string;
};
"idempotency_keys": {
"key": string;
"actor_id": string;
"action": string;
"record_id": string;
"payload_hash": string;
"created_at": string;
};
"import_batches": {
"id": string;
"resource": string;
"original_reference": string;
"state": string;
"created_by": string;
"created_at": string;
"committed_at": string | null;
};
"import_rows": {
"batch_id": string;
"row_number": number;
"data": unknown;
"record_id": string | null;
};
"job_runs": {
"job_name": string;
"last_completed_at": string | null;
"run_count": string;
};
"maintenance_categories": {
"code": string;
"label": string;
};
"maintenance_components": {
"maintenance_id": string;
"category": string;
"work_detail": string;
};
"maintenance_items": {
"id": string;
"maintenance_id": string;
"kind": string;
"description": string;
"amount": number;
"part_identifier": string | null;
"tyre_position": string | null;
"warranty_until": string | null;
};
"maintenance_records": {
"id": string;
"vehicle_id": string;
"driver_id": string | null;
"trip_id": string | null;
"business_date": string | null;
"odometer": number | null;
"category": string | null;
"description": string | null;
"supplier": string | null;
"next_service_date": string | null;
"next_service_odometer": number | null;
"remarks": string | null;
"state": string;
"created_by": string;
"created_at": string;
"version": number;
"archived_at": string | null;
};
"notification_reads": {
"notification_id": string;
"user_id": string;
"read_at": string;
};
"notifications": {
"id": string;
"dedup_key": string;
"type": string;
"message": string;
"vehicle_id": string | null;
"driver_id": string | null;
"trip_id": string | null;
"action_link": string;
"created_at": string;
"resolved_at": string | null;
};
"office_bookings": {
"id": string;
"business_date": string;
"trip_id": string | null;
"external_vehicle": string | null;
"driver_contact": string | null;
"cargo": string | null;
"origin": string;
"destination": string;
"quoted_freight": number;
"commission": number;
"description": string | null;
"state": string;
"created_by": string;
"version": number;
};
"office_expenses": {
"id": string;
"business_date": string;
"category": string;
"description": string;
"amount": number;
"vehicle_id": string | null;
"driver_id": string | null;
"payment_method": string;
"remarks": string | null;
"state": string;
"created_by": string;
"version": number;
};
"oil_changes": {
"maintenance_id": string;
"specification": string;
"quantity_litres": number;
"previous_date": string | null;
"previous_odometer": number | null;
"next_due_odometer": number | null;
};
"period_close_snapshots": {
"id": string;
"period_id": string;
"close_version": number;
"summary": unknown;
"closed_by": string;
"closed_at": string;
};
"permissions": {
"code": string;
"description": string;
};
"print_template_settings": {
"kind": string;
"orientation": string;
"signatures": string;
"version": number;
};
"revenue_entries": {
"id": string;
"business_date": string;
"amount": number;
"kind": string;
"vehicle_id": string | null;
"driver_id": string | null;
"trip_id": string | null;
"booking_id": string | null;
"reversal_of": string | null;
"created_by": string;
"created_at": string;
};
"role_permissions": {
"role_id": string;
"permission_code": string;
"scope": string;
};
"roles": {
"id": string;
"name": string;
"reserved": boolean;
"version": number;
};
"routes": {
"id": string;
"origin": string;
"destination": string;
"archived": boolean;
"version": number;
"created_by": string;
"created_at": string;
};
"settlement_allocations": {
"id": string;
"cash_transaction_id": string;
"revenue_entry_id": string | null;
"expense_entry_id": string | null;
"amount": number;
};
"trip_expense_lines": {
"id": string;
"trip_id": string;
"category": string;
"business_date": string;
"amount": number;
"description": string;
};
"trip_financials": {
"trip_id": string;
"fare": number;
};
"trip_status_history": {
"id": string;
"trip_id": string;
"state": string;
"reason": string | null;
"actor_id": string;
"created_at": string;
};
"trips": {
"id": string;
"trip_number": string;
"business_date": string;
"vehicle_id": string;
"driver_id": string;
"cycle_number": string;
"origin": string | null;
"destination": string | null;
"route_description": string | null;
"cargo": string | null;
"customer_reference": string | null;
"operational_state": string;
"financial_state": string;
"start_odometer": number;
"end_odometer": number | null;
"fuel_litres": number | null;
"fuel_basis": string;
"weight": number | null;
"weight_unit": string;
"remarks": string | null;
"created_by": string;
"created_at": string;
"version": number;
"archived_at": string | null;
};
"user_roles": {
"user_id": string;
"role_id": string;
};
"user_vehicle_scopes": {
"user_id": string;
"vehicle_id": string;
};
"vehicle_driver_assignments": {
"id": string;
"vehicle_id": string;
"driver_id": string;
"started_at": string;
"ended_at": string | null;
"remarks": string | null;
"created_by": string;
"previous_assignment_id": string | null;
"transfer_date": string | null;
};
"vehicle_financials": {
"vehicle_id": string;
"purchase_price": number | null;
};
"vehicles": {
"id": string;
"registration": string;
"manufacturer": string | null;
"model": string | null;
"owner_company_id": string | null;
"vehicle_class": string | null;
"purchase_date": string | null;
"opening_odometer": number;
"current_odometer": number;
"status": string;
"service_interval_km": number | null;
"fuel_target": number | null;
"document_expiry": string | null;
"remarks": string | null;
"created_by": string;
"created_at": string;
"updated_at": string;
"version": number;
"purchase_year": number | null;
"major_maintenance_work": string | null;
"address": string | null;
"permit_expiry": string | null;
"insurance_expiry": string | null;
};
}
