import type { Payment } from '@/schemas/models'
import type { PaymentChannel, PaymentMethod } from '@/schemas/enums'
import { invoices } from '@/fixtures/billing'
import { asOf } from '@/fixtures/tenant'

/**
 * Payments received.
 *
 * Every posted payment is generated from a bill's `amount_paid`, so the two
 * cannot drift: an invoice shows it was paid because a payment says so. The
 * other statuses are written by hand, one story each, and none of them moves
 * an invoice — only posted money does.
 */

type Profile = { method: PaymentMethod; channel: PaymentChannel; afterBill: number; by: string }

/** How each account habitually pays, and how many days after the bill date. */
const PROFILE: Record<string, Profile> = {
  'cus-0001': { method: 'check', channel: 'walk_in', afterBill: 15, by: 'M. Castillo' },
  'cus-0002': { method: 'credit_card', channel: 'portal', afterBill: 18, by: 'system' },
  'cus-0003': { method: 'ach', channel: 'portal', afterBill: 19, by: 'system' },
  'cus-0004': { method: 'check', channel: 'mail', afterBill: 17, by: 'J. Whitaker' },
  'cus-0005': { method: 'cash', channel: 'walk_in', afterBill: 12, by: 'M. Castillo' },
  'cus-0006': { method: 'money_order', channel: 'walk_in', afterBill: 19, by: 'J. Whitaker' },
  'cus-0007': { method: 'credit_card', channel: 'agent_phone', afterBill: 10, by: 'M. Castillo' },
  'cus-0008': { method: 'auto_pay', channel: 'auto_pay', afterBill: 20, by: 'system' },
}

const addDays = (d: string, n: number) => {
  const x = new Date(`${d}T00:00:00Z`)
  x.setUTCDate(x.getUTCDate() + n)
  return x.toISOString().slice(0, 10)
}
const tz = (d: string) => (d >= '2025-03-09' && d < '2025-11-02' ? '-05:00' : '-06:00')
const at = (d: string, time = '10:24:00') => `${d}T${time}${tz(d)}`
/** Deterministic, digit-only references that look like what each rail issues. */
const digits = (seed: string, n: number) => {
  let h = 0
  for (const ch of seed) h = (h * 31 + ch.charCodeAt(0)) % 1_000_000_007
  return String(h).padStart(n, '0').slice(-n)
}

type Draft = Omit<Payment, 'id' | 'payment_number'>

function base(customerId: string, date: string, amount: string, profile: Profile, seed: string): Draft {
  const m = profile.method
  return {
    customer_id: customerId,
    payment_date: date,
    amount,
    payment_method: m,
    channel: profile.channel,
    reference_number: m === 'ach' || m === 'auto_pay' ? `ACH-${digits(seed, 9)}` : m === 'money_order' ? `MO-${digits(seed, 10)}` : null,
    provider_authorization_code: m === 'credit_card' || m === 'debit_card' ? digits(seed, 6) : null,
    check_number: m === 'check' ? digits(seed, 4) : null,
    check_date: m === 'check' ? date : null,
    check_bank_name: m === 'check' ? (customerId === 'cus-0004' ? 'Texas Treasury' : 'Citizens State Bank') : null,
    status: 'posted',
    applied_amount: amount,
    unapplied_amount: '0.00',
    is_deposit: false,
    deposit_status: null,
    nsf_date: null,
    nsf_reason: null,
    refund_reason: null,
    reversed_at: null,
    reversed_reason: null,
    notes: null,
    received_by: profile.by,
    created_at: at(date),
    applications: [],
  }
}

/* ---- Posted: one per paid bill ---------------------------------------- */

const posted: Draft[] = invoices
  /* Issued (first_issued_at set), live, and paid something. */
  .filter((i) => i.first_issued_at !== null && i.status !== 'void' && Number(i.amount_paid) > 0)
  .map((i) => {
    const profile = PROFILE[i.customer_id]
    /* Paid on the habit, but never after the as-of date and never after the due date for a partial. */
    let date = addDays(i.invoice_date, profile.afterBill)
    if (date > asOf.validAt) date = asOf.validAt
    return { ...base(i.customer_id, date, i.amount_paid, profile, i.id), applications: [{ invoice_id: i.id, amount: i.amount_paid }] }
  })

/* ---- The exceptions, one story each ------------------------------------ */

const bill = (id: string) => {
  const i = invoices.find((x) => x.id === id)
  if (!i) throw new Error(`payments fixture: no invoice ${id}`)
  return i
}

const stories: Draft[] = [
  /* Boyd paid January through the portal by bank draft; it has not settled. */
  (() => {
    const i = bill('inv-202601-0002')
    return {
      ...base('cus-0002', '2026-02-13', i.balance, { method: 'ach', channel: 'portal', afterBill: 0, by: 'system' }, 'boyd-ach'),
      status: 'pending' as const,
      applications: [{ invoice_id: i.id, amount: i.balance }],
      notes: 'Portal e-check. Settles in 2–3 business days; the bill stays open until it does.',
    }
  })(),
  /* Brazos Linen started paying down December by ACH this morning. */
  (() => {
    const i = bill('inv-202512-0003')
    return {
      ...base('cus-0003', asOf.validAt, i.balance, PROFILE['cus-0003'], 'linen-ach'),
      status: 'pending' as const,
      applications: [{ invoice_id: i.id, amount: i.balance }],
      notes: 'December only. January remains open pending the disputed-usage review.',
    }
  })(),
  /* Fry's October check bounced — which is why October is still open. */
  (() => {
    const i = bill('inv-202510-0006')
    return {
      ...base('cus-0006', '2025-11-04', i.amount_due, { method: 'check', channel: 'walk_in', afterBill: 0, by: 'J. Whitaker' }, 'fry-check'),
      status: 'nsf' as const,
      applications: [{ invoice_id: i.id, amount: i.amount_due }],
      nsf_date: '2025-11-12',
      nsf_reason: 'Returned check — insufficient funds',
      notes: 'Returned-check fee assessed. Account moved to cash or money order only.',
    }
  })(),
  /* A card terminal timeout captured Herrera's payment twice; the second was reversed. */
  {
    ...base('cus-0001', '2026-01-28', '100.00', { method: 'credit_card', channel: 'agent_phone', afterBill: 0, by: 'M. Castillo' }, 'herrera-dup'),
    status: 'reversed',
    applications: [{ invoice_id: 'inv-202601-0001', amount: '100.00' }],
    reversed_at: at('2026-01-29', '08:40:00'),
    reversed_reason: 'Duplicate capture after a terminal timeout; customer was charged once',
  },
  /* The bakery paid December twice — once by phone, once online. The second was refunded. */
  (() => {
    const i = bill('inv-202512-0007')
    return {
      ...base('cus-0007', '2025-12-27', i.amount_due, { method: 'credit_card', channel: 'portal', afterBill: 0, by: 'system' }, 'bakery-dup'),
      status: 'refunded' as const,
      applied_amount: '0.00',
      unapplied_amount: i.amount_due,
      refund_reason: 'Duplicate of the phone payment on Dec 26 — refunded to card Dec 30',
    }
  })(),
  /* A cash payment keyed with the digits transposed, voided at the counter and re-entered. */
  {
    ...base('cus-0005', '2025-12-28', '58.00', PROFILE['cus-0005'], 'nwosu-void'),
    status: 'voided',
    applications: [{ invoice_id: 'inv-202512-0005', amount: '58.00' }],
    notes: 'Keyed $58.00 for the amount tendered. Voided at the counter and re-entered for the bill amount.',
  },
  /* Vance's new-service deposit, held on account rather than applied to a bill. */
  {
    ...base('cus-0008', '2025-12-15', '150.00', { method: 'debit_card', channel: 'walk_in', afterBill: 0, by: 'J. Whitaker' }, 'vance-dep'),
    applied_amount: '0.00',
    unapplied_amount: '150.00',
    is_deposit: true,
    deposit_status: 'held',
    notes: 'New-service deposit. Refundable after 12 months of on-time payment.',
  },
]

/** Numbered in the order received, the way the cashiering system issues them. */
export const payments: Payment[] = [...posted, ...stories]
  .sort((a, b) => a.payment_date.localeCompare(b.payment_date) || a.customer_id.localeCompare(b.customer_id))
  .map((p, i) => ({
    ...p,
    id: `pmt-${String(i + 1).padStart(4, '0')}`,
    payment_number: `PMT-${p.payment_date.slice(2, 4)}${p.payment_date.slice(5, 7)}-${String(1040 + i).padStart(5, '0')}`,
  }))

export const paymentById = new Map(payments.map((p) => [p.id, p]))
