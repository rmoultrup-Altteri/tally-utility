/**
 * Controlled vocabularies.
 *
 * Every set here is transcribed from a CHECK constraint in `sql/tu.sql` — the
 * database is the source of truth and will reject anything else. When the API
 * arrives these should be regenerated from the .NET OpenAPI document rather
 * than maintained by hand.
 */

import { z } from 'zod'

/* ---- Invoice -------------------------------------------------------- */

export const InvoiceStatus = z.enum([
  'draft',
  'pending',
  'held',
  'sent',
  'paid',
  'partial',
  'overdue',
  'void',
  'write_off',
])
export type InvoiceStatus = z.infer<typeof InvoiceStatus>

export const InvoiceType = z.enum([
  'regular',
  'final',
  'correction',
  'duplicate',
  'prebill',
  'consolidated',
  'credit_memo',
])
export type InvoiceType = z.infer<typeof InvoiceType>

/** Only these three invoice types may carry `replaces_invoice_id` (AC-31). */
export const CORRECTING_INVOICE_TYPES: readonly InvoiceType[] = [
  'correction',
  'duplicate',
  'credit_memo',
]

export const VoidReasonCode = z.enum([
  'wrong_read',
  'wrong_rate',
  'wrong_customer',
  'duplicate',
  'service_date_error',
  'system_error',
  'other',
])
export type VoidReasonCode = z.infer<typeof VoidReasonCode>

export const DunningStage = z.enum([
  'current',
  'reminder_sent',
  'late_fee_assessed',
  'shutoff_warning',
  'shutoff_scheduled',
  'disconnected',
  'payment_plan',
  'collections',
  'resolved',
  'written_off',
])
export type DunningStage = z.infer<typeof DunningStage>

export const DeliveryMethod = z.enum([
  'email',
  'mail',
  'both',
  'portal_only',
  'text_message',
])
export type DeliveryMethod = z.infer<typeof DeliveryMethod>

/* ---- Meter reads ----------------------------------------------------- */

export const ReadMethod = z.enum([
  'manual',
  'ami',
  'amr',
  'estimated',
  'customer_reported',
  'rolled_back',
  'virtual',
  'photo_ai',
])
export type ReadMethod = z.infer<typeof ReadMethod>

export const ReadingPurpose = z.enum([
  'regular_cycle',
  'final_read',
  'initial_read',
  'special_request',
  'audit',
  'turn_on',
  'turn_off',
  'dispute_recheck',
  'installation',
  'removal',
])
export type ReadingPurpose = z.infer<typeof ReadingPurpose>

export const QualityFlag = z.enum([
  'normal',
  'high',
  'low',
  'zero',
  'negative',
  'suspect',
  'verified',
])
export type QualityFlag = z.infer<typeof QualityFlag>

export const ValidationStatus = z.enum([
  'pending_review',
  'reviewed_clean',
  'reviewed_with_exception',
  'approved',
  'released_to_billing',
  'locked',
  'void_released',
  'excluded',
])
export type ValidationStatus = z.infer<typeof ValidationStatus>

export const ReadingStatus = z.enum([
  'active',
  'disputed',
  'under_review',
  'replaced',
  'voided',
])
export type ReadingStatus = z.infer<typeof ReadingStatus>

export const AccessStatus = z.enum([
  'accessed',
  'locked_gate',
  'aggressive_dog',
  'meter_buried',
  'meter_obstructed',
  'meter_damaged',
  'meter_not_found',
  'unsafe_conditions',
  'no_access_permission',
  'key_required',
  'ami_offline',
  'other',
])
export type AccessStatus = z.infer<typeof AccessStatus>

export const EstimationReason = z.enum([
  'access_issue',
  'meter_malfunction',
  'new_meter_install',
  'ami_sync_failure',
  'prior_estimation_correction',
  'seasonal_closure',
  'historical_average',
  'same_period_prior_year',
  'weather_prevented_read',
  'other',
])
export type EstimationReason = z.infer<typeof EstimationReason>

export const ConsumptionUnit = z.enum([
  'gallons',
  'ccf',
  'cubic_feet',
  'kgal',
  'kwh',
  'therms',
  'cubic_meters',
  'mcf',
  'kw',
])
export type ConsumptionUnit = z.infer<typeof ConsumptionUnit>

/* ---- Billing runs ---------------------------------------------------- */

export const RunType = z.enum([
  'regular',
  'off_cycle',
  'correction',
  'final',
  'dry_run',
])
export type RunType = z.infer<typeof RunType>

export const RunStatus = z.enum([
  'pending',
  'in_progress',
  'review',
  'approved',
  'posted',
  'failed',
  'cancelled',
])
export type RunStatus = z.infer<typeof RunStatus>

/**
 * The operator's rate-date election on a correction (AC-31).
 * `run_default` inherits the run's `correction_rate_mode`, which is itself
 * only ever `historical` or `current` — `custom` exists per-target only.
 */
export const RateDateMode = z.enum([
  'run_default',
  'historical',
  'current',
  'custom',
])
export type RateDateMode = z.infer<typeof RateDateMode>

export const CorrectionRateMode = z.enum(['historical', 'current'])
export type CorrectionRateMode = z.infer<typeof CorrectionRateMode>

/* ---- Exceptions / anomalies ------------------------------------------ */

export const AnomalySeverity = z.enum(['low', 'medium', 'high', 'critical'])
export type AnomalySeverity = z.infer<typeof AnomalySeverity>

export const AnomalyStatus = z.enum([
  'open',
  'acknowledged',
  'investigating',
  'resolved',
  'false_positive',
  'deferred',
  'snoozed',
])
export type AnomalyStatus = z.infer<typeof AnomalyStatus>

export const AnomalyType = z.enum([
  'high_usage',
  'low_usage',
  'zero_usage',
  'negative_consumption',
  'possible_leak',
  'stuck_meter',
  'meter_rollover',
  'tamper_detected',
  'endpoint_offline',
  'repeated_access_issue',
  'endpoint_swap_unreported',
  'missing_reading',
  'estimated_streak',
  'partial_period_anomaly',
  'unbilled_service',
  'unbilled_usage',
  'rate_mismatch',
  'rate_schedule_mismatch',
  'billing_run_exception',
  'revenue_leakage',
  'duplicate_account',
  'address_mismatch',
  'stale_account',
  'unusual_payment_pattern',
  'auto_pay_failure_streak',
  'payment_method_expiring',
  'multiple_nsf_pattern',
  'credit_balance_stale',
  'deposit_refund_overdue',
  'escheatment_due',
  'escheatment_overdue',
  'tax_exemption_expired',
  'disconnect_protection_expiring',
  'import_column_outlier_pattern',
  'import_low_confidence_mapping',
  'other',
])
export type AnomalyType = z.infer<typeof AnomalyType>

export const DetectionMethod = z.enum([
  'statistical',
  'rule_based',
  'ai_analysis',
  'manual',
])
export type DetectionMethod = z.infer<typeof DetectionMethod>

/* ---- Customers ------------------------------------------------------- */

export const CustomerStatus = z.enum([
  'active',
  'inactive',
  'final_billed',
  'collections',
  'closed',
])
export type CustomerStatus = z.infer<typeof CustomerStatus>

export const CustomerType = z.enum([
  'residential',
  'commercial',
  'small_commercial',
  'large_commercial',
  'industrial',
  'government',
  'wholesale',
])
export type CustomerType = z.infer<typeof CustomerType>

export const DisconnectProtectionType = z.enum([
  'medical_certificate',
  'elderly_disabled',
  'military_deployment',
  'bankruptcy_automatic_stay',
  'regulatory_moratorium',
  'payment_arrangement',
  'pending_dispute',
  'other',
])
export type DisconnectProtectionType = z.infer<typeof DisconnectProtectionType>

/* ---- Rates ----------------------------------------------------------- */

export const RateScheduleStatus = z.enum([
  'draft',
  'active',
  'expired',
  'archived',
])
export type RateScheduleStatus = z.infer<typeof RateScheduleStatus>

export const CalculationType = z.enum([
  'fixed_monthly',
  'fixed_annual',
  'per_unit_usage',
  'percentage_of_bill',
  'percentage_of_charges',
  'usage_modifier',
  'tiered_usage',
  'formula',
])
export type CalculationType = z.infer<typeof CalculationType>

export const RateUnit = z.enum([
  'flat',
  'per_month',
  'per_year',
  'per_day',
  'per_gallon',
  'per_kgal',
  'per_ccf',
  'per_mcf',
  'per_therm',
  'per_kwh',
  'per_cubic_meter',
  'percent',
  'decimal',
])
export type RateUnit = z.infer<typeof RateUnit>

export const DisplayGroup = z.enum([
  'base_charges',
  'usage_charges',
  'riders',
  'taxes_fees',
  'adjustments',
  'other',
])
export type DisplayGroup = z.infer<typeof DisplayGroup>

/** Why a new reference-data version exists. Required on every succession (AC-14). */
export const ChangeType = z.enum([
  'initial',
  'succession',
  'correction',
  'backfill',
])
export type ChangeType = z.infer<typeof ChangeType>

export const PartialPeriodPolicy = z.enum([
  'prorated',
  'charge_both',
  'period_holder',
])
export type PartialPeriodPolicy = z.infer<typeof PartialPeriodPolicy>

/* ---- Ledger ---------------------------------------------------------- */

export const TransactionType = z.enum([
  'charge',
  'payment',
  'adjustment',
  'credit_issued',
  'credit_applied',
  'late_fee',
  'deposit',
  'refund',
  'write_off',
  'transfer',
  'nsf',
  'escheat',
  'donation',
  'void_reversal',
])
export type TransactionType = z.infer<typeof TransactionType>

/* ---- Service orders -------------------------------------------------- */

export const ServiceOrderStatus = z.enum([
  'open',
  'scheduled',
  'dispatched',
  'in_progress',
  'on_hold',
  'awaiting_billing_action',
  'completed',
  'requires_followup',
  'cancelled',
  'superseded',
])
export type ServiceOrderStatus = z.infer<typeof ServiceOrderStatus>

export const ServiceOrderPriority = z.enum(['low', 'normal', 'high', 'emergency'])
export type ServiceOrderPriority = z.infer<typeof ServiceOrderPriority>

/* ---- Payments (payments_*_check in the DDL) --------------------------- */

export const PaymentStatus = z.enum(['pending', 'posted', 'nsf', 'reversed', 'refunded', 'voided'])
export type PaymentStatus = z.infer<typeof PaymentStatus>

export const PaymentMethod = z.enum([
  'cash',
  'check',
  'ach',
  'credit_card',
  'debit_card',
  'money_order',
  'online',
  'auto_pay',
  'write_off',
  'refund',
  'wire',
  'other',
])
export type PaymentMethod = z.infer<typeof PaymentMethod>

/** How the payment was captured — distinct from what it was paid with. */
export const PaymentChannel = z.enum([
  'portal',
  'mobile_app',
  'agent_phone',
  'ivr',
  'walk_in',
  'mail',
  'auto_pay',
  'batch_file',
  'api',
  'lockbox',
])
export type PaymentChannel = z.infer<typeof PaymentChannel>
