/**
 * Entity schemas.
 *
 * Transcribed from the DDL in `application/database/schema.sql`. Money and
 * rates are `string`, never `number`: the engine is .NET `decimal` end to end
 * and the portal must not be the place a cent goes missing.
 *
 * Only the columns the prototype's screens actually use are modelled. When the
 * API lands these should be regenerated from the .NET OpenAPI document.
 */

import { z } from 'zod'
import {
  AccessStatus,
  AnomalySeverity,
  AnomalyStatus,
  AnomalyType,
  CalculationType,
  ChangeType,
  ConsumptionUnit,
  CorrectionRateMode,
  CustomerStatus,
  CustomerType,
  DetectionMethod,
  DisconnectProtectionType,
  DisplayGroup,
  DunningStage,
  EstimationReason,
  InvoiceStatus,
  InvoiceType,
  PartialPeriodPolicy,
  QualityFlag,
  RateDateMode,
  RateUnit,
  ReadMethod,
  ReadingPurpose,
  ReadingStatus,
  RunStatus,
  RunType,
  TransactionType,
  ValidationStatus,
  VoidReasonCode,
} from './enums'

const uuid = z.string()
/** A plain calendar date, `YYYY-MM-DD`. Never a timestamp, never zone-shifted. */
const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'expected YYYY-MM-DD')
/** An instant the database stamped. */
const instant = z.string()
/** Exact decimal carried as digits. Parsed only at the display edge. */
const decimal = z.string().regex(/^-?\d+(\.\d+)?$/, 'expected exact decimal digits')

/* ---- Customer -------------------------------------------------------- */

export const Customer = z.object({
  id: uuid,
  customer_number: z.string(),
  customer_type: CustomerType,
  first_name: z.string().nullable(),
  last_name: z.string().nullable(),
  company_name: z.string().nullable(),
  email: z.string().nullable(),
  phone: z.string().nullable(),
  status: CustomerStatus,
  /** Set only through `customer_state_events`; the UI collects a reason with any change. */
  do_not_disconnect: z.boolean(),
  disconnect_protection_type: DisconnectProtectionType.nullable(),
  disconnect_protection_expiry: isoDate.nullable(),
  billing_hold: z.boolean(),
  billing_hold_reason: z.string().nullable(),
  is_tax_exempt: z.boolean(),
  move_in_date: isoDate.nullable(),
  deposit_amount: decimal,
  balance: decimal,
})
export type Customer = z.infer<typeof Customer>

/** Display name for either a person or a company, without leaking nulls. */
export function customerName(c: Customer): string {
  if (c.company_name) return c.company_name
  return [c.first_name, c.last_name].filter(Boolean).join(' ') || c.customer_number
}

/* ---- Service location ------------------------------------------------ */

export const ServiceLocation = z.object({
  id: uuid,
  location_number: z.string(),
  address: z.string(),
  city: z.string(),
  state: z.string(),
  zip: z.string(),
  /** Drives franchise-fee applicability — an in-city premise pays, an environs one does not. */
  inside_city_limits: z.boolean(),
  franchise_city: z.string().nullable(),
  billing_cycle: z.string(),
})
export type ServiceLocation = z.infer<typeof ServiceLocation>

/* ---- Meter ----------------------------------------------------------- */

export const Meter = z.object({
  id: uuid,
  meter_number: z.string(),
  serial_number: z.string().nullable(),
  manufacturer: z.string().nullable(),
  model: z.string().nullable(),
  size: z.string().nullable(),
  read_type: z.string(),
  /** Dial-to-volume multiplier. Honour the value effective on the READ date. */
  multiplier: decimal,
  gas_btu_factor: decimal.nullable(),
  /** The index value at which the register wraps to zero. */
  rollover_point: decimal.nullable(),
  route_id: z.string().nullable(),
  route_sequence: z.number().int().nullable(),
  status: z.string(),
  /** Database-maintained. The UI must never write this. */
  consecutive_estimate_count: z.number().int(),
})
export type Meter = z.infer<typeof Meter>

/* ---- Meter reading --------------------------------------------------- */

export const MeterReading = z.object({
  id: uuid,
  meter_id: uuid,
  reading_date: isoDate,
  reading_value: decimal,
  previous_value: decimal.nullable(),
  previous_reading_date: isoDate.nullable(),
  consumption: decimal.nullable(),
  /** Defaults to `gallons` in the schema — gas surfaces must never inherit that silently. */
  consumption_unit: ConsumptionUnit,
  days_in_period: z.number().int().nullable(),
  read_method: ReadMethod,
  reading_purpose: ReadingPurpose,
  is_estimated: z.boolean(),
  estimation_reason: EstimationReason.nullable(),
  quality_flag: QualityFlag,
  status: ReadingStatus,
  validation_status: ValidationStatus,
  auto_approved: z.boolean(),
  access_status: AccessStatus,
  skip_code: z.string().nullable(),
  trouble_message: z.string().nullable(),
  tamper_count_1_changed_flag: z.boolean(),
  dispute_reason: z.string().nullable(),
  is_service_transition: z.boolean(),
  /** Once true the read's facts freeze; correct with a replacement reading. */
  billing_period_locked: z.boolean(),
  /* Gas-specific derivation chain. */
  gas_meter_factor: decimal.nullable(),
  gas_pressure_corrected_volume: decimal.nullable(),
  gas_btu_factor: decimal.nullable(),
  gas_therms: decimal.nullable(),
  /* Contextual comparison — drives the variance column. */
  consumption_prior_period: decimal.nullable(),
  consumption_same_period_last_year: decimal.nullable(),
  consumption_pct_vs_typical: decimal.nullable(),
  notes: z.string().nullable(),
})
export type MeterReading = z.infer<typeof MeterReading>

/* ---- Billing run ----------------------------------------------------- */

export const BillingRun = z.object({
  id: uuid,
  run_number: z.string(),
  billing_period: z.string(),
  period_start: isoDate,
  period_end: isoDate,
  run_type: RunType,
  /** Nothing a dry run produces is real. Chrome must say so unmistakably. */
  is_dry_run: z.boolean(),
  correction_rate_mode: CorrectionRateMode,
  status: RunStatus,
  total_locations: z.number().int(),
  total_invoices: z.number().int(),
  total_amount: decimal,
  total_exceptions: z.number().int(),
  total_estimated_reads: z.number().int(),
  started_at: instant.nullable(),
  completed_at: instant.nullable(),
  approved_at: instant.nullable(),
  posted_at: instant.nullable(),
  /** The bi-temporal coordinate pair this run resolved once and passed to every lookup. */
  valid_at: isoDate,
  recorded_at: instant,
})
export type BillingRun = z.infer<typeof BillingRun>

/* ---- Invoice --------------------------------------------------------- */

export const Invoice = z.object({
  id: uuid,
  invoice_number: z.string(),
  billing_run_id: uuid.nullable(),
  customer_id: uuid,
  location_id: uuid,
  invoice_type: InvoiceType,
  /** Lineage. Only correction / duplicate / credit_memo may carry it. */
  replaces_invoice_id: uuid.nullable(),
  invoice_date: isoDate,
  billing_period: z.string(),
  period_start: isoDate,
  period_end: isoDate,
  due_date: isoDate,
  previous_balance: decimal,
  total_charges: decimal,
  total_credits: decimal,
  total_taxes: decimal,
  total_adjustments: decimal,
  amount_due: decimal,
  amount_paid: decimal,
  balance: decimal,
  tax_breakdown: z.array(
    z.object({ label: z.string(), basis: decimal, rate: decimal, amount: decimal }),
  ),
  has_estimated_reads: z.boolean(),
  estimated_read_count: z.number().int(),
  dunning_stage: DunningStage,
  has_anomalies: z.boolean(),
  /** A human stopped this bill, and a human must release it. */
  held_at: instant.nullable(),
  hold_reason: z.string().nullable(),
  sent_at: instant.nullable(),
  voided_at: instant.nullable(),
  void_reason_code: VoidReasonCode.nullable(),
  void_reason_notes: z.string().nullable(),
  void_rebill_expected: z.boolean(),
  /** Write-once, database-stamped. Its presence is what makes a bill correctable. */
  first_issued_at: instant.nullable(),
  status: InvoiceStatus,
})
export type Invoice = z.infer<typeof Invoice>

/** An issued bill's content is frozen — the only correction is void then rebill. */
export function isIssued(invoice: Invoice): boolean {
  return invoice.first_issued_at !== null
}

/* ---- Invoice line ---------------------------------------------------- */

export const InvoiceLine = z.object({
  id: uuid,
  invoice_id: uuid,
  line_order: z.number().int(),
  charge_type: z.string(),
  description: z.string(),
  display_group: DisplayGroup,
  rate_schedule_code: z.string().nullable(),
  rate_item_code: z.string().nullable(),
  usage_quantity: decimal.nullable(),
  usage_unit: z.string().nullable(),
  rate: decimal.nullable(),
  tier_label: z.string().nullable(),
  coverage_start: isoDate.nullable(),
  coverage_end: isoDate.nullable(),
  days_covered: z.number().int().nullable(),
  days_in_period: z.number().int().nullable(),
  partial_period_policy_applied: PartialPeriodPolicy.nullable(),
  is_taxable: z.boolean(),
  taxable_amount: decimal.nullable(),
  /* The gas derivation the inspector rail spells out. */
  gas_meter_factor: decimal.nullable(),
  gas_ccf_used: decimal.nullable(),
  gas_therms_billed: decimal.nullable(),
  gas_commodity_rate: decimal.nullable(),
  gas_btu_factor: decimal.nullable(),
  amount: decimal,
})
export type InvoiceLine = z.infer<typeof InvoiceLine>

/* ---- Exception (anomaly) --------------------------------------------- */

export const Exception = z.object({
  id: uuid,
  anomaly_type: AnomalyType,
  severity: AnomalySeverity,
  confidence: z.number().min(0).max(1).nullable(),
  status: AnomalyStatus,
  snoozed_until: isoDate.nullable(),
  snooze_reason: z.string().nullable(),
  entity_type: z.string(),
  entity_id: uuid,
  customer_id: uuid.nullable(),
  meter_id: uuid.nullable(),
  invoice_id: uuid.nullable(),
  description: z.string(),
  details: z.record(z.string(), z.unknown()),
  /** Presented, never applied. The trust boundary for the AI features. */
  suggested_action: z
    .object({ label: z.string(), explanation: z.string() })
    .nullable(),
  detection_method: DetectionMethod,
  detector_name: z.string().nullable(),
  detected_at: instant,
  recurrence_count: z.number().int(),
  first_detected_at: instant,
  estimated_impact: decimal.nullable(),
  assigned_to: z.string().nullable(),
  /** True when this exception stops a bill from being delivered (AC-22). */
  blocks_delivery: z.boolean(),
})
export type Exception = z.infer<typeof Exception>

/* ---- Rate schedule and date-effective items -------------------------- */

export const RateSchedule = z.object({
  id: uuid,
  code: z.string(),
  name: z.string(),
  customer_type: CustomerType,
  tariff_number: z.string().nullable(),
  regulatory_authority: z.string().nullable(),
  effective_date: isoDate,
  expiry_date: isoDate.nullable(),
  status: z.string(),
  minimum_bill_amount: decimal.nullable(),
  partial_period_policy: PartialPeriodPolicy.nullable(),
})
export type RateSchedule = z.infer<typeof RateSchedule>

/**
 * One version of a rate item. Reference data is close-then-insert: a change
 * closes the current row and inserts a successor with `supersedes_id`,
 * `change_type` and a required `change_reason` (AC-14). Nothing is ever edited
 * in place, and nothing is ever deleted.
 */
export const RateItemVersion = z.object({
  id: uuid,
  item_code: z.string(),
  item_name: z.string(),
  display_group: DisplayGroup,
  calculation_type: CalculationType,
  rate: decimal,
  rate_unit: RateUnit,
  /** Valid time — the world the rate applies to. */
  effective_from: isoDate,
  effective_to: isoDate.nullable(),
  /** Transaction time — when the database learned it. */
  recorded_from: instant,
  recorded_until: instant.nullable(),
  supersedes_id: uuid.nullable(),
  change_type: ChangeType,
  change_reason: z.string(),
  /** Copyable, first-class: this is what goes into a PUC filing. */
  regulatory_reference: z.string().nullable(),
  changed_by: z.string(),
})
export type RateItemVersion = z.infer<typeof RateItemVersion>

/* ---- Ledger ---------------------------------------------------------- */

export const LedgerEntry = z.object({
  id: uuid,
  customer_id: uuid,
  transaction_date: isoDate,
  transaction_type: TransactionType,
  description: z.string(),
  amount: decimal,
  running_balance: decimal,
  reference_type: z.string().nullable(),
  reference_id: uuid.nullable(),
})
export type LedgerEntry = z.infer<typeof LedgerEntry>

/* ---- Correction election (AC-31) ------------------------------------- */

/**
 * The operator's rate-date election, recorded BEFORE the rebill runs. An
 * off-run manual rebill is refused by the database, so the UI must walk the
 * operator through this rather than offering a one-click "correct".
 */
export const CorrectionTarget = z.object({
  id: uuid,
  billing_run_id: uuid,
  replaced_invoice_id: uuid,
  rate_date_mode: RateDateMode,
  rate_date_override: isoDate.nullable(),
  void_reason_code: VoidReasonCode,
  void_reason_notes: z.string(),
  elected_by: z.string(),
  elected_at: instant,
})
export type CorrectionTarget = z.infer<typeof CorrectionTarget>
