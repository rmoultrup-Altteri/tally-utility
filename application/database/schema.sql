-- =============================================================================
-- TallyUtility Database Schema
-- Generated: 2026-05-14
-- Database: tally (PostgreSQL)
-- Schema: public
-- Tables: 60
-- =============================================================================

-- Extensions
-- uuid_generate_v4() is used throughout; requires:
-- CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================================================
-- CORE TENANT & USER TABLES
-- =============================================================================

CREATE TABLE tenants (
    id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name                        TEXT NOT NULL,
    slug                        TEXT NOT NULL UNIQUE,
    status                      TEXT NOT NULL DEFAULT 'active',
    subscription_tier           TEXT NOT NULL DEFAULT 'starter',
    settings                    JSONB NOT NULL DEFAULT '{}',
    billing_email               TEXT,
    phone                       TEXT,
    address_line1               TEXT,
    address_line2               TEXT,
    city                        TEXT,
    state                       TEXT,
    zip                         TEXT,
    logo_url                    TEXT,
    -- Billing behavior policies
    default_partial_period_policy       TEXT NOT NULL DEFAULT 'prorated',
    payment_allocation_strategy         TEXT NOT NULL DEFAULT 'oldest_first',
    overpayment_handling                TEXT NOT NULL DEFAULT 'hold_as_credit',
    credit_application_timing           TEXT NOT NULL DEFAULT 'on_invoice_generation',
    minimum_refund_amount               NUMERIC(10,2) NOT NULL DEFAULT 5.00,
    below_threshold_action              TEXT NOT NULL DEFAULT 'hold_for_escheat',
    donation_program_name               TEXT,
    -- Read/billing run behavior
    auto_approve_clean_reads            BOOLEAN NOT NULL DEFAULT TRUE,
    unreviewed_read_billing_policy      TEXT NOT NULL DEFAULT 'block_run',
    meter_redeployment_policy           TEXT NOT NULL DEFAULT 'either',
    default_import_error_policy         TEXT NOT NULL DEFAULT 'partial_commit',
    void_only_unbilled_disposition      TEXT NOT NULL DEFAULT 'write_off',
    void_rebill_threshold               NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    onboarded_at                        TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE users (
    id              UUID PRIMARY KEY,  -- managed externally (e.g. Supabase Auth)
    tenant_id       UUID NOT NULL REFERENCES tenants(id),
    role            TEXT NOT NULL DEFAULT 'operator',
    display_name    TEXT NOT NULL,
    email           TEXT NOT NULL,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    last_login_at   TIMESTAMPTZ,
    preferences     JSONB NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE tenant_sequences (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id),
    sequence_type   TEXT NOT NULL,
    prefix          TEXT NOT NULL DEFAULT '',
    current_value   BIGINT NOT NULL DEFAULT 0,
    pad_length      INTEGER NOT NULL DEFAULT 6,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, sequence_type)
);

-- =============================================================================
-- CUSTOMER & ACCOUNT TABLES
-- =============================================================================

CREATE TABLE customers (
    id                              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id                       UUID NOT NULL REFERENCES tenants(id),
    customer_number                 TEXT NOT NULL,
    customer_type                   TEXT NOT NULL DEFAULT 'residential',
    -- Identity
    first_name                      TEXT,
    last_name                       TEXT,
    company_name                    TEXT,
    date_of_birth                   DATE,
    tax_id_type                     TEXT,
    tax_id_last4                    TEXT,
    ssn_on_file                     BOOLEAN NOT NULL DEFAULT FALSE,
    id_type                         TEXT,
    id_number                       TEXT,
    id_issuing_state                TEXT,
    id_expiration_date              DATE,
    id_verified                     BOOLEAN NOT NULL DEFAULT FALSE,
    id_verified_by                  UUID REFERENCES users(id),
    id_verified_at                  TIMESTAMPTZ,
    -- Contact
    email                           TEXT,
    phone                           TEXT,
    alt_phone                       TEXT,
    preferred_contact_method        TEXT DEFAULT 'mail',
    preferred_language              TEXT DEFAULT 'en',
    billing_delivery_method         TEXT NOT NULL DEFAULT 'email',
    -- Billing address
    billing_address_line1           TEXT,
    billing_address_line2           TEXT,
    billing_city                    TEXT,
    billing_county                  TEXT,
    billing_state                   TEXT,
    billing_zip                     TEXT,
    -- Landlord / ownership
    is_property_owner               BOOLEAN NOT NULL DEFAULT TRUE,
    landlord_customer_id            UUID REFERENCES customers(id),
    landlord_responsible            BOOLEAN NOT NULL DEFAULT FALSE,
    -- Disconnect protection
    do_not_disconnect               BOOLEAN NOT NULL DEFAULT FALSE,
    disconnect_protection_type      TEXT,
    disconnect_protection_start     DATE,
    disconnect_protection_expiry    DATE,
    disconnect_protection_notes     TEXT,
    -- Deposit tracking
    deposit_amount                  NUMERIC(12,2) DEFAULT 0,
    deposit_status                  TEXT DEFAULT 'none',
    deposit_received_date           DATE,
    deposit_refund_date             DATE,
    deposit_refund_amount           NUMERIC(12,2),
    deposit_interest_earned         NUMERIC(12,2) DEFAULT 0,
    deposit_notes                   TEXT,
    move_in_date                    DATE,
    -- Tax exemption (summary flags; detail in customer_tax_exemptions)
    is_tax_exempt                   BOOLEAN NOT NULL DEFAULT FALSE,
    tax_exemption_reason            TEXT,
    tax_exemption_certificate       TEXT,
    tax_exemption_expiry_date       DATE,
    tax_exemption_notes             TEXT,
    tax_exemption_verified_by       UUID REFERENCES users(id),
    tax_exemption_verified_at       TIMESTAMPTZ,
    -- Donation opt-in
    donation_opt_in                 BOOLEAN NOT NULL DEFAULT FALSE,
    donation_opt_in_date            DATE,
    donation_opt_in_source          TEXT,
    -- Billing hold
    billing_hold                    BOOLEAN NOT NULL DEFAULT FALSE,
    billing_hold_reason             TEXT,
    billing_hold_set_at             TIMESTAMPTZ,
    billing_hold_set_by             UUID REFERENCES users(id),
    -- Invoice consolidation
    consolidate_invoices            BOOLEAN NOT NULL DEFAULT FALSE,
    -- Status & metadata
    status                          TEXT NOT NULL DEFAULT 'active',
    notes                           TEXT,
    metadata                        JSONB NOT NULL DEFAULT '{}',
    external_id                     TEXT,
    external_id_source              TEXT,
    created_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, customer_number),
    UNIQUE (tenant_id, external_id)
);

CREATE TABLE customer_contacts (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id),
    customer_id     UUID NOT NULL REFERENCES customers(id),
    contact_type    TEXT NOT NULL,
    is_primary      BOOLEAN NOT NULL DEFAULT FALSE,
    can_make_changes BOOLEAN NOT NULL DEFAULT FALSE,
    first_name      TEXT NOT NULL,
    last_name       TEXT NOT NULL,
    title           TEXT,
    company         TEXT,
    email           TEXT,
    phone           TEXT,
    alt_phone       TEXT,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE customer_tax_exemptions (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id               UUID NOT NULL REFERENCES tenants(id),
    customer_id             UUID NOT NULL REFERENCES customers(id),
    exemption_type          TEXT NOT NULL,
    exemption_reason        TEXT,
    service_types           TEXT[],
    certificate_number      TEXT,
    issuing_authority       TEXT,
    certificate_url         TEXT,
    effective_start         DATE NOT NULL DEFAULT CURRENT_DATE,
    effective_end           DATE,
    status                  TEXT NOT NULL DEFAULT 'active',
    revoked_at              TIMESTAMPTZ,
    revoked_by              UUID REFERENCES users(id),
    revoked_reason          TEXT,
    verified_by             UUID REFERENCES users(id),
    verified_at             TIMESTAMPTZ,
    verification_notes      TEXT,
    notes                   TEXT,
    metadata                JSONB NOT NULL DEFAULT '{}',
    created_by              UUID REFERENCES users(id),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE customer_interactions (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id               UUID NOT NULL REFERENCES tenants(id),
    customer_id             UUID NOT NULL REFERENCES customers(id),
    location_id             UUID REFERENCES service_locations(id),
    interaction_type        TEXT NOT NULL,
    channel                 TEXT,
    reason                  TEXT NOT NULL,
    subject                 TEXT NOT NULL,
    description             TEXT,
    status                  TEXT NOT NULL DEFAULT 'open',
    resolution              TEXT,
    resolved_at             TIMESTAMPTZ,
    follow_up_required      BOOLEAN NOT NULL DEFAULT FALSE,
    follow_up_date          DATE,
    follow_up_assigned_to   UUID REFERENCES users(id),
    follow_up_notes         TEXT,
    handled_by              UUID REFERENCES users(id),
    duration_minutes        INTEGER,
    invoice_id              UUID,  -- soft ref to invoices
    service_order_id        UUID,  -- soft ref to service_orders
    ai_audit_id             UUID REFERENCES ai_audit_log(id),
    metadata                JSONB NOT NULL DEFAULT '{}',
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE customer_credits (
    id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id                   UUID NOT NULL REFERENCES tenants(id),
    customer_id                 UUID NOT NULL REFERENCES customers(id),
    origin_type                 TEXT NOT NULL,
    origin_notes                TEXT,
    source_payment_id           UUID REFERENCES payments(id),
    source_adhoc_charge_id      UUID REFERENCES adhoc_charges(id),
    source_invoice_id           UUID REFERENCES invoices(id),
    source_reference            TEXT,
    original_amount             NUMERIC(12,2) NOT NULL,
    applied_amount              NUMERIC(12,2) NOT NULL DEFAULT 0,
    remaining_amount            NUMERIC(12,2) NOT NULL,
    status                      TEXT NOT NULL DEFAULT 'active',
    issued_date                 DATE NOT NULL DEFAULT CURRENT_DATE,
    expires_date                DATE,
    issued_by                   UUID REFERENCES users(id),
    last_activity_date          DATE NOT NULL DEFAULT CURRENT_DATE,
    -- Escheatment tracking
    escheat_status              TEXT NOT NULL DEFAULT 'active',
    due_diligence_sent_at       TIMESTAMPTZ,
    escheated_at                TIMESTAMPTZ,
    escheated_to_jurisdiction   TEXT,
    escheat_report_reference    TEXT,
    notes                       TEXT,
    metadata                    JSONB NOT NULL DEFAULT '{}',
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- SERVICE LOCATIONS
-- =============================================================================

CREATE TABLE communities (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id           UUID NOT NULL REFERENCES tenants(id),
    community_name      TEXT NOT NULL,
    community_code      TEXT,
    community_type      TEXT,
    contact_name        TEXT,
    contact_email       TEXT,
    contact_phone       TEXT,
    city                TEXT,
    state               TEXT,
    zip                 TEXT,
    master_customer_id  UUID REFERENCES customers(id),
    total_units_planned INTEGER,
    build_out_date      DATE,
    revenue_category    TEXT,
    notes               TEXT,
    status              TEXT NOT NULL DEFAULT 'active',
    metadata            JSONB NOT NULL DEFAULT '{}',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, community_code),
    UNIQUE (tenant_id, community_name)
);

CREATE TABLE service_locations (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id           UUID NOT NULL REFERENCES tenants(id),
    customer_id         UUID NOT NULL REFERENCES customers(id),
    community_id        UUID REFERENCES communities(id),
    location_number     TEXT NOT NULL,
    address_line1       TEXT NOT NULL,
    address_line2       TEXT,
    city                TEXT NOT NULL,
    county              TEXT,
    state               TEXT NOT NULL,
    zip                 TEXT NOT NULL,
    latitude            NUMERIC(10,7),
    longitude           NUMERIC(10,7),
    parcel_id           TEXT,
    location_type       TEXT DEFAULT 'residential_single_family',
    status              TEXT NOT NULL DEFAULT 'active',
    inside_city_limits  BOOLEAN NOT NULL DEFAULT TRUE,
    franchise_city      TEXT,
    billing_cycle       TEXT NOT NULL DEFAULT 'monthly',
    billing_cycle_id    UUID REFERENCES billing_cycles(id),
    budget_billing      BOOLEAN NOT NULL DEFAULT FALSE,
    budget_amount       NUMERIC(12,2),
    metadata            JSONB NOT NULL DEFAULT '{}',
    external_id         TEXT,
    external_id_source  TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, location_number),
    UNIQUE (tenant_id, external_id)
);

CREATE TABLE custom_location_types (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id),
    type_key        TEXT NOT NULL,
    type_label      TEXT NOT NULL,
    description     TEXT,
    display_order   INTEGER NOT NULL DEFAULT 0,
    status          TEXT NOT NULL DEFAULT 'active',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, type_key)
);

-- =============================================================================
-- METER MANAGEMENT
-- =============================================================================

CREATE TABLE meters (
    id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id                   UUID NOT NULL REFERENCES tenants(id),
    meter_number                TEXT NOT NULL,
    location_id                 UUID NOT NULL REFERENCES service_locations(id),
    rate_schedule_id            UUID REFERENCES rate_schedules(id),
    service_type                TEXT NOT NULL,
    is_virtual                  BOOLEAN NOT NULL DEFAULT FALSE,
    derives_from_meter_id       UUID REFERENCES meters(id),
    -- Physical attributes
    manufacturer                TEXT,
    model                       TEXT,
    serial_number               TEXT,
    size                        TEXT,
    dial_count                  INTEGER,
    num_dials                   INTEGER DEFAULT 6,
    seal_number                 TEXT,
    install_date                DATE,
    removal_date                DATE,
    warranty_expiration         DATE,
    -- Read configuration
    read_type                   TEXT NOT NULL DEFAULT 'manual',
    multiplier                  NUMERIC(10,4) NOT NULL DEFAULT 1.0,
    -- Gas-specific
    meter_factor                NUMERIC(10,6),
    gas_btu_factor              NUMERIC(10,6),
    -- AMI/AMR integration
    ami_system                  TEXT,
    ami_endpoint_id             TEXT,
    ami_api_config              JSONB DEFAULT '{}',
    ami_last_sync_at            TIMESTAMPTZ,
    ami_sync_status             TEXT DEFAULT 'not_configured',
    ami_sync_error              TEXT,
    -- Testing/maintenance
    test_interval_months        INTEGER,
    last_test_date              DATE,
    next_test_due_date          DATE,
    last_test_result            TEXT,
    -- Route assignment
    route_id                    UUID REFERENCES read_routes(id),
    route_sequence              INTEGER,
    -- Status & lifecycle
    status                      TEXT NOT NULL DEFAULT 'active',
    start_date                  DATE NOT NULL DEFAULT CURRENT_DATE,
    end_date                    DATE,
    last_read_value             NUMERIC(14,2),
    last_read_date              DATE,
    location_notes              TEXT,
    -- Estimation control
    estimation_blocked          BOOLEAN NOT NULL DEFAULT FALSE,
    estimation_blocked_reason   TEXT,
    estimation_blocked_set_at   TIMESTAMPTZ,
    estimation_blocked_set_by   UUID REFERENCES users(id),
    -- Meter swap lineage
    replaces_meter_id           UUID REFERENCES meters(id),
    swap_reason                 TEXT,
    warehouse_location          TEXT,
    -- External reference
    metadata                    JSONB NOT NULL DEFAULT '{}',
    external_id                 TEXT,
    external_id_source          TEXT,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, meter_number),
    UNIQUE (tenant_id, external_id)
);

CREATE TABLE meter_deployments (
    id                              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id                       UUID NOT NULL REFERENCES tenants(id),
    meter_id                        UUID NOT NULL REFERENCES meters(id),
    deployment_number               INTEGER NOT NULL,
    location_id                     UUID NOT NULL REFERENCES service_locations(id),
    rate_schedule_id                UUID REFERENCES rate_schedules(id),
    install_date                    DATE NOT NULL,
    install_read_value              NUMERIC(14,2),
    installed_by                    UUID REFERENCES users(id),
    installed_by_name               TEXT,
    removal_date                    DATE,
    removal_read_value              NUMERIC(14,2),
    removal_reason                  TEXT,
    removed_by                      UUID REFERENCES users(id),
    removed_by_name                 TEXT,
    warehouse_location_after_removal TEXT,
    notes                           TEXT,
    metadata                        JSONB NOT NULL DEFAULT '{}',
    created_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (meter_id, deployment_number)
);

CREATE TABLE meter_endpoint_history (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id           UUID NOT NULL REFERENCES tenants(id),
    meter_id            UUID NOT NULL REFERENCES meters(id),
    endpoint_id         TEXT NOT NULL,
    endpoint_type       TEXT,
    install_date        DATE NOT NULL,
    removal_date        DATE,
    removal_reason      TEXT,
    installed_by        UUID REFERENCES users(id),
    installed_by_name   TEXT,
    removed_by          UUID REFERENCES users(id),
    removed_by_name     TEXT,
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE meter_photos (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id               UUID NOT NULL REFERENCES tenants(id),
    meter_id                UUID NOT NULL REFERENCES meters(id),
    meter_reading_id        UUID REFERENCES meter_readings(id),
    photo_type              TEXT NOT NULL,
    caption                 TEXT,
    storage_path            TEXT NOT NULL,
    file_name               TEXT,
    file_size_bytes         BIGINT,
    mime_type               TEXT,
    taken_at                TIMESTAMPTZ,
    taken_by                UUID REFERENCES users(id),
    taken_by_name           TEXT,
    latitude                NUMERIC(10,7),
    longitude               NUMERIC(10,7),
    gps_accuracy_meters     INTEGER,
    upload_source           TEXT DEFAULT 'web_upload',
    metadata                JSONB NOT NULL DEFAULT '{}',
    -- AI extraction
    ai_extraction_status    TEXT DEFAULT 'not_attempted',
    ai_extracted_value      NUMERIC(14,2),
    ai_confidence           NUMERIC(5,4),
    ai_anomalies            TEXT[],
    ai_notes                TEXT,
    ai_extracted_at         TIMESTAMPTZ,
    ai_model_version        TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- READ ROUTES & CYCLES
-- =============================================================================

CREATE TABLE read_routes (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id               UUID NOT NULL REFERENCES tenants(id),
    route_code              TEXT NOT NULL,
    route_name              TEXT NOT NULL,
    description             TEXT,
    read_frequency          TEXT DEFAULT 'monthly',
    typical_read_day        INTEGER,
    estimated_meter_count   INTEGER,
    estimated_time_hours    NUMERIC(4,1),
    assigned_to             TEXT,
    assigned_to_user_id     UUID REFERENCES users(id),
    default_billing_cycle_id UUID REFERENCES billing_cycles(id),
    status                  TEXT NOT NULL DEFAULT 'active',
    metadata                JSONB NOT NULL DEFAULT '{}',
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, route_code)
);

CREATE TABLE billing_cycles (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id               UUID NOT NULL REFERENCES tenants(id),
    cycle_code              TEXT NOT NULL,
    cycle_name              TEXT NOT NULL,
    description             TEXT,
    frequency               TEXT NOT NULL DEFAULT 'monthly',
    read_day                INTEGER NOT NULL,
    bill_day                INTEGER NOT NULL,
    due_days_after_bill     INTEGER NOT NULL DEFAULT 21,
    read_route_code         TEXT,
    assigned_reader         TEXT,
    requires_read_cycle     BOOLEAN NOT NULL DEFAULT TRUE,
    status                  TEXT NOT NULL DEFAULT 'active',
    metadata                JSONB NOT NULL DEFAULT '{}',
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, cycle_code)
);

CREATE TABLE read_cycle_instances (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id               UUID NOT NULL REFERENCES tenants(id),
    billing_cycle_id        UUID NOT NULL REFERENCES billing_cycles(id),
    period                  TEXT NOT NULL,
    period_start            DATE NOT NULL,
    period_end              DATE NOT NULL,
    read_window_start       DATE NOT NULL,
    read_window_end         DATE NOT NULL,
    status                  TEXT NOT NULL DEFAULT 'draft',
    issued_at               TIMESTAMPTZ,
    issued_by               UUID REFERENCES users(id),
    reads_complete_at       TIMESTAMPTZ,
    completed_by            UUID REFERENCES users(id),
    billing_run_id          UUID REFERENCES billing_runs(id),
    -- Progress counters
    total_meters_locked     INTEGER NOT NULL DEFAULT 0,
    total_reads_captured    INTEGER NOT NULL DEFAULT 0,
    total_reads_approved    INTEGER NOT NULL DEFAULT 0,
    total_meters_skipped    INTEGER NOT NULL DEFAULT 0,
    reader_overrides        JSONB NOT NULL DEFAULT '{}',
    notes                   TEXT,
    metadata                JSONB NOT NULL DEFAULT '{}',
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, billing_cycle_id, period)
);

CREATE TABLE read_cycle_meters (
    id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id                   UUID NOT NULL REFERENCES tenants(id),
    read_cycle_instance_id      UUID NOT NULL REFERENCES read_cycle_instances(id),
    meter_id                    UUID NOT NULL REFERENCES meters(id),
    read_route_id               UUID REFERENCES read_routes(id),
    assigned_reader_user_id     UUID REFERENCES users(id),
    assigned_reader_name        TEXT,
    read_status                 TEXT NOT NULL DEFAULT 'pending',
    skip_reason                 TEXT,
    expected_read_date          DATE,
    captured_at                 TIMESTAMPTZ,
    captured_reading_id         UUID REFERENCES meter_readings(id),
    sequence_in_route           INTEGER,
    notes                       TEXT,
    metadata                    JSONB NOT NULL DEFAULT '{}',
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (read_cycle_instance_id, meter_id)
);

-- =============================================================================
-- METER READINGS
-- =============================================================================

CREATE TABLE meter_readings (
    id                              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id                       UUID NOT NULL REFERENCES tenants(id),
    meter_id                        UUID NOT NULL REFERENCES meters(id),
    billing_cycle_id                UUID REFERENCES billing_cycles(id),
    read_cycle_meter_id             UUID REFERENCES read_cycle_meters(id),
    -- Register
    register_type                   TEXT NOT NULL DEFAULT 'main',
    register_label                  TEXT,
    -- Reading values
    reading_date                    DATE NOT NULL,
    reading_value                   NUMERIC(14,2) NOT NULL,
    previous_value                  NUMERIC(14,2),
    previous_reading_date           DATE,
    consumption                     NUMERIC(14,2),
    consumption_unit                TEXT NOT NULL DEFAULT 'gallons',
    days_in_period                  INTEGER,
    raw_read_value                  NUMERIC(14,2),
    -- Read method & collector
    read_method                     TEXT NOT NULL DEFAULT 'manual',
    read_by                         TEXT,
    data_collector_user_id          TEXT,
    read_sequence_number            INTEGER,
    actual_read_order               INTEGER,
    reading_timestamp               TIMESTAMPTZ,
    reading_purpose                 TEXT NOT NULL DEFAULT 'regular_cycle',
    -- GPS
    gps_latitude                    NUMERIC(10,7),
    gps_longitude                   NUMERIC(10,7),
    gps_accuracy_rating             TEXT,
    gps_changed_latitude            NUMERIC(10,7),
    gps_changed_longitude           NUMERIC(10,7),
    -- AMR/Endpoint data
    endpoint_id                     TEXT,
    changed_endpoint_id             TEXT,
    endpoint_type_received          TEXT,
    extended_endpoint_type_received TEXT,
    endpoint_read_datetime          TIMESTAMPTZ,
    -- Access
    access_status                   TEXT NOT NULL DEFAULT 'accessed',
    access_notes                    TEXT,
    skip_code                       TEXT,
    force_complete_reason_code      TEXT,
    trouble_code_1                  TEXT,
    trouble_code_2                  TEXT,
    trouble_message                 TEXT,
    read_condition                  TEXT,
    amr_read_status                 TEXT,
    -- Tamper
    tamper_count_1                  INTEGER,
    tamper_count_2                  INTEGER,
    tamper_count_1_changed_flag     BOOLEAN DEFAULT FALSE,
    tamper_count_2_changed_flag     BOOLEAN DEFAULT FALSE,
    tamper_investigated             BOOLEAN NOT NULL DEFAULT FALSE,
    tamper_investigation_notes      TEXT,
    -- Estimation
    is_estimated                    BOOLEAN NOT NULL DEFAULT FALSE,
    estimation_reason               TEXT,
    -- Quality & status
    quality_flag                    TEXT DEFAULT 'normal',
    status                          TEXT NOT NULL DEFAULT 'active',
    -- Replacement lineage
    replaced_by_reading_id          UUID REFERENCES meter_readings(id),
    replaces_reading_id             UUID REFERENCES meter_readings(id),
    replaces_read_id                UUID REFERENCES meter_readings(id),
    voided_from_invoice_id          UUID REFERENCES invoices(id),
    -- Dispute tracking
    dispute_reason                  TEXT,
    dispute_raised_by               UUID REFERENCES users(id),
    dispute_raised_at               TIMESTAMPTZ,
    dispute_resolved_by             UUID REFERENCES users(id),
    dispute_resolved_at             TIMESTAMPTZ,
    dispute_resolution_notes        TEXT,
    -- Gas-specific computed fields
    gas_meter_factor                NUMERIC(10,6),
    gas_pressure_corrected_volume   NUMERIC(14,2),
    gas_btu_factor                  NUMERIC(10,6),
    gas_therms                      NUMERIC(14,2),
    -- Contextual consumption comparison
    consumption_prior_period        NUMERIC(14,2),
    consumption_same_period_last_year NUMERIC(14,2),
    consumption_pct_vs_typical      NUMERIC(8,2),
    -- Service transition (move-in/move-out)
    is_service_transition               BOOLEAN NOT NULL DEFAULT FALSE,
    transition_outgoing_customer_id     UUID REFERENCES customers(id),
    transition_incoming_customer_id     UUID REFERENCES customers(id),
    -- Validation workflow
    validation_status               TEXT NOT NULL DEFAULT 'pending_review',
    auto_approved                   BOOLEAN NOT NULL DEFAULT FALSE,
    validated_by                    UUID REFERENCES users(id),
    validated_at                    TIMESTAMPTZ,
    assigned_to_user_id             UUID REFERENCES users(id),
    -- Billing lock
    billing_period_locked           BOOLEAN NOT NULL DEFAULT FALSE,
    locked_at                       TIMESTAMPTZ,
    locked_by_billing_run_id        UUID REFERENCES billing_runs(id),
    locked_by_invoice_id            UUID REFERENCES invoices(id),
    triggers_correction_workflow    BOOLEAN NOT NULL DEFAULT FALSE,
    -- Field confirmation
    confirmed_by_field_reader_at    TIMESTAMPTZ,
    confirmed_by_field_reader_id    UUID REFERENCES users(id),
    -- Attempt tracking
    attempted_count                 INTEGER NOT NULL DEFAULT 1,
    requires_followup               BOOLEAN NOT NULL DEFAULT FALSE,
    followup_priority               TEXT,
    followup_notes                  TEXT,
    -- Source tracking
    source_system                   TEXT,
    import_job_id                   UUID REFERENCES import_jobs(id),
    vendor_reference                TEXT,
    entered_by                      UUID REFERENCES users(id),
    notes                           TEXT,
    created_at                      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- TARIFF / RATE ENGINE
-- =============================================================================

CREATE TABLE rate_schedules (
    id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id                   UUID NOT NULL REFERENCES tenants(id),
    code                        TEXT NOT NULL,
    name                        TEXT NOT NULL,
    description                 TEXT,
    service_type                TEXT NOT NULL,
    customer_type               TEXT NOT NULL,
    wna_zone_id                 UUID REFERENCES wna_zones(id),
    franchise_city              TEXT,
    regulatory_authority        TEXT,
    tariff_number               TEXT,
    tariff_document_url         TEXT,
    regulatory_code             TEXT,
    effective_date              DATE NOT NULL,
    expiry_date                 DATE,
    status                      TEXT NOT NULL DEFAULT 'active',
    -- Gas
    gas_meter_factor_required   BOOLEAN NOT NULL DEFAULT FALSE,
    gas_usage_formula           TEXT,
    -- Sewer
    sewer_calc_method           TEXT,
    sewer_cap_gallons           NUMERIC(12,2),
    sewer_percent_of_water      NUMERIC(5,4),
    winter_avg_months           INTEGER[],
    -- Billing behavior
    bill_section_label          TEXT,
    partial_period_policy       TEXT,
    partial_period_policy_override TEXT,
    prorate_tier_breakpoints    BOOLEAN NOT NULL DEFAULT FALSE,
    minimum_bill_amount         NUMERIC(12,2),
    allow_estimation            BOOLEAN NOT NULL DEFAULT TRUE,
    estimation_method           TEXT,
    metadata                    JSONB NOT NULL DEFAULT '{}',
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, code)
);

CREATE TABLE rate_items (
    id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id                   UUID NOT NULL REFERENCES tenants(id),
    item_code                   TEXT NOT NULL,
    item_name                   TEXT NOT NULL,
    description                 TEXT,
    service_type                TEXT NOT NULL,
    calculation_type            TEXT NOT NULL,
    current_rate                NUMERIC(14,6),
    rate_unit                   TEXT,
    active_months               INTEGER[] NOT NULL DEFAULT '{1,2,3,4,5,6,7,8,9,10,11,12}',
    applies_to_customer_types   TEXT[] NOT NULL DEFAULT '{residential,commercial,industrial,government,wholesale}',
    update_frequency            TEXT,
    calc_owner                  TEXT,
    is_taxable_default          BOOLEAN NOT NULL DEFAULT FALSE,
    is_a_tax                    BOOLEAN NOT NULL DEFAULT FALSE,
    display_name                TEXT,
    display_group               TEXT,
    tier_config                 JSONB,
    annual_billing_anchor       INTEGER,
    status                      TEXT NOT NULL DEFAULT 'active',
    effective_date              DATE NOT NULL DEFAULT CURRENT_DATE,
    expiry_date                 DATE,
    notes                       TEXT,
    metadata                    JSONB NOT NULL DEFAULT '{}',
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, item_code)
);

CREATE TABLE rate_schedule_items (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id               UUID NOT NULL REFERENCES tenants(id),
    rate_schedule_id        UUID NOT NULL REFERENCES rate_schedules(id),
    rate_item_id            UUID NOT NULL REFERENCES rate_items(id),
    rate_override           NUMERIC(14,6),
    rate_unit_override      TEXT,
    active_months_override  INTEGER[],
    is_taxable_override     BOOLEAN,
    display_order           INTEGER NOT NULL DEFAULT 0,
    display_name_override   TEXT,
    effective_date          DATE NOT NULL DEFAULT CURRENT_DATE,
    expiry_date             DATE,
    status                  TEXT NOT NULL DEFAULT 'active',
    notes                   TEXT,
    metadata                JSONB NOT NULL DEFAULT '{}',
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (rate_schedule_id, rate_item_id, effective_date)
);

CREATE TABLE rate_item_history (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id               UUID NOT NULL REFERENCES tenants(id),
    rate_item_id            UUID NOT NULL REFERENCES rate_items(id),
    effective_date          DATE NOT NULL,
    end_date                DATE,
    rate_value              NUMERIC(14,6) NOT NULL,
    rate_unit               TEXT,
    changed_by              UUID REFERENCES users(id),
    change_reason           TEXT,
    regulatory_reference    TEXT,
    notes                   TEXT,
    metadata                JSONB NOT NULL DEFAULT '{}',
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Archive table for older rate history (same structure as rate_item_history)
CREATE TABLE rate_item_history_archive (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id               UUID NOT NULL,
    rate_item_id            UUID NOT NULL,
    effective_date          DATE NOT NULL,
    end_date                DATE,
    rate_value              NUMERIC(14,6) NOT NULL,
    rate_unit               TEXT,
    changed_by              UUID,
    change_reason           TEXT,
    regulatory_reference    TEXT,
    notes                   TEXT,
    metadata                JSONB NOT NULL DEFAULT '{}',
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE rate_item_dependencies (
    id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id                   UUID NOT NULL REFERENCES tenants(id),
    rate_schedule_id            UUID NOT NULL REFERENCES rate_schedules(id),
    dependent_rate_item_id      UUID NOT NULL REFERENCES rate_items(id),
    base_rate_item_id           UUID NOT NULL REFERENCES rate_items(id),
    notes                       TEXT,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (rate_schedule_id, dependent_rate_item_id, base_rate_item_id)
);

CREATE TABLE franchise_fee_rules (
    id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id                   UUID NOT NULL REFERENCES tenants(id),
    city_name                   TEXT NOT NULL,
    fee_percentage              NUMERIC(8,6) NOT NULL,
    applies_to                  TEXT NOT NULL DEFAULT 'total_bill',
    applies_to_customer_types   TEXT[] NOT NULL DEFAULT '{residential,commercial,industrial,government,wholesale}',
    effective_date              DATE NOT NULL DEFAULT CURRENT_DATE,
    expiry_date                 DATE,
    status                      TEXT NOT NULL DEFAULT 'active',
    remittance_frequency        TEXT,
    remittance_contact          TEXT,
    ordinance_reference         TEXT,
    notes                       TEXT,
    metadata                    JSONB NOT NULL DEFAULT '{}',
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, city_name, effective_date)
);

-- =============================================================================
-- WNA (WEATHER NORMALIZATION ADJUSTMENT)
-- =============================================================================

CREATE TABLE wna_zones (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id               UUID NOT NULL REFERENCES tenants(id),
    zone_code               TEXT NOT NULL,
    zone_name               TEXT NOT NULL,
    description             TEXT,
    active_months           INTEGER[] NOT NULL DEFAULT '{11,12,1,2,3,4}',
    normal_hdd              NUMERIC(10,2),
    base_load_consumption   NUMERIC(10,4),
    heating_factor          NUMERIC(10,6),
    calculation_notes       TEXT,
    weather_station_name    TEXT,
    weather_station_id      TEXT,
    calc_owner              TEXT,
    status                  TEXT NOT NULL DEFAULT 'active',
    effective_date          DATE NOT NULL DEFAULT CURRENT_DATE,
    expiry_date             DATE,
    metadata                JSONB NOT NULL DEFAULT '{}',
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, zone_code)
);

CREATE TABLE wna_monthly_adjustments (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id           UUID NOT NULL REFERENCES tenants(id),
    wna_zone_id         UUID NOT NULL REFERENCES wna_zones(id),
    billing_month       DATE NOT NULL,
    actual_hdd          NUMERIC(10,2),
    normal_hdd          NUMERIC(10,2),
    adjustment_factor   NUMERIC(14,6),
    adjustment_unit     TEXT DEFAULT 'per_mcf',
    status              TEXT NOT NULL DEFAULT 'pending',
    approved_by         UUID REFERENCES users(id),
    approved_at         TIMESTAMPTZ,
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, wna_zone_id, billing_month)
);

CREATE TABLE customer_winter_averages (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id               UUID NOT NULL REFERENCES tenants(id),
    meter_id                UUID NOT NULL REFERENCES meters(id),
    customer_id             UUID NOT NULL REFERENCES customers(id),
    winter_year             INTEGER NOT NULL,
    winter_months           INTEGER[] NOT NULL,
    avg_consumption         NUMERIC(14,2) NOT NULL,
    consumption_unit        TEXT NOT NULL,
    months_used             INTEGER NOT NULL,
    sample_size             INTEGER NOT NULL,
    computed_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    computed_by_user_id     UUID REFERENCES users(id),
    confidence              TEXT NOT NULL DEFAULT 'good',
    notes                   TEXT,
    metadata                JSONB NOT NULL DEFAULT '{}',
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (meter_id, winter_year)
);

-- =============================================================================
-- BILLING RUNS
-- =============================================================================

CREATE TABLE billing_runs (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id               UUID NOT NULL REFERENCES tenants(id),
    run_number              TEXT NOT NULL,
    billing_period          TEXT NOT NULL,
    period_start            DATE NOT NULL,
    period_end              DATE NOT NULL,
    billing_cycle_id        UUID REFERENCES billing_cycles(id),
    read_cycle_instance_id  UUID REFERENCES read_cycle_instances(id),
    run_type                TEXT NOT NULL DEFAULT 'regular',
    is_dry_run              BOOLEAN NOT NULL DEFAULT FALSE,
    scope                   JSONB NOT NULL DEFAULT '{}',
    data_cutoff_at          TIMESTAMPTZ,
    generation_method       TEXT NOT NULL DEFAULT 'manual',
    generated_by            UUID REFERENCES users(id),
    correction_rate_mode    TEXT NOT NULL DEFAULT 'historical',
    status                  TEXT NOT NULL DEFAULT 'pending',
    -- Counters
    total_locations         INTEGER DEFAULT 0,
    total_invoices          INTEGER DEFAULT 0,
    total_amount            NUMERIC(14,2) DEFAULT 0,
    total_exceptions        INTEGER DEFAULT 0,
    total_estimated_reads   INTEGER DEFAULT 0,
    -- Lifecycle timestamps
    started_at              TIMESTAMPTZ,
    completed_at            TIMESTAMPTZ,
    last_heartbeat_at       TIMESTAMPTZ,
    approved_by             UUID REFERENCES users(id),
    approved_at             TIMESTAMPTZ,
    posted_by               UUID REFERENCES users(id),
    posted_at               TIMESTAMPTZ,
    cancelled_at            TIMESTAMPTZ,
    cancelled_by            UUID REFERENCES users(id),
    notes                   TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, run_number)
);

CREATE TABLE billing_run_meters (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id           UUID NOT NULL REFERENCES tenants(id),
    billing_run_id      UUID NOT NULL REFERENCES billing_runs(id),
    meter_id            UUID NOT NULL REFERENCES meters(id),
    meter_reading_id    UUID REFERENCES meter_readings(id),
    invoice_id          UUID REFERENCES invoices(id),
    outcome             TEXT NOT NULL,
    skip_reason         TEXT,
    is_estimated_read   BOOLEAN NOT NULL DEFAULT FALSE,
    consumption         NUMERIC(14,2),
    consumption_unit    TEXT,
    has_anomaly         BOOLEAN NOT NULL DEFAULT FALSE,
    anomaly_types       TEXT[],
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (billing_run_id, meter_id)
);

CREATE TABLE correction_run_targets (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id               UUID NOT NULL REFERENCES tenants(id),
    billing_run_id          UUID NOT NULL REFERENCES billing_runs(id),
    voided_invoice_id       UUID NOT NULL REFERENCES invoices(id),
    meter_id                UUID NOT NULL REFERENCES meters(id),
    customer_id             UUID NOT NULL REFERENCES customers(id),
    location_id             UUID REFERENCES service_locations(id),
    correction_invoice_id   UUID REFERENCES invoices(id),
    rate_date_mode          TEXT NOT NULL DEFAULT 'run_default',
    rate_date_override      DATE,
    created_by              UUID REFERENCES users(id),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (billing_run_id, voided_invoice_id)
);

-- =============================================================================
-- INVOICES
-- =============================================================================

CREATE TABLE invoices (
    id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id                   UUID NOT NULL REFERENCES tenants(id),
    invoice_number              TEXT NOT NULL,
    billing_run_id              UUID REFERENCES billing_runs(id),
    customer_id                 UUID NOT NULL REFERENCES customers(id),
    location_id                 UUID REFERENCES service_locations(id),
    -- Consolidation
    parent_invoice_id           UUID REFERENCES invoices(id),
    is_consolidated             BOOLEAN NOT NULL DEFAULT FALSE,
    is_consolidated_child       BOOLEAN NOT NULL DEFAULT FALSE,
    -- Type & lineage
    invoice_type                TEXT NOT NULL DEFAULT 'regular',
    replaces_invoice_id         UUID REFERENCES invoices(id),
    -- Period
    invoice_date                DATE NOT NULL,
    billing_period              TEXT NOT NULL,
    period_start                DATE NOT NULL,
    period_end                  DATE NOT NULL,
    due_date                    DATE NOT NULL,
    -- Financials
    previous_balance            NUMERIC(12,2) NOT NULL DEFAULT 0,
    total_charges               NUMERIC(12,2) NOT NULL DEFAULT 0,
    total_credits               NUMERIC(12,2) NOT NULL DEFAULT 0,
    total_taxes                 NUMERIC(12,2) NOT NULL DEFAULT 0,
    total_adjustments           NUMERIC(12,2) NOT NULL DEFAULT 0,
    amount_due                  NUMERIC(12,2) NOT NULL DEFAULT 0,
    amount_paid                 NUMERIC(12,2) NOT NULL DEFAULT 0,
    balance                     NUMERIC(12,2) NOT NULL DEFAULT 0,
    tax_breakdown               JSONB NOT NULL DEFAULT '[]',
    -- Read flags
    has_estimated_reads         BOOLEAN NOT NULL DEFAULT FALSE,
    estimated_read_count        INTEGER NOT NULL DEFAULT 0,
    -- Late fees
    late_fee_assessed           BOOLEAN NOT NULL DEFAULT FALSE,
    late_fee_amount             NUMERIC(12,2) DEFAULT 0,
    -- Collections
    dunning_stage               TEXT NOT NULL DEFAULT 'current',
    write_off_reason            TEXT,
    write_off_date              DATE,
    write_off_approved_by       UUID REFERENCES users(id),
    -- Anomalies
    has_anomalies               BOOLEAN NOT NULL DEFAULT FALSE,
    -- Hold
    held_at                     TIMESTAMPTZ,
    held_by                     UUID REFERENCES users(id),
    hold_reason                 TEXT,
    -- Delivery
    delivery_method             TEXT DEFAULT 'email',
    sent_at                     TIMESTAMPTZ,
    pdf_url                     TEXT,
    pdf_generated_at            TIMESTAMPTZ,
    delivery_confirmed_at       TIMESTAMPTZ,
    delivery_failed_reason      TEXT,
    delivery_attempts           INTEGER NOT NULL DEFAULT 0,
    -- Void
    voided_at                   TIMESTAMPTZ,
    voided_by                   UUID REFERENCES users(id),
    void_reason_code            TEXT,
    void_reason_notes           TEXT,
    void_rebill_expected        BOOLEAN NOT NULL DEFAULT TRUE,
    -- Status
    status                      TEXT NOT NULL DEFAULT 'draft',
    notes                       TEXT,
    metadata                    JSONB NOT NULL DEFAULT '{}',
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, invoice_number)
);

CREATE TABLE invoice_line_items (
    id                              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id                       UUID NOT NULL REFERENCES tenants(id),
    invoice_id                      UUID NOT NULL REFERENCES invoices(id),
    line_order                      INTEGER NOT NULL DEFAULT 0,
    service_type                    TEXT NOT NULL,
    meter_id                        UUID REFERENCES meters(id),
    charge_type                     TEXT NOT NULL,
    description                     TEXT NOT NULL,
    rate_schedule_id                UUID REFERENCES rate_schedules(id),
    rate_item_id                    UUID REFERENCES rate_items(id),
    meter_reading_id                UUID REFERENCES meter_readings(id),
    adhoc_charge_id                 UUID REFERENCES adhoc_charges(id),
    -- Usage details
    usage_quantity                  NUMERIC(14,2),
    usage_unit                      TEXT,
    rate                            NUMERIC(12,6),
    tier_label                      TEXT,
    -- Period coverage
    coverage_start                  DATE,
    coverage_end                    DATE,
    days_covered                    INTEGER,
    days_in_period                  INTEGER,
    partial_period_policy_applied   TEXT,
    -- Tax
    taxable_amount                  NUMERIC(12,2),
    is_taxable                      BOOLEAN NOT NULL DEFAULT FALSE,
    -- Gas-specific
    gas_meter_factor                NUMERIC(10,6),
    gas_ccf_used                    NUMERIC(14,2),
    gas_therms_billed               NUMERIC(14,2),
    gas_commodity_rate              NUMERIC(12,6),
    -- Amount
    amount                          NUMERIC(12,2) NOT NULL,
    metadata                        JSONB NOT NULL DEFAULT '{}',
    created_at                      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE invoice_events (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id   UUID NOT NULL REFERENCES tenants(id),
    invoice_id  UUID NOT NULL REFERENCES invoices(id),
    event_type  TEXT NOT NULL,
    operator_id UUID REFERENCES users(id),
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    metadata    JSONB NOT NULL DEFAULT '{}'
);

CREATE TABLE invoice_applications (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id),
    invoice_id      UUID NOT NULL REFERENCES invoices(id),
    source_type     TEXT NOT NULL,
    source_id       UUID NOT NULL,
    amount          NUMERIC(12,2) NOT NULL,
    applied_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    applied_by      UUID REFERENCES users(id),
    reversed_at     TIMESTAMPTZ,
    reversed_by     UUID REFERENCES users(id),
    reversed_reason TEXT,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- AD-HOC CHARGES
-- =============================================================================

CREATE TABLE adhoc_charges (
    id                              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id                       UUID NOT NULL REFERENCES tenants(id),
    charge_number                   TEXT NOT NULL,
    customer_id                     UUID NOT NULL REFERENCES customers(id),
    location_id                     UUID REFERENCES service_locations(id),
    meter_id                        UUID REFERENCES meters(id),
    charge_type                     TEXT NOT NULL,
    description                     TEXT NOT NULL,
    amount                          NUMERIC(12,2) NOT NULL,
    is_taxable                      BOOLEAN NOT NULL DEFAULT FALSE,
    service_type                    TEXT,
    effective_date                  DATE NOT NULL DEFAULT CURRENT_DATE,
    target_billing_period           TEXT,
    status                          TEXT NOT NULL DEFAULT 'pending',
    -- Billing linkage
    billed_on_invoice_id            UUID REFERENCES invoices(id),
    billed_on_line_item_id          UUID REFERENCES invoice_line_items(id),
    billed_by_billing_run_id        UUID REFERENCES billing_runs(id),
    billed_at                       TIMESTAMPTZ,
    -- Source
    source                          TEXT NOT NULL DEFAULT 'manual',
    external_reference              TEXT,
    triggered_by_payment_id         UUID REFERENCES payments(id),
    triggered_by_reading_id         UUID REFERENCES meter_readings(id),
    triggered_by_invoice_id         UUID REFERENCES invoices(id),
    -- Approval workflow
    requires_approval               BOOLEAN NOT NULL DEFAULT FALSE,
    approval_threshold_at_creation  NUMERIC(12,2),
    approved_by                     UUID REFERENCES users(id),
    approved_at                     TIMESTAMPTZ,
    -- Void/waive
    voided_at                       TIMESTAMPTZ,
    voided_by                       UUID REFERENCES users(id),
    void_reason                     TEXT,
    voided_from_invoice_id          UUID REFERENCES invoices(id),
    waived_at                       TIMESTAMPTZ,
    waived_by                       UUID REFERENCES users(id),
    waive_reason                    TEXT,
    -- AI lineage
    created_by                      UUID REFERENCES users(id),
    created_by_ai                   BOOLEAN NOT NULL DEFAULT FALSE,
    ai_audit_id                     UUID REFERENCES ai_audit_log(id),
    created_by_suggestion_id        UUID REFERENCES ai_suggestions(id),
    reason                          TEXT,
    metadata                        JSONB NOT NULL DEFAULT '{}',
    created_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, charge_number)
);

-- =============================================================================
-- PAYMENTS
-- =============================================================================

CREATE TABLE payment_methods (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id),
    customer_id     UUID NOT NULL REFERENCES customers(id),
    provider        TEXT NOT NULL,
    provider_token  TEXT NOT NULL,
    method_type     TEXT NOT NULL,
    last_four       TEXT,
    card_brand      TEXT,
    expiry_month    SMALLINT,
    expiry_year     SMALLINT,
    bank_name       TEXT,
    account_type    TEXT,
    holder_name     TEXT,
    nickname        TEXT,
    is_default      BOOLEAN NOT NULL DEFAULT FALSE,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    verified_at     TIMESTAMPTZ,
    last_used_at    TIMESTAMPTZ,
    metadata        JSONB NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (provider, provider_token)
);

CREATE TABLE payments (
    id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id                   UUID NOT NULL REFERENCES tenants(id),
    payment_number              TEXT NOT NULL,
    customer_id                 UUID NOT NULL REFERENCES customers(id),
    payment_date                DATE NOT NULL,
    amount                      NUMERIC(12,2) NOT NULL,
    payment_method              TEXT NOT NULL,
    payment_method_id           UUID REFERENCES payment_methods(id),
    channel                     TEXT NOT NULL DEFAULT 'walk_in',
    source_system               TEXT NOT NULL DEFAULT 'internal',
    reference_number            TEXT,
    provider_transaction_id     TEXT,
    provider_authorization_code TEXT,
    check_number                TEXT,
    check_date                  DATE,
    check_bank_name             TEXT,
    status                      TEXT NOT NULL DEFAULT 'posted',
    applied_amount              NUMERIC(12,2) NOT NULL DEFAULT 0,
    unapplied_amount            NUMERIC(12,2) NOT NULL DEFAULT 0,
    -- Deposit
    is_deposit                  BOOLEAN NOT NULL DEFAULT FALSE,
    deposit_status              TEXT,
    -- NSF
    nsf_date                    DATE,
    nsf_reason                  TEXT,
    nsf_fee_charge_id           UUID REFERENCES adhoc_charges(id),
    nsf_original_payment_id     UUID REFERENCES payments(id),
    -- Refund
    refunds_payment_id          UUID REFERENCES payments(id),
    refund_reason               TEXT,
    -- Reversal
    reversed_at                 TIMESTAMPTZ,
    reversed_by                 UUID REFERENCES users(id),
    reversed_reason             TEXT,
    -- Misc
    notes                       TEXT,
    received_by                 UUID REFERENCES users(id),
    metadata                    JSONB NOT NULL DEFAULT '{}',
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, payment_number)
);

CREATE TABLE auto_pay_settings (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id           UUID NOT NULL REFERENCES tenants(id),
    customer_id         UUID NOT NULL REFERENCES customers(id) UNIQUE,
    payment_method_id   UUID NOT NULL REFERENCES payment_methods(id),
    enabled             BOOLEAN NOT NULL DEFAULT TRUE,
    billing_day         INTEGER NOT NULL,
    pause_until         DATE,
    pause_reason        TEXT,
    last_run_at         TIMESTAMPTZ,
    last_run_status     TEXT,
    next_run_at         DATE,
    consecutive_failures INTEGER NOT NULL DEFAULT 0,
    max_amount          NUMERIC(12,2),
    enrolled_via        TEXT,
    enrolled_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    disabled_at         TIMESTAMPTZ,
    disabled_reason     TEXT,
    metadata            JSONB NOT NULL DEFAULT '{}',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE payment_provider_logs (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id           UUID NOT NULL REFERENCES tenants(id),
    provider            TEXT NOT NULL,
    endpoint            TEXT NOT NULL,
    http_method         TEXT,
    request_body        TEXT,
    response_body       TEXT,
    http_status         INTEGER,
    is_error            BOOLEAN NOT NULL DEFAULT FALSE,
    error_message       TEXT,
    error_code          TEXT,
    customer_id         UUID REFERENCES customers(id),
    payment_id          UUID REFERENCES payments(id),
    payment_method_id   UUID REFERENCES payment_methods(id),
    correlation_id      TEXT,
    operation_type      TEXT,
    duration_ms         INTEGER,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- ACCOUNT LEDGER
-- =============================================================================

CREATE TABLE account_ledger (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id           UUID NOT NULL REFERENCES tenants(id),
    customer_id         UUID NOT NULL REFERENCES customers(id),
    location_id         UUID REFERENCES service_locations(id),
    transaction_date    DATE NOT NULL,
    transaction_type    TEXT NOT NULL,
    description         TEXT NOT NULL,
    amount              NUMERIC(12,2) NOT NULL,
    running_balance     NUMERIC(12,2),
    reference_type      TEXT,
    reference_id        UUID,
    created_by          UUID REFERENCES users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- COLLECTIONS / DUNNING
-- =============================================================================

CREATE TABLE dunning_events (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id               UUID NOT NULL REFERENCES tenants(id),
    invoice_id              UUID NOT NULL REFERENCES invoices(id),
    customer_id             UUID NOT NULL REFERENCES customers(id),
    event_type              TEXT NOT NULL,
    event_date              TIMESTAMPTZ NOT NULL DEFAULT now(),
    triggered_by            UUID REFERENCES users(id),
    triggered_automatically BOOLEAN NOT NULL DEFAULT FALSE,
    amount_related          NUMERIC(12,2),
    scheduled_date          DATE,
    previous_stage          TEXT,
    new_stage               TEXT,
    notes                   TEXT,
    metadata                JSONB NOT NULL DEFAULT '{}',
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE escheatment_events (
    id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id                   UUID NOT NULL REFERENCES tenants(id),
    customer_credit_id          UUID NOT NULL REFERENCES customer_credits(id),
    customer_id                 UUID NOT NULL REFERENCES customers(id),
    event_type                  TEXT NOT NULL,
    event_date                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    amount_related              NUMERIC(12,2),
    notice_method               TEXT,
    notice_reference            TEXT,
    jurisdiction                TEXT,
    regulatory_reference        TEXT,
    triggered_by                UUID REFERENCES users(id),
    triggered_automatically     BOOLEAN NOT NULL DEFAULT FALSE,
    notes                       TEXT,
    metadata                    JSONB NOT NULL DEFAULT '{}',
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- SERVICE ORDERS
-- =============================================================================

CREATE TABLE service_orders (
    id                              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id                       UUID NOT NULL REFERENCES tenants(id),
    order_number                    TEXT NOT NULL,
    order_type                      TEXT NOT NULL,
    status                          TEXT NOT NULL DEFAULT 'open',
    priority                        TEXT NOT NULL DEFAULT 'normal',
    customer_id                     UUID REFERENCES customers(id),
    location_id                     UUID REFERENCES service_locations(id),
    meter_id                        UUID REFERENCES meters(id),
    description                     TEXT NOT NULL,
    completion_notes                TEXT,
    external_order_id               TEXT,
    external_system                 TEXT,
    requested_date                  DATE,
    scheduled_date                  DATE,
    dispatched_at                   TIMESTAMPTZ,
    started_at                      TIMESTAMPTZ,
    completed_at                    TIMESTAMPTZ,
    billing_applied_at              TIMESTAMPTZ,
    assigned_to                     TEXT,
    cancelled_at                    TIMESTAMPTZ,
    cancelled_by                    UUID REFERENCES users(id),
    cancellation_reason             TEXT,
    parent_order_id                 UUID REFERENCES service_orders(id),
    -- Triggered artifacts
    triggered_adhoc_charge_ids      UUID[],
    triggered_reading_ids           UUID[],
    triggered_new_meter_id          UUID REFERENCES meters(id),
    triggered_replaced_meter_id     UUID REFERENCES meters(id),
    -- AI lineage
    created_by_ai                   BOOLEAN NOT NULL DEFAULT FALSE,
    ai_audit_id                     UUID REFERENCES ai_audit_log(id),
    created_by_suggestion_id        UUID REFERENCES ai_suggestions(id),
    billing_action_suggestion_id    UUID REFERENCES ai_suggestions(id),
    metadata                        JSONB NOT NULL DEFAULT '{}',
    created_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, order_number)
);

-- =============================================================================
-- BILL MESSAGES
-- =============================================================================

CREATE TABLE bill_messages (
    id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id                   UUID NOT NULL REFERENCES tenants(id),
    title                       TEXT,
    message_body                TEXT NOT NULL,
    effective_start             DATE NOT NULL,
    effective_end               DATE,
    target_customer_classes     TEXT[],
    target_service_types        TEXT[],
    target_service_areas        TEXT[],
    target_billing_cycle_ids    UUID[],
    priority                    INTEGER NOT NULL DEFAULT 5,
    display_group               TEXT,
    status                      TEXT NOT NULL DEFAULT 'draft',
    created_by                  UUID REFERENCES users(id),
    approved_by                 UUID REFERENCES users(id),
    approved_at                 TIMESTAMPTZ,
    metadata                    JSONB NOT NULL DEFAULT '{}',
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- ALERTS & ANOMALIES
-- =============================================================================

CREATE TABLE alerts (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id),
    alert_type      TEXT NOT NULL,
    priority        TEXT NOT NULL DEFAULT 'normal',
    title           TEXT NOT NULL,
    message         TEXT NOT NULL,
    source_type     TEXT,
    source_id       UUID,
    target_user_id  UUID REFERENCES users(id),
    target_role     TEXT,
    channel         TEXT NOT NULL DEFAULT 'in_app',
    dedup_key       TEXT,
    is_read         BOOLEAN NOT NULL DEFAULT FALSE,
    read_at         TIMESTAMPTZ,
    is_dismissed    BOOLEAN NOT NULL DEFAULT FALSE,
    dismissed_at    TIMESTAMPTZ,
    snoozed_until   TIMESTAMPTZ,
    expires_at      TIMESTAMPTZ,
    action_url      TEXT,
    action_label    TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE anomalies (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id               UUID NOT NULL REFERENCES tenants(id),
    anomaly_type            TEXT NOT NULL,
    severity                TEXT NOT NULL DEFAULT 'medium',
    confidence              NUMERIC(3,2),
    status                  TEXT NOT NULL DEFAULT 'open',
    snoozed_until           DATE,
    snooze_reason           TEXT,
    entity_type             TEXT NOT NULL,
    entity_id               UUID NOT NULL,
    location_id             UUID REFERENCES service_locations(id),
    meter_id                UUID REFERENCES meters(id),
    customer_id             UUID REFERENCES customers(id),
    description             TEXT NOT NULL,
    details                 JSONB NOT NULL DEFAULT '{}',
    suggested_action        JSONB,
    detection_method        TEXT NOT NULL DEFAULT 'statistical',
    detector_name           TEXT,
    detected_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    dedup_key               TEXT,
    recurrence_count        INTEGER NOT NULL DEFAULT 1,
    first_detected_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_detected_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    linked_anomaly_id       UUID REFERENCES anomalies(id),
    estimated_impact        NUMERIC(12,2),
    assigned_to             UUID REFERENCES users(id),
    resolved_by             UUID REFERENCES users(id),
    resolved_at             TIMESTAMPTZ,
    resolution_notes        TEXT,
    resolution_suggestion_id UUID REFERENCES ai_suggestions(id),
    feedback_category       TEXT,
    feedback_notes          TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, dedup_key)
);

-- =============================================================================
-- CUSTOM FIELDS
-- =============================================================================

CREATE TABLE custom_field_definitions (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id),
    entity_type     TEXT NOT NULL,
    field_key       TEXT NOT NULL,
    field_label     TEXT NOT NULL,
    field_type      TEXT NOT NULL,
    is_required     BOOLEAN NOT NULL DEFAULT FALSE,
    is_searchable   BOOLEAN NOT NULL DEFAULT FALSE,
    is_visible_on_list BOOLEAN NOT NULL DEFAULT FALSE,
    is_sensitive    BOOLEAN NOT NULL DEFAULT FALSE,
    display_order   INTEGER NOT NULL DEFAULT 0,
    default_value   TEXT,
    options         JSONB DEFAULT '[]',
    validation_rules JSONB DEFAULT '{}',
    help_text       TEXT,
    status          TEXT NOT NULL DEFAULT 'active',
    created_by      UUID REFERENCES users(id),
    updated_by      UUID REFERENCES users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, entity_type, field_key)
);

-- =============================================================================
-- DATA IMPORT
-- =============================================================================

CREATE TABLE import_mapping_templates (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id           UUID NOT NULL REFERENCES tenants(id),
    name                TEXT NOT NULL,
    description         TEXT,
    import_type         TEXT NOT NULL,
    source_system       TEXT,
    source_format       TEXT,
    column_mapping      JSONB NOT NULL DEFAULT '[]',
    learned_transforms  JSONB NOT NULL DEFAULT '[]',
    times_used          INTEGER NOT NULL DEFAULT 0,
    last_used_at        TIMESTAMPTZ,
    last_success_rate   NUMERIC(5,4),
    status              TEXT NOT NULL DEFAULT 'active',
    created_by          UUID REFERENCES users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, name)
);

CREATE TABLE import_jobs (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id               UUID NOT NULL REFERENCES tenants(id),
    initiated_by            UUID NOT NULL REFERENCES users(id),
    import_type             TEXT NOT NULL,
    source_type             TEXT NOT NULL,
    source_file_url         TEXT,
    source_filename         TEXT,
    source_file_size_bytes  BIGINT,
    source_file_hash        TEXT,
    idempotency_key         TEXT,
    mapping_template_id     UUID REFERENCES import_mapping_templates(id),
    column_mapping          JSONB DEFAULT '[]',
    error_handling_policy   TEXT NOT NULL,
    is_dry_run              BOOLEAN NOT NULL DEFAULT FALSE,
    import_summary          JSONB DEFAULT '{}',
    status                  TEXT NOT NULL DEFAULT 'pending',
    mapping_suggestion_id   UUID REFERENCES ai_suggestions(id),
    -- Row counters
    total_rows              INTEGER DEFAULT 0,
    processed_rows          INTEGER DEFAULT 0,
    committed_rows          INTEGER DEFAULT 0,
    held_rows               INTEGER DEFAULT 0,
    error_rows              INTEGER DEFAULT 0,
    warning_rows            INTEGER DEFAULT 0,
    skipped_rows            INTEGER DEFAULT 0,
    -- AI / validation
    ai_extraction_log       JSONB DEFAULT '{}',
    validation_errors       JSONB DEFAULT '[]',
    started_at              TIMESTAMPTZ,
    completed_at            TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, idempotency_key)
);

CREATE TABLE import_column_mappings (
    id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id                   UUID NOT NULL REFERENCES tenants(id),
    import_job_id               UUID NOT NULL REFERENCES import_jobs(id),
    source_column_name          TEXT,
    source_column_position      INTEGER NOT NULL,
    sample_values               JSONB NOT NULL DEFAULT '[]',
    content_classification      TEXT,
    classification_confidence   NUMERIC(3,2),
    proposed_target_field       TEXT,
    mapping_confidence          NUMERIC(3,2),
    proposed_transforms         JSONB DEFAULT '[]',
    operator_decision           TEXT NOT NULL DEFAULT 'pending',
    final_target_field          TEXT,
    final_transforms            JSONB DEFAULT '[]',
    operator_notes              TEXT,
    decided_by                  UUID REFERENCES users(id),
    decided_at                  TIMESTAMPTZ,
    has_outlier_pattern         BOOLEAN NOT NULL DEFAULT FALSE,
    outlier_count               INTEGER DEFAULT 0,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (import_job_id, source_column_position)
);

CREATE TABLE import_staging (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id),
    import_job_id   UUID NOT NULL REFERENCES import_jobs(id),
    row_number      INTEGER NOT NULL,
    raw_data        JSONB NOT NULL,
    mapped_data     JSONB,
    status          TEXT NOT NULL DEFAULT 'pending',
    matched_by      TEXT,
    errors          JSONB DEFAULT '[]',
    warnings        JSONB DEFAULT '[]',
    target_entity   TEXT,
    target_id       UUID,
    depends_on_row_numbers INTEGER[],
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- AI LAYER
-- =============================================================================

CREATE TABLE ai_sessions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id           UUID NOT NULL REFERENCES tenants(id),
    user_id             UUID NOT NULL REFERENCES users(id),
    title               TEXT,
    auto_titled         BOOLEAN NOT NULL DEFAULT FALSE,
    status              TEXT NOT NULL DEFAULT 'active',
    started_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at            TIMESTAMPTZ,
    last_activity_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    message_count       INTEGER NOT NULL DEFAULT 0,
    tool_call_count     INTEGER NOT NULL DEFAULT 0,
    suggestion_count    INTEGER NOT NULL DEFAULT 0,
    total_input_tokens  INTEGER NOT NULL DEFAULT 0,
    total_output_tokens INTEGER NOT NULL DEFAULT 0,
    total_cost_usd      NUMERIC(10,4) NOT NULL DEFAULT 0,
    primary_provider    TEXT,
    primary_model_id    TEXT,
    metadata            JSONB NOT NULL DEFAULT '{}',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE ai_audit_log (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id           UUID NOT NULL REFERENCES tenants(id),
    session_id          UUID REFERENCES ai_sessions(id),
    user_id             UUID REFERENCES users(id),
    parent_audit_id     UUID REFERENCES ai_audit_log(id),
    action_type         TEXT NOT NULL,
    triggered_by        TEXT NOT NULL DEFAULT 'user_chat',
    ai_response_type    TEXT,
    entity_type         TEXT,
    entity_id           UUID,
    user_prompt         TEXT,
    ai_interpretation   TEXT,
    result_summary      TEXT,
    error_message       TEXT,
    suggestion_id       UUID REFERENCES ai_suggestions(id),
    entity_changes      JSONB,
    provider            TEXT,
    model_id            TEXT,
    input_tokens        INTEGER,
    output_tokens       INTEGER,
    cost_usd            NUMERIC(10,6),
    latency_ms          INTEGER,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE ai_suggestions (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id               UUID NOT NULL REFERENCES tenants(id),
    session_id              UUID REFERENCES ai_sessions(id),
    audit_log_id            UUID REFERENCES ai_audit_log(id),
    proposed_by_user_id     UUID REFERENCES users(id),
    suggestion_type         TEXT NOT NULL,
    title                   TEXT NOT NULL,
    reasoning               TEXT NOT NULL,
    confidence              NUMERIC(3,2),
    primary_entity_type     TEXT,
    primary_entity_id       UUID,
    proposed_changes        JSONB NOT NULL DEFAULT '[]',
    status                  TEXT NOT NULL DEFAULT 'pending',
    reviewed_by             UUID REFERENCES users(id),
    reviewed_at             TIMESTAMPTZ,
    decision_reason         TEXT,
    rejected_items          JSONB DEFAULT '[]',
    executed_at             TIMESTAMPTZ,
    execution_audit_log_id  UUID REFERENCES ai_audit_log(id),
    execution_error         TEXT,
    expires_at              TIMESTAMPTZ,
    superseded_by_id        UUID REFERENCES ai_suggestions(id),
    metadata                JSONB NOT NULL DEFAULT '{}',
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE ai_tool_calls (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id),
    audit_log_id    UUID NOT NULL REFERENCES ai_audit_log(id),
    session_id      UUID REFERENCES ai_sessions(id),
    sequence_number INTEGER NOT NULL,
    tool_name       TEXT NOT NULL,
    tool_category   TEXT NOT NULL DEFAULT 'read',
    tool_input      JSONB NOT NULL DEFAULT '{}',
    tool_output     JSONB,
    output_summary  TEXT,
    status          TEXT NOT NULL DEFAULT 'pending',
    error_message   TEXT,
    suggestion_id   UUID REFERENCES ai_suggestions(id),
    started_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at    TIMESTAMPTZ,
    duration_ms     INTEGER,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- OPERATIONAL / INFRASTRUCTURE
-- =============================================================================

CREATE TABLE materialized_view_refresh_log (
    view_name           TEXT PRIMARY KEY,
    last_refresh_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_duration_ms    INTEGER,
    last_error          TEXT
);

-- =============================================================================
-- END OF SCHEMA
-- =============================================================================
