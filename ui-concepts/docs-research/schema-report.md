# TallyUtility — Data Model Extraction for Zod Schemas & UI Fixtures

**Sources read:**
- `/Users/ryanscomputer/code/tally-utility/application/database/schema.sql` (59 tables, human-readable DDL)
- `/Users/ryanscomputer/code/tally-utility/sql/tu.sql` (the real applied DDL — authoritative)
- `/Users/ryanscomputer/code/tally-utility/sql/v5.4.0-*.sql` … `v5.4.2-11-*.sql` (patch stack)

**Key finding up front:** `schema.sql` contains **zero CHECK constraints**. Every value vocabulary lives in `sql/tu.sql` and the `v5.4.x` patch files. `tu.sql` also adds **23 tables** and ~20 columns not present in `schema.sql`. Anything transcribed from `schema.sql` alone will have the right columns but none of the enums.

There are **no Postgres `ENUM` types and no `DOMAIN`s** in this schema. Every value set is `TEXT` + a `CHECK (col = ANY (ARRAY[...]))` constraint.

---

# 1. Table inventory by domain area

## 1.1 Tenancy & users

| Table | Purpose | Key columns |
|---|---|---|
| `tenants` | Utility company; owns every row in the system. Also carries billing-policy defaults. | `id` PK, `slug` UNIQUE, `name`, `status`, `subscription_tier`, `settings` jsonb, `billing_email`, address cols, `logo_url`, `default_partial_period_policy`, `payment_allocation_strategy`, `overpayment_handling`, `credit_application_timing`, `minimum_refund_amount` num(10,2), `below_threshold_action`, `donation_program_name`, `auto_approve_clean_reads` bool, `unreviewed_read_billing_policy`, `meter_redeployment_policy`, `default_import_error_policy`, `void_only_unbilled_disposition`, `void_rebill_threshold` num(10,2), `onboarded_at`, `created_at`, `updated_at` |
| `users` | Operator accounts; `id` is managed externally (was Supabase Auth). | `id` PK (not generated), `tenant_id` FK, `role`, `display_name`, `email`, `is_active`, `last_login_at`, `preferences` jsonb |
| `tenant_sequences` | Number generators (invoice/customer/meter/etc). | `id` PK, `tenant_id`, `(tenant_id, sequence_type)` UNIQUE, `prefix`, `current_value` bigint, `pad_length` int |
| `tenant_configuration_history` | Append-only log of tenant policy changes (patch v5.4.1-02). | `id` PK, `seq` bigint GENERATED ALWAYS AS IDENTITY UNIQUE, `tenant_id`, `config_key`, `old_value` jsonb, `new_value` jsonb, `effective_from` tstz, `changed_by`, `change_source`, `change_reason`, `created_at` |
| `jurisdictions` | Regulatory jurisdiction; drives WNA applicability (patch v5.4.0-03). | `id` PK, `(tenant_id, jurisdiction_code)` UNIQUE, `jurisdiction_name`, `description`, `wna_applicable` bool, `wna_zone_id` FK, `metadata`, `created_at`, `updated_at` |

## 1.2 Customers / accounts / premises

| Table | Purpose | Key columns |
|---|---|---|
| `customers` | The account of record. ~60 columns spanning identity, contact, deposit summary, tax exemption summary, disconnect protection, billing hold. | `(tenant_id, customer_number)` UNIQUE, `(tenant_id, external_id)` UNIQUE, `customer_type`, `status`, `landlord_customer_id` self-FK, `billing_hold`, `deposit_status`, `is_tax_exempt`, `do_not_disconnect`, `consolidate_invoices`, `is_state_agency` (added by patch -07) |
| `customer_contacts` | Additional contacts on an account. | `customer_id`, `contact_type`, `is_primary`, `can_make_changes`, `first_name`, `last_name`, `title`, `company`, `email`, `phone`, `alt_phone`, `notes` |
| `customer_tax_exemptions` | Certificate-backed exemption detail; bi-temporal since patch -03. | `customer_id`, `exemption_type`, `exemption_reason`, `service_types` text[], `certificate_number`, `issuing_authority`, `certificate_url`, `effective_start` date, `effective_end` date, `status`, `revoked_at/by/reason`, `verified_by/at`, `recorded_at`, `recorded_until`, `change_type`, `change_reason`, `changed_by`, `supersedes_id`, `closed_type`, `closed_reason`, `closed_by` |
| `customer_interactions` | CSR contact log. | `customer_id`, `location_id`, `interaction_type`, `channel`, `reason`, `subject`, `description`, `status`, `resolution`, `resolved_at`, `follow_up_required`, `follow_up_date`, `follow_up_assigned_to`, `handled_by`, `duration_minutes`, `invoice_id` (soft ref), `service_order_id` (soft ref), `ai_audit_id` |
| `customer_credits` | Unapplied credit balances + escheatment tracking. | `customer_id`, `origin_type`, `source_payment_id`, `source_adhoc_charge_id`, `source_invoice_id`, `original_amount`, `applied_amount`, `remaining_amount` (all num(12,2)), `status`, `issued_date`, `expires_date`, `last_activity_date`, `escheat_status`, `due_diligence_sent_at`, `escheated_at`, `escheated_to_jurisdiction`, `escheat_report_reference`, `deposit_id` (added by patch -06) |
| `customer_state_events` | Append-only account-status transition log (patch -06). | `customer_id`, `from_status`, `to_status`, `effective_at` tstz, `reason_code` (non-blank), `changed_by`, `source`, `seq` bigint IDENTITY, `created_at` |
| `customer_attribute_history` | Append-only date-effective attribute change log (patch -06/-07). | `customer_id`, `attribute`, `old_value` text, `new_value` text, `effective_at` tstz, `changed_by`, `source`, `seq` bigint IDENTITY, `created_at` |
| `customer_program_enrollments` | Assistance / disconnect-protection program enrollment (patch -04). | `customer_id`, `program_type` FK→`program_types.code`, `effective_start_date`, `effective_end_date`, `expiry_type`, `status`, `attestation_artifact_url`, `attestation_received_at`, `attestation_verified_at`, `attestation_verified_by`, `enrollment_data` jsonb object, `enrolled_by`, `supersedes_enrollment_id` self-FK |
| `program_types` | Program catalog (tenant-less reference table). | `code` PK, `display_name`, `is_disconnect_protective` bool, `description` |
| `communities` | Subdivisions / MUDs / apartment complexes. | `(tenant_id, community_code)` UNIQUE, `(tenant_id, community_name)` UNIQUE, `community_type`, `contact_name/email/phone`, `city/state/zip`, `master_customer_id`, `total_units_planned`, `build_out_date`, `revenue_category`, `status` |
| `service_locations` | Premise / service point. | `(tenant_id, location_number)` UNIQUE, `(tenant_id, external_id)` UNIQUE, `customer_id`, `community_id`, address cols, `latitude`/`longitude` num(10,7), `parcel_id`, `location_type`, `status`, `inside_city_limits`, `franchise_city`, `billing_cycle`, `billing_cycle_id`, `budget_billing`, `budget_amount`, `jurisdiction_id` (patch) |
| `custom_location_types` | Tenant-defined location types. | `(tenant_id, type_key)` UNIQUE, `type_label`, `description`, `display_order`, `status` |

## 1.3 Meters & reads

| Table | Purpose | Key columns |
|---|---|---|
| `meters` | Physical or virtual meter. | `(tenant_id, meter_number)` UNIQUE, `(tenant_id, external_id)` UNIQUE, `location_id`, `rate_schedule_id`, `service_type`, `is_virtual`, `derives_from_meter_id`, `size`, `read_type`, `multiplier`, `meter_factor`, `gas_btu_factor`, `ami_*`, `route_id` + `route_sequence`, `status`, `start_date`/`end_date`, `estimation_blocked`, `replaces_meter_id`, `swap_reason`. Patch adds `rollover_point`, `meter_pressure_class`, `tamper_flag`, `tamper_reported_at`, `tamper_signal_source`, `tamper_reason`, `zone_confirmed_at/by`, `pressure_class_confirmed_at/by`, `consecutive_estimate_count`, `consecutive_estimate_streak_started_on`, `last_validated_actual_reading_id` |
| `meter_deployments` | Install→removal episodes of a meter at a location. | `(meter_id, deployment_number)` UNIQUE, `location_id`, `rate_schedule_id`, `install_date`, `install_read_value`, `installed_by`/`installed_by_name`, `removal_date`, `removal_read_value`, `removal_reason`, `removed_by`/`removed_by_name`, `warehouse_location_after_removal`, `fp_mismatch_confirmed_at/by`, `fp_mismatch_reason` (patch) |
| `meter_endpoint_history` | AMR/AMI endpoint swap history. | `meter_id`, `endpoint_id`, `endpoint_type`, `install_date`, `removal_date`, `removal_reason`, `installed_by`/`_name`, `removed_by`/`_name` |
| `meter_photos` | Photos + AI dial extraction. | `meter_id`, `meter_reading_id`, `photo_type`, `caption`, `storage_path`, `file_name`, `file_size_bytes`, `mime_type`, `taken_at`, `taken_by`/`taken_by_name`, `latitude`/`longitude`, `gps_accuracy_meters`, `upload_source`, `ai_extraction_status`, `ai_extracted_value` num(14,2), `ai_confidence` num(5,4), `ai_anomalies` text[], `ai_notes`, `ai_extracted_at`, `ai_model_version` |
| `read_routes` | Reader walk routes. | `(tenant_id, route_code)` UNIQUE, `route_name`, `read_frequency`, `typical_read_day` int, `estimated_meter_count`, `estimated_time_hours` num(4,1), `assigned_to`, `assigned_to_user_id`, `default_billing_cycle_id`, `status` |
| `billing_cycles` | Cycle definition. | `(tenant_id, cycle_code)` UNIQUE, `cycle_name`, `frequency`, `read_day` int, `bill_day` int, `due_days_after_bill` int, `read_route_code`, `assigned_reader`, `requires_read_cycle` bool, `status` |
| `read_cycle_instances` | One concrete period of a billing cycle. | `(tenant_id, billing_cycle_id, period)` UNIQUE, `period_start`, `period_end`, `read_window_start`, `read_window_end`, `status`, `issued_at`/`issued_by`, `reads_complete_at`, `completed_by`, `billing_run_id`, `total_meters_locked`, `total_reads_captured`, `total_reads_approved`, `total_meters_skipped`, `reader_overrides` jsonb |
| `read_cycle_meters` | Per-meter worklist row inside an instance. | `(read_cycle_instance_id, meter_id)` UNIQUE, `read_route_id`, `assigned_reader_user_id`, `assigned_reader_name`, `read_status`, `skip_reason`, `expected_read_date`, `captured_at`, `captured_reading_id`, `sequence_in_route` |
| `meter_readings` | The read itself. ~90 columns. | see §4 for the full list |
| `read_validation_exceptions` | Read-level exception queue (patch -05). | see §4 |
| `customer_winter_averages` | Winter-average basis for sewer / WNA. | `(meter_id, winter_year)` UNIQUE, `customer_id`, `winter_months` int[], `avg_consumption` num(14,2), `consumption_unit`, `months_used`, `sample_size`, `computed_at`, `computed_by_user_id`, `confidence` |

## 1.4 Rating / tariffs / PGA / WNA

| Table | Purpose | Key columns |
|---|---|---|
| `rate_schedules` | Tariff header. Content moved to `rate_schedule_versions` in patch -03; the header retains the same columns for compatibility. | `(tenant_id, code)` UNIQUE, `name`, `service_type`, `customer_type`, `wna_zone_id`, `franchise_city`, `regulatory_authority`, `tariff_number`, `tariff_document_url`, `regulatory_code`, `effective_date`, `expiry_date`, `status`, `version` int, `archive_reason`, `activated_at`, `archived_at`, gas/sewer/billing-behavior cols |
| `rate_schedule_versions` | Bi-temporal content of a rate schedule (patch -03). | see §4 |
| `rate_items` | Charge component catalog. | `(tenant_id, item_code)` UNIQUE, `item_name`, `service_type`, `calculation_type`, `current_rate` num(14,6), `rate_unit`, `active_months` int[], `applies_to_customer_types` text[], `update_frequency`, `calc_owner`, `is_taxable_default`, `is_a_tax`, `display_name`, `display_group`, `tier_config` jsonb, `annual_billing_anchor` int, `regulatory_class`, `version` int, `status`, `effective_date`, `expiry_date` |
| `rate_item_versions` | Bi-temporal rate values (patch -03). | `rate_item_id`, `item_name`, `service_type`, `calculation_type`, `rate_value` num(14,6), `rate_unit`, `active_months` int[], `applies_to_customer_types` text[], `update_frequency`, `calc_owner`, `is_taxable_default`, `is_a_tax`, `display_name`, `display_group`, `tier_config` jsonb, `annual_billing_anchor`, `regulatory_class`, `regulatory_reference`, `effective_date`, `expiry_date`, `recorded_at`, `recorded_until`, `change_type`, `change_reason`, `changed_by`, `supersedes_id`, `closed_type`, `closed_reason`, `closed_by` |
| `rate_schedule_items` | Schedule↔item link with per-schedule overrides. | `(rate_schedule_id, rate_item_id, effective_date)` UNIQUE, `rate_override` num(14,6), `rate_unit_override`, `active_months_override` int[], `is_taxable_override` bool, `display_order`, `display_name_override`, `effective_date`, `expiry_date`, `status`, plus bi-temporal cols `recorded_at`, `recorded_until`, `change_type`, `change_reason`, `changed_by`, `supersedes_id`, `closed_type`, `closed_reason`, `closed_by` |
| `rate_item_history` / `rate_item_history_archive` | **Retired.** All DML blocked by triggers. Legacy rate-change log. | `rate_item_id`, `effective_date`, `end_date`, `rate_value`, `rate_unit`, `changed_by`, `change_reason`, `regulatory_reference` |
| `rate_item_dependencies` | Which item's base another item computes on. | `(rate_schedule_id, dependent_rate_item_id, base_rate_item_id)` UNIQUE |
| `franchise_fee_rules` | City franchise fee. Bi-temporal since patch -03. | `(tenant_id, city_name, effective_date)` UNIQUE, `fee_percentage` num(8,6), `applies_to`, `applies_to_customer_types` text[], `effective_date`, `expiry_date`, `status`, `remittance_frequency`, `remittance_contact`, `ordinance_reference`, + bi-temporal cols |
| `regulatory_surcharge_rules` | Regulatory cost-recovery riders, e.g. the Texas Pipeline Safety Fee (patch -07). | `rate_item_id`, `surcharge_kind`, `cycle_start`, `cycle_end`, `cap_per_service` num(12,2), `excluded_from_tax_bases` bool, `exempts_state_agencies` bool, `regulatory_reference`, `tariff_filing_reference`, + bi-temporal cols |
| `regulatory_surcharge_service_locks` | Per-meter once-per-cycle lock for a rider. | PK `(rate_item_id, meter_id)`, `tenant_id`, `touched_at` |
| `wna_zones` | Weather-normalization zone header. | `(tenant_id, zone_code)` UNIQUE, `zone_name`, `active_months` int[] DEFAULT `{11,12,1,2,3,4}`, `normal_hdd` num(10,2), `base_load_consumption` num(10,4), `heating_factor` num(10,6), `weather_station_name`/`_id`, `calc_owner`, `status`, `effective_date`, `expiry_date`, `wna_adjustment_floor`, `wna_adjustment_ceiling`, `wna_clamp_basis`, `version` |
| `wna_zone_versions` | Bi-temporal WNA zone content (patch -03). | `wna_zone_id`, `zone_name`, `active_months`, `normal_hdd`, `base_load_consumption`, `heating_factor`, `calculation_notes`, `weather_station_name`/`_id`, `calc_owner`, `wna_adjustment_floor`, `wna_adjustment_ceiling`, `wna_clamp_basis`, `effective_date`, `expiry_date`, + bi-temporal cols |
| `wna_monthly_adjustments` | Monthly adjustment factor per zone. | `(tenant_id, wna_zone_id, billing_month)` UNIQUE, `actual_hdd`, `normal_hdd`, `adjustment_factor` num(14,6), `adjustment_unit`, `status`, `approved_by`, `approved_at`, + bi-temporal cols |
| `wna_clamp_events` | Log of floor/ceiling clamps applied. | `wna_zone_id`, `wna_monthly_adjustment_id`, `customer_id`, `invoice_id`, `billing_month`, `bound_hit`, `raw_adjustment` num(14,6), `clamped_adjustment` num(14,6), `clamp_basis`, `floor_value_at_clamp`, `ceiling_value_at_clamp` |
| `pga_monitoring_settings` | PGA alert thresholds per tenant. | `tenant_id` UNIQUE, `low_alert_threshold_pct` num(5,2), `medium_alert_threshold_pct` num(5,2), `re_alert_interval_days` int |
| `pga_monthly_reconciliations` | PGA true-up, immutable. | `(tenant_id, reconciliation_month)` UNIQUE, `actual_gas_cost` num(14,2), `pga_recovered_revenue` num(14,2), `monthly_variance` num(14,2), `deferred_balance_after` num(14,2), `trailing_12mo_pga_revenue` num(14,2), `low_threshold_pct_applied`, `medium_threshold_pct_applied`, `threshold_band` |

## 1.5 Billing runs / invoices / lines

| Table | Purpose | Key columns |
|---|---|---|
| `billing_runs` | A bill generation batch. | see §4 |
| `billing_run_meters` | Per-meter outcome inside a run. | `(billing_run_id, meter_id)` UNIQUE, `meter_reading_id`, `invoice_id`, `outcome`, `skip_reason`, `is_estimated_read`, `consumption`, `consumption_unit`, `has_anomaly`, `anomaly_types` text[] |
| `correction_run_targets` | Void→rebill pairing for correction runs. | `(billing_run_id, voided_invoice_id)` UNIQUE, `meter_id`, `customer_id`, `location_id`, `correction_invoice_id`, `rate_date_mode`, `rate_date_override` date, `created_by` |
| `invoices` | The bill. | see §4 |
| `invoice_line_items` | Bill lines. | see §4 |
| `invoice_line_item_bases` | Which lines a percentage-of line was computed on (patch -08). | `(line_item_id, base_line_item_id)` UNIQUE, `invoice_id`, `base_amount` num(12,2) non-zero |
| `invoice_events` | Append-only invoice lifecycle log. | `invoice_id`, `event_type`, `operator_id`, `occurred_at`, `metadata` jsonb |
| `invoice_applications` | Money applied to an invoice. | `invoice_id`, `source_type`, `source_id` uuid, `amount` num(12,2), `applied_at`, `applied_by`, `reversed_at`, `reversed_by`, `reversed_reason`, `notes` |
| `invoice_exceptions` | Bill review queue (patch -05). | see §4 |
| `invoice_calculation_snapshots` | Frozen calculation inputs, 1:1 with invoice (patch -04/-10). | `invoice_id` UNIQUE, `billing_run_id`, `valid_at` date, `recorded_at` tstz, `snapshot_schema_version` (`^v[0-9]+$`), `formula_version`, `rate_inputs`/`gas_factors`/`wna_inputs`/`tax_inputs`/`read_inputs`/`customer_inputs`/`period_inputs` jsonb objects, `line_items` jsonb array, `content_hash` text GENERATED ALWAYS STORED (sha256 hex), `captured_at`, `captured_by`, `notes` |
| `invoice_snapshot_references` | Which reference rows a snapshot consumed. | `(snapshot_id, source_table, source_row_id)` UNIQUE, `role` |
| `adhoc_charges` | One-off charges. | `(tenant_id, charge_number)` UNIQUE, `customer_id`, `location_id`, `meter_id`, `charge_type`, `description`, `amount` num(12,2), `is_taxable`, `service_type`, `effective_date`, `target_billing_period`, `status`, `billed_on_invoice_id`, `billed_on_line_item_id`, `billed_by_billing_run_id`, `billed_at`, `source`, `external_reference`, `triggered_by_payment_id`, `triggered_by_reading_id`, `triggered_by_invoice_id`, `requires_approval`, `approval_threshold_at_creation`, `approved_by`, `approved_at`, `voided_at`/`voided_by`/`void_reason`, `voided_from_invoice_id`, `waived_at`/`waived_by`/`waive_reason`, `created_by`, `created_by_ai`, `ai_audit_id`, `created_by_suggestion_id`, `regulatory_class` (patch) |
| `bill_messages` | Bill inserts / notices. | `title`, `message_body`, `effective_start`, `effective_end`, `target_customer_classes` text[], `target_service_types` text[], `target_service_areas` text[], `target_billing_cycle_ids` uuid[], `priority` int, `display_group`, `status`, `created_by`, `approved_by`, `approved_at` |

## 1.6 Payments / ledger / collections

| Table | Purpose | Key columns |
|---|---|---|
| `payments` | Received money. | see §4 |
| `payment_methods` | Tokenized instruments. | `(provider, provider_token)` UNIQUE, `customer_id`, `method_type`, `last_four`, `card_brand`, `expiry_month`/`expiry_year` smallint, `bank_name`, `account_type`, `holder_name`, `nickname`, `is_default`, `is_active`, `verified_at`, `last_used_at` |
| `auto_pay_settings` | Autopay enrollment, one per customer. | `customer_id` UNIQUE, `payment_method_id`, `enabled`, `billing_day` int, `pause_until`, `pause_reason`, `last_run_at`, `last_run_status`, `next_run_at` date, `consecutive_failures` int, `max_amount` num(12,2), `enrolled_via`, `enrolled_at`, `disabled_at`, `disabled_reason` |
| `payment_provider_logs` | Gateway call log. | `provider`, `endpoint`, `http_method`, `request_body`, `response_body`, `http_status` int, `is_error`, `error_message`, `error_code`, `customer_id`, `payment_id`, `payment_method_id`, `correlation_id`, `operation_type`, `duration_ms` |
| `account_ledger` | Append-only running-balance ledger. | see §4 |
| `deposits` | Security deposits (patch -06). | `customer_id`, `basis`, `trigger_basis`, `instrument`, `principal` num(12,2) >0, `posted_on` date, `source_payment_id`, `cap_amount` num(12,2), `cap_basis_annual_billing` num(12,2), `cap_binding` bool, `instrument_issuer`, `instrument_reference`, `instrument_expires_on`, `status`, `refund_eligibility_on`, `refunded_on`, `released_on`, `legacy_interest_earned` num(12,2), `notes`, `created_by` |
| `deposit_events` | Append-only deposit ledger incl. interest accrual. | `deposit_id`, `event_type`, `amount` num(12,2) ≥0, `effective_on` date, `period_start`, `period_end`, `rate_applied` num(8,6), `principal_basis` num(12,2), `ledger_entry_id`, `reason`, `created_by`, `source` |
| `deposit_interest_rates` | Rate schedule for deposit interest. | `(tenant_id, effective_date)` UNIQUE, `annual_rate` num(8,6) in [0,1], `source_reference`, `notes`, `created_by` |
| `deposit_waiver_determinations` | Why a deposit was waived. | `customer_id`, `waiver_class`, `determined_on` date, `certification_reference`, `certification_expires_on` date, `determined_by`, `notes` |
| `dunning_events` | Collections timeline. | `invoice_id`, `customer_id`, `event_type`, `event_date` tstz, `triggered_by`, `triggered_automatically`, `amount_related` num(12,2), `scheduled_date`, `previous_stage`, `new_stage`, `notes` |
| `escheatment_events` | Unclaimed-property lifecycle. | `customer_credit_id`, `customer_id`, `event_type`, `event_date` tstz, `amount_related`, `notice_method`, `notice_reference`, `jurisdiction`, `regulatory_reference`, `triggered_by`, `triggered_automatically` |

## 1.7 Exceptions / queues / alerts

| Table | Purpose | Key columns |
|---|---|---|
| `alerts` | Operator notifications. | `alert_type`, `priority`, `title`, `message`, `source_type`, `source_id`, `target_user_id`, `target_role`, `channel`, `dedup_key`, `is_read`, `read_at`, `is_dismissed`, `dismissed_at`, `snoozed_until`, `expires_at`, `action_url`, `action_label` |
| `anomalies` | Detected anomalies with dedup + feedback loop. | see §4 |
| `read_validation_exceptions` | Read-level exception queue. | see §4 |
| `invoice_exceptions` | Bill-level review queue. | see §4 |

## 1.8 Service orders / lifecycle

`service_orders` — `(tenant_id, order_number)` UNIQUE, `order_type`, `status`, `priority`, `customer_id`, `location_id`, `meter_id`, `description`, `completion_notes`, `external_order_id`, `external_system`, `requested_date`, `scheduled_date`, `dispatched_at`, `started_at`, `completed_at`, `billing_applied_at`, `assigned_to`, `cancelled_at`, `cancelled_by`, `cancellation_reason`, `parent_order_id` self-FK, `triggered_adhoc_charge_ids` uuid[], `triggered_reading_ids` uuid[], `triggered_new_meter_id`, `triggered_replaced_meter_id`, `created_by_ai`, `ai_audit_id`, `created_by_suggestion_id`, `billing_action_suggestion_id`, `metadata`, `created_at`, `updated_at`.

Conditional CHECKs on `service_orders`:
- `order_type IN ('new_connect','reconnect','disconnect','transfer')` ⇒ `customer_id IS NOT NULL AND location_id IS NOT NULL`
- `order_type IN ('meter_install','meter_replace','meter_change_out','meter_test','meter_reread','meter_test_failed_replace')` ⇒ `meter_id IS NOT NULL`
- `order_type IN ('leak_check','pressure_test','backflow_test','inspection','seasonal_turn_on','seasonal_turn_off')` ⇒ `location_id IS NOT NULL`

## 1.9 Import, custom fields, AI / audit

| Table | Purpose | Key columns |
|---|---|---|
| `import_mapping_templates` | Reusable column mappings. | `(tenant_id, name)` UNIQUE, `import_type`, `source_system`, `source_format`, `column_mapping` jsonb, `learned_transforms` jsonb, `times_used`, `last_used_at`, `last_success_rate` num(5,4), `status`, `created_by` |
| `import_jobs` | An import run. | `(tenant_id, idempotency_key)` UNIQUE, `initiated_by`, `import_type`, `source_type`, `source_file_url`, `source_filename`, `source_file_size_bytes`, `source_file_hash`, `mapping_template_id`, `column_mapping` jsonb, `error_handling_policy`, `is_dry_run`, `import_summary` jsonb, `status`, `mapping_suggestion_id`, row counters (`total_rows`, `processed_rows`, `committed_rows`, `held_rows`, `error_rows`, `warning_rows`, `skipped_rows`), `ai_extraction_log` jsonb, `validation_errors` jsonb, `started_at`, `completed_at` |
| `import_column_mappings` | Per-column mapping decisions. | `(import_job_id, source_column_position)` UNIQUE, `source_column_name`, `sample_values` jsonb, `content_classification`, `classification_confidence` num(3,2), `proposed_target_field`, `mapping_confidence` num(3,2), `proposed_transforms` jsonb, `operator_decision`, `final_target_field`, `final_transforms` jsonb, `operator_notes`, `decided_by`, `decided_at`, `has_outlier_pattern`, `outlier_count` |
| `import_staging` | Staged rows. | `import_job_id`, `row_number`, `raw_data` jsonb, `mapped_data` jsonb, `status`, `matched_by`, `errors` jsonb, `warnings` jsonb, `target_entity`, `target_id`, `depends_on_row_numbers` int[] |
| `custom_field_definitions` | Tenant-defined extra fields. | `(tenant_id, entity_type, field_key)` UNIQUE, `field_label`, `field_type`, `is_required`, `is_searchable`, `is_visible_on_list`, `is_sensitive`, `display_order`, `default_value`, `options` jsonb, `validation_rules` jsonb, `help_text`, `status`, `created_by`, `updated_by` |
| `ai_sessions` | Chat sessions. | `user_id`, `title`, `auto_titled`, `status`, `started_at`, `ended_at`, `last_activity_at`, `message_count`, `tool_call_count`, `suggestion_count`, `total_input_tokens`, `total_output_tokens`, `total_cost_usd` num(10,4), `primary_provider`, `primary_model_id` |
| `ai_audit_log` | Every AI action. | `session_id`, `user_id`, `parent_audit_id`, `action_type`, `triggered_by`, `ai_response_type`, `entity_type`, `entity_id`, `user_prompt`, `ai_interpretation`, `result_summary`, `error_message`, `suggestion_id`, `entity_changes` jsonb, `provider`, `model_id`, `input_tokens`, `output_tokens`, `cost_usd` num(10,6), `latency_ms` |
| `ai_suggestions` | Proposed mutations awaiting approval. | `session_id`, `audit_log_id`, `proposed_by_user_id`, `suggestion_type`, `title`, `reasoning`, `confidence` num(3,2), `primary_entity_type`, `primary_entity_id`, `proposed_changes` jsonb, `status`, `reviewed_by`, `reviewed_at`, `decision_reason`, `rejected_items` jsonb, `executed_at`, `execution_audit_log_id`, `execution_error`, `expires_at`, `superseded_by_id` |
| `ai_tool_calls` | Tool invocations. | `audit_log_id`, `session_id`, `sequence_number`, `tool_name`, `tool_category`, `tool_input` jsonb, `tool_output` jsonb, `output_summary`, `status`, `error_message`, `suggestion_id`, `started_at`, `completed_at`, `duration_ms` |
| `materialized_view_refresh_log` | MV refresh bookkeeping. | `view_name` PK, `last_refresh_at`, `last_duration_ms`, `last_error` |

---

# 2. Every enumerated / CHECK-constrained value set

All are `TEXT` columns with `CHECK (col = ANY (ARRAY[...]))`. Exact values, verbatim.

## 2.1 Service & customer classification

- **`service_type`** — `meters`, `adhoc_charges`, `rate_schedules`, `rate_schedule_versions`:
  `water`, `sewer`, `electric`, `gas`, `stormwater`, `trash`, `reclaimed_water`
- **`service_type`** — `rate_items`, `rate_item_versions` (adds `all`):
  `water`, `sewer`, `electric`, `gas`, `stormwater`, `trash`, `reclaimed_water`, `all`
- **`service_type`** — `invoice_line_items` (adds `general`):
  `water`, `sewer`, `electric`, `gas`, `stormwater`, `trash`, `reclaimed_water`, `general`
- **`customer_type`** — `customers`, `rate_schedules`, `rate_schedule_versions`:
  `residential`, `commercial`, `small_commercial`, `large_commercial`, `industrial`, `government`, `wholesale`
  - note: `rate_items.applies_to_customer_types` and `franchise_fee_rules.applies_to_customer_types` DEFAULT to the narrower array `{residential,commercial,industrial,government,wholesale}`
- **`meter_readings.consumption_unit`**:
  `gallons`, `ccf`, `cubic_feet`, `kgal`, `kwh`, `therms`, `cubic_meters`, `mcf`, `kw`

## 2.2 Status values — one per table, do NOT share a single Zod enum

| Table.column | Allowed values |
|---|---|
| `tenants.status` | `onboarding`, `active`, `suspended`, `churned` |
| `tenants.subscription_tier` | `starter`, `professional`, `enterprise` |
| `users.role` | `platform_admin`, `tenant_admin`, `operator`, `viewer` |
| `customers.status` | `active`, `inactive`, `final_billed`, `collections`, `closed` |
| `service_locations.status` | `active`, `inactive`, `demolished` |
| `communities.status` | `active`, `inactive`, `closed` |
| `custom_location_types.status` | `active` (+ generic; no explicit CHECK found) |
| `meters.status` | `active`, `inactive`, `removed`, `failed`, `testing` |
| `meter_readings.status` | `active`, `disputed`, `under_review`, `replaced`, `voided` |
| `meter_readings.validation_status` | `pending_review`, `reviewed_clean`, `reviewed_with_exception`, `approved`, `released_to_billing`, `locked`, `void_released`, `excluded` |
| `read_cycle_instances.status` | `draft`, `issued`, `reading`, `reads_complete`, `billed`, `cancelled` |
| `read_cycle_meters.read_status` | `pending`, `reading`, `captured`, `validated`, `approved`, `skipped`, `cant_read` |
| `read_routes.status` | `active`, `inactive`, `archived` |
| `billing_cycles.status` | `active`, `paused`, `archived` |
| `billing_runs.status` | `pending`, `in_progress`, `review`, `approved`, `posted`, `failed`, `cancelled` |
| `invoices.status` | `draft`, `pending`, `held`, `sent`, `paid`, `partial`, `overdue`, `void`, `write_off` |
| `adhoc_charges.status` | `pending`, `billed`, `void`, `waived`, `void_pending_rebill` |
| `payments.status` | `pending`, `posted`, `nsf`, `reversed`, `refunded`, `voided` |
| `customer_credits.status` | `active`, `fully_applied`, `refunded`, `donated`, `escheated`, `voided` |
| `customer_tax_exemptions.status` | `pending_verification`, `active`, `expired`, `revoked`, `rejected` |
| `customer_interactions.status` | `open`, `in_progress`, `waiting_customer`, `resolved`, `escalated`, `closed` |
| `customer_program_enrollments.status` | `pending_application`, `active`, `expired`, `breached`, `canceled`, `superseded` |
| `service_orders.status` | `open`, `scheduled`, `dispatched`, `in_progress`, `on_hold`, `awaiting_billing_action`, `completed`, `requires_followup`, `cancelled`, `superseded` |
| `anomalies.status` | `open`, `acknowledged`, `investigating`, `resolved`, `false_positive`, `deferred`, `snoozed` |
| `read_validation_exceptions.status` | `open`, `resolved` |
| `invoice_exceptions.status` | `open`, `resolved`, `overridden` |
| `deposits.status` | `held`, `partial_applied`, `applied`, `refund_pending`, `refunded`, `released` |
| `rate_schedules.status` | `draft`, `active`, `expired`, `archived` — an older narrower CHECK (`draft`, `active`, `archived`) is also present |
| `rate_items.status` | `active`, `paused`, `archived` |
| `rate_schedule_items.status` | `active`, `paused`, `archived` |
| `wna_zones.status` | `active`, `paused`, `archived` |
| `franchise_fee_rules.status` | `active`, `superseded`, `archived` |
| `wna_monthly_adjustments.status` | `pending`, `approved`, `applied`, `archived` |
| `bill_messages.status` | `draft`, `active`, `archived` |
| `import_jobs.status` | `pending`, `inspecting`, `awaiting_mapping_approval`, `validating`, `validated`, `awaiting_error_review`, `importing`, `complete`, `partial`, `failed`, `cancelled` |
| `import_staging.status` | `pending`, `valid`, `warning`, `failed_validation`, `failed_fk_reference`, `awaiting_dependency`, `awaiting_review`, `imported`, `imported_with_warnings`, `updated_existing`, `skipped`, `rejected_by_operator` |
| `import_mapping_templates.status` | `active`, `archived`, `draft` |
| `custom_field_definitions.status` | `active` (+ generic) |
| `ai_sessions.status` | `active`, `ended`, `archived`, `deleted` |
| `ai_suggestions.status` | `pending`, `approved`, `partially_approved`, `rejected`, `expired`, `executed`, `execution_failed`, `superseded` |
| `ai_tool_calls.status` | `pending`, `success`, `error`, `timeout`, `rejected_by_user` |
| `pga_monthly_reconciliations.threshold_band` | `none`, `low`, `medium` |

## 2.3 Invoicing

- **`invoices.invoice_type`**: `regular`, `final`, `correction`, `duplicate`, `prebill`, `consolidated`, `credit_memo`
- **`invoices.dunning_stage`**: `current`, `reminder_sent`, `late_fee_assessed`, `shutoff_warning`, `shutoff_scheduled`, `disconnected`, `payment_plan`, `collections`, `resolved`, `written_off`
- **`invoices.void_reason_code`**: `wrong_read`, `wrong_rate`, `wrong_customer`, `duplicate`, `service_date_error`, `system_error`, `other`
- **`invoices.delivery_method`**: `email`, `mail`, `both`, `portal_only`, `text_message`
- **`customers.billing_delivery_method`**: `email`, `mail`, `both`, `portal_only` (no `text_message`)
- **`invoice_line_items.charge_type`**: `base_charge`, `usage_charge`, `surcharge`, `tax`, `late_fee`, `deposit`, `credit`, `adjustment`, `penalty`, `adhoc`, `minimum_bill_adjustment`, `consolidated_summary`, `misc`
- **`invoice_line_items.partial_period_policy_applied`**, **`rate_schedules.partial_period_policy`**, **`rate_schedules.partial_period_policy_override`**, **`rate_schedule_versions.partial_period_policy(_override)`**, **`tenants.default_partial_period_policy`**: `prorated`, `charge_both`, `period_holder`
- **`invoice_events.event_type`** (current, widened by patch -05): `created`, `sent`, `held`, `released_from_hold`, `voided`, `void_attempted_blocked`, `correction_initiated`, `correction_posted`, `payment_applied`, `written_off`, `status_changed`, `reversal_chain_depth_exceeded`, `exception_raised`, `exception_resolved`, `exception_overridden`
  - two earlier narrower CHECKs also exist: one omitting the three `exception_*` values, and one further omitting `reversal_chain_depth_exceeded`

## 2.4 Billing runs

- **`billing_runs.run_type`**: `regular`, `off_cycle`, `correction`, `final`, `dry_run` (an earlier CHECK omits `dry_run`)
- **`billing_runs.generation_method`**: `manual`, `scheduled`, `api`, `ai_initiated`
- **`billing_run_meters.outcome`**: `billed`, `billed_estimated`, `skipped_no_read`, `skipped_pending_review`, `skipped_no_rate_schedule`, `skipped_inactive_mid_run`, `skipped_excluded_reading`, `skipped_negative_consumption`, `skipped_zero_usage_suppressed`, `skipped_unbillable`, `failed_calculation`
- **`correction_run_targets.rate_date_mode`**: `run_default`, `historical`, `current`, `custom`

## 2.5 Meter reads

- **`meter_readings.read_method`**: `manual`, `ami`, `amr`, `estimated`, `customer_reported`, `rolled_back`, `virtual`, `photo_ai`
- **`meters.read_type`**: `manual`, `ami`, `amr`, `estimated`, `virtual`
- **`meter_readings.reading_purpose`**: `regular_cycle`, `final_read`, `initial_read`, `special_request`, `audit`, `turn_on`, `turn_off`, `dispute_recheck`, `installation`, `removal`
- **`meter_readings.register_type`**: `main`, `reverse_flow`, `demand`, `generation`, `tou_peak`, `tou_off_peak`, `tou_shoulder`, `secondary`, `other`
- **`meter_readings.access_status`**: `accessed`, `locked_gate`, `aggressive_dog`, `meter_buried`, `meter_obstructed`, `meter_damaged`, `meter_not_found`, `unsafe_conditions`, `no_access_permission`, `key_required`, `ami_offline`, `other`
- **`meter_readings.quality_flag`**: `normal`, `high`, `low`, `zero`, `negative`, `suspect`, `verified`
- **`meter_readings.estimation_reason`**: `access_issue`, `meter_malfunction`, `new_meter_install`, `ami_sync_failure`, `prior_estimation_correction`, `seasonal_closure`, `historical_average`, `same_period_prior_year`, `weather_prevented_read`, `other`
- **`meter_readings.amr_read_status`**: `success`, `partial`, `no_response`, `invalid`, `timeout`, `manual_override`
- **`meter_readings.followup_priority`**: `low`, `normal`, `high`, `urgent`
- **`read_cycle_meters.skip_reason`** (nullable): `no_access`, `locked_gate`, `dog`, `hazard`, `meter_damaged`, `customer_refused`, `weather`, `other`
- **`read_routes.read_frequency`**: `daily`, `weekly`, `biweekly`, `monthly`, `bimonthly`, `quarterly`
- **`billing_cycles.frequency`** and **`service_locations.billing_cycle`**: `monthly`, `bimonthly`, `quarterly`

## 2.6 Meters

- **`meters.size`**: `5/8_inch`, `3/4_inch`, `1_inch`, `1.5_inch`, `2_inch`, `3_inch`, `4_inch`, `6_inch`, `8_inch`, `10_inch`, `12_inch`, `other`
- **`meters.ami_sync_status`**: `not_configured`, `active`, `error`, `paused` (the literal `not_configured` is duplicated in the CHECK array as written)
- **`meters.last_test_result`**: `passed`, `failed`, `conditional`, `not_tested`
- **`meters.swap_reason`**: `upgrade_size`, `damage`, `hardware_failure`, `ami_upgrade`, `tamper`, `weather`, `end_of_life`, `customer_request`, `accuracy_test_failure`, `other`
- **`meter_deployments.removal_reason`**: `upgrade_size`, `damage`, `hardware_failure`, `ami_upgrade`, `tamper`, `weather`, `end_of_life`, `customer_request`, `accuracy_test_failure`, `testing_required`, `relocation`, `other`
- **`meter_endpoint_history.removal_reason`**: `failed`, `battery_dead`, `upgrade`, `damaged`, `theft`, `meter_removal`, `other`
- **`meters.tamper_signal_source`** (nullable): `ami_alarm`, `field_observation`, `billing_analyst_flagged`
- **`meters.meter_pressure_class`** (nullable): `residential_base`, `elevated`
- **`meter_photos.photo_type`**: `install`, `inspection`, `annual`, `damage`, `tamper`, `leak`, `removal`, `reading`, `access_issue`, `other`
- **`meter_photos.ai_extraction_status`**: `not_attempted`, `pending`, `success`, `low_confidence`, `failed`, `manual_override`
- **`meter_photos.upload_source`**: `web_upload`, `mobile_web`, `customer_portal`, `email`, `api`, `import`

## 2.7 Exception queues

- **`read_validation_exceptions.rule_code`**: `high_vs_history`, `low_vs_history`, `reverse_read`, `max_dial_rollover`, `consecutive_estimate_over_cap`, `zero_read_active_account`, `reading_date_gap`, `negative_consumption`, `meter_master_incomplete`, `tamper_indicated`, `other`
- **`read_validation_exceptions.resolution_disposition`** (nullable): `estimate_accepted`, `manual_read_entered`, `read_corrected`, `field_order_dispatched`, `excluded`, `override`
- **`read_validation_exceptions.detected_by`**: `system`, `operator`, `import`
- **`invoice_exceptions.criterion`**: `high_bill`, `zero_bill_active_account`, `negative_bill`, `consecutive_estimate_streak`, `out_of_tolerance_usage`, `rider_trueup_over_threshold`, `missing_rebill_approval`, `unresolved_read_exception`, `batch_baseline_breach`, `meter_master_incomplete`, `tamper_detected`, `canary_mismatch`, `manual`, `other`
- **`invoice_exceptions.queue`**: `batch_hold`, `billing_analyst`, `senior_analyst`, `csr`, `field_ops`, `informational`
- **`invoice_exceptions.exception_source`**: `bill_detector`, `batch_baseline`, `read_carryforward`, `manual`
- **`invoice_exceptions.escalation_target`** (nullable): `senior_analyst`, `billing_manager`, `cfo`
- **`severity`** on `read_validation_exceptions`, `invoice_exceptions`, `anomalies`: `low`, `medium`, `high`, `critical`

## 2.8 Anomalies & alerts

- **`anomalies.anomaly_type`** (37 values, current widened list):
  `high_usage`, `low_usage`, `zero_usage`, `negative_consumption`, `possible_leak`, `stuck_meter`, `meter_rollover`, `tamper_detected`, `endpoint_offline`, `repeated_access_issue`, `endpoint_swap_unreported`, `missing_reading`, `estimated_streak`, `partial_period_anomaly`, `unbilled_service`, `unbilled_usage`, `rate_mismatch`, `rate_schedule_mismatch`, `billing_run_exception`, `revenue_leakage`, `duplicate_account`, `address_mismatch`, `stale_account`, `unusual_payment_pattern`, `auto_pay_failure_streak`, `payment_method_expiring`, `multiple_nsf_pattern`, `credit_balance_stale`, `deposit_refund_overdue`, `escheatment_due`, `escheatment_overdue`, `tax_exemption_expired`, `disconnect_protection_expiring`, `import_column_outlier_pattern`, `import_low_confidence_mapping`, `reference_correction_review`, `other`
  - an earlier CHECK is identical minus `reference_correction_review`
- **`anomalies.entity_type`** (constrained by patch -11 — **singular** names):
  `customer`, `service_location`, `meter`, `meter_reading`, `invoice`, `invoice_line_item`, `billing_run`, `rate_schedule`, `payment`, `payment_method`, `customer_credit`, `deposit`, `customer_tax_exemption`, `escheatment_event`, `import_job`
- **`anomalies.detection_method`**: `statistical`, `rule_based`, `ai_analysis`, `manual`
- **`anomalies.feedback_category`**: `true_positive_resolved`, `true_positive_escalated`, `false_positive_threshold_too_tight`, `false_positive_seasonal_variation`, `false_positive_known_issue`, `false_positive_other`
- **`alerts.alert_type`**: `anomaly`, `billing_exception`, `meter_issue`, `import_complete`, `import_error`, `system`, `payment_received`, `payment_nsf`, `payment_method_expiring`, `auto_pay_disabled`, `account_past_due`, `disconnect_warning`, `credit_approaching_escheat`, `dunning_action_due`, `tax_exemption_expiring`, `disconnect_protection_expiring`, `bill_message_approaching_expiry`, `billing_run_review_needed`, `ai_suggestion`, `suggestion_needs_review`, `tool_approval_needed`
- **`alerts.channel`**: `in_app`, `email`, `sms`, `push`, `multiple`
- **`alerts.priority`**: `low`, `normal`, `high`, `urgent`

## 2.9 Payments, ledger, credits, deposits

- **`payments.payment_method`**: `cash`, `check`, `ach`, `credit_card`, `debit_card`, `money_order`, `online`, `auto_pay`, `write_off`, `refund`, `wire`, `other`
- **`payments.channel`**: `portal`, `mobile_app`, `agent_phone`, `ivr`, `walk_in`, `mail`, `auto_pay`, `batch_file`, `api`, `lockbox`
- **`payments.source_system`**: `internal`, `paymentus_webhook`, `stripe_webhook`, `bank_lockbox`, `imported`, `other_webhook`
- **`payments.deposit_status`**: `held`, `partial_applied`, `applied`, `refunded`
- **`customers.deposit_status`**: `none`, `held`, `partial_applied`, `applied`, `refunded`, `refund_pending`
- **`payment_methods.method_type`**: `credit_card`, `debit_card`, `ach`, `bank_account`
- **`payment_methods.account_type`**: `checking`, `savings`, `business_checking`, `business_savings`
- **`auto_pay_settings.last_run_status`**: `success`, `failed`, `skipped_paused`, `skipped_no_balance`, `skipped_below_threshold`
- **`auto_pay_settings.enrolled_via`** and **`customers.donation_opt_in_source`**: `portal`, `paper_form`, `phone`, `agent`, `in_person`
- **`account_ledger.transaction_type`** (current, widened by patch -06):
  `charge`, `payment`, `adjustment`, `credit_issued`, `credit_applied`, `late_fee`, `deposit`, `refund`, `write_off`, `transfer`, `nsf`, `escheat`, `donation`, `void_reversal`, `deposit_interest`
  - earlier CHECK omits `deposit_interest`
- **`account_ledger.reference_type`** (current, widened by patch -06):
  `invoice`, `payment`, `customer_credit`, `adhoc_charge`, `invoice_application`, `billing_run`, `escheatment_event`, `manual`, `invoice_void`, `refund`, `deposit`
  - earlier CHECK omits `deposit`
- **`customer_credits.origin_type`**: `overpayment`, `goodwill`, `dispute_resolution`, `deposit_refund`, `transfer`, `adjustment`, `refund_reissue`, `regulatory_rebate`, `promotion`, `other`
- **`customer_credits.escheat_status`**: `active`, `dormancy_approaching`, `due_diligence_sent`, `escheated`, `owner_claimed`
- **`deposits.basis`**: `credit_evaluation`, `adequate_assurance_366`, `additional_trigger`, `tariff`, `legacy_unknown`
- **`deposits.trigger_basis`** (nullable; required iff `basis = 'additional_trigger'`): `nsf`, `disconnect_history`, `broken_dpa`
- **`deposits.instrument`**: `cash`, `letter_of_credit`, `certificate_of_deposit`, `surety_bond`, `prepayment`, `guarantor`, `other_agreed`
- **`deposit_events.event_type`**: `posted`, `applied_to_balance`, `interest_accrued`, `interest_credited`, `refund_initiated`, `refunded`, `released`
- **`deposit_events.source`**: `operator`, `system`, `backfill`
- **`deposit_waiver_determinations.waiver_class`**: `family_violence_certified`, `age_65_no_balance`, `good_payment_history`, `tariff`
- **`dunning_events.event_type`**: `reminder_sent`, `late_fee_applied`, `shutoff_notice_sent`, `shutoff_scheduled`, `disconnected`, `reconnected`, `payment_plan_created`, `payment_plan_broken`, `sent_to_collections`, `written_off`, `resolved`
- **`escheatment_events.event_type`**: `dormancy_flag`, `due_diligence_sent`, `owner_responded`, `owner_claimed_credit`, `escheated_to_state`, `owner_reclaimed_from_state`, `exemption_applied`, `donated`
- **`escheatment_events.notice_method`**: `email`, `first_class_mail`, `certified_mail`, `registered_mail`

## 2.10 Rating / tariffs

- **`calculation_type`** (`rate_items`, `rate_item_versions`): `fixed_monthly`, `fixed_annual`, `per_unit_usage`, `percentage_of_bill`, `percentage_of_charges`, `usage_modifier`, `tiered_usage`, `formula`
- **`rate_unit`** (`rate_items`, `rate_item_versions`): `flat`, `per_month`, `per_year`, `per_day`, `per_gallon`, `per_kgal`, `per_ccf`, `per_mcf`, `per_therm`, `per_kwh`, `per_cubic_meter`, `percent`, `decimal`
- **`display_group`** (`rate_items`, `rate_item_versions`): `base_charges`, `usage_charges`, `riders`, `taxes_fees`, `adjustments`, `other`
- **`calc_owner`** (`rate_items`, `rate_item_versions`, also `wna_zones`/`wna_zone_versions`): `regulatory`, `gas_marketing`, `accounting`, `finance`, `strategic_finance`, `state_of_tx`, `external`, `operations`, `other`
- **`update_frequency`**: `never`, `monthly`, `quarterly`, `annually`, `on_rate_case`, `as_needed`
- **`regulatory_class`** (`rate_items`, `rate_item_versions`, `adhoc_charges`): `regulated`, `unregulated`
- **`sewer_calc_method`**: `flat`, `metered`, `winter_avg`, `percent_of_water`
- **`gas_usage_formula`**: `standard`, `with_meter_factor`, `with_temp_factor`
- **`estimation_method`** (nullable): `historical_average_3mo`, `historical_average_12mo`, `same_period_prior_year`, `last_actual_reading`, `zero`
- **`rate_schedules.archive_reason`** (nullable): `abandoned_draft`, `superseded_by_filing`, `service_discontinued`
- **`franchise_fee_rules.applies_to`**: `total_bill`, `gross_revenue`, `base_and_usage`, `usage_only`
- **`franchise_fee_rules.remittance_frequency`**: `monthly`, `quarterly`, `annually`
- **`regulatory_surcharge_rules.surcharge_kind`**: `pipeline_safety_fee`, `other_regulatory_cost_recovery`
- **`wna_monthly_adjustments.adjustment_unit`**: `per_mcf`, `per_ccf`, `per_therm`, `percent`, `flat`
- **`wna_zone_versions.wna_clamp_basis`** and **`wna_clamp_events.clamp_basis`**: `percent_of_base`, `dollars`
- **`wna_clamp_events.bound_hit`**: `floor`, `ceiling`
- **`customer_winter_averages.confidence`**: `good`, `partial`, `insufficient`
- **`invoice_snapshot_references.source_table`** (current, widened by patch -07):
  `rate_schedule_versions`, `wna_zone_versions`, `rate_item_versions`, `rate_schedule_items`, `franchise_fee_rules`, `customer_tax_exemptions`, `wna_monthly_adjustments`, `regulatory_surcharge_rules`
  - earlier CHECK omits `regulatory_surcharge_rules`
- **`rate_items.annual_billing_anchor`**: integer 1–12 or NULL
- **`winter_avg_months`** / **`active_months`**: integer arrays constrained to be subsets of `{1..12}`, length 1–12

## 2.11 Bi-temporal vocabulary (shared by all versioned reference tables)

- **`change_type`**: `initial`, `succession`, `correction`, `backfill`
- **`closed_type`** (nullable): `superseded`, `retracted`
- **`rate_schedule_versions.service_type_change_basis`** (nullable): `transcription_error` only — and only when `supersedes_id IS NOT NULL`

## 2.12 Customers

- **`customers.id_type`**: `drivers_license`, `state_id`, `passport`, `military_id`, `matricula`, `other`
- **`customers.tax_id_type`**: `ssn`, `ein`, `itin`
- **`customers.preferred_contact_method`**: `mail`, `email`, `phone`, `text`, `portal`
- **`customers.preferred_language`**: `en`, `es`, `vi`, `zh`, `ko`, `other`
- **`customers.disconnect_protection_type`**: `medical_certificate`, `elderly_disabled`, `military_deployment`, `bankruptcy_automatic_stay`, `regulatory_moratorium`, `payment_arrangement`, `pending_dispute`, `other`
- **`customers.tax_exemption_reason`**: `residential`, `government`, `nonprofit_501c3`, `religious`, `educational`, `agricultural`, `industrial_manufacturing`, `reseller`, `diplomatic`, `other`
- **`customer_tax_exemptions.exemption_type`**: `non_profit`, `government`, `agricultural`, `industrial`, `sales_for_resale`, `religious`, `educational`, `medical`, `other`
  - an earlier CHECK omits `industrial`
- **`customer_contacts.contact_type`**: `billing`, `service`, `emergency`, `authorized_agent`, `property_manager`, `other`
- **`customer_interactions.interaction_type`**: `phone_inbound`, `phone_outbound`, `email_inbound`, `email_outbound`, `walk_in`, `portal_message`, `mail_inbound`, `mail_outbound`, `text_inbound`, `text_outbound`, `ai_chat`, `field_visit`, `other`
- **`customer_interactions.channel`**: `phone`, `email`, `in_person`, `portal`, `mail`, `text`, `ai`, `field`, `other`
- **`customer_interactions.reason`**: `billing_inquiry`, `payment_issue`, `high_bill_complaint`, `service_request`, `leak_report`, `water_quality`, `outage_report`, `meter_issue`, `disconnect_reconnect`, `payment_arrangement`, `name_address_change`, `general_inquiry`, `complaint`, `compliment`, `other`
- **`customer_attribute_history.attribute`** (current, widened by patch -07): `billing_delivery_method`, `billing_hold`, `consolidate_invoices`, `do_not_disconnect`, `landlord_responsible`, `customer_type`, `autopay_enabled`, `deposit_status`, `is_state_agency`
  - earlier CHECK omits `is_state_agency`
  - additional CHECK: for the boolean attributes (`billing_hold`, `consolidate_invoices`, `do_not_disconnect`, `landlord_responsible`, `autopay_enabled`, `is_state_agency`), `new_value` must be `'true'` or `'false'` and `old_value` must be NULL or `'true'`/`'false'`
- **`customer_attribute_history.source`** and **`customer_state_events.source`**: `operator`, `system`, `initial`, `backfill`
- **`customer_state_events.from_status`** (nullable) / **`to_status`**: `active`, `inactive`, `final_billed`, `collections`, `closed`
- **`communities.community_type`**: `subdivision`, `mud`, `hoa`, `apartment_complex`, `mobile_home_park`, `commercial_development`, `industrial_park`, `mixed_use`, `municipality`, `other`
- **`customer_program_enrollments.expiry_type`**: `calendar`, `event`

## 2.13 Service orders & ad-hoc charges

- **`service_orders.order_type`**: `new_connect`, `disconnect`, `reconnect`, `transfer`, `meter_install`, `meter_replace`, `meter_change_out`, `meter_test`, `meter_reread`, `meter_test_failed_replace`, `final_read`, `leak_check`, `pressure_test`, `backflow_test`, `inspection`, `tamper_response`, `damage_repair`, `customer_complaint`, `seasonal_turn_on`, `seasonal_turn_off`, `adjustment`, `other`
- **`service_orders.priority`**: `low`, `normal`, `high`, `emergency`
- **`adhoc_charges.charge_type`**: `tap_fee`, `reconnection_fee`, `disconnection_fee`, `after_hours_fee`, `meter_test_fee`, `meter_install_fee`, `damage_fee`, `returned_payment_fee`, `late_fee`, `penalty`, `deposit`, `deposit_refund`, `credit`, `adjustment`, `backflow_test_fee`, `hydrant_meter_rental`, `miscellaneous`
- **`adhoc_charges.source`**: `manual`, `service_order`, `ai_suggestion`, `import`, `system_generated`, `payment_reversal`

## 2.14 Tenant policy vocabularies

- **`tenants.payment_allocation_strategy`**: `oldest_first`, `newest_first`, `largest_first`, `manual_only`
- **`tenants.overpayment_handling`**: `hold_as_credit`, `refund_automatically`, `apply_to_specific_invoices`
- **`tenants.credit_application_timing`**: `on_invoice_generation`, `on_due_date`, `manual_only`
- **`tenants.meter_redeployment_policy`**: `reuse_record`, `new_record`, `either`
- **`tenants.unreviewed_read_billing_policy`**: `block_run`, `skip_unreviewed`, `proceed_with_warning`
- **`tenant_configuration_history.change_source`**: `onboarding`, `trigger`, `backfill`, `manual`
- **`tenant_configuration_history.config_key`** — must match `settings.%` OR be one of: `default_partial_period_policy`, `payment_allocation_strategy`, `overpayment_handling`, `credit_application_timing`, `minimum_refund_amount`, `below_threshold_action`, `donation_program_name`, `auto_approve_clean_reads`, `unreviewed_read_billing_policy`, `meter_redeployment_policy`, `default_import_error_policy`, `void_only_unbilled_disposition`, `void_rebill_threshold`

## 2.15 Import / custom fields / AI

- **`import_type`** (`import_jobs`, `import_mapping_templates`): `customers`, `meters`, `readings`, `rates`, `payments`, `locations`, `full_system`, `custom`
- **`import_jobs.source_type`**: `csv`, `excel`, `pdf`, `legacy_export`, `api`, `ai_extracted`
- **`import_staging.matched_by`**: `external_id`, `customer_number`, `location_number`, `meter_number`, `composite_key`, `none`
- **`import_column_mappings.content_classification`**: `person_name`, `company_name`, `address`, `city`, `state`, `zip_code`, `phone`, `email`, `date`, `currency`, `number`, `text`, `boolean`, `id_or_code`, `meter_serial`, `amr_ami_endpoint`, `mixed`, `empty`, `unknown`
- **`import_column_mappings.operator_decision`**: `pending`, `accepted`, `overridden`, `ignored`
- **`custom_field_definitions.field_type`**: `text`, `number`, `decimal`, `date`, `boolean`, `select`, `multi_select`, `email`, `phone`, `url`, `textarea`
- **`custom_field_definitions.entity_type`** (**plural** table names — different from `anomalies.entity_type`): `customers`, `service_locations`, `meters`, `meter_readings`, `invoices`, `billing_runs`, `service_orders`, `payments`, `customer_credits`, `adhoc_charges`
- **`custom_field_definitions.field_key`** — must NOT be any of: `id`, `tenant_id`, `status`, `created_at`, `updated_at`, `metadata`, `notes`, `customer_number`, `location_number`, `meter_number`, `invoice_number`, `run_number`, `payment_number`, `charge_number`, `order_number`, `customer_id`, `location_id`, `meter_id`, `invoice_id`, `billing_run_id`, `payment_id`, `charge_id`, `order_id`, `amount`, `description`, `effective_date`, `due_date`, `start_date`, `end_date`, `created_by`, `updated_by`, `approved_by`, `approved_at`
- **`ai_audit_log.action_type`**: `query`, `analysis`, `report_generation`, `navigation`, `suggestion_created`, `suggestion_approved`, `suggestion_rejected`, `mutation_executed`, `clarification`, `error`
- **`ai_audit_log.triggered_by`**: `user_chat`, `user_report_request`, `user_navigation`, `scheduled_analysis`, `webhook`
- **`ai_audit_log.ai_response_type`**: `text_answer`, `report_export`, `chart`, `navigation`, `data_table`, `suggestion`, `error`, `clarification_request`
- **`ai_suggestions.suggestion_type`**: `waive_late_fee`, `adjust_invoice`, `apply_credit`, `transfer_credit`, `merge_duplicate_customers`, `update_customer_field`, `update_meter_field`, `create_adhoc_charge`, `reverse_payment`, `update_rate_assignment`, `send_email_draft`, `close_anomaly`, `schedule_service_order`, `mark_disconnect_protection`, `other`
- **`ai_tool_calls.tool_category`**: `read`, `generate`, `navigation`, `write`, `external_api`
- **`payment_provider_logs.operation_type`**: `tokenize`, `charge`, `refund`, `void`, `capture`, `webhook_received`, `status_check`, `method_list`, `method_delete`
- **`payment_provider_logs.http_method`**: `GET`, `POST`, `PUT`, `DELETE`, `PATCH`
- **`bill_messages.display_group`**: `header`, `footer`, `notice_box`, `insert`

---

# 3. Date-effectivity / bi-temporal column patterns

There are **four distinct patterns**. Do not collapse them into one Zod mixin.

### Pattern A — Full bi-temporal (valid time + transaction time)

Columns:
```
effective_date   DATE        NOT NULL      -- valid time start
expiry_date      DATE        NULL          -- valid time end (open-ended when NULL)
recorded_at      TIMESTAMPTZ NOT NULL DEFAULT now()   -- transaction time start
recorded_until   TIMESTAMPTZ NULL          -- transaction time end
change_type      TEXT        NOT NULL      -- initial | succession | correction | backfill
change_reason    TEXT        NULL
changed_by       UUID        NULL
supersedes_id    UUID        NULL          -- self-FK
closed_type      TEXT        NULL          -- superseded | retracted
closed_reason    TEXT        NULL
closed_by        UUID        NULL
```

Tables using it:
- `rate_schedule_versions`
- `rate_item_versions`
- `wna_zone_versions`
- `rate_schedule_items`
- `franchise_fee_rules`
- `wna_monthly_adjustments`
- `regulatory_surcharge_rules`
- `customer_tax_exemptions` — same transaction-time columns, but valid time uses **`effective_start` / `effective_end`** instead of `effective_date` / `expiry_date`

Invariants enforced across all of them:
- `expiry_date IS NULL OR expiry_date >= effective_date`
- `change_type = 'correction'` ⇒ `change_reason IS NOT NULL`
- `supersedes_id IS NOT NULL` ⇒ `change_type IN ('succession','correction')`
- The close quartet is all-NULL or all-set: either (`recorded_until`, `closed_type`, `closed_reason`, `closed_by`) are all NULL, or (`recorded_until`, `closed_type`, `closed_reason`) are all NOT NULL with `recorded_until >= recorded_at`
- A `BEFORE INSERT OR UPDATE OR DELETE` trigger (`a_enforce_bitemporal_assertion` / `b_enforce_bitemporal_assertion`) makes the row an assertion, never an edit

### Pattern B — Simple valid-time bracket (no transaction time)

- `rate_schedules`: `effective_date` / `expiry_date`
- `rate_items`: `effective_date` / `expiry_date`
- `wna_zones`: `effective_date` / `expiry_date`
- `bill_messages`: `effective_start` / `effective_end`
- `customer_program_enrollments`: `effective_start_date` / `effective_end_date`
- `regulatory_surcharge_rules`: additionally `cycle_start` / `cycle_end` (the rider's recovery cycle)
- `deposit_interest_rates`: `effective_date` alone (open-ended forward)
- `rate_item_history` / `rate_item_history_archive` (retired): `effective_date` / `end_date`

### Pattern C — Append-only event log with an effective instant + monotonic sequence

- `customer_state_events`: `effective_at` TIMESTAMPTZ, `seq` bigint GENERATED ALWAYS AS IDENTITY, `source`, `created_at`
- `customer_attribute_history`: `effective_at` TIMESTAMPTZ, `seq` bigint IDENTITY, `source`, `created_at`
- `tenant_configuration_history`: `effective_from` TIMESTAMPTZ, `seq` bigint IDENTITY UNIQUE, `created_at`
- `deposit_events`: `effective_on` DATE, plus `period_start` / `period_end` DATE for `interest_accrued` rows only
- `invoice_events`: `occurred_at` TIMESTAMPTZ (no `seq`; ordering by `occurred_at`)
- `dunning_events`, `escheatment_events`: `event_date` TIMESTAMPTZ
- `wna_clamp_events`: `billing_month` DATE + `created_at`

### Pattern D — Snapshot coordinate pair

`invoice_calculation_snapshots` carries **both** halves of the bi-temporal coordinate as the as-of point used to price the invoice:
- `valid_at` DATE — the point in valid time (which tariff was in force)
- `recorded_at` TIMESTAMPTZ — the point in transaction time (what the database believed at that moment)

Every temporal lookup for that invoice must use both. Patch v5.4.2-10 binds this pair to facts the database itself holds (period end inside the run window, recorded rate-date election for corrections).

### Episodic lifecycle windows (date-bracketed but not temporal versioning)

- `meters`: `start_date` / `end_date`, plus `install_date` / `removal_date`
- `meter_deployments`: `install_date` / `removal_date`
- `meter_endpoint_history`: `install_date` / `removal_date`
- `customers`: `disconnect_protection_start` / `disconnect_protection_expiry`, `move_in_date`, `tax_exemption_expiry_date`
- `read_cycle_instances`: `period_start` / `period_end` and `read_window_start` / `read_window_end`
- `invoices`: `period_start` / `period_end`, `invoice_date`, `due_date`
- `invoice_line_items`: `coverage_start` / `coverage_end` with `days_covered` / `days_in_period`
- `deposits`: `posted_on`, `refund_eligibility_on`, `refunded_on`, `released_on`, `instrument_expires_on`
- `deposit_waiver_determinations`: `determined_on`, `certification_expires_on`
- `customer_credits`: `issued_date`, `expires_date`, `last_activity_date`

---

# 4. Full column lists for the first-iteration UI tables

These 16 tables cover customer 360, meter read exceptions, bill review, rate schedule, and invoice detail.

## 4.1 `customers`

```
id                              UUID PK DEFAULT uuid_generate_v4()
tenant_id                       UUID NOT NULL FK→tenants(id)
customer_number                 TEXT NOT NULL          -- UNIQUE (tenant_id, customer_number)
customer_type                   TEXT NOT NULL DEFAULT 'residential'
-- Identity
first_name                      TEXT
last_name                       TEXT
company_name                    TEXT
date_of_birth                   DATE
tax_id_type                     TEXT
tax_id_last4                    TEXT
ssn_on_file                     BOOLEAN NOT NULL DEFAULT FALSE
id_type                         TEXT
id_number                       TEXT
id_issuing_state                TEXT
id_expiration_date              DATE
id_verified                     BOOLEAN NOT NULL DEFAULT FALSE
id_verified_by                  UUID FK→users(id)
id_verified_at                  TIMESTAMPTZ
-- Contact
email                           TEXT
phone                           TEXT
alt_phone                       TEXT
preferred_contact_method        TEXT DEFAULT 'mail'
preferred_language              TEXT DEFAULT 'en'
billing_delivery_method         TEXT NOT NULL DEFAULT 'email'
-- Billing address
billing_address_line1           TEXT
billing_address_line2           TEXT
billing_city                    TEXT
billing_county                  TEXT
billing_state                   TEXT
billing_zip                     TEXT
-- Landlord / ownership
is_property_owner               BOOLEAN NOT NULL DEFAULT TRUE
landlord_customer_id            UUID FK→customers(id)
landlord_responsible            BOOLEAN NOT NULL DEFAULT FALSE
-- Disconnect protection
do_not_disconnect               BOOLEAN NOT NULL DEFAULT FALSE
disconnect_protection_type      TEXT
disconnect_protection_start     DATE
disconnect_protection_expiry    DATE
disconnect_protection_notes     TEXT
-- Deposit summary (projection of the deposits table)
deposit_amount                  NUMERIC(12,2) DEFAULT 0
deposit_status                  TEXT DEFAULT 'none'
deposit_received_date           DATE
deposit_refund_date             DATE
deposit_refund_amount           NUMERIC(12,2)
deposit_interest_earned         NUMERIC(12,2) DEFAULT 0
deposit_notes                   TEXT
move_in_date                    DATE
-- Tax exemption summary (detail in customer_tax_exemptions)
is_tax_exempt                   BOOLEAN NOT NULL DEFAULT FALSE
tax_exemption_reason            TEXT
tax_exemption_certificate       TEXT
tax_exemption_expiry_date       DATE
tax_exemption_notes             TEXT
tax_exemption_verified_by       UUID FK→users(id)
tax_exemption_verified_at       TIMESTAMPTZ
-- Donation opt-in
donation_opt_in                 BOOLEAN NOT NULL DEFAULT FALSE
donation_opt_in_date            DATE
donation_opt_in_source          TEXT
-- Billing hold
billing_hold                    BOOLEAN NOT NULL DEFAULT FALSE
billing_hold_reason             TEXT
billing_hold_set_at             TIMESTAMPTZ
billing_hold_set_by             UUID FK→users(id)
-- Invoice consolidation
consolidate_invoices            BOOLEAN NOT NULL DEFAULT FALSE
-- Status & lifecycle (status_* added by patch v5.4.2-06)
status                          TEXT NOT NULL DEFAULT 'active'
status_reason                   TEXT
status_changed_at               TIMESTAMPTZ
status_changed_by               UUID
-- Regulatory (added by patch v5.4.2-07)
is_state_agency                 BOOLEAN NOT NULL DEFAULT FALSE
-- Metadata
notes                           TEXT
metadata                        JSONB NOT NULL DEFAULT '{}'
external_id                     TEXT                   -- UNIQUE (tenant_id, external_id)
external_id_source              TEXT
created_at                      TIMESTAMPTZ NOT NULL DEFAULT now()
updated_at                      TIMESTAMPTZ NOT NULL DEFAULT now()
```

## 4.2 `service_locations`

```
id                  UUID PK
tenant_id           UUID NOT NULL FK→tenants(id)
customer_id         UUID NOT NULL FK→customers(id)
community_id        UUID FK→communities(id)
location_number     TEXT NOT NULL          -- UNIQUE (tenant_id, location_number)
address_line1       TEXT NOT NULL
address_line2       TEXT
city                TEXT NOT NULL
county              TEXT
state               TEXT NOT NULL
zip                 TEXT NOT NULL
latitude            NUMERIC(10,7)
longitude           NUMERIC(10,7)
parcel_id           TEXT
location_type       TEXT DEFAULT 'residential_single_family'
status              TEXT NOT NULL DEFAULT 'active'
inside_city_limits  BOOLEAN NOT NULL DEFAULT TRUE
franchise_city      TEXT
billing_cycle       TEXT NOT NULL DEFAULT 'monthly'
billing_cycle_id    UUID FK→billing_cycles(id)
budget_billing      BOOLEAN NOT NULL DEFAULT FALSE
budget_amount       NUMERIC(12,2)
jurisdiction_id     UUID FK→jurisdictions(id)   -- patch v5.4.0-03
metadata            JSONB NOT NULL DEFAULT '{}'
external_id         TEXT                   -- UNIQUE (tenant_id, external_id)
external_id_source  TEXT
created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
```

## 4.3 `meters`

```
id                          UUID PK
tenant_id                   UUID NOT NULL FK→tenants(id)
meter_number                TEXT NOT NULL          -- UNIQUE (tenant_id, meter_number)
location_id                 UUID NOT NULL FK→service_locations(id)
rate_schedule_id            UUID FK→rate_schedules(id)
service_type                TEXT NOT NULL
is_virtual                  BOOLEAN NOT NULL DEFAULT FALSE
derives_from_meter_id       UUID FK→meters(id)
-- Physical
manufacturer                TEXT
model                       TEXT
serial_number               TEXT
size                        TEXT
dial_count                  INTEGER
num_dials                   INTEGER DEFAULT 6
seal_number                 TEXT
install_date                DATE
removal_date                DATE
warranty_expiration         DATE
-- Read configuration
read_type                   TEXT NOT NULL DEFAULT 'manual'
multiplier                  NUMERIC(10,4) NOT NULL DEFAULT 1.0
-- Gas-specific
meter_factor                NUMERIC(10,6)
gas_btu_factor              NUMERIC(10,6)
-- AMI/AMR
ami_system                  TEXT
ami_endpoint_id             TEXT
ami_api_config              JSONB DEFAULT '{}'
ami_last_sync_at            TIMESTAMPTZ
ami_sync_status             TEXT DEFAULT 'not_configured'
ami_sync_error              TEXT
-- Testing / maintenance
test_interval_months        INTEGER
last_test_date              DATE
next_test_due_date          DATE
last_test_result            TEXT
-- Route assignment
route_id                    UUID FK→read_routes(id)
route_sequence              INTEGER
-- Status & lifecycle
status                      TEXT NOT NULL DEFAULT 'active'
start_date                  DATE NOT NULL DEFAULT CURRENT_DATE
end_date                    DATE
last_read_value             NUMERIC(14,2)
last_read_date              DATE
location_notes              TEXT
-- Estimation control
estimation_blocked          BOOLEAN NOT NULL DEFAULT FALSE
estimation_blocked_reason   TEXT
estimation_blocked_set_at   TIMESTAMPTZ
estimation_blocked_set_by   UUID FK→users(id)
-- Swap lineage
replaces_meter_id           UUID FK→meters(id)
swap_reason                 TEXT
warehouse_location          TEXT
-- Added by patches v5.4.0-02 / v5.4.1-01 / v5.4.2-05
rollover_point                          NUMERIC(14,2)
meter_pressure_class                    TEXT
tamper_flag                             BOOLEAN NOT NULL DEFAULT FALSE
tamper_reported_at                      TIMESTAMPTZ
tamper_signal_source                    TEXT
tamper_reason                           TEXT
zone_confirmed_at                       TIMESTAMPTZ
zone_confirmed_by                       UUID
pressure_class_confirmed_at             TIMESTAMPTZ
pressure_class_confirmed_by             UUID
consecutive_estimate_count              INTEGER NOT NULL DEFAULT 0
consecutive_estimate_streak_started_on  DATE
last_validated_actual_reading_id        UUID
-- Metadata
metadata                    JSONB NOT NULL DEFAULT '{}'
external_id                 TEXT                   -- UNIQUE (tenant_id, external_id)
external_id_source          TEXT
created_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
```

## 4.4 `meter_readings`

```
id                              UUID PK
tenant_id                       UUID NOT NULL FK→tenants(id)
meter_id                        UUID NOT NULL FK→meters(id)
billing_cycle_id                UUID FK→billing_cycles(id)
read_cycle_meter_id             UUID FK→read_cycle_meters(id)
location_id                     UUID                    -- added by patch (denormalized, trigger-populated)
-- Register
register_type                   TEXT NOT NULL DEFAULT 'main'
register_label                  TEXT
-- Values
reading_date                    DATE NOT NULL
reading_value                   NUMERIC(14,2) NOT NULL
previous_value                  NUMERIC(14,2)
previous_reading_date           DATE
consumption                     NUMERIC(14,2)
consumption_unit                TEXT NOT NULL DEFAULT 'gallons'
days_in_period                  INTEGER
raw_read_value                  NUMERIC(14,2)
-- Read method & collector
read_method                     TEXT NOT NULL DEFAULT 'manual'
read_by                         TEXT
data_collector_user_id          TEXT
read_sequence_number            INTEGER
actual_read_order               INTEGER
reading_timestamp               TIMESTAMPTZ
reading_purpose                 TEXT NOT NULL DEFAULT 'regular_cycle'
-- GPS
gps_latitude                    NUMERIC(10,7)
gps_longitude                   NUMERIC(10,7)
gps_accuracy_rating             TEXT
gps_changed_latitude            NUMERIC(10,7)
gps_changed_longitude           NUMERIC(10,7)
-- AMR / endpoint
endpoint_id                     TEXT
changed_endpoint_id             TEXT
endpoint_type_received          TEXT
extended_endpoint_type_received TEXT
endpoint_read_datetime          TIMESTAMPTZ
-- Access
access_status                   TEXT NOT NULL DEFAULT 'accessed'
access_notes                    TEXT
skip_code                       TEXT
force_complete_reason_code      TEXT
trouble_code_1                  TEXT
trouble_code_2                  TEXT
trouble_message                 TEXT
read_condition                  TEXT
amr_read_status                 TEXT
-- Tamper
tamper_count_1                  INTEGER
tamper_count_2                  INTEGER
tamper_count_1_changed_flag     BOOLEAN DEFAULT FALSE
tamper_count_2_changed_flag     BOOLEAN DEFAULT FALSE
tamper_investigated             BOOLEAN NOT NULL DEFAULT FALSE
tamper_investigation_notes      TEXT
-- Estimation
is_estimated                    BOOLEAN NOT NULL DEFAULT FALSE
estimation_reason               TEXT
-- Quality & status
quality_flag                    TEXT DEFAULT 'normal'
status                          TEXT NOT NULL DEFAULT 'active'
-- Replacement lineage
replaced_by_reading_id          UUID FK→meter_readings(id)
replaces_reading_id             UUID FK→meter_readings(id)
replaces_read_id                UUID FK→meter_readings(id)
voided_from_invoice_id          UUID FK→invoices(id)
-- Dispute
dispute_reason                  TEXT
dispute_raised_by               UUID FK→users(id)
dispute_raised_at               TIMESTAMPTZ
dispute_resolved_by             UUID FK→users(id)
dispute_resolved_at             TIMESTAMPTZ
dispute_resolution_notes        TEXT
-- Gas-specific computed
gas_meter_factor                NUMERIC(10,6)
gas_pressure_corrected_volume   NUMERIC(14,2)
gas_btu_factor                  NUMERIC(10,6)
gas_therms                      NUMERIC(14,2)
-- Contextual comparison
consumption_prior_period            NUMERIC(14,2)
consumption_same_period_last_year   NUMERIC(14,2)
consumption_pct_vs_typical          NUMERIC(8,2)
-- Service transition
is_service_transition               BOOLEAN NOT NULL DEFAULT FALSE
transition_outgoing_customer_id     UUID FK→customers(id)
transition_incoming_customer_id     UUID FK→customers(id)
-- Validation workflow
validation_status               TEXT NOT NULL DEFAULT 'pending_review'
auto_approved                   BOOLEAN NOT NULL DEFAULT FALSE
validated_by                    UUID FK→users(id)
validated_at                    TIMESTAMPTZ
assigned_to_user_id             UUID FK→users(id)
-- Billing lock
billing_period_locked           BOOLEAN NOT NULL DEFAULT FALSE
locked_at                       TIMESTAMPTZ
locked_by_billing_run_id        UUID FK→billing_runs(id)
locked_by_invoice_id            UUID FK→invoices(id)
triggers_correction_workflow    BOOLEAN NOT NULL DEFAULT FALSE
-- Field confirmation
confirmed_by_field_reader_at    TIMESTAMPTZ
confirmed_by_field_reader_id    UUID FK→users(id)
-- Attempt tracking
attempted_count                 INTEGER NOT NULL DEFAULT 1
requires_followup               BOOLEAN NOT NULL DEFAULT FALSE
followup_priority               TEXT
followup_notes                  TEXT
-- Source
source_system                   TEXT
import_job_id                   UUID FK→import_jobs(id)
vendor_reference                TEXT
entered_by                      UUID FK→users(id)
notes                           TEXT
created_at                      TIMESTAMPTZ NOT NULL DEFAULT now()
```

## 4.5 `read_validation_exceptions`

```
id                      UUID PK
tenant_id               UUID NOT NULL FK→tenants(id)
meter_reading_id        UUID NOT NULL          -- FK (meter_reading_id, tenant_id) → meter_readings(id, tenant_id)
meter_id                UUID NOT NULL          -- FK (meter_id, tenant_id) → meters(id, tenant_id)
rule_code               TEXT NOT NULL
severity                TEXT NOT NULL DEFAULT 'medium'
detail                  JSONB NOT NULL DEFAULT '{}'    -- must be a JSON object
detected_at             TIMESTAMPTZ NOT NULL DEFAULT now()
detected_by             TEXT NOT NULL DEFAULT 'system'
raised_by_user_id       UUID FK→users(id)
status                  TEXT NOT NULL DEFAULT 'open'
resolution_disposition  TEXT
resolution_reason_code  TEXT
resolution_notes        TEXT
resolved_by             UUID FK→users(id)
resolved_at             TIMESTAMPTZ
field_order_id          UUID                   -- FK (field_order_id, tenant_id) → service_orders(id, tenant_id)
replacement_reading_id  UUID                   -- FK (replacement_reading_id, tenant_id) → meter_readings(id, tenant_id)
notes                   TEXT
created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
-- UNIQUE (id, tenant_id)
```

Resolution invariants (CHECK constraints):
- `status = 'open'` ⇒ `resolution_disposition`, `resolution_reason_code`, `resolved_by`, `resolved_at`, `field_order_id`, `replacement_reading_id` are all NULL
- `status = 'resolved'` ⇒ `resolution_disposition IS NOT NULL`, `resolution_reason_code` non-blank, `resolved_by IS NOT NULL`, `resolved_at IS NOT NULL`
- `resolution_disposition = 'field_order_dispatched'` ⇒ `field_order_id IS NOT NULL`
- `resolution_disposition IN ('manual_read_entered','read_corrected')` ⇒ `replacement_reading_id IS NOT NULL`
- `rule_code = 'consecutive_estimate_over_cap'` may only resolve with disposition `override` or `field_order_dispatched`

## 4.6 `invoices`

```
id                          UUID PK
tenant_id                   UUID NOT NULL FK→tenants(id)
invoice_number              TEXT NOT NULL          -- UNIQUE (tenant_id, invoice_number)
billing_run_id              UUID FK→billing_runs(id)
customer_id                 UUID NOT NULL FK→customers(id)
location_id                 UUID FK→service_locations(id)
-- Consolidation
parent_invoice_id           UUID FK→invoices(id)
is_consolidated             BOOLEAN NOT NULL DEFAULT FALSE
is_consolidated_child       BOOLEAN NOT NULL DEFAULT FALSE
-- Type & lineage
invoice_type                TEXT NOT NULL DEFAULT 'regular'
replaces_invoice_id         UUID FK→invoices(id)   -- tenant-composite FK as of patch -10
-- Period
invoice_date                DATE NOT NULL
billing_period              TEXT NOT NULL
period_start                DATE NOT NULL
period_end                  DATE NOT NULL
due_date                    DATE NOT NULL
-- Financials
previous_balance            NUMERIC(12,2) NOT NULL DEFAULT 0
total_charges               NUMERIC(12,2) NOT NULL DEFAULT 0
total_credits               NUMERIC(12,2) NOT NULL DEFAULT 0
total_taxes                 NUMERIC(12,2) NOT NULL DEFAULT 0
total_adjustments           NUMERIC(12,2) NOT NULL DEFAULT 0
amount_due                  NUMERIC(12,2) NOT NULL DEFAULT 0
amount_paid                 NUMERIC(12,2) NOT NULL DEFAULT 0
balance                     NUMERIC(12,2) NOT NULL DEFAULT 0
tax_breakdown               JSONB NOT NULL DEFAULT '[]'
-- Read flags
has_estimated_reads         BOOLEAN NOT NULL DEFAULT FALSE
estimated_read_count        INTEGER NOT NULL DEFAULT 0
-- Late fees
late_fee_assessed           BOOLEAN NOT NULL DEFAULT FALSE
late_fee_amount             NUMERIC(12,2) DEFAULT 0
-- Collections
dunning_stage               TEXT NOT NULL DEFAULT 'current'
write_off_reason            TEXT
write_off_date              DATE
write_off_approved_by       UUID FK→users(id)
-- Anomalies
has_anomalies               BOOLEAN NOT NULL DEFAULT FALSE
-- Hold
held_at                     TIMESTAMPTZ
held_by                     UUID FK→users(id)
hold_reason                 TEXT
-- Delivery
delivery_method             TEXT DEFAULT 'email'
sent_at                     TIMESTAMPTZ
pdf_url                     TEXT                   -- write-once once set
pdf_generated_at            TIMESTAMPTZ            -- write-once once set
delivery_confirmed_at       TIMESTAMPTZ
delivery_failed_reason      TEXT
delivery_attempts           INTEGER NOT NULL DEFAULT 0
-- Void
voided_at                   TIMESTAMPTZ            -- write-once; only with status='void'
voided_by                   UUID FK→users(id)
void_reason_code            TEXT
void_reason_notes           TEXT
void_rebill_expected        BOOLEAN NOT NULL DEFAULT TRUE
-- Issuance stamp (patch v5.4.2-10) — database-stamped, write-once
first_issued_at             TIMESTAMPTZ
-- Status
status                      TEXT NOT NULL DEFAULT 'draft'
notes                       TEXT
metadata                    JSONB NOT NULL DEFAULT '{}'
created_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
```

## 4.7 `invoice_line_items`

```
id                              UUID PK
tenant_id                       UUID NOT NULL FK→tenants(id)
invoice_id                      UUID NOT NULL FK→invoices(id)
line_order                      INTEGER NOT NULL DEFAULT 0
service_type                    TEXT NOT NULL
meter_id                        UUID FK→meters(id)
charge_type                     TEXT NOT NULL
description                     TEXT NOT NULL
rate_schedule_id                UUID FK→rate_schedules(id)
rate_item_id                    UUID FK→rate_items(id)
meter_reading_id                UUID FK→meter_readings(id)
adhoc_charge_id                 UUID FK→adhoc_charges(id)
-- Usage detail
usage_quantity                  NUMERIC(14,2)
usage_unit                      TEXT
rate                            NUMERIC(12,6)
tier_label                      TEXT
-- Period coverage
coverage_start                  DATE
coverage_end                    DATE
days_covered                    INTEGER
days_in_period                  INTEGER
partial_period_policy_applied   TEXT
-- Tax
taxable_amount                  NUMERIC(12,2)
is_taxable                      BOOLEAN NOT NULL DEFAULT FALSE
-- Gas-specific
gas_meter_factor                NUMERIC(10,6)
gas_ccf_used                    NUMERIC(14,2)
gas_therms_billed               NUMERIC(14,2)
gas_commodity_rate              NUMERIC(12,6)
-- Amount
amount                          NUMERIC(12,2) NOT NULL
metadata                        JSONB NOT NULL DEFAULT '{}'
created_at                      TIMESTAMPTZ NOT NULL DEFAULT now()
-- UNIQUE (id, tenant_id) added by patch for composite FKs
```

## 4.8 `invoice_exceptions`

```
id                              UUID PK
tenant_id                       UUID NOT NULL FK→tenants(id)
invoice_id                      UUID NOT NULL          -- FK (invoice_id, tenant_id) → invoices(id, tenant_id) ON DELETE CASCADE
billing_run_id                  UUID FK→billing_runs(id)
criterion                       TEXT NOT NULL
severity                        TEXT NOT NULL DEFAULT 'medium'
exception_source                TEXT NOT NULL DEFAULT 'bill_detector'
detail                          JSONB NOT NULL DEFAULT '{}'   -- must be a JSON object
estimated_impact                NUMERIC(12,2)
queue                           TEXT NOT NULL
blocks_delivery                 BOOLEAN NOT NULL
sla_days                        INTEGER                -- NULL or >= 0
escalation_target               TEXT
routing_reason                  TEXT NOT NULL          -- non-blank
anomaly_id                      UUID FK→anomalies(id)
read_validation_exception_id    UUID                   -- FK (..., tenant_id) → read_validation_exceptions(id, tenant_id)
detected_at                     TIMESTAMPTZ NOT NULL DEFAULT now()
raised_by_user_id               UUID FK→users(id)
assigned_to                     UUID FK→users(id)
status                          TEXT NOT NULL DEFAULT 'open'
resolution_reason_code          TEXT
resolution_notes                TEXT
resolved_by                     UUID FK→users(id)
resolved_at                     TIMESTAMPTZ
notes                           TEXT
created_at                      TIMESTAMPTZ NOT NULL DEFAULT now()
```

Invariants:
- `criterion = 'unresolved_read_exception'` ⇒ `read_validation_exception_id IS NOT NULL`
- `status = 'open'` ⇒ `resolution_reason_code`, `resolved_by`, `resolved_at` all NULL
- `status IN ('resolved','overridden')` ⇒ `resolution_reason_code` non-blank, `resolved_by IS NOT NULL`, `resolved_at IS NOT NULL`

## 4.9 `billing_runs`

```
id                      UUID PK
tenant_id               UUID NOT NULL FK→tenants(id)
run_number              TEXT NOT NULL          -- UNIQUE (tenant_id, run_number)
billing_period          TEXT NOT NULL
period_start            DATE NOT NULL
period_end              DATE NOT NULL
billing_cycle_id        UUID FK→billing_cycles(id)
read_cycle_instance_id  UUID FK→read_cycle_instances(id)
run_type                TEXT NOT NULL DEFAULT 'regular'
is_dry_run              BOOLEAN NOT NULL DEFAULT FALSE
scope                   JSONB NOT NULL DEFAULT '{}'
data_cutoff_at          TIMESTAMPTZ
generation_method       TEXT NOT NULL DEFAULT 'manual'
generated_by            UUID FK→users(id)
correction_rate_mode    TEXT NOT NULL DEFAULT 'historical'
status                  TEXT NOT NULL DEFAULT 'pending'
-- Counters
total_locations         INTEGER DEFAULT 0
total_invoices          INTEGER DEFAULT 0
total_amount            NUMERIC(14,2) DEFAULT 0
total_exceptions        INTEGER DEFAULT 0
total_estimated_reads   INTEGER DEFAULT 0
-- Lifecycle
started_at              TIMESTAMPTZ            -- database-stamped, write-once (patch -10)
completed_at            TIMESTAMPTZ
last_heartbeat_at       TIMESTAMPTZ
approved_by             UUID FK→users(id)
approved_at             TIMESTAMPTZ
posted_by               UUID FK→users(id)
posted_at               TIMESTAMPTZ
cancelled_at            TIMESTAMPTZ
cancelled_by            UUID FK→users(id)
notes                   TEXT
created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
```

## 4.10 `billing_run_meters`

```
id                  UUID PK
tenant_id           UUID NOT NULL FK→tenants(id)
billing_run_id      UUID NOT NULL FK→billing_runs(id)
meter_id            UUID NOT NULL FK→meters(id)
meter_reading_id    UUID FK→meter_readings(id)
invoice_id          UUID FK→invoices(id)
outcome             TEXT NOT NULL
skip_reason         TEXT
is_estimated_read   BOOLEAN NOT NULL DEFAULT FALSE
consumption         NUMERIC(14,2)
consumption_unit    TEXT
has_anomaly         BOOLEAN NOT NULL DEFAULT FALSE
anomaly_types       TEXT[]
created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
-- UNIQUE (billing_run_id, meter_id)
```

## 4.11 `rate_schedules` (header)

```
id                              UUID PK
tenant_id                       UUID NOT NULL FK→tenants(id)
code                            TEXT NOT NULL          -- UNIQUE (tenant_id, code)
name                            TEXT NOT NULL
description                     TEXT
service_type                    TEXT NOT NULL
customer_type                   TEXT NOT NULL
wna_zone_id                     UUID FK→wna_zones(id)
franchise_city                  TEXT
regulatory_authority            TEXT
tariff_number                   TEXT
tariff_document_url             TEXT
regulatory_code                 TEXT
effective_date                  DATE NOT NULL
expiry_date                     DATE
status                          TEXT NOT NULL DEFAULT 'active'
-- Gas
gas_meter_factor_required       BOOLEAN NOT NULL DEFAULT FALSE
gas_usage_formula               TEXT
-- Sewer
sewer_calc_method               TEXT
sewer_cap_gallons               NUMERIC(12,2)
sewer_percent_of_water          NUMERIC(5,4)           -- (0,1] when not NULL
winter_avg_months               INTEGER[]              -- subset of {1..12}, length 1–12
-- Billing behavior
bill_section_label              TEXT
partial_period_policy           TEXT
partial_period_policy_override  TEXT
prorate_tier_breakpoints        BOOLEAN NOT NULL DEFAULT FALSE
minimum_bill_amount             NUMERIC(12,2)          -- >= 0 when not NULL
allow_estimation                BOOLEAN NOT NULL DEFAULT TRUE
estimation_method               TEXT
-- Version / lifecycle (patch v5.4.2-03)
version                         INTEGER NOT NULL DEFAULT 1
archive_reason                  TEXT
activated_at                    TIMESTAMPTZ
archived_at                     TIMESTAMPTZ
metadata                        JSONB NOT NULL DEFAULT '{}'
created_at                      TIMESTAMPTZ NOT NULL DEFAULT now()
updated_at                      TIMESTAMPTZ NOT NULL DEFAULT now()
```

## 4.12 `rate_schedule_versions` (bi-temporal content)

```
id                              UUID PK
tenant_id                       UUID NOT NULL
rate_schedule_id                UUID NOT NULL
-- Content (moved off rate_schedules)
name                            TEXT NOT NULL
description                     TEXT
service_type                    TEXT NOT NULL
customer_type                   TEXT NOT NULL
wna_zone_id                     UUID
franchise_city                  TEXT
regulatory_authority            TEXT
tariff_number                   TEXT
tariff_document_url             TEXT
regulatory_code                 TEXT
sewer_calc_method               TEXT
sewer_cap_gallons               NUMERIC(12,2)
winter_avg_months               INTEGER[]
gas_meter_factor_required       BOOLEAN NOT NULL DEFAULT FALSE
gas_usage_formula               TEXT
bill_section_label              TEXT
partial_period_policy           TEXT
metadata                        JSONB NOT NULL DEFAULT '{}'
allow_estimation                BOOLEAN NOT NULL DEFAULT TRUE
estimation_method               TEXT
sewer_percent_of_water          NUMERIC(5,4)
partial_period_policy_override  TEXT
prorate_tier_breakpoints        BOOLEAN NOT NULL DEFAULT FALSE
minimum_bill_amount             NUMERIC(12,2)
-- Valid time
effective_date                  DATE NOT NULL
expiry_date                     DATE
-- Transaction time + change event
recorded_at                     TIMESTAMPTZ NOT NULL DEFAULT now()
recorded_until                  TIMESTAMPTZ
change_type                     TEXT NOT NULL
change_reason                   TEXT
changed_by                      UUID
supersedes_id                   UUID
service_type_change_basis       TEXT                   -- only 'transcription_error', only with supersedes_id
closed_type                     TEXT
closed_reason                   TEXT
closed_by                       UUID
```

## 4.13 `rate_items`

```
id                          UUID PK
tenant_id                   UUID NOT NULL FK→tenants(id)
item_code                   TEXT NOT NULL          -- UNIQUE (tenant_id, item_code)
item_name                   TEXT NOT NULL
description                 TEXT
service_type                TEXT NOT NULL
calculation_type            TEXT NOT NULL
current_rate                NUMERIC(14,6)
rate_unit                   TEXT
active_months               INTEGER[] NOT NULL DEFAULT '{1,2,3,4,5,6,7,8,9,10,11,12}'
applies_to_customer_types   TEXT[]    NOT NULL DEFAULT '{residential,commercial,industrial,government,wholesale}'
update_frequency            TEXT
calc_owner                  TEXT
is_taxable_default          BOOLEAN NOT NULL DEFAULT FALSE
is_a_tax                    BOOLEAN NOT NULL DEFAULT FALSE
display_name                TEXT
display_group               TEXT
tier_config                 JSONB                  -- required with a 'tiers' array when calculation_type='tiered_usage'
annual_billing_anchor       INTEGER                -- 1..12 or NULL
regulatory_class            TEXT NOT NULL          -- patch v5.4.2-07
version                     INTEGER NOT NULL DEFAULT 1
status                      TEXT NOT NULL DEFAULT 'active'
effective_date              DATE NOT NULL DEFAULT CURRENT_DATE
expiry_date                 DATE
notes                       TEXT
metadata                    JSONB NOT NULL DEFAULT '{}'
created_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
-- UNIQUE (id, tenant_id) added for composite FKs
```

## 4.14 `payments`

```
id                          UUID PK
tenant_id                   UUID NOT NULL FK→tenants(id)
payment_number              TEXT NOT NULL          -- UNIQUE (tenant_id, payment_number)
customer_id                 UUID NOT NULL FK→customers(id)
payment_date                DATE NOT NULL
amount                      NUMERIC(12,2) NOT NULL
payment_method              TEXT NOT NULL
payment_method_id           UUID FK→payment_methods(id)
channel                     TEXT NOT NULL DEFAULT 'walk_in'
source_system               TEXT NOT NULL DEFAULT 'internal'
reference_number            TEXT
provider_transaction_id     TEXT
provider_authorization_code TEXT
check_number                TEXT
check_date                  DATE
check_bank_name             TEXT
status                      TEXT NOT NULL DEFAULT 'posted'
applied_amount              NUMERIC(12,2) NOT NULL DEFAULT 0
unapplied_amount            NUMERIC(12,2) NOT NULL DEFAULT 0
-- Deposit
is_deposit                  BOOLEAN NOT NULL DEFAULT FALSE
deposit_status              TEXT
-- NSF
nsf_date                    DATE
nsf_reason                  TEXT
nsf_fee_charge_id           UUID FK→adhoc_charges(id)
nsf_original_payment_id     UUID FK→payments(id)
-- Refund
refunds_payment_id          UUID FK→payments(id)
refund_reason               TEXT
-- Reversal
reversed_at                 TIMESTAMPTZ
reversed_by                 UUID FK→users(id)
reversed_reason             TEXT
-- Misc
notes                       TEXT
received_by                 UUID FK→users(id)
metadata                    JSONB NOT NULL DEFAULT '{}'
created_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
-- UNIQUE (id, tenant_id) added for composite FKs
```

## 4.15 `account_ledger`

```
id                          UUID PK
tenant_id                   UUID NOT NULL FK→tenants(id)
customer_id                 UUID NOT NULL FK→customers(id)
location_id                 UUID FK→service_locations(id)
transaction_date            DATE NOT NULL
transaction_type            TEXT NOT NULL
description                 TEXT NOT NULL
amount                      NUMERIC(12,2) NOT NULL
running_balance             NUMERIC(12,2)          -- computed by a BEFORE INSERT trigger
reference_type              TEXT
reference_id                UUID
reverses_ledger_entry_id    UUID                   -- patch v5.4.2-02
reversal_reason             TEXT                   -- patch v5.4.2-02
created_by                  UUID FK→users(id)
created_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
-- UNIQUE (id, tenant_id) added for composite FKs
```

## 4.16 `anomalies`

```
id                          UUID PK
tenant_id                   UUID NOT NULL FK→tenants(id)
anomaly_type                TEXT NOT NULL
severity                    TEXT NOT NULL DEFAULT 'medium'
confidence                  NUMERIC(3,2)
status                      TEXT NOT NULL DEFAULT 'open'
snoozed_until               DATE
snooze_reason               TEXT
entity_type                 TEXT NOT NULL          -- singular names; see §2.8
entity_id                   UUID NOT NULL
location_id                 UUID FK→service_locations(id)
meter_id                    UUID FK→meters(id)
customer_id                 UUID FK→customers(id)
description                 TEXT NOT NULL
details                     JSONB NOT NULL DEFAULT '{}'
suggested_action            JSONB
detection_method            TEXT NOT NULL DEFAULT 'statistical'
detector_name               TEXT
detected_at                 TIMESTAMPTZ NOT NULL DEFAULT now()
dedup_key                   TEXT                   -- UNIQUE (tenant_id, dedup_key)
recurrence_count            INTEGER NOT NULL DEFAULT 1
first_detected_at           TIMESTAMPTZ NOT NULL DEFAULT now()
last_detected_at            TIMESTAMPTZ NOT NULL DEFAULT now()
linked_anomaly_id           UUID FK→anomalies(id)
estimated_impact            NUMERIC(12,2)
assigned_to                 UUID FK→users(id)
resolved_by                 UUID FK→users(id)
resolved_at                 TIMESTAMPTZ
resolution_notes            TEXT
resolution_suggestion_id    UUID FK→ai_suggestions(id)
feedback_category           TEXT
feedback_notes              TEXT
created_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
```

## 4.17 Bonus — `invoice_calculation_snapshots` (needed for invoice detail "why this amount")

```
id                      UUID PK
tenant_id               UUID NOT NULL FK→tenants(id)
invoice_id              UUID NOT NULL UNIQUE   -- FK (invoice_id, tenant_id) → invoices(id, tenant_id) ON DELETE CASCADE
billing_run_id          UUID FK→billing_runs(id)
valid_at                DATE NOT NULL
recorded_at             TIMESTAMPTZ NOT NULL
snapshot_schema_version TEXT NOT NULL         -- matches '^v[0-9]+$'
formula_version         TEXT NOT NULL         -- non-blank
rate_inputs             JSONB NOT NULL        -- object
gas_factors             JSONB NOT NULL        -- object
wna_inputs              JSONB NOT NULL        -- object
tax_inputs              JSONB NOT NULL        -- object
read_inputs             JSONB NOT NULL        -- object
customer_inputs         JSONB NOT NULL        -- object
period_inputs           JSONB NOT NULL        -- object
line_items              JSONB NOT NULL        -- array
content_hash            TEXT GENERATED ALWAYS AS (sha256 hex of the payload) STORED
captured_at             TIMESTAMPTZ NOT NULL DEFAULT now()
captured_by             UUID FK→users(id)
notes                   TEXT
```

---

# 5. Notable invariants visible in the DDL

## 5.1 No hard delete, no truncate

`BEFORE DELETE` and `BEFORE TRUNCATE` triggers (`no_hard_delete`, `no_truncate`) installed in a loop, each accompanied by `REVOKE DELETE ON <table> FROM tally_app`, on:

**Money:** `account_ledger`, `payments`, `invoice_applications`, `customer_credits`, `adhoc_charges`, `escheatment_events`, `payment_methods`, `payment_provider_logs`
**Bills:** `dunning_events`, `billing_runs`, `billing_run_meters`, `correction_run_targets`, `wna_monthly_adjustments`, `wna_clamp_events` (invoices/lines/events have their own guards with a draft-cascade exception)
**Parties & premises:** `tenants`, `users`, `customers`, `customer_contacts`, `customer_interactions`, `customer_tax_exemptions`, `customer_winter_averages`, `customer_program_enrollments`, `service_locations`
**Metering:** `meters`, `meter_deployments`, `meter_readings`, `meter_endpoint_history`, `meter_photos`, `read_cycle_instances`
**Operations & audit:** `service_orders`, `anomalies`, `import_jobs`, `ai_audit_log`

Plus separately: `deposits`, `invoice_exceptions`, `read_validation_exceptions`, `invoices`, `invoice_line_items`, `invoice_events`, `invoice_calculation_snapshots`, `invoice_snapshot_references`, `invoice_line_item_bases`, `regulatory_surcharge_rules`, `tenant_configuration_history`.

Several guards are set `ENABLE ALWAYS` so they fire even for replication/superuser sessions: `account_ledger.no_hard_delete`, `account_ledger.no_truncate`, `invoice_events.no_truncate`, `invoices.no_truncate`, `invoice_line_items.no_truncate`.

## 5.2 Issued invoices are immutable (CI-012)

`public.is_invoice_issued(status)` = `status IS NOT NULL AND status NOT IN ('draft','held')`. A `draft`/`held` invoice is a fully editable working row.

Once issued, these columns cannot change:
`id`, `tenant_id`, `invoice_number`, `billing_run_id`, `customer_id`, `location_id`, `parent_invoice_id`, `is_consolidated`, `is_consolidated_child`, `invoice_type`, `replaces_invoice_id`, `invoice_date`, `billing_period`, `period_start`, `period_end`, `due_date`, `previous_balance`, `total_charges`, `total_credits`, `total_taxes`, `total_adjustments`, `amount_due`, `tax_breakdown`, `has_estimated_reads`, `estimated_read_count`, `has_anomalies`, `created_at`.

Additional rules:
- `pdf_url` and `pdf_generated_at` are **write-once** — settable while NULL, frozen after
- `voided_at` is **write-once** and may only be set together with `status = 'void'`
- `status = 'void'` requires `voided_at IS NOT NULL`
- A `void` invoice is **sealed**: only `notes`, `metadata`, `updated_at` may change; it can never be un-voided
- No backward transition — an issued invoice cannot return to `draft` or `held`
- Hard delete is permitted **only** for `status = 'draft'`, and only when no `adhoc_charges.billed_on_invoice_id` and no `meter_readings.locked_by_invoice_id` point at it

**UI consequence:** the correction path is `void_invoice()` + rebill, never an edit form on an issued bill.

`invoice_line_items` has a matching `BEFORE INSERT OR UPDATE OR DELETE` guard (lines follow their invoice's draft/issued state).

## 5.3 Other immutability guards

`BEFORE UPDATE` (and where noted, `DELETE`) triggers:
- `account_ledger` — fully append-only; `running_balance` is computed by the DB on insert
- `payments` — a posted payment's identity is frozen (CI-013); reverse and post a new one
- `adhoc_charges` — identity frozen once `billed`/`void`/`waived`
- `customer_credits` — origin frozen (CI-013); void and issue a new credit
- `invoice_applications` — frozen; reversal is a separate stamped field set
- `invoice_events` — UPDATE and DELETE both blocked; also `trg_invoice_events_no_future` rejects future `occurred_at`
- `invoice_calculation_snapshots` — UPDATE and DELETE blocked; `content_hash` is a `GENERATED ALWAYS ... STORED` sha256 over the whole payload, so tampering is detectable
- `invoice_snapshot_references` — UPDATE and DELETE blocked
- `pga_monthly_reconciliations` — UPDATE and DELETE blocked
- `tenant_configuration_history` — UPDATE, DELETE and TRUNCATE blocked, plus an insert-source guard

## 5.4 Retired tables

`rate_item_history` and `rate_item_history_archive` carry `retired_read_only` triggers on **INSERT, UPDATE and DELETE** — no DML at all — plus `retired_no_truncate`. They are historical-read-only legacy; new rate history lives in `rate_item_versions`.

## 5.5 Bi-temporal assertion triggers

`a_enforce_bitemporal_assertion` / `b_enforce_bitemporal_assertion` (`BEFORE INSERT OR UPDATE OR DELETE`) on: `rate_schedule_versions`, `rate_item_versions`, `wna_zone_versions`, `rate_schedule_items`, `franchise_fee_rules`, `regulatory_surcharge_rules`, `customer_tax_exemptions`, `wna_monthly_adjustments`.

A version row is *asserted*, never edited. Corrections are new rows with `change_type='correction'` and a `supersedes_id`; retirement closes the old row via the `recorded_until` / `closed_type` / `closed_reason` / `closed_by` quartet.

## 5.6 Event tables written by the database, not the application

`a_enforce_event_written_by_db` on `customer_state_events` and `customer_attribute_history` — the app cannot insert into them directly. They are populated by AFTER triggers:
- `z_log_customer_state_event` AFTER INSERT ON `customers`
- `z_log_customer_attribute_changes` AFTER INSERT OR UPDATE ON `customers`
- `z_log_autopay_attribute_change` AFTER INSERT OR UPDATE ON `auto_pay_settings`
- `z_project_customer_deposit_scalars` AFTER INSERT OR UPDATE ON `deposits`
- `z_project_deposit_status` AFTER INSERT ON `deposit_events`
- `y_post_deposit_event` AFTER INSERT ON `deposits`

Similarly `trg_record_tenant_configuration_change` AFTER INSERT OR UPDATE ON `tenants` populates `tenant_configuration_history`, guarded by `guard_tenant_configuration_history_source`.

`z_log_invoice_exception_event` AFTER INSERT OR UPDATE ON `invoice_exceptions` writes the `exception_raised` / `exception_resolved` / `exception_overridden` rows into `invoice_events`.

## 5.7 Dry-run isolation

- `dry_run_no_ledger` BEFORE INSERT ON `account_ledger` — a dry run cannot post money
- `dry_run_no_read_locks` BEFORE UPDATE ON `meter_readings` — a dry run cannot lock reads
- `dry_run_terminal_status` BEFORE UPDATE ON `billing_runs` — a dry run cannot reach a posting terminal status

## 5.8 Read/bill gates

- `trg_enforce_reading_validation_workflow` BEFORE UPDATE ON `meter_readings` — enforces the `validation_status` progression
- `z_enforce_read_exception_gate` BEFORE INSERT OR UPDATE ON `meter_readings` — a read with an open validation exception cannot be released to billing
- `z_raise_consecutive_estimate_exception` AFTER INSERT ON `meter_readings` — raises the `consecutive_estimate_over_cap` exception
- `enforce_meter_estimate_counter` BEFORE UPDATE ON `meters` — the estimate streak counter is DB-maintained
- `enforce_billing_run_meter_gate` BEFORE INSERT OR UPDATE ON `billing_run_meters`
- `enforce_invoice_predelivery_gate` BEFORE UPDATE ON `invoices` — an invoice with a `blocks_delivery` exception cannot be sent
- `trg_enforce_invoice_hold_metadata`, `trg_enforce_billing_hold_metadata`, `trg_enforce_meter_estimation_block_metadata` — a hold/block flag must arrive with its reason and stamp

## 5.9 Soft-delete / archive markers instead of deletion

The whole schema uses status markers rather than row removal:
- `status IN ('archived','inactive','closed','removed','void','cancelled','superseded','demolished')` across nearly every table
- `customer_credits.status = 'voided'`
- `meter_readings.status = 'voided'` with `replaced_by_reading_id` / `replaces_reading_id` lineage
- `rate_schedules.archived_at` + `archive_reason`
- `invoices.voided_at` + `void_reason_code` + `void_rebill_expected`
- `adhoc_charges.voided_at` / `waived_at`
- `customer_program_enrollments.status = 'superseded'` + `supersedes_enrollment_id`
- version tables: `recorded_until` + `closed_type = 'superseded' | 'retracted'`

## 5.10 Tenant isolation is structural

Newer tables use **composite foreign keys on `(id, tenant_id)`** rather than a bare `id`, so a cross-tenant reference is impossible at the FK level:
`invoice_calculation_snapshots → invoices(id, tenant_id)`, `invoice_exceptions → invoices(id, tenant_id)`, `read_validation_exceptions → meter_readings(id, tenant_id)` and `→ meters(id, tenant_id)` and `→ service_orders(id, tenant_id)`, `deposits → customers(id, tenant_id)` and `→ payments(id, tenant_id)`, `deposit_events → deposits(id, tenant_id)` and `→ account_ledger(id, tenant_id)`, `customer_state_events`/`customer_attribute_history`/`deposit_waiver_determinations → customers(id, tenant_id)`, `invoice_line_item_bases → invoice_line_items(id, tenant_id)`, `regulatory_surcharge_rules → rate_items(id, tenant_id)`, `regulatory_surcharge_service_locks → rate_items/meters(id, tenant_id)`, `invoices.replaces_invoice_id` (patch -10).

RLS is `FORCE`-enabled with an application role `tally_app`; patch v5.4.2-11 additionally set `security_invoker` on views that previously ran with the owner's rights.

## 5.11 Range non-overlap

`deposit_events` carries a GiST exclusion constraint:
```sql
EXCLUDE USING gist (deposit_id WITH =, daterange(period_start, period_end, '[]') WITH &&)
  WHERE (event_type = 'interest_accrued')
```
Interest accrual periods for a single deposit can never overlap.

## 5.12 Arithmetic / shape constraints worth mirroring in Zod refinements

- `pga_monthly_reconciliations`: `monthly_variance = actual_gas_cost - pga_recovered_revenue`; `reconciliation_month` must be the 1st of a month; `medium_threshold_pct_applied > low_threshold_pct_applied`; `threshold_band` must equal the band computed from `abs(deferred_balance_after)/trailing_12mo_pga_revenue`
- `deposits`: `principal > 0`; `cap_amount > 0 AND principal <= cap_amount`; `cap_binding` ⇒ `principal = cap_amount`; `instrument='cash'` ⇒ no issuer/reference/expiry, non-cash ⇒ non-blank `instrument_reference`; `status='refunded'` ⟺ `refunded_on IS NOT NULL`; `status='released'` ⟺ `released_on IS NOT NULL` and instrument ≠ `cash`; `legacy_interest_earned` only when `basis='legacy_unknown'`
- `deposit_events`: `event_type='interest_accrued'` ⟺ `period_start`, `period_end` (with `period_end >= period_start`), `rate_applied`, `principal_basis > 0` all present; for every other event type those four must be NULL
- `deposit_waiver_determinations`: `waiver_class='family_violence_certified'` ⇒ non-blank `certification_reference`; `certification_expires_on >= determined_on`
- `regulatory_surcharge_rules`: `cycle_end >= cycle_start`; `cap_per_service > 0` when present; `surcharge_kind='pipeline_safety_fee'` ⇒ `cap_per_service IS NOT NULL AND excluded_from_tax_bases AND exempts_state_agencies`
- `rate_items` / `rate_item_versions`: `calculation_type='tiered_usage'` ⇒ `tier_config->'tiers'` is a JSON array
- `wna_zone_versions`: floor/ceiling require a `wna_clamp_basis`; `wna_adjustment_floor <= wna_adjustment_ceiling`
- `invoice_line_item_bases`: `line_item_id <> base_line_item_id`; `base_amount <> 0`
- `deposit_interest_rates`: `annual_rate` between 0 and 1 inclusive
- `customer_program_enrollments`: `effective_end_date >= effective_start_date`; `enrollment_data` must be a JSON object
- Blank-string rejection: several non-blank checks use `length(btrim(x)) > 0`; the tax-exemption certificate gate additionally requires **at least one alphanumeric character** in `certificate_number` or `certificate_url`

## 5.13 Views available to a UI

Regular (security_invoker as of patch -11):
- `customer_tax_exemptions_renewal_due` — exemptions in or past the renewal-notice window, with a derived `renewal_state` (`renewal_due` / `lapsed`)
- `deposits_refund_due`
- `regulatory_surcharge_billing_summary`
- `adhoc_void_pending_review`
- `void_released_read_alerts`

Materialized (refresh tracked in `materialized_view_refresh_log`):
- `usage_statistics`
- `payment_health_statistics`
- `credit_aging_statistics`
- `compliance_statistics`

---

# 6. Three cautions for whoever writes the Zod schemas

1. **`schema.sql` is a readable rendering, not a `pg_dump`.** It carries column names and types but zero CHECK constraints, and it omits 23 tables and ~20 columns that the applied patch stack adds. Treat `sql/tu.sql` as authoritative for both structure and vocabulary.

2. **Several columns carry two conflicting CHECK constraints**, because a patch added a widened list without dropping the narrower original. Where §2 lists two variants — `anomalies.anomaly_type`, `invoice_events.event_type`, `account_ledger.transaction_type` and `.reference_type`, `billing_runs.run_type`, `customer_tax_exemptions.exemption_type`, `rate_schedules.status`, `invoice_snapshot_references.source_table` — the **narrower** constraint is the effective one in a live database where both exist, but the **widened** list is the intended vocabulary. For fixtures, stay inside the narrow intersection; for UI dropdowns, offer the widened list.

3. **`entity_type` means two different things.** `anomalies.entity_type` uses *singular* entity names (`customer`, `meter_reading`, `invoice_line_item`, …). `custom_field_definitions.entity_type` and `ai_audit_log.entity_type` use *plural* table names (`customers`, `meter_readings`, `invoices`, …). Do not share one Zod enum between them. The same caution applies to `status`, `severity`, `priority`, `channel`, `source`, `event_type`, `change_type`, `charge_type`, `display_group`, `service_type`, `deposit_status`, `exemption_type` and `removal_reason` — each is table-scoped and several differ subtly between tables.
