import type { PaymentChannel, PaymentMethod, PaymentStatus } from '@/schemas/enums'
import type { Tone } from '@/components/ui/State'

/** Payment words, shared by the list and the add-payment page. */

export const STATUS: Record<PaymentStatus, { label: string; tone: Tone; meaning: string }> = {
  pending: { label: 'Pending', tone: 'pending', meaning: 'Awaiting settlement — bills stay open' },
  posted: { label: 'Posted', tone: 'posted', meaning: 'Applied to bills or held on account' },
  nsf: { label: 'NSF', tone: 'critical', meaning: 'Returned unpaid by the bank' },
  reversed: { label: 'Reversed', tone: 'warning', meaning: 'Taken back after posting' },
  refunded: { label: 'Refunded', tone: 'held', meaning: 'Money returned to the customer' },
  voided: { label: 'Voided', tone: 'void', meaning: 'Cancelled at entry, never counted' },
}

export const STATUS_ORDER: PaymentStatus[] = ['pending', 'posted', 'nsf', 'reversed', 'refunded', 'voided']

export const METHOD: Record<PaymentMethod, string> = {
  cash: 'Cash',
  check: 'Check',
  ach: 'ACH / e-check',
  credit_card: 'Credit card',
  debit_card: 'Debit card',
  money_order: 'Money order',
  online: 'Online',
  auto_pay: 'AutoPay',
  write_off: 'Write-off',
  refund: 'Refund',
  wire: 'Wire',
  other: 'Other',
}

export const CHANNEL: Record<PaymentChannel, string> = {
  portal: 'Customer portal',
  mobile_app: 'Mobile app',
  agent_phone: 'By phone',
  ivr: 'IVR',
  walk_in: 'Walk-in',
  mail: 'Mail',
  auto_pay: 'AutoPay',
  batch_file: 'Batch file',
  api: 'API',
  lockbox: 'Lockbox',
}

/** What a customer, account and invoice look like to the payment pages. */
export type CustomerRef = {
  id: string
  name: string
  number: string
  street: string | null
  cityLine: string | null
}
export type InvoiceRef = { id: string; number: string; customerId: string }

export const cents = (v: string | number) => Math.round(Number(v) * 100)
export const fromCents = (c: number) => (c / 100).toFixed(2)
