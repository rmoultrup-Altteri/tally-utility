import type { DunningStage } from '@/schemas/enums'

/**
 * Collections and disconnect.
 *
 * A wrongful disconnect is the highest-consequence error this product can
 * make, so the worklist is built the opposite way round from a normal
 * collections queue. It does not lead with who owes the most. It leads with
 * who is genuinely eligible for field work today, and it states, per account,
 * every rule that was evaluated to reach that answer.
 *
 * The bypass evaluation is a daily engine, not a flag on a customer record:
 * a temperature forecast moves, a medical certificate expires, an agency
 * pledge clears. What is true this morning is not what was true yesterday,
 * and the audit trail has to show which it was at the moment someone acted.
 */

/* ---- Jurisdiction conditions evaluated today -------------------------- */

/**
 * Texas does not use a calendar winter moratorium. 16 TAC §7.460 is
 * forecast-driven: service may not be disconnected when the National Weather
 * Service forecasts the temperature dropping below the threshold within the
 * next 24 hours — and the protection covers RESIDENTIAL service only.
 * That last clause is why anything is actionable on this screen today.
 */
export type Condition = {
  code: string
  label: string
  state: 'in_force' | 'clear' | 'not_adopted'
  detail: string
  citation: string
  scope: string
}

export const conditionsToday: Condition[] = [
  {
    code: 'temperature_hold',
    label: 'Temperature hold',
    state: 'in_force',
    detail: 'NWS College Station forecasts 26°F within 24 hours. Threshold is 32°F.',
    citation: '16 TAC §7.460(d)',
    scope: 'Residential service only',
  },
  {
    code: 'winter_window',
    label: 'Calendar winter moratorium',
    state: 'not_adopted',
    detail: 'Texas has no fixed seasonal window. The forecast rule above governs instead.',
    citation: '—',
    scope: 'All service',
  },
  {
    code: 'dpa_offer',
    label: 'Deferred payment plan offer',
    state: 'in_force',
    detail: 'A DPA must be offered before disconnect where arrears accrued during a bill-spike month.',
    citation: '16 TAC §7.45(g)',
    scope: 'Residential service',
  },
  {
    code: 'notice_maturity',
    label: 'Notice service period',
    state: 'in_force',
    detail: 'Ten days must elapse between the formal disconnect notice and field work.',
    citation: '16 TAC §7.460(b)',
    scope: 'All service',
  },
]

/** The instant the engine last evaluated every account against the above. */
export const evaluatedAt = '2026-02-14T05:30:00-06:00'
/** When the forecast currently clears the threshold again. */
export const holdClearsOn = '2026-02-17'

/* ---- Bypass conditions ------------------------------------------------ */

export type BypassCode =
  | 'temperature_hold'
  | 'medical_certificate'
  | 'dpa_good_standing'
  | 'agency_pledge'
  | 'bankruptcy_stay'
  | 'formal_dispute'
  | 'payment_pending'
  | 'senior_grace'
  | 'scra_protection'
  | 'designee_not_notified'
  | 'notice_immature'

/**
 * `absolute` conditions are prohibitions on all collections activity, not
 * merely on disconnect — the bankruptcy stay bars even sending a notice.
 * `protection` sits with the customer and outlasts the weather.
 * `weather` lifts on a forecast.
 * `process` is the utility's own unfinished work, and is the only category
 * anyone here can clear by doing something today.
 */
export type BypassCategory = 'absolute' | 'protection' | 'weather' | 'process'

export type Bypass = {
  code: BypassCode
  label: string
  short: string
  category: BypassCategory
  citation: string
}

export const BYPASSES: Record<BypassCode, Bypass> = {
  bankruptcy_stay: {
    code: 'bankruptcy_stay',
    label: 'Bankruptcy automatic stay',
    short: 'Stay',
    category: 'absolute',
    citation: '11 USC §362',
  },
  medical_certificate: {
    code: 'medical_certificate',
    label: 'Medical certification on file',
    short: 'Medical',
    category: 'protection',
    citation: '16 TAC §7.460(h)',
  },
  scra_protection: {
    code: 'scra_protection',
    label: 'Servicemember protection',
    short: 'SCRA',
    category: 'protection',
    citation: '50 USC §3901',
  },
  senior_grace: {
    code: 'senior_grace',
    label: 'Senior / disabled extended grace',
    short: 'Senior',
    category: 'protection',
    citation: '16 TAC §7.460(i)',
  },
  dpa_good_standing: {
    code: 'dpa_good_standing',
    label: 'Payment arrangement in good standing',
    short: 'DPA',
    category: 'protection',
    citation: '16 TAC §7.45(g)',
  },
  agency_pledge: {
    code: 'agency_pledge',
    label: 'Agency pledge pending remittance',
    short: 'Pledge',
    category: 'protection',
    citation: 'LIHEAP · 45 CFR §96.85',
  },
  formal_dispute: {
    code: 'formal_dispute',
    label: 'Formal dispute open',
    short: 'Dispute',
    category: 'protection',
    citation: '16 TAC §7.460(f)',
  },
  payment_pending: {
    code: 'payment_pending',
    label: 'Payment posted, not yet cleared',
    short: 'Payment',
    category: 'process',
    citation: 'Internal · clearing window',
  },
  designee_not_notified: {
    code: 'designee_not_notified',
    label: 'Third-party designee not yet notified',
    short: 'Designee',
    category: 'process',
    citation: '16 TAC §7.460(c)',
  },
  notice_immature: {
    code: 'notice_immature',
    label: 'Notice service period not elapsed',
    short: 'Notice',
    category: 'process',
    citation: '16 TAC §7.460(b)',
  },
  temperature_hold: {
    code: 'temperature_hold',
    label: 'Temperature hold in force',
    short: 'Weather',
    category: 'weather',
    citation: '16 TAC §7.460(d)',
  },
}

/* ---- The worklist ----------------------------------------------------- */

export type Notice = { type: string; sentAt: string; channel: string }

export type WorklistRow = {
  id: string
  /** Present only where the account is modelled in full elsewhere. */
  customerId?: string
  accountNumber: string
  name: string
  isResidential: boolean
  address: string
  city: string
  balance: string
  /** The portion under formal dispute, which is not collectible meanwhile. */
  disputed?: string
  pastDueDays: number
  stage: DunningStage
  lastNotice: Notice | null
  bypasses: { code: BypassCode; detail: string; expires?: string }[]
  deposit: string
  priorDisconnects: number
  /** What this account needs from an operator today, if anything. */
  nextAction?: string
}

export const worklist: WorklistRow[] = [
  {
    id: 'wl-01',
    customerId: 'cus-0007',
    accountNumber: '200-140558',
    name: 'Kettle & Crumb Bakery',
    isResidential: false,
    address: '311 S Main St',
    city: 'Bryan',
    balance: '489.31',
    pastDueDays: 38,
    stage: 'shutoff_scheduled',
    lastNotice: { type: 'Formal disconnect notice', sentAt: '2026-02-02', channel: 'Certified mail' },
    bypasses: [],
    deposit: '600.00',
    priorDisconnects: 1,
    nextAction: 'Dispatch disconnect order',
  },
  {
    id: 'wl-02',
    accountNumber: '200-151903',
    name: 'Vance Brothers Welding',
    isResidential: false,
    address: '4402 Old Reliance Rd',
    city: 'Bryan',
    balance: '2417.80',
    pastDueDays: 51,
    stage: 'shutoff_scheduled',
    lastNotice: { type: 'Formal disconnect notice', sentAt: '2026-01-30', channel: 'Certified mail' },
    bypasses: [],
    deposit: '0.00',
    priorDisconnects: 0,
    nextAction: 'Dispatch disconnect order',
  },
  {
    id: 'wl-03',
    accountNumber: '100-318776',
    name: 'Trent, Mikayla',
    isResidential: true,
    address: '2207 Manor Dr',
    city: 'Bryan',
    balance: '487.62',
    pastDueDays: 58,
    stage: 'shutoff_scheduled',
    lastNotice: { type: 'Formal disconnect notice', sentAt: '2026-01-28', channel: 'Certified mail' },
    bypasses: [
      {
        code: 'temperature_hold',
        detail: 'Residential service, forecast 26°F. Payment arrangement breached 2026-01-19.',
      },
    ],
    deposit: '0.00',
    priorDisconnects: 2,
  },
  {
    id: 'wl-04',
    accountNumber: '100-304512',
    name: 'Pham, Long',
    isResidential: true,
    address: '815 Timber St',
    city: 'College Station',
    balance: '291.40',
    pastDueDays: 44,
    stage: 'shutoff_scheduled',
    lastNotice: { type: 'Formal disconnect notice', sentAt: '2026-02-01', channel: 'Certified mail' },
    bypasses: [
      { code: 'temperature_hold', detail: 'Residential service, forecast 26°F.' },
      {
        code: 'payment_pending',
        detail: '$180.00 posted 2026-02-13 by ACH. Clears 2026-02-17; balance falls to $111.40.',
      },
    ],
    deposit: '0.00',
    priorDisconnects: 0,
    nextAction: 'Re-evaluate after clearing',
  },
  {
    id: 'wl-05',
    customerId: 'cus-0001',
    accountNumber: '100-248193',
    name: 'Herrera, Marisol',
    isResidential: true,
    address: '1418 Ashburn St',
    city: 'Bryan',
    balance: '318.44',
    pastDueDays: 47,
    stage: 'shutoff_warning',
    lastNotice: { type: 'Past-due notice', sentAt: '2026-02-04', channel: 'Mail' },
    bypasses: [
      {
        code: 'medical_certificate',
        detail: 'Oxygen concentrator. Certified by Dr. A. Reyes, St Joseph Health.',
        expires: '2026-04-30',
      },
      { code: 'temperature_hold', detail: 'Residential service, forecast 26°F.' },
    ],
    deposit: '0.00',
    priorDisconnects: 0,
    nextAction: 'Re-certification due 2026-04-30 — begin outreach 2026-03-30',
  },
  {
    id: 'wl-06',
    customerId: 'cus-0006',
    accountNumber: '100-290118',
    name: 'Fry, Wendell',
    isResidential: true,
    address: '1502 Groesbeck St',
    city: 'Bryan',
    balance: '604.19',
    pastDueDays: 96,
    stage: 'collections',
    lastNotice: { type: 'Agency placement notice', sentAt: '2026-01-26', channel: 'Mail' },
    bypasses: [
      {
        code: 'agency_pledge',
        detail: 'Brazos Valley Community Action pledged $300.00 on 2026-02-09. Remittance not received.',
        expires: '2026-03-11',
      },
      { code: 'temperature_hold', detail: 'Residential service, forecast 26°F.' },
    ],
    deposit: '0.00',
    priorDisconnects: 1,
    nextAction: 'Confirm pledge remittance with agency',
  },
  {
    id: 'wl-07',
    accountNumber: '100-331204',
    name: 'Okafor, Priscilla',
    isResidential: true,
    address: '1120 Dexter Dr',
    city: 'College Station',
    balance: '402.11',
    pastDueDays: 63,
    stage: 'shutoff_warning',
    lastNotice: { type: 'Past-due notice', sentAt: '2026-02-03', channel: 'Mail' },
    bypasses: [
      {
        code: 'scra_protection',
        detail: 'Active-duty orders on file, deployed 2025-11-04. Interest capped at 6%.',
        expires: '2026-11-04',
      },
      { code: 'temperature_hold', detail: 'Residential service, forecast 26°F.' },
    ],
    deposit: '0.00',
    priorDisconnects: 0,
  },
  {
    id: 'wl-08',
    accountNumber: '100-259840',
    name: 'Sandoval, Rita',
    isResidential: true,
    address: '706 Post Oak Ln',
    city: 'Bryan',
    balance: '228.90',
    pastDueDays: 39,
    stage: 'shutoff_warning',
    lastNotice: { type: 'Past-due notice', sentAt: '2026-02-05', channel: 'Mail' },
    bypasses: [
      { code: 'senior_grace', detail: 'Age 74. Extended grace granted 2026-01-15.', expires: '2026-03-15' },
      { code: 'temperature_hold', detail: 'Residential service, forecast 26°F.' },
    ],
    deposit: '0.00',
    priorDisconnects: 0,
  },
  {
    id: 'wl-09',
    accountNumber: '100-287365',
    name: 'Hollis, Duane',
    isResidential: true,
    address: '3318 Pendleton Dr',
    city: 'Bryan',
    balance: '744.03',
    pastDueDays: 71,
    stage: 'payment_plan',
    lastNotice: { type: 'Payment arrangement confirmation', sentAt: '2026-01-08', channel: 'Email' },
    bypasses: [
      {
        code: 'dpa_good_standing',
        detail: '9-month arrangement, 4 instalments paid, next due 2026-02-20. No missed payments.',
      },
      { code: 'temperature_hold', detail: 'Residential service, forecast 26°F.' },
    ],
    deposit: '0.00',
    priorDisconnects: 0,
  },
  {
    id: 'wl-10',
    customerId: 'cus-0003',
    accountNumber: '200-114027',
    name: 'Brazos Linen Service',
    isResidential: false,
    address: '2905 Finfeather Rd',
    city: 'Bryan',
    balance: '11842.67',
    disputed: '4180.00',
    pastDueDays: 62,
    stage: 'shutoff_scheduled',
    lastNotice: { type: 'Formal disconnect notice', sentAt: '2026-01-29', channel: 'Certified mail' },
    bypasses: [
      {
        code: 'formal_dispute',
        detail:
          'Dispute filed 2026-02-06 over $4,180.00 of demand charges. Disconnect is barred while the disputed amount is at issue; the undisputed $7,662.67 remains collectible by other means.',
      },
    ],
    deposit: '4200.00',
    priorDisconnects: 0,
    nextAction: 'Respond to dispute by 2026-02-27',
  },
  {
    id: 'wl-11',
    accountNumber: '100-342119',
    name: 'Ferris, Odell',
    isResidential: true,
    address: '1907 Cavitt Ave',
    city: 'Bryan',
    balance: '356.75',
    pastDueDays: 54,
    stage: 'shutoff_scheduled',
    lastNotice: { type: 'Formal disconnect notice', sentAt: '2026-01-31', channel: 'Certified mail' },
    bypasses: [
      {
        code: 'designee_not_notified',
        detail:
          'Third-party designee on file (daughter, L. Ferris) has not been served a copy of the disconnect notice.',
      },
      { code: 'temperature_hold', detail: 'Residential service, forecast 26°F.' },
    ],
    deposit: '0.00',
    priorDisconnects: 0,
    nextAction: 'Serve designee copy — blocks disconnect until sent',
  },
  {
    id: 'wl-12',
    accountNumber: '100-312088',
    name: 'Estrada, Camila',
    isResidential: true,
    address: '4110 Hampton Ct',
    city: 'College Station',
    balance: '512.30',
    pastDueDays: 49,
    stage: 'shutoff_warning',
    lastNotice: { type: 'Formal disconnect notice', sentAt: '2026-02-11', channel: 'Certified mail' },
    bypasses: [
      { code: 'notice_immature', detail: 'Ten-day service period matures 2026-02-21.' },
      { code: 'temperature_hold', detail: 'Residential service, forecast 26°F.' },
    ],
    deposit: '0.00',
    priorDisconnects: 0,
  },
  {
    id: 'wl-13',
    customerId: 'cus-0002',
    accountNumber: '100-301884',
    name: 'Boyd, Curtis',
    isResidential: true,
    address: '907 Fairview Ave',
    city: 'Bryan',
    balance: '96.10',
    pastDueDays: 22,
    stage: 'reminder_sent',
    lastNotice: { type: 'Reminder', sentAt: '2026-02-08', channel: 'Email' },
    bypasses: [{ code: 'temperature_hold', detail: 'Residential service, forecast 26°F.' }],
    deposit: '150.00',
    priorDisconnects: 0,
    nextAction: 'Past-due notice due today',
  },
]

/* ---- Eligibility ------------------------------------------------------ */

export type Verdict = {
  eligible: boolean
  category: BypassCategory | 'eligible'
  reason: string
}

const CATEGORY_ORDER: BypassCategory[] = ['absolute', 'protection', 'process', 'weather']

/**
 * The single question the screen exists to answer.
 *
 * An account often carries several conditions at once, so the category order
 * below decides which one gets named — and it is ordered by what this office
 * should DO, not by which condition outlasts the others. An absolute bar is
 * named first because nothing may be touched. A customer protection next,
 * because it is not ours to clear. Then our own outstanding work, because it
 * is the only thing anyone here can finish today. The weather is named last,
 * since it clears on a forecast whether or not anyone acts.
 *
 * Consequence: a row named for process work is usually ALSO weather-held. The
 * row's condition chips show every rule evaluated, so the named reason is a
 * priority, never a claim that it is the only thing standing in the way.
 */
export function evaluate(row: WorklistRow): Verdict {
  for (const category of CATEGORY_ORDER) {
    const hit = row.bypasses.find((b) => BYPASSES[b.code].category === category)
    if (hit) {
      return { eligible: false, category, reason: BYPASSES[hit.code].label }
    }
  }
  return { eligible: true, category: 'eligible', reason: 'No bypass condition in force' }
}

/**
 * Pipeline totals. Only the rows above are modelled in full; the counts are
 * the cycle's, and the screen says so rather than implying thirteen accounts
 * are the whole book.
 */
export const pipeline = {
  total: 37,
  modelled: worklist.length,
  eligibleWhenHoldLifts: 14,
  noticesDueToday: 9,
} as const

/* ---- Absolute exclusion ----------------------------------------------- */

/**
 * The automatic stay is not a bypass condition on a worklist row. It removes
 * the account from collections entirely — no notices, no calls, no field
 * activity — and the ledger splits at the petition date. Putting it in the
 * same table as "blocked today" would understate what it is, so it gets its
 * own place on the screen.
 */
export const stayedAccounts = [
  {
    id: 'bk-01',
    accountNumber: '100-274930',
    name: 'Delacroix, Jean-Baptiste',
    address: '1622 Villa Maria Rd',
    city: 'Bryan',
    chapter: 'Chapter 13',
    caseNumber: '26-30118-hdh13',
    petitionDate: '2026-02-02',
    prePetitionBalance: '882.14',
    postPetitionBalance: '64.20',
    /** §366(b): 20 days from the order for relief to request adequate assurance. */
    assuranceDeadline: '2026-02-22',
    noticedAt: '2026-02-03T11:20:00-06:00',
  },
]

/* ---- Reconnect / relight ---------------------------------------------- */

/**
 * Every reconnect is a scheduled truck roll with a gas-specific tail: the
 * meter is not simply re-energised. A tech has to be on site, pressure-test
 * the line, relight every pilot, and the customer has to be present to give
 * access. That is why the queue is prioritised rather than first-in-first-out.
 */
export type ReconnectRow = {
  id: string
  accountNumber: string
  name: string
  address: string
  disconnectedAt: string
  paidAt: string | null
  slaDueAt: string
  priority: 'medical' | 'temperature' | 'standard'
  priorityReason: string
  fee: string
  feeWaived: boolean
  feeNote: string
  customerConfirmed: boolean
}

export const reconnectQueue: ReconnectRow[] = [
  {
    id: 'rc-01',
    accountNumber: '100-298447',
    name: 'Ibarra, Soledad',
    address: '2811 Kent St, Bryan',
    disconnectedAt: '2026-02-11T14:05:00-06:00',
    paidAt: '2026-02-13T16:40:00-06:00',
    slaDueAt: '2026-02-14T16:40:00-06:00',
    priority: 'medical',
    priorityReason: 'Nebuliser on file; certification lodged after disconnect',
    fee: '65.00',
    feeWaived: true,
    feeNote: 'Waived — certification predates the disconnect order',
    customerConfirmed: true,
  },
  {
    id: 'rc-02',
    accountNumber: '100-286612',
    name: 'Whitfield, Aaron',
    address: '515 Bittle Ln, Bryan',
    disconnectedAt: '2026-02-12T10:22:00-06:00',
    paidAt: '2026-02-14T07:55:00-06:00',
    slaDueAt: '2026-02-15T07:55:00-06:00',
    priority: 'temperature',
    priorityReason: 'Forecast 26°F overnight; no alternative heat reported',
    fee: '65.00',
    feeWaived: false,
    feeNote: 'After-hours differential $40.00 applies after 5:00 PM',
    customerConfirmed: false,
  },
  {
    id: 'rc-03',
    accountNumber: '200-149022',
    name: 'Cornerstone Auto Body',
    address: '1204 Wallis Rd, Bryan',
    disconnectedAt: '2026-02-09T09:10:00-06:00',
    paidAt: '2026-02-13T11:02:00-06:00',
    slaDueAt: '2026-02-15T11:02:00-06:00',
    priority: 'standard',
    priorityReason: 'Commercial, 48-hour SLA',
    fee: '145.00',
    feeWaived: false,
    feeNote: 'Commercial relight — two appliances, pressure test required',
    customerConfirmed: true,
  },
]

/* ---- Audit trail ------------------------------------------------------ */

/**
 * Subpoena-ready means every decision carries its rationale and its source.
 * "The system decided" is an answer a regulator accepts only when the rule it
 * applied, and the value it read, are both on the record.
 */
export type AuditEntry = {
  id: string
  at: string
  account: string
  action: string
  rationale: string
  source: 'system' | 'operator'
  actor: string
}

export const auditTrail: AuditEntry[] = [
  {
    id: 'au-01',
    at: evaluatedAt,
    account: 'All residential',
    action: 'Temperature hold applied',
    rationale: 'NWS College Station 24-hour forecast low 26°F against a 32°F threshold.',
    source: 'system',
    actor: 'dunning-evaluator',
  },
  {
    id: 'au-02',
    at: '2026-02-14T05:30:04-06:00',
    account: '100-304512',
    action: 'Disconnect eligibility withheld',
    rationale: 'ACH payment of $180.00 posted 2026-02-13 has not cleared the settlement window.',
    source: 'system',
    actor: 'dunning-evaluator',
  },
  {
    id: 'au-03',
    at: '2026-02-13T15:41:00-06:00',
    account: '100-342119',
    action: 'Designee notification flagged outstanding',
    rationale: 'Third-party designee recorded 2025-08-02 was not served the 2026-01-31 notice.',
    source: 'system',
    actor: 'dunning-evaluator',
  },
  {
    id: 'au-04',
    at: '2026-02-13T09:18:00-06:00',
    account: '100-290118',
    action: 'Agency pledge recorded',
    rationale: 'Brazos Valley Community Action pledge of $300.00 accepted; collections suspended pending remittance.',
    source: 'operator',
    actor: 'Dana Pearce',
  },
  {
    id: 'au-05',
    at: '2026-02-03T11:20:00-06:00',
    account: '100-274930',
    action: 'All collections activity stopped',
    rationale: 'Chapter 13 petition 26-30118-hdh13 filed 2026-02-02. Automatic stay under 11 USC §362.',
    source: 'operator',
    actor: 'Dana Pearce',
  },
]
