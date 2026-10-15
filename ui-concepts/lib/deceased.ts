import type { Exception } from '@/schemas/models'

/**
 * A deceased account (R-08).
 *
 * Death is a customer status with a date, not a protective program. The
 * account carries a hold that blocks shutoff and collections until it is
 * changed over to a family member, and the change-over needs proof: a death
 * certificate, an obituary, and a will, conservatorship or spouse
 * documentation. Each is recorded on its own, with the date it came in.
 *
 * The hold gets a one-month review clock. It starts when the death is
 * recorded, and any update on the account restarts it. If it runs out, a
 * medium exception asks someone to look, so the account doesn't sit frozen.
 *
 * Every step is a log entry with who and when, and none is edited after.
 */

export type ProofKind = 'death_certificate' | 'obituary' | 'authority'

export const PROOFS: { kind: ProofKind; label: string }[] = [
  { kind: 'death_certificate', label: 'Death certificate' },
  { kind: 'obituary', label: 'Obituary' },
  { kind: 'authority', label: 'Will, conservatorship or spouse documentation' },
]

export const proofLabel = (k: ProofKind) => PROOFS.find((p) => p.kind === k)!.label

export type NewHolder = {
  name: string
  relationship: string
  /** The family member's account, when it is already open. */
  account_number: string | null
  phone: string | null
}

type StepBase = {
  id: string
  customer_id: string
  /** The day the step was recorded. Any step restarts the review clock from here. */
  on: string
  at: string
  by: string
  notes: string | null
}

export type DeceasedStep = StepBase &
  (
    | { kind: 'death_recorded'; date_of_death: string }
    | { kind: 'proof'; proof: ProofKind; received: string }
    | { kind: 'note' }
    | { kind: 'transferred'; new_holder: NewHolder; effective: string }
  )

export type DeceasedState = {
  customerId: string
  steps: DeceasedStep[]
  dateOfDeath: string
  recordedOn: string
  recordedBy: string
  proofs: Partial<Record<ProofKind, Extract<DeceasedStep, { kind: 'proof' }>>>
  allProofs: boolean
  transfer: Extract<DeceasedStep, { kind: 'transferred' }> | null
  /** True until the account is changed over to a family member. */
  holdActive: boolean
  lastUpdateOn: string
  reviewDueOn: string
}

/** One calendar month later; the 31st lands on the last day of a shorter month. */
export function addMonth(iso: string): string {
  const [y, m, d] = iso.split('-').map(Number)
  const ny = m === 12 ? y + 1 : y
  const nm = m === 12 ? 1 : m + 1
  const last = new Date(Date.UTC(ny, nm, 0)).getUTCDate()
  return `${ny}-${String(nm).padStart(2, '0')}-${String(Math.min(d, last)).padStart(2, '0')}`
}

/** The account's deceased state from its steps, or null when no death is recorded. */
export function deceasedState(customerId: string, all: DeceasedStep[]): DeceasedState | null {
  const steps = all.filter((s) => s.customer_id === customerId).sort((a, b) => (a.at < b.at ? -1 : 1))
  const death = steps.find((s): s is Extract<DeceasedStep, { kind: 'death_recorded' }> => s.kind === 'death_recorded')
  if (!death) return null
  const proofs: DeceasedState['proofs'] = {}
  for (const s of steps) if (s.kind === 'proof' && !proofs[s.proof]) proofs[s.proof] = s
  const transfer = steps.find((s): s is Extract<DeceasedStep, { kind: 'transferred' }> => s.kind === 'transferred') ?? null
  const lastUpdateOn = steps.reduce((d, s) => (s.on > d ? s.on : d), death.on)
  return {
    customerId,
    steps,
    dateOfDeath: death.date_of_death,
    recordedOn: death.on,
    recordedBy: death.by,
    proofs,
    allProofs: PROOFS.every((p) => proofs[p.kind]),
    transfer,
    holdActive: !transfer,
    lastUpdateOn,
    reviewDueOn: addMonth(lastUpdateOn),
  }
}

/** True when the clock has run out on a held account. */
export const reviewOverdue = (s: DeceasedState, today: string) => s.holdActive && today >= s.reviewDueOn

/**
 * The review exception for an account whose clock has run out, or null.
 * It resolves when the account is changed over, so a transferred account
 * never raises one.
 */
export function reviewException(s: DeceasedState, today: string, ids: { id: string; meterId: string | null }): Exception | null {
  if (!reviewOverdue(s, today)) return null
  const detected = `${s.reviewDueOn}T06:00:00-06:00`
  const missing = PROOFS.filter((p) => !s.proofs[p.kind]).map((p) => p.label)
  return {
    id: ids.id,
    anomaly_type: 'deceased_account_review',
    severity: 'medium',
    confidence: 1,
    status: 'open',
    snoozed_until: null,
    snooze_reason: null,
    entity_type: 'customer',
    entity_id: s.customerId,
    customer_id: s.customerId,
    meter_id: ids.meterId,
    invoice_id: null,
    description: 'Deceased account with no update in one month',
    details: {
      date_of_death: s.dateOfDeath,
      death_recorded: s.recordedOn,
      last_update: s.lastUpdateOn,
      review_due: s.reviewDueOn,
      proof_outstanding: missing.length ? missing.join('; ') : 'none',
    },
    suggested_action: {
      label: 'Open the account',
      explanation:
        'Opens the account to chase the outstanding proof or record what the family has said. Any update restarts the one-month clock. This resolves when the account is changed over to a family member.',
    },
    detection_method: 'rule_based',
    detector_name: 'deceased_account_review',
    detected_at: detected,
    recurrence_count: 1,
    first_detected_at: detected,
    estimated_impact: null,
    assigned_to: null,
    blocks_delivery: false,
  }
}
