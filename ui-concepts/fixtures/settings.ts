import { tenant } from '@/fixtures/tenant'

/**
 * The tenant settings catalog.
 *
 * Every tenant-configurable value the configurable-rules review settled on
 * (`tally-utility-memory/application/configurable-rules/`), grouped the way an
 * administrator thinks about them rather than the way the schema stores them
 * — the schema splits these across thirteen typed columns on `tenants`, the
 * `tenants.settings` JSONB, `tenant_sequences` and `billing_cycles`.
 *
 * Each setting says how far the tenant's hand reaches:
 *
 * - **regulated** — shown, never editable. The rule is statute or a platform
 *   invariant; the page states it so nobody goes looking for the switch.
 * - **tariff** — editable, but the value must match the filed tariff or city
 *   ordinance. Saving one asks for the reference.
 * - **gap** — ruled configurable but with no schema home yet. Built to the
 *   spec so the page pressure-tests it, the same as the rest of the concepts.
 * - **open** — the domain expert has not ruled. The control shows the
 *   question rather than pretending a default is settled.
 *
 * Pure data, so client forms import it directly.
 */

export type Option = { value: string; label: string; hint?: string }

type Base = {
  key: string
  label: string
  hint?: string
  citation?: string
  /** Read-only. The string says why. */
  regulated?: string
  tariff?: boolean
  gap?: boolean
  /** The question still with the domain expert. */
  open?: string
  /** Shown only when another setting has this value. */
  showWhen?: { key: string; equals: string }
}

export type Column =
  | { key: string; label: string; kind: 'text'; placeholder?: string; readOnly?: boolean; optional?: boolean }
  | { key: string; label: string; kind: 'date' }
  | { key: string; label: string; kind: 'number'; min?: number; max?: number; unit?: string }
  | { key: string; label: string; kind: 'percent'; min?: number; max?: number }
  | { key: string; label: string; kind: 'money' }
  | { key: string; label: string; kind: 'select'; options: Option[] }
  | { key: string; label: string; kind: 'toggle' }

export type Row = Record<string, string | number | boolean>

export type SettingDef = Base &
  (
    | { kind: 'number'; default: number | null; unit?: string; min?: number; max?: number; step?: number; minNote?: string; maxNote?: string; nullable?: string }
    | { kind: 'percent'; default: number; min?: number; max?: number; step?: number }
    | { kind: 'money'; default: string; min?: number }
    | { kind: 'toggle'; default: boolean }
    | { kind: 'select'; default: string; options: Option[]; caution?: Record<string, string> }
    | { kind: 'text'; default: string; placeholder?: string; required?: boolean }
    | { kind: 'time'; default: string }
    | { kind: 'months'; default: string[] }
    | { kind: 'multi'; default: string[]; options: Option[] }
    | { kind: 'list'; default: number[]; unit: string }
    | { kind: 'rows'; default: Row[]; columns: Column[]; fixedRows?: boolean; addLabel?: string; newRow?: Row }
    | { kind: 'appearance'; default: null }
    | { kind: 'density'; default: null }
  )

export type SettingGroup = {
  title: string
  note?: string
  settings: SettingDef[]
  /** Rules that sit here but are not settings — stated so nobody hunts for the switch. */
  fixed?: string[]
  link?: { href: string; label: string }
}

export type SectionKey =
  | 'organization'
  | 'roles'
  | 'billing'
  | 'reads'
  | 'exceptions'
  | 'rates'
  | 'taxes'
  | 'payments'
  | 'autopay'
  | 'deposits'
  | 'plans'
  | 'dunning'
  | 'disconnect'
  | 'writeoff'
  | 'notices'
  | 'imports'
  | 'corrections'
  | 'personal'

export type SettingSection = {
  key: SectionKey
  title: string
  summary: string
  area: 'Organization' | 'Billing' | 'Money in' | 'Collections' | 'Operations' | 'You'
  groups: SettingGroup[]
  /** Saved per operator, immediately, with no effective date or reason. Open to every role. */
  personal?: boolean
  /** Has its own screen rather than the shared form. */
  custom?: boolean
}

export const MONTHS: Option[] = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'].map((m) => ({
  value: m,
  label: m[0].toUpperCase() + m.slice(1),
}))

const ANOMALIES: Option[] = [
  { value: 'negative_consumption', label: 'Negative consumption' },
  { value: 'high_usage', label: 'High usage' },
  { value: 'low_usage', label: 'Low usage' },
  { value: 'zero_usage', label: 'Zero usage' },
  { value: 'estimated_streak', label: 'Estimate streak' },
]

const ESTIMATION_METHODS: Option[] = [
  { value: 'same_period_prior_year', label: 'Same period, prior year', hint: 'Best for heating load' },
  { value: 'historical_average_3mo', label: '3-month average' },
  { value: 'historical_average_12mo', label: '12-month average' },
  { value: 'last_actual_reading', label: 'Last actual reading' },
  { value: 'zero', label: 'Zero' },
]

const FREQUENCY: Option[] = [
  { value: 'monthly', label: 'Monthly' },
  { value: 'bimonthly', label: 'Bimonthly' },
  { value: 'quarterly', label: 'Quarterly' },
]

export const SECTIONS: SettingSection[] = [
  /* ---- Organization ---------------------------------------------------- */
  {
    key: 'organization',
    area: 'Organization',
    title: 'Organization',
    summary: 'Profile, regulatory posture, plan and number formats',
    groups: [
      {
        title: 'Profile',
        note: 'Printed on bills and notices. Not versioned — a corrected phone number is not a policy change.',
        settings: [
          { key: 'org.name', label: 'Utility name', kind: 'text', default: tenant.name, required: true },
          { key: 'org.billing_email', label: 'Billing email', kind: 'text', default: 'billing@brazosvalleygas.example', required: true },
          { key: 'org.phone', label: 'Customer service phone', kind: 'text', default: '(979) 555-0142', required: true },
          { key: 'org.address', label: 'Remit-to address', kind: 'text', default: 'PO Box 4182, Bryan, TX 77805', required: true },
        ],
      },
      {
        title: 'Regulatory posture',
        settings: [
          {
            key: 'org.regulator',
            label: 'Regulator',
            kind: 'text',
            default: tenant.jurisdiction,
            regulated: 'Set when the tenant is onboarded. Only a platform administrator may change it (CI-132).',
            gap: true,
          },
          {
            key: 'org.spanish_good_cause_exemption',
            label: 'Spanish good-cause exemption on file',
            kind: 'toggle',
            default: false,
            hint: 'Bills and notices go out in English and Spanish statewide. Turn this on only with a granted exemption on file.',
            citation: '16 TAC §7.45',
            gap: true,
          },
        ],
      },
      {
        title: 'Number formats',
        note: 'How new numbers are issued. Existing numbers never change.',
        settings: [
          {
            key: 'org.sequences',
            label: 'Sequences',
            kind: 'rows',
            fixedRows: true,
            columns: [
              { key: 'type', label: 'Sequence', kind: 'text', readOnly: true },
              { key: 'prefix', label: 'Prefix', kind: 'text', placeholder: 'none', optional: true },
              { key: 'pad', label: 'Digits', kind: 'number', min: 4, max: 10 },
            ],
            default: [
              { type: 'Invoice', prefix: 'INV-', pad: 6 },
              { type: 'Payment', prefix: 'PMT-', pad: 6 },
              { type: 'Account', prefix: '100-', pad: 6 },
              { type: 'Service order', prefix: 'SO-', pad: 6 },
            ],
          },
        ],
      },
      {
        title: 'Plan',
        settings: [
          {
            key: 'org.subscription_tier',
            label: 'Subscription',
            kind: 'select',
            default: 'professional',
            options: [
              { value: 'starter', label: 'Starter' },
              { value: 'professional', label: 'Professional' },
              { value: 'enterprise', label: 'Enterprise' },
            ],
            regulated: 'Managed by Tally Utility. Whether a tenant administrator may change it is open under the RBAC model.',
          },
        ],
      },
    ],
  },

  {
    key: 'roles',
    area: 'Organization',
    title: 'Roles & access',
    summary: 'Who may change settings, and what each role may do',
    custom: true,
    groups: [],
  },

  /* ---- Billing --------------------------------------------------------- */
  {
    key: 'billing',
    area: 'Billing',
    title: 'Billing cycles & runs',
    summary: 'Cycle calendar, payment terms, the run gate and batch quality bands',
    groups: [
      {
        title: 'Cycles',
        note: 'A premise belongs to a cycle through its billing-cycle link, which is authoritative.',
        settings: [
          {
            key: 'billing.cycles',
            label: 'Billing cycles',
            kind: 'rows',
            addLabel: 'Add cycle',
            columns: [
              { key: 'code', label: 'Cycle', kind: 'text' },
              { key: 'frequency', label: 'Frequency', kind: 'select', options: FREQUENCY },
              { key: 'read_day', label: 'Read day', kind: 'number', min: 1, max: 31 },
              { key: 'bill_day', label: 'Bill day', kind: 'number', min: 1, max: 31 },
              { key: 'due_days', label: 'Due after bill', kind: 'number', min: 15, max: 60, unit: 'days' },
              { key: 'reads', label: 'Read cycle', kind: 'toggle' },
              {
                key: 'status',
                label: 'Status',
                kind: 'select',
                options: [
                  { value: 'active', label: 'Active' },
                  { value: 'paused', label: 'Paused' },
                  { value: 'archived', label: 'Archived' },
                ],
              },
            ],
            newRow: { code: '', frequency: 'monthly', read_day: 1, bill_day: 4, due_days: 21, reads: true, status: 'paused' },
            default: [
              { code: '01', frequency: 'monthly', read_day: 21, bill_day: 24, due_days: 20, reads: true, status: 'active' },
              { code: '02', frequency: 'monthly', read_day: 28, bill_day: 3, due_days: 20, reads: true, status: 'active' },
              { code: '03', frequency: 'monthly', read_day: 7, bill_day: 10, due_days: 20, reads: true, status: 'active' },
              { code: '04', frequency: 'monthly', read_day: 14, bill_day: 17, due_days: 20, reads: true, status: 'active' },
            ],
          },
        ],
      },
      {
        title: 'Payment terms',
        settings: [
          {
            key: 'billing.payment_terms_days',
            label: 'Default payment terms',
            kind: 'number',
            unit: 'days',
            default: 21,
            min: 15,
            max: 60,
            minNote: 'A bill must allow at least 15 days to pay. The floor is enforced, not advised.',
            citation: '16 TAC §7.45',
          },
          {
            key: 'billing.issue_warning_below_days',
            label: 'Warn at issue when terms fall below',
            kind: 'number',
            unit: 'days',
            default: 15,
            min: 15,
            max: 60,
          },
          {
            key: 'billing.small_balance_carry_forward',
            label: 'Carry forward balances under',
            kind: 'money',
            default: '1.00',
            min: 0,
            hint: 'Bills below this are not rendered; the balance rolls into next month.',
            gap: true,
          },
          { key: 'billing.deliver_zero_amount', label: 'Deliver zero-amount bills', kind: 'toggle', default: true },
          { key: 'billing.deliver_credit_memos', label: 'Deliver credit-memo bills', kind: 'toggle', default: false },
        ],
      },
      {
        title: 'Run gate',
        note: 'What stops a billing run before it posts.',
        settings: [
          {
            key: 'billing.unreviewed_read_policy',
            label: 'Unreviewed reads',
            kind: 'select',
            default: 'block_run',
            options: [
              { value: 'block_run', label: 'Block the run' },
              { value: 'skip_unreviewed', label: 'Skip those accounts' },
              { value: 'proceed_with_warning', label: 'Proceed with a warning' },
            ],
            caution: { proceed_with_warning: 'Bills will issue on reads nobody has looked at.' },
          },
          {
            key: 'billing.require_separate_approver',
            label: 'Require a second person to approve a run',
            kind: 'toggle',
            default: false,
            hint: 'Segregation of duties: whoever starts the run cannot post it.',
          },
          { key: 'billing.skip_rate_warning', label: 'Warn when skipped accounts exceed', kind: 'percent', default: 5, max: 100 },
          { key: 'billing.estimation_rate_warning', label: 'Warn when estimated reads exceed', kind: 'percent', default: 10, max: 100 },
          { key: 'billing.anomaly_rate_warning', label: 'Warn when anomalies exceed', kind: 'percent', default: 15, max: 100 },
          { key: 'billing.amount_swing_warning', label: 'Warn on a bill amount swing over', kind: 'percent', default: 30, max: 1000 },
          {
            key: 'billing.review_required_anomalies',
            label: 'Anomalies that require review',
            kind: 'multi',
            default: ['negative_consumption'],
            options: ANOMALIES,
          },
          {
            key: 'billing.review_recommended_anomalies',
            label: 'Anomalies that recommend review',
            kind: 'multi',
            default: ['high_usage', 'estimated_streak'],
            options: ANOMALIES,
          },
          { key: 'billing.stale_review_days', label: 'A review goes stale after', kind: 'number', unit: 'days', default: 7, min: 1, max: 60 },
        ],
        fixed: ['The pipeline stages and their order are fixed by the platform.'],
      },
      {
        title: 'Batch quality bands',
        note: 'Whole-batch checks against expectation. Any breach holds the batch, not just the bill.',
        settings: [
          {
            key: 'billing.revenue_band',
            label: 'Revenue band',
            kind: 'percent',
            default: 10,
            max: 100,
            hint: 'Against degree-day-adjusted expected revenue for the cycle.',
            gap: true,
          },
          { key: 'billing.class_band', label: 'Customer-class band', kind: 'percent', default: 5, max: 100, hint: 'Against the same class a year ago.', gap: true },
          { key: 'billing.canary_band', label: 'Canary-account band', kind: 'percent', default: 3, max: 100, gap: true },
        ],
      },
      {
        title: 'Partial periods',
        settings: [
          {
            key: 'billing.partial_period_policy',
            label: 'Customer charge on a partial month',
            kind: 'select',
            default: 'prorated',
            tariff: true,
            options: [
              { value: 'prorated', label: 'Prorate by days' },
              { value: 'charge_both', label: 'Full charge to each customer' },
              { value: 'period_holder', label: 'Full charge to the period holder' },
            ],
            hint: 'Must match the filed tariff. The Texas convention is a full, unprorated customer charge. A rate schedule can override this.',
          },
        ],
      },
    ],
  },
  {
    key: 'reads',
    area: 'Billing',
    title: 'Reads & estimation',
    summary: 'Read approval, estimation limits and anomaly detection',
    groups: [
      {
        title: 'Read approval',
        settings: [
          { key: 'reads.auto_approve_clean', label: 'Approve clean reads automatically', kind: 'toggle', default: true },
          {
            key: 'reads.meter_redeployment',
            label: 'A redeployed meter',
            kind: 'select',
            default: 'either',
            options: [
              { value: 'reuse_record', label: 'Reuses its record' },
              { value: 'new_record', label: 'Gets a new record' },
              { value: 'either', label: 'Operator chooses' },
            ],
          },
        ],
      },
      {
        title: 'Estimation',
        settings: [
          { key: 'reads.estimation_enabled', label: 'Estimate missing reads', kind: 'toggle', default: true },
          {
            key: 'reads.max_consecutive_estimates',
            label: 'Consecutive estimates allowed',
            kind: 'number',
            default: 3,
            min: 1,
            max: 5,
            maxNote: 'An actual read is required at least every six months, so a monthly meter can carry five estimates at most.',
            hint: 'Counted per meter. Only a validated actual read resets it.',
            citation: '16 TAC §7.45',
          },
          { key: 'reads.stale_meter_days', label: 'A meter is stale after', kind: 'number', unit: 'days', default: 180, min: 30, max: 365 },
          { key: 'reads.default_method', label: 'Estimation method', kind: 'select', default: 'same_period_prior_year', options: ESTIMATION_METHODS },
        ],
        fixed: ['An estimate is trued up by a single catch-up on the next actual read. Cancel and rebill is used only on the dispute or correction path.'],
      },
      {
        title: 'Anomaly detection',
        note: 'Seasonal by design: zero usage in July is normal for a heating customer.',
        settings: [
          { key: 'reads.auto_skip_negative', label: 'Skip negative consumption automatically', kind: 'toggle', default: false },
          { key: 'reads.high_usage_months', label: 'High-usage check runs in', kind: 'months', default: MONTHS.map((m) => m.value) },
          { key: 'reads.high_usage_multiplier', label: 'High usage at', kind: 'number', unit: '× typical', default: 3, min: 1, step: 0.1 },
          { key: 'reads.high_usage_stddev', label: 'and beyond', kind: 'number', unit: 'standard deviations', default: 2, min: 0.5, step: 0.1 },
          { key: 'reads.low_usage_months', label: 'Low-usage check runs in', kind: 'months', default: ['nov', 'dec', 'jan', 'feb', 'mar'] },
          { key: 'reads.low_usage_multiplier', label: 'Low usage below', kind: 'number', unit: '× typical', default: 0.25, min: 0, max: 1, step: 0.05 },
          { key: 'reads.zero_usage_months', label: 'Zero-usage check runs in', kind: 'months', default: ['oct', 'nov', 'dec', 'jan', 'feb', 'mar', 'apr'] },
        ],
      },
    ],
  },
  {
    key: 'rates',
    area: 'Billing',
    title: 'Rates, PGA & WNA',
    summary: 'Rating defaults, the PGA deferred account and weather normalization',
    groups: [
      {
        title: 'Rating',
        note: 'Rate schedules and items are edited where they live, with their filing.',
        link: { href: '/rates', label: 'Open Rates & tariffs' },
        settings: [
          {
            key: 'rates.prorate_tier_breakpoints',
            label: 'Prorate tier breakpoints on a short or long period',
            kind: 'toggle',
            default: true,
            tariff: true,
          },
        ],
      },
      {
        title: 'PGA deferred account',
        link: { href: '/rates/pga', label: 'Open the PGA console' },
        settings: [
          {
            key: 'rates.pga_reconciliation',
            label: 'Reconciliation',
            kind: 'select',
            default: 'annual',
            tariff: true,
            gap: true,
            options: [
              { value: 'annual', label: 'Annual' },
              { value: 'semiannual', label: 'Semiannual' },
              { value: 'quarterly', label: 'Quarterly' },
            ],
          },
          { key: 'rates.pga_carrying_cost', label: 'Carrying-cost rate', kind: 'percent', default: 4.25, max: 25, step: 0.01, tariff: true, gap: true },
          { key: 'rates.pga_amortization_months', label: 'Amortize a true-up over', kind: 'number', unit: 'months', default: 12, min: 1, max: 36, tariff: true, gap: true },
          { key: 'rates.pga_balance_alert', label: 'Alert when the deferred balance passes', kind: 'money', default: '250000.00', min: 0, gap: true },
        ],
      },
      {
        title: 'Weather normalization',
        note: 'There is no statewide WNA rule. Every value here comes from the tariff.',
        settings: [
          { key: 'rates.wna_deadband', label: 'Deadband', kind: 'percent', default: 0, max: 50, step: 0.5, tariff: true },
          { key: 'rates.wna_normal_years', label: 'Normal HDD from the last', kind: 'number', unit: 'years', default: 10, min: 1, max: 30, tariff: true },
          {
            key: 'rates.wna_base_load',
            label: 'Base load from',
            kind: 'select',
            default: 'summer_average',
            tariff: true,
            options: [
              { value: 'summer_average', label: 'Summer-month average' },
              { value: 'regression', label: 'Regression on HDD' },
            ],
          },
          {
            key: 'rates.wna_floor',
            label: 'Adjustment floor',
            kind: 'number',
            unit: '% of the bill',
            default: null,
            min: -100,
            max: 0,
            tariff: true,
            nullable: 'No floor. Large adjustments are applied in full.',
          },
          {
            key: 'rates.wna_ceiling',
            label: 'Adjustment ceiling',
            kind: 'number',
            unit: '% of the bill',
            default: null,
            min: 0,
            max: 100,
            tariff: true,
            nullable: 'No ceiling. Large adjustments are applied in full.',
          },
        ],
      },
    ],
  },
  {
    key: 'taxes',
    area: 'Billing',
    title: 'Taxes & franchise fees',
    summary: 'Franchise fees by city and the taxability of one-off charges',
    groups: [
      {
        title: 'Franchise fees',
        note: 'One row per city, each set by its ordinance.',
        settings: [
          {
            key: 'taxes.franchise',
            label: 'Franchise fees',
            kind: 'rows',
            tariff: true,
            addLabel: 'Add city',
            columns: [
              { key: 'city', label: 'City', kind: 'text' },
              { key: 'rate', label: 'Fee', kind: 'percent', min: 0, max: 10 },
              {
                key: 'applies_to',
                label: 'Applies to',
                kind: 'select',
                options: [
                  { value: 'total_bill', label: 'Total bill' },
                  { value: 'gross_revenue', label: 'Gross revenue' },
                  { value: 'base_and_usage', label: 'Base and usage' },
                  { value: 'usage_only', label: 'Usage only' },
                ],
              },
              {
                key: 'remit',
                label: 'Remit',
                kind: 'select',
                options: [
                  { value: 'monthly', label: 'Monthly' },
                  { value: 'quarterly', label: 'Quarterly' },
                  { value: 'annually', label: 'Annually' },
                ],
              },
              { key: 'ordinance', label: 'Ordinance', kind: 'text', placeholder: 'Ord. no.' },
            ],
            newRow: { city: '', rate: 0, applies_to: 'base_and_usage', remit: 'quarterly', ordinance: '' },
            default: [
              { city: 'Bryan', rate: 4, applies_to: 'base_and_usage', remit: 'quarterly', ordinance: 'Ord. 2022-114' },
              { city: 'College Station', rate: 4, applies_to: 'base_and_usage', remit: 'quarterly', ordinance: 'Ord. 2023-4471' },
            ],
          },
        ],
        fixed: ['Gross receipts tax is reported, not configured.'],
      },
      {
        title: 'One-off charges',
        settings: [
          {
            key: 'taxes.adhoc_taxability',
            label: 'Taxability by charge',
            kind: 'rows',
            fixedRows: true,
            columns: [
              { key: 'charge', label: 'Charge', kind: 'text', readOnly: true },
              {
                key: 'taxable',
                label: 'Sales tax',
                kind: 'select',
                options: [
                  { value: 'inherit', label: 'Follow the account' },
                  { value: 'taxable', label: 'Always taxable' },
                  { value: 'exempt', label: 'Never taxable' },
                ],
              },
            ],
            default: [
              { charge: 'Late fee', taxable: 'exempt' },
              { charge: 'Reconnection fee', taxable: 'inherit' },
              { charge: 'Returned-payment fee', taxable: 'exempt' },
              { charge: 'Meter test fee', taxable: 'inherit' },
              { charge: 'Damaged equipment', taxable: 'inherit' },
            ],
          },
          { key: 'taxes.max_defer_attempts', label: 'Defer a one-off charge at most', kind: 'number', unit: 'times', default: 3, min: 0, max: 12 },
          { key: 'taxes.pickup_on_corrections', label: 'Pick up pending charges on correction runs', kind: 'toggle', default: false },
        ],
      },
    ],
  },

  /* ---- Money in -------------------------------------------------------- */
  {
    key: 'payments',
    area: 'Money in',
    title: 'Payments & credits',
    summary: 'Allocation order, overpayments, refunds and unclaimed credits',
    groups: [
      {
        title: 'Allocation',
        settings: [
          {
            key: 'payments.allocation',
            label: 'Apply a payment to',
            kind: 'select',
            default: 'oldest_first',
            options: [
              { value: 'oldest_first', label: 'Oldest bill first' },
              { value: 'newest_first', label: 'Newest bill first' },
              { value: 'largest_first', label: 'Largest bill first' },
              { value: 'manual_only', label: 'Nothing until an operator applies it' },
            ],
            caution: { manual_only: 'Every payment will sit unapplied until someone allocates it, and the account can look delinquent meanwhile.' },
            hint: 'Texas does not mandate an order.',
          },
        ],
        fixed: [
          'A customer’s own instruction on a payment always overrides this.',
          'A payment is on time by its postmark or sent date, never the date it was posted.',
        ],
      },
      {
        title: 'Overpayments and refunds',
        settings: [
          {
            key: 'payments.overpayment',
            label: 'An overpayment',
            kind: 'select',
            default: 'hold_as_credit',
            options: [
              { value: 'hold_as_credit', label: 'Stays on the account as a credit' },
              { value: 'refund_automatically', label: 'Is refunded automatically' },
              { value: 'apply_to_specific_invoices', label: 'Is applied to chosen bills' },
            ],
          },
          {
            key: 'payments.credit_timing',
            label: 'Apply a credit',
            kind: 'select',
            default: 'on_invoice_generation',
            options: [
              { value: 'on_invoice_generation', label: 'When the next bill is made' },
              { value: 'on_due_date', label: 'On the due date' },
              { value: 'manual_only', label: 'Only by hand' },
            ],
          },
          { key: 'payments.minimum_refund', label: 'Smallest refund issued', kind: 'money', default: '5.00', min: 0 },
          {
            key: 'payments.below_threshold',
            label: 'A credit below that',
            kind: 'select',
            default: 'hold_for_escheat',
            options: [
              { value: 'hold_for_escheat', label: 'Is held, then reported as unclaimed property' },
              { value: 'apply_to_donation_if_opted_in', label: 'Goes to the assistance fund, if the customer opted in' },
            ],
            hint: 'Unclaimed deposits are reportable after 18 months; other credits after three years.',
          },
          {
            key: 'payments.donation_program',
            label: 'Assistance fund name',
            kind: 'text',
            default: '',
            placeholder: 'e.g. Neighbor-to-Neighbor',
            required: true,
            showWhen: { key: 'payments.below_threshold', equals: 'apply_to_donation_if_opted_in' },
          },
          { key: 'payments.convenience_fee', label: 'Card convenience fee', kind: 'money', default: '0.00', min: 0, tariff: true, gap: true },
        ],
      },
    ],
  },
  {
    key: 'autopay',
    area: 'Money in',
    title: 'Autopay & returned payments',
    summary: 'Draft day, returned-payment fee and when autopay switches off',
    groups: [
      {
        title: 'Autopay',
        settings: [
          {
            key: 'autopay.default_draft_day',
            label: 'Default draft day',
            kind: 'number',
            unit: 'days before due',
            default: 0,
            min: 0,
            max: 10,
            hint: 'Customers can choose their own. 0 drafts on the due date.',
          },
          {
            key: 'autopay.disable_after_returns',
            label: 'Turn autopay off after',
            kind: 'number',
            unit: 'returns in 12 months',
            default: 2,
            min: 1,
            max: 6,
            gap: true,
          },
        ],
      },
      {
        title: 'Returned payments',
        settings: [
          { key: 'autopay.returned_payment_fee', label: 'Returned-payment fee', kind: 'money', default: '25.00', min: 0, tariff: true },
        ],
        fixed: [
          'An ACH return for insufficient or uncollected funds is presented again once, never more.',
          'No fee is charged on an unauthorized-debit return.',
          'The mapping from bank return codes to actions is fixed by the platform.',
        ],
      },
    ],
  },
  {
    key: 'deposits',
    area: 'Money in',
    title: 'Deposits',
    summary: 'Interest rate, waivers and accepted instruments',
    groups: [
      {
        title: 'Amount and refund',
        settings: [
          {
            key: 'deposits.residential_cap',
            label: 'Residential deposit cap',
            kind: 'text',
            default: 'One-sixth of estimated annual billing',
            regulated: 'Statutory ceiling for residential service.',
            citation: '16 TAC §7.45',
          },
          {
            key: 'deposits.refund_after',
            label: 'Refunded after',
            kind: 'text',
            default: '12 consecutive bills paid on time, no more than two late',
            regulated: 'Statutory. The refund and its interest are automatic.',
            citation: '16 TAC §7.45',
          },
          {
            key: 'deposits.interest',
            label: 'Interest rate by year',
            kind: 'rows',
            gap: true,
            addLabel: 'Add a year',
            columns: [
              { key: 'from', label: 'Effective from', kind: 'date' },
              { key: 'rate', label: 'Rate', kind: 'percent', min: 0, max: 20 },
            ],
            newRow: { from: '', rate: 0 },
            default: [
              { from: '2025-01-01', rate: 4.12 },
              { from: '2026-01-01', rate: 3.85 },
            ],
            hint: 'Set each January from the published rate. Interest is owed once a deposit has been held 31 days, back to the first day.',
          },
        ],
      },
      {
        title: 'Waivers and instruments',
        settings: [
          {
            key: 'deposits.family_violence_waiver',
            label: 'Family-violence waiver',
            kind: 'toggle',
            default: true,
            regulated: 'Mandatory. Tenant waivers may extend the statutory ones but never narrow them.',
          },
          { key: 'deposits.senior_waiver', label: 'Waive for customers 65 and over', kind: 'toggle', default: false, tariff: true },
          {
            key: 'deposits.instruments',
            label: 'Accepted instead of cash',
            kind: 'multi',
            default: [],
            gap: true,
            options: [
              { value: 'surety_bond', label: 'Surety bond' },
              { value: 'letter_of_credit', label: 'Letter of credit' },
              { value: 'guarantor', label: 'Guarantor' },
            ],
          },
        ],
      },
    ],
  },
  {
    key: 'plans',
    area: 'Money in',
    title: 'Budget billing & payment plans',
    summary: 'Levelized billing and deferred payment agreements',
    groups: [
      {
        title: 'Budget billing',
        settings: [
          { key: 'plans.budget_window', label: 'Average over', kind: 'number', unit: 'months', default: 12, min: 3, max: 24, gap: true },
          {
            key: 'plans.budget_review',
            label: 'Review the installment',
            kind: 'select',
            default: 'quarterly',
            gap: true,
            options: [
              { value: 'quarterly', label: 'Quarterly' },
              { value: 'semiannual', label: 'Twice a year' },
              { value: 'annual', label: 'Annually' },
            ],
          },
          { key: 'plans.budget_variance', label: 'Re-level early when off by more than', kind: 'percent', default: 20, max: 100, gap: true },
          { key: 'plans.budget_anniversary', label: 'Settle-up month', kind: 'select', default: 'aug', options: MONTHS, gap: true },
          {
            key: 'plans.budget_settle_up',
            label: 'Settle a balance by',
            kind: 'select',
            default: 'amortize',
            gap: true,
            options: [
              { value: 'credit', label: 'Crediting or billing it at once' },
              { value: 'amortize', label: 'Spreading it into the next year' },
              { value: 'cash_collect', label: 'Collecting it separately' },
            ],
          },
        ],
      },
      {
        title: 'Deferred payment agreements',
        settings: [
          { key: 'plans.dpa_max_months', label: 'Longest agreement', kind: 'number', unit: 'months', default: 6, min: 1, max: 24, gap: true },
          { key: 'plans.dpa_down_payment', label: 'Down payment', kind: 'percent', default: 0, max: 100, gap: true },
          {
            key: 'plans.dpa_grace_days',
            label: 'Grace on an installment',
            kind: 'number',
            unit: 'days',
            default: 5,
            min: 0,
            max: 30,
            hint: 'A payment inside the grace period means the agreement was never broken.',
            gap: true,
          },
          {
            key: 'plans.dpa_max_broken',
            label: 'Broken agreements before a customer is ineligible',
            kind: 'number',
            default: 1,
            min: 0,
            max: 5,
            gap: true,
            open: 'Eligibility beyond the statutory offer has not been ruled.',
          },
        ],
        fixed: [
          'One active agreement per account.',
          'An agreement must be offered before disconnect where the rule requires it.',
          'A broken agreement returns the account to the shutoff steps, and no further agreement is owed.',
        ],
      },
    ],
  },

  /* ---- Collections ----------------------------------------------------- */
  {
    key: 'dunning',
    area: 'Collections',
    title: 'Dunning',
    summary: 'Automatic reminders, late fees, termination notices and disconnect scheduling',
    custom: true,
    groups: [],
  },
  {
    key: 'disconnect',
    area: 'Collections',
    title: 'Disconnect & reconnect',
    summary: 'Field fees, service-transition charges and customer protections',
    groups: [
      {
        title: 'Fees',
        note: 'Each fee must match the filed tariff.',
        settings: [
          { key: 'disconnect.reconnect_fee', label: 'Reconnection', kind: 'money', default: '45.00', min: 0, tariff: true },
          { key: 'disconnect.reconnect_after_hours_fee', label: 'Reconnection, after hours', kind: 'money', default: '85.00', min: 0, tariff: true },
          { key: 'disconnect.connect_transfer_fee', label: 'Connect or transfer', kind: 'money', default: '25.00', min: 0, tariff: true },
          { key: 'disconnect.seasonal_fee', label: 'Seasonal disconnect and reconnect', kind: 'money', default: '65.00', min: 0, tariff: true },
          { key: 'disconnect.tamper_fee', label: 'Tampering investigation', kind: 'money', default: '150.00', min: 0, tariff: true },
          { key: 'disconnect.meter_test_fee', label: 'Customer-requested meter test', kind: 'money', default: '30.00', min: 0, tariff: true },
        ],
      },
      {
        title: 'Service transitions',
        settings: [
          { key: 'disconnect.auto_charge_disconnect', label: 'Charge the disconnection fee automatically', kind: 'toggle', default: true },
          { key: 'disconnect.auto_charge_turn_on', label: 'Charge the turn-on fee automatically', kind: 'toggle', default: true },
          {
            key: 'disconnect.turn_on_vacancy_days',
            label: 'Charge turn-on only after a vacancy of',
            kind: 'number',
            unit: 'days',
            default: 3,
            min: 0,
            max: 60,
          },
        ],
      },
      {
        title: 'Protections',
        settings: [
          {
            key: 'disconnect.medical_hold_days',
            label: 'Seriously-ill hold',
            kind: 'number',
            unit: 'days',
            default: 20,
            min: 20,
            max: 63,
            minNote: 'The hold is at least 20 days.',
            hint: 'Needs a physician’s statement within five working days of delinquency, and an installment agreement.',
            citation: '16 TAC §7.45',
            tariff: true,
          },
          {
            key: 'disconnect.extra_protections',
            label: 'Your own protection types',
            kind: 'rows',
            addLabel: 'Add a protection type',
            columns: [
              { key: 'code', label: 'Code', kind: 'text', placeholder: 'snake_case' },
              { key: 'label', label: 'Shown as', kind: 'text' },
              { key: 'days', label: 'Lasts', kind: 'number', min: 1, max: 365, unit: 'days' },
            ],
            newRow: { code: '', label: '', days: 30 },
            default: [{ code: 'agency_pledge', label: 'Agency pledge pending', days: 30 }],
            hint: 'Added to the statutory types, never in place of them.',
          },
        ],
        fixed: [
          'The statutory protection types — bankruptcy stay, seriously-ill hold, agency pledge, active payment agreement and open dispute — cannot be removed.',
          'The extreme-weather hold is self-executing: a prior-day high and a 24-hour forecast at or below 32°F at the county’s nearest NWS station. Missing weather data blocks disconnects.',
          'A disconnect at a site with no meter photo needs supervisor approval.',
        ],
      },
    ],
  },
  {
    key: 'writeoff',
    area: 'Collections',
    title: 'Write-off & bad debt',
    summary: 'When balances are written off or referred to an agency',
    groups: [
      {
        title: 'Write-off',
        settings: [
          { key: 'writeoff.aging_days', label: 'Write off a final bill after', kind: 'number', unit: 'days', default: 180, min: 30, max: 1095, gap: true },
          { key: 'writeoff.small_debit', label: 'Write off small debit balances under', kind: 'money', default: '5.00', min: 0, gap: true },
          {
            key: 'writeoff.small_credit',
            label: 'Write off small credit balances under',
            kind: 'money',
            default: '0.00',
            min: 0,
            gap: true,
            hint: 'Credits are owed to the customer; above zero this is usually wrong. Prefer the unclaimed-property route.',
          },
          { key: 'writeoff.agency_referral_days', label: 'Refer to a collection agency after', kind: 'number', unit: 'days', default: 120, min: 30, max: 730, gap: true },
          { key: 'writeoff.credit_bureau', label: 'Report to credit bureaus', kind: 'toggle', default: false, gap: true },
        ],
        fixed: ['Approval limits apply per customer, not per bill, so a write-off cannot be split under a limit.'],
      },
    ],
  },

  /* ---- Operations ------------------------------------------------------ */
  {
    key: 'notices',
    area: 'Operations',
    title: 'Notices & delivery',
    summary: 'Mail and email delivery, retries and returned mail',
    groups: [
      {
        title: 'Delivery',
        settings: [
          {
            key: 'notices.email_provider',
            label: 'Email provider',
            kind: 'select',
            default: 'postmark',
            options: [
              { value: 'ses', label: 'Amazon SES' },
              { value: 'sendgrid', label: 'SendGrid' },
              { value: 'mailgun', label: 'Mailgun' },
              { value: 'postmark', label: 'Postmark' },
            ],
          },
          {
            key: 'notices.mail_vendor',
            label: 'Print and mail vendor',
            kind: 'select',
            default: 'lob',
            options: [
              { value: 'lob', label: 'Lob' },
              { value: 'click2mail', label: 'Click2Mail' },
              { value: 'postal_methods', label: 'PostalMethods' },
            ],
          },
          { key: 'notices.mail_batch_time', label: 'Send the day’s mail batch at', kind: 'time', default: '16:00' },
          {
            key: 'notices.mail_skip_holidays',
            label: 'Skip the mail batch on holidays',
            kind: 'toggle',
            default: true,
            open: 'There is no holiday calendar behind this yet — the same calendar dunning needs.',
          },
        ],
        fixed: [
          'Paperless is elected by the customer, never defaulted. Without consent everything goes by mail.',
          'Termination notices go by mail or hand delivery even to a paperless customer.',
          'Statutory notices cannot be opted out of and are never deduplicated.',
          'Notice templates are versioned by effective date and kept seven years.',
        ],
      },
      {
        title: 'Retries',
        settings: [
          { key: 'notices.pdf_attempts', label: 'Render a bill PDF at most', kind: 'number', unit: 'times', default: 3, min: 1, max: 10 },
          { key: 'notices.pdf_backoff', label: 'Between render attempts, wait', kind: 'list', unit: 'minutes', default: [1, 5, 15] },
          { key: 'notices.delivery_attempts', label: 'Attempt delivery at most', kind: 'number', unit: 'times', default: 3, min: 1, max: 10 },
          { key: 'notices.delivery_backoff', label: 'Between delivery attempts, wait', kind: 'list', unit: 'minutes', default: [5, 30, 240] },
        ],
      },
      {
        title: 'Returned mail',
        settings: [
          { key: 'notices.returned_threshold', label: 'Flag an address after', kind: 'number', unit: 'returned pieces', default: 2, min: 1, max: 10, gap: true },
          { key: 'notices.returned_email', label: 'Email the customer when mail comes back', kind: 'toggle', default: true, gap: true },
          {
            key: 'notices.returned_suppress',
            label: 'Stop mailing a flagged address',
            kind: 'toggle',
            default: false,
            gap: true,
            hint: 'Statutory notices are still sent, by another channel.',
          },
        ],
      },
    ],
  },
  {
    key: 'exceptions',
    area: 'Operations',
    title: 'Exceptions & approvals',
    summary: 'Review deadlines and who may approve how much',
    groups: [
      {
        title: 'Review deadlines',
        note: 'How long an exception may sit before it escalates.',
        settings: [
          { key: 'exceptions.sla_batch_hold', label: 'Batch hold', kind: 'number', unit: 'business days', default: 1, min: 1, max: 10, gap: true },
          { key: 'exceptions.sla_critical', label: 'Critical', kind: 'number', unit: 'business days', default: 1, min: 1, max: 10, gap: true },
          { key: 'exceptions.sla_required', label: 'Review required', kind: 'number', unit: 'business days', default: 2, min: 1, max: 10, gap: true },
          { key: 'exceptions.sla_impact', label: 'Bill impact', kind: 'number', unit: 'business days', default: 3, min: 1, max: 10, gap: true },
          { key: 'exceptions.sla_csr', label: 'Customer service', kind: 'number', unit: 'business days', default: 5, min: 1, max: 20, gap: true },
          { key: 'exceptions.sla_field', label: 'Field work', kind: 'number', unit: 'business days', default: 3, min: 1, max: 20, gap: true },
        ],
        fixed: ['Review-recommended items follow the stale-review setting under Billing cycles & runs.'],
      },
      {
        title: 'Approval limits',
        note: 'Above a limit, the action waits for someone whose limit covers it.',
        settings: [
          {
            key: 'exceptions.approval_limits',
            label: 'Limits by role',
            kind: 'rows',
            fixedRows: true,
            gap: true,
            columns: [
              { key: 'role', label: 'Role', kind: 'text', readOnly: true },
              { key: 'adjustment', label: 'Adjustment', kind: 'money' },
              { key: 'writeoff', label: 'Write-off', kind: 'money' },
              { key: 'refund', label: 'Refund', kind: 'money' },
            ],
            default: [
              { role: 'Customer service rep', adjustment: '50.00', writeoff: '0.00', refund: '100.00' },
              { role: 'Billing analyst', adjustment: '500.00', writeoff: '100.00', refund: '500.00' },
              { role: 'Billing supervisor', adjustment: '5000.00', writeoff: '2500.00', refund: '5000.00' },
            ],
          },
        ],
      },
    ],
  },
  {
    key: 'imports',
    area: 'Operations',
    title: 'Imports & operations',
    summary: 'Import error handling and report refresh',
    groups: [
      {
        title: 'Imports',
        settings: [
          {
            key: 'imports.error_policy',
            label: 'When some rows fail',
            kind: 'select',
            default: 'partial_commit',
            options: [
              { value: 'partial_commit', label: 'Import the good rows' },
              { value: 'all_or_nothing', label: 'Import nothing' },
            ],
            hint: 'Each import can override this.',
          },
        ],
        fixed: ['Custom fields can never hold an identity number — SSN, driver’s licence or the like.'],
      },
      {
        title: 'Report refresh',
        settings: [
          { key: 'ops.manual_refresh', label: 'Allow refreshing reports by hand', kind: 'toggle', default: true },
          { key: 'ops.manual_refresh_interval', label: 'At most every', kind: 'number', unit: 'minutes', default: 15, min: 5, max: 240 },
          {
            key: 'ops.manual_refresh_role',
            label: 'Who may refresh',
            kind: 'select',
            default: 'admin',
            options: [
              { value: 'operator', label: 'Operators and up' },
              { value: 'admin', label: 'Administrators and up' },
              { value: 'owner', label: 'Owners only' },
            ],
          },
        ],
      },
    ],
  },
  {
    key: 'corrections',
    area: 'Operations',
    title: 'Corrections',
    summary: 'Fixed for gas — shown so nobody hunts for the switch',
    groups: [
      {
        title: 'Void and rebill',
        note: 'None of these is configurable for a gas tenant. The database refuses anything less.',
        settings: [
          {
            key: 'corrections.void_rebill_threshold',
            label: 'Small-correction shortcut',
            kind: 'text',
            default: 'None — every gas correction is a void and rebill',
            regulated: 'There is no dollar shortcut for gas.',
          },
          {
            key: 'corrections.rate_mode',
            label: 'Rates used on a rebill',
            kind: 'text',
            default: 'The rates in force for the service period',
            regulated: 'Current rates on a historical period are refused.',
          },
        ],
        fixed: [
          'Backbilling is capped by cause: a non-registering meter three months; rate misapplication six months; meter error to the shorter of the error period or the last test; tampering uncapped.',
          'Which cause applies is fixed by the platform, never by the tenant.',
        ],
      },
    ],
  },

  /* ---- You ------------------------------------------------------------- */
  {
    key: 'personal',
    area: 'You',
    title: 'Your preferences',
    summary: 'Appearance, density, start page and what you are emailed about',
    personal: true,
    groups: [
      {
        title: 'Preferences',
        note: 'These are yours alone and take effect at once.',
        settings: [
          { key: 'me.appearance', label: 'Appearance', kind: 'appearance', default: null },
          { key: 'me.density', label: 'Density', kind: 'density', default: null },
          {
            key: 'me.start_page',
            label: 'Open to',
            kind: 'select',
            default: 'dashboard',
            options: [
              { value: 'dashboard', label: 'Dashboard' },
              { value: 'exceptions', label: 'Exceptions' },
              { value: 'collections', label: 'Collections' },
            ],
          },
          {
            key: 'me.email_on',
            label: 'Email me when',
            kind: 'multi',
            default: ['run_ready', 'assigned'],
            options: [
              { value: 'run_ready', label: 'A run is ready to approve' },
              { value: 'assigned', label: 'An exception is assigned to me' },
              { value: 'settings_changed', label: 'A tenant setting changes' },
              { value: 'dunning_preview', label: 'The dunning preview is ready' },
            ],
          },
        ],
      },
    ],
  },
]

export const sectionByKey = new Map(SECTIONS.map((s) => [s.key, s]))

export const settingByKey = new Map(SECTIONS.flatMap((s) => s.groups.flatMap((g) => g.settings.map((d) => [d.key, d] as const))))

export const AREAS = ['Organization', 'Billing', 'Money in', 'Collections', 'Operations', 'You'] as const

export function defaultsOf(section: SettingSection): Record<string, unknown> {
  const out: Record<string, unknown> = {}
  for (const g of section.groups) for (const d of g.settings) out[d.key] = d.default
  return out
}
