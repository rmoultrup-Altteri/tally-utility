import type { RateItemVersion, RateSchedule } from '@/schemas/models'

/**
 * Date-effective rate data.
 *
 * Reference data is close-then-insert: changing a rate closes the standing row
 * and inserts a successor carrying `supersedes_id`, a `change_type` and a
 * required `change_reason`. Nothing is edited in place and nothing is deleted,
 * so the timeline below is the complete history — including the late-recorded
 * January PGA factor that caused a bill to be voided and rebilled.
 */

export const rateSchedules: RateSchedule[] = [
  {
    id: 'rs-r1',
    code: 'R-1',
    name: 'Residential Firm Gas Service',
    customer_type: 'residential',
    tariff_number: 'GUD-10928',
    regulatory_authority: 'Railroad Commission of Texas',
    effective_date: '2025-04-01',
    expiry_date: null,
    status: 'active',
    minimum_bill_amount: '22.50',
    partial_period_policy: 'prorated',
  },
  {
    id: 'rs-g1',
    code: 'G-1',
    name: 'General Service — Small Commercial',
    customer_type: 'small_commercial',
    tariff_number: 'GUD-10928',
    regulatory_authority: 'Railroad Commission of Texas',
    effective_date: '2025-04-01',
    expiry_date: null,
    status: 'active',
    minimum_bill_amount: '48.00',
    partial_period_policy: 'prorated',
  },
  {
    id: 'rs-g2',
    code: 'G-2',
    name: 'General Service — Large Commercial',
    customer_type: 'large_commercial',
    tariff_number: 'GUD-10928',
    regulatory_authority: 'Railroad Commission of Texas',
    effective_date: '2025-04-01',
    expiry_date: null,
    status: 'active',
    minimum_bill_amount: '190.00',
    partial_period_policy: 'prorated',
  },
]

/**
 * The PGA factor's full version chain.
 *
 * Note `pga-v4`: its valid time starts 2026-01-01, but it was not recorded
 * until 2026-02-16 — six weeks late. Any bill computed for January before that
 * instant used `pga-v3` and was *correct at the time it was computed*. That is
 * exactly the situation bi-temporality exists to make reproducible, and it is
 * why INV-2026-01-004913 was voided and rebilled rather than quietly edited.
 */
export const pgaVersions: RateItemVersion[] = [
  {
    id: 'pga-v1',
    item_code: 'PGA-GAS',
    item_name: 'Purchased gas adjustment',
    display_group: 'usage_charges',
    calculation_type: 'per_unit_usage',
    rate: '0.361200',
    rate_unit: 'per_therm',
    effective_from: '2025-10-01',
    effective_to: '2025-10-31',
    recorded_from: '2025-09-24T14:02:00-05:00',
    recorded_until: null,
    supersedes_id: null,
    change_type: 'initial',
    change_reason: 'October 2025 monthly gas cost filing',
    regulatory_reference: 'RRC GUD-10928 · PGA 2025-10',
    changed_by: 'K. Shaffer',
  },
  {
    id: 'pga-v2',
    item_code: 'PGA-GAS',
    item_name: 'Purchased gas adjustment',
    display_group: 'usage_charges',
    calculation_type: 'per_unit_usage',
    rate: '0.394800',
    rate_unit: 'per_therm',
    effective_from: '2025-11-01',
    effective_to: '2025-11-30',
    recorded_from: '2025-10-27T09:41:00-05:00',
    recorded_until: null,
    supersedes_id: 'pga-v1',
    change_type: 'succession',
    change_reason: 'November 2025 monthly gas cost filing',
    regulatory_reference: 'RRC GUD-10928 · PGA 2025-11',
    changed_by: 'K. Shaffer',
  },
  {
    id: 'pga-v3',
    item_code: 'PGA-GAS',
    item_name: 'Purchased gas adjustment',
    display_group: 'usage_charges',
    calculation_type: 'per_unit_usage',
    rate: '0.412000',
    rate_unit: 'per_therm',
    effective_from: '2025-12-01',
    effective_to: '2025-12-31',
    recorded_from: '2025-11-25T11:18:00-06:00',
    recorded_until: null,
    supersedes_id: 'pga-v2',
    change_type: 'succession',
    change_reason: 'December 2025 monthly gas cost filing',
    regulatory_reference: 'RRC GUD-10928 · PGA 2025-12',
    changed_by: 'K. Shaffer',
  },
  {
    id: 'pga-v4',
    item_code: 'PGA-GAS',
    item_name: 'Purchased gas adjustment',
    display_group: 'usage_charges',
    calculation_type: 'per_unit_usage',
    rate: '0.376400',
    rate_unit: 'per_therm',
    effective_from: '2026-01-01',
    effective_to: '2026-01-31',
    recorded_from: '2026-02-16T08:52:00-06:00',
    recorded_until: null,
    supersedes_id: 'pga-v3',
    change_type: 'backfill',
    change_reason:
      'January 2026 filing recorded late by Gas Supply. Bills issued for January before this instant used the December factor.',
    regulatory_reference: 'RRC GUD-10928 · PGA 2026-01',
    changed_by: 'D. Pearce',
  },
  {
    id: 'pga-v5',
    item_code: 'PGA-GAS',
    item_name: 'Purchased gas adjustment',
    display_group: 'usage_charges',
    calculation_type: 'per_unit_usage',
    rate: '0.438500',
    rate_unit: 'per_therm',
    effective_from: '2026-02-01',
    effective_to: '2026-02-28',
    recorded_from: '2026-01-28T10:07:00-06:00',
    recorded_until: null,
    supersedes_id: 'pga-v4',
    change_type: 'succession',
    change_reason: 'February 2026 monthly gas cost filing',
    regulatory_reference: 'RRC GUD-10928 · PGA 2026-02',
    changed_by: 'K. Shaffer',
  },
  {
    id: 'pga-v6',
    item_code: 'PGA-GAS',
    item_name: 'Purchased gas adjustment',
    display_group: 'usage_charges',
    calculation_type: 'per_unit_usage',
    rate: '0.401900',
    rate_unit: 'per_therm',
    effective_from: '2026-03-01',
    effective_to: null,
    recorded_from: '2026-02-14T16:30:00-06:00',
    recorded_until: null,
    supersedes_id: 'pga-v5',
    change_type: 'succession',
    change_reason: 'March 2026 monthly gas cost filing — scheduled, not yet in effect',
    regulatory_reference: 'RRC GUD-10928 · PGA 2026-03',
    changed_by: 'K. Shaffer',
  },
]

/** The other rate items on R-1, at their currently standing versions. */
export const r1Items: RateItemVersion[] = [
  {
    id: 'cust-v2',
    item_code: 'CUST-CHG-RES',
    item_name: 'Residential customer charge',
    display_group: 'base_charges',
    calculation_type: 'fixed_monthly',
    rate: '22.500000',
    rate_unit: 'per_month',
    effective_from: '2025-04-01',
    effective_to: null,
    recorded_from: '2025-03-11T13:20:00-05:00',
    recorded_until: null,
    supersedes_id: 'cust-v1',
    change_type: 'succession',
    change_reason: 'GRIP rate case settlement — base charge increase',
    regulatory_reference: 'RRC GUD-10928 · Final Order ¶14',
    changed_by: 'K. Shaffer',
  },
  {
    id: 'dist1-v2',
    item_code: 'DIST-RES-T1',
    item_name: 'Distribution — first 50 therms',
    display_group: 'usage_charges',
    calculation_type: 'tiered_usage',
    rate: '0.182400',
    rate_unit: 'per_therm',
    effective_from: '2025-04-01',
    effective_to: null,
    recorded_from: '2025-03-11T13:20:00-05:00',
    recorded_until: null,
    supersedes_id: 'dist1-v1',
    change_type: 'succession',
    change_reason: 'GRIP rate case settlement — block 1 rate',
    regulatory_reference: 'RRC GUD-10928 · Final Order ¶14',
    changed_by: 'K. Shaffer',
  },
  {
    id: 'dist2-v2',
    item_code: 'DIST-RES-T2',
    item_name: 'Distribution — over 50 therms',
    display_group: 'usage_charges',
    calculation_type: 'tiered_usage',
    rate: '0.141900',
    rate_unit: 'per_therm',
    effective_from: '2025-04-01',
    effective_to: null,
    recorded_from: '2025-03-11T13:20:00-05:00',
    recorded_until: null,
    supersedes_id: 'dist2-v1',
    change_type: 'succession',
    change_reason: 'GRIP rate case settlement — block 2 rate',
    regulatory_reference: 'RRC GUD-10928 · Final Order ¶14',
    changed_by: 'K. Shaffer',
  },
  {
    id: 'wna-v3',
    item_code: 'WNA-RES',
    item_name: 'Weather normalization adjustment',
    display_group: 'adjustments',
    calculation_type: 'usage_modifier',
    rate: '-0.021300',
    rate_unit: 'per_therm',
    effective_from: '2026-02-01',
    effective_to: '2026-02-28',
    recorded_from: '2026-02-03T08:15:00-06:00',
    recorded_until: null,
    supersedes_id: 'wna-v2',
    change_type: 'succession',
    change_reason: 'February 2026 WNA — zone BV-N, Form 2, 612 HDD vs 548 normal',
    regulatory_reference: 'RRC GUD-10928 · WNA Schedule',
    changed_by: 'system',
  },
  {
    id: 'psf-v1',
    item_code: 'PSF-TX',
    item_name: 'Pipeline safety fee',
    display_group: 'riders',
    calculation_type: 'fixed_monthly',
    rate: '0.500000',
    rate_unit: 'per_month',
    effective_from: '2024-09-01',
    effective_to: null,
    recorded_from: '2024-08-12T10:00:00-05:00',
    recorded_until: null,
    supersedes_id: null,
    change_type: 'initial',
    change_reason: 'Statutory pipeline safety fee per meter',
    regulatory_reference: 'TX Nat. Res. Code §121.211',
    changed_by: 'K. Shaffer',
  },
  {
    id: 'grip-v1',
    item_code: 'GRIP-2025',
    item_name: 'Cost of service adjustment (GRIP)',
    display_group: 'riders',
    calculation_type: 'per_unit_usage',
    rate: '0.030700',
    rate_unit: 'per_therm',
    effective_from: '2025-06-01',
    effective_to: null,
    recorded_from: '2025-05-19T09:30:00-05:00',
    recorded_until: null,
    supersedes_id: null,
    change_type: 'initial',
    change_reason: 'Annual GRIP interim rate adjustment',
    regulatory_reference: 'RRC GRIP 2025 · Docket 10928-A',
    changed_by: 'K. Shaffer',
  },
  {
    id: 'fran-v1',
    item_code: 'FRAN-BRYAN',
    item_name: 'City of Bryan franchise fee',
    display_group: 'taxes_fees',
    calculation_type: 'percentage_of_charges',
    rate: '0.040000',
    rate_unit: 'percent',
    effective_from: '2023-01-01',
    effective_to: '2027-12-31',
    recorded_from: '2022-11-30T15:45:00-06:00',
    recorded_until: null,
    supersedes_id: null,
    change_type: 'initial',
    change_reason: 'Five-year franchise agreement with City of Bryan',
    regulatory_reference: 'City of Bryan Ord. 2022-114',
    changed_by: 'K. Shaffer',
  },
]

/**
 * Resolve the version standing at a bi-temporal coordinate.
 *
 * Both axes are required and there is no fallback to "the current value" —
 * unknowable at a coordinate is an error, not a reason to reach for today's
 * number. The schema's own lookup functions raise on a NULL coordinate for
 * exactly this reason.
 */
export function versionAsOf(
  versions: RateItemVersion[],
  validAt: string,
  recordedAt: string,
): RateItemVersion | null {
  const candidates = versions.filter((v) => {
    const inValidTime = v.effective_from <= validAt && (v.effective_to === null || v.effective_to >= validAt)
    const inRecordedTime =
      v.recorded_from <= recordedAt && (v.recorded_until === null || v.recorded_until > recordedAt)
    return inValidTime && inRecordedTime
  })
  if (candidates.length === 0) return null
  return candidates.reduce((latest, v) => (v.recorded_from > latest.recorded_from ? v : latest))
}
