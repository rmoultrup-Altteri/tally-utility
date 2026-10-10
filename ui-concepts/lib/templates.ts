import { tenant, cycle } from '@/fixtures/tenant'
import { customerById, locationById, serviceLinks } from '@/fixtures/accounts'
import { customerName } from '@/schemas/models'
import type { Channel, ChannelContent, Lang, RequiredBlock, Template } from '@/fixtures/templates'
import { REASON, REASON_SHORT, billFor, explain, monthName } from '@/lib/bill-explain'

/**
 * Merge fields, rendering and the checks a template must pass before it is
 * saved — shared by the editor, the outreach board and the assistant, so a
 * template that previews cleanly is the template that sends.
 */

export type MergeField = { key: string; group: string; label: string; sample: string }

/** Every field a template may use. A field not on this list is refused, not silently left blank. */
export const MERGE_FIELDS: MergeField[] = [
  { key: 'utility.name', group: 'Utility', label: 'Utility name', sample: tenant.name },
  { key: 'utility.phone', group: 'Utility', label: 'Customer service phone', sample: tenant.phone },
  { key: 'utility.emergency_phone', group: 'Utility', label: 'Gas emergency line', sample: tenant.emergencyPhone },
  { key: 'utility.portal_url', group: 'Utility', label: 'Customer portal', sample: tenant.portalUrl },
  { key: 'customer.first_name', group: 'Customer', label: 'First name', sample: 'Marisol' },
  { key: 'customer.name', group: 'Customer', label: 'Full name', sample: 'Marisol Herrera' },
  { key: 'account.number', group: 'Customer', label: 'Account number', sample: '100-248193' },
  { key: 'account.balance', group: 'Customer', label: 'Account balance', sample: '$318.44' },
  { key: 'service.address', group: 'Customer', label: 'Service address', sample: '1418 Ashburn St, Bryan' },
  { key: 'bill.number', group: 'Bill', label: 'Bill number', sample: 'INV-2026-02-004182' },
  { key: 'bill.period', group: 'Bill', label: 'Bill period', sample: 'February' },
  { key: 'bill.amount_due', group: 'Bill', label: 'Amount due, with any balance', sample: '$257.89' },
  { key: 'bill.current_charges', group: 'Bill', label: 'This period’s charges', sample: '$165.46' },
  { key: 'bill.due_date', group: 'Bill', label: 'Due date', sample: 'March 9, 2026' },
  { key: 'bill.change_amount', group: 'Bill', label: 'Change from the comparison bill', sample: '$48.34' },
  { key: 'bill.compare_label', group: 'Bill', label: 'What it is compared with', sample: 'last February' },
  { key: 'bill.main_reason', group: 'Bill', label: 'Main reason, as a sentence', sample: 'Most of the difference is colder weather — your heating ran more.' },
  { key: 'bill.main_reason_short', group: 'Bill', label: 'Main reason, a few words', sample: 'colder weather' },
  { key: 'bill.explain_link', group: 'Bill', label: 'Link to the bill explanation', sample: `${tenant.portalUrl}/b/4182` },
  { key: 'balance.past_due', group: 'Collections', label: 'Past-due amount', sample: '$92.43' },
  { key: 'fee.amount', group: 'Collections', label: 'Late fee', sample: '$4.62' },
  { key: 'notice.disconnect_date', group: 'Collections', label: 'Disconnect on or after', sample: 'March 2, 2026' },
  { key: 'notice.pay_by', group: 'Collections', label: 'Pay by', sample: 'February 27, 2026' },
  { key: 'payment.amount', group: 'Payments', label: 'Payment amount', sample: '$165.46' },
  { key: 'payment.date', group: 'Payments', label: 'Payment date', sample: 'February 10, 2026' },
  { key: 'arrangement.installments', group: 'Payments', label: 'Installments', sample: '4' },
  { key: 'arrangement.amount', group: 'Payments', label: 'Installment amount', sample: '$23.11' },
  { key: 'arrangement.first_date', group: 'Payments', label: 'First installment', sample: 'March 9, 2026' },
  { key: 'budget.monthly', group: 'Payments', label: 'Budget billing amount', sample: '$71.00' },
  { key: 'deposit.amount', group: 'Service', label: 'Deposit', sample: '$150.00' },
  { key: 'appointment.date', group: 'Service', label: 'Appointment date', sample: 'February 18, 2026' },
  { key: 'appointment.window', group: 'Service', label: 'Appointment window', sample: '8 a.m.–12 p.m.' },
  { key: 'service_order.number', group: 'Service', label: 'Service order number', sample: 'SO-26-01184' },
  { key: 'rate.effective_date', group: 'Rates', label: 'New rates effective', sample: 'April 1, 2026' },
  { key: 'rate.typical_change', group: 'Rates', label: 'Typical residential change', sample: '$3.71' },
  { key: 'rate.docket', group: 'Rates', label: 'Docket', sample: 'RRC GUD-11042' },
  { key: 'pga.rate', group: 'Rates', label: 'Current gas cost', sample: '$0.4385' },
]

export const MERGE_GROUPS = [...new Set(MERGE_FIELDS.map((f) => f.group))]

const FIELD = new Map(MERGE_FIELDS.map((f) => [f.key, f]))
const SAMPLES: MergeContext = Object.fromEntries(MERGE_FIELDS.map((f) => [f.key, f.sample]))
const TOKEN = /\{\{\s*([a-z_]+\.[a-z_]+)\s*\}\}/g

export type MergeContext = Record<string, string>

/* ---- Context from a real account ------------------------------------- */

const MONTHS_ES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre']

export function longDate(iso: string, lang: Lang): string {
  const [y, m, d] = iso.slice(0, 10).split('-').map(Number)
  if (lang === 'es') return `${d} de ${MONTHS_ES[m - 1]} de ${y}`
  return new Date(Date.UTC(y, m - 1, d)).toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric', timeZone: 'UTC' })
}

const usd = (v: string | number) =>
  `$${Math.abs(Number(v)).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

/**
 * The merge values for one account, from its own records: the bill in the
 * live cycle, compared with the same month last year by the same engine the
 * bill explanation uses. Fields the account has no record for keep the
 * catalog's sample, so a preview never shows a hole.
 */
export function contextFor(customerId: string, lang: Lang, overrides: MergeContext = {}): MergeContext {
  const ctx: MergeContext = Object.fromEntries(MERGE_FIELDS.map((f) => [f.key, f.sample]))
  ctx['bill.period'] = lang === 'es' ? 'febrero' : 'February'
  ctx['bill.compare_label'] = lang === 'es' ? 'febrero del año pasado' : 'last February'
  ctx['bill.main_reason_short'] = REASON_SHORT[lang].weather
  for (const [k, iso] of Object.entries(SAMPLE_DATES)) ctx[k] = longDate(iso, lang)

  const c = customerById.get(customerId)
  if (c) {
    const link = serviceLinks.find((l) => l.customerId === c.id)
    const loc = link ? locationById.get(link.locationId) : undefined
    ctx['customer.name'] = customerName(c)
    ctx['customer.first_name'] = c.first_name ?? customerName(c)
    ctx['account.number'] = c.customer_number
    ctx['account.balance'] = usd(c.balance)
    ctx['balance.past_due'] = usd(c.balance)
    ctx['deposit.amount'] = usd(Number(c.deposit_amount) || 150)
    if (loc) ctx['service.address'] = `${loc.address}, ${loc.city}`

    const bill = billFor(c.id, `${cycle.periodLabel}`)
    if (bill) {
      ctx['bill.number'] = bill.invoice_number
      ctx['bill.period'] = monthName(bill.billing_period, lang)
      ctx['bill.amount_due'] = usd(bill.amount_due)
      ctx['bill.current_charges'] = usd(Number(bill.total_charges) + Number(bill.total_taxes))
      ctx['bill.due_date'] = longDate(bill.due_date, lang)
      ctx['bill.explain_link'] = `${tenant.portalUrl}/b/${bill.invoice_number.slice(-4)}`
      const e = explain(bill, 'year')
      if (e) {
        const priorMonth = monthName(e.prior.billing_period, lang)
        ctx['bill.compare_label'] = lang === 'es' ? `${priorMonth} del año pasado` : `last ${priorMonth}`
        ctx['bill.change_amount'] = usd(Math.abs(e.delta) / 100)
        ctx['bill.main_reason'] = REASON[lang][e.verdict]
        ctx['bill.main_reason_short'] = REASON_SHORT[lang][e.verdict]
      }
    }
  }
  return { ...ctx, ...overrides }
}

/** Sample dates as plain dates, so each language formats them its own way. */
const SAMPLE_DATES: Record<string, string> = {
  'bill.due_date': '2026-03-09',
  'notice.disconnect_date': '2026-03-02',
  'notice.pay_by': '2026-02-27',
  'payment.date': '2026-02-10',
  'arrangement.first_date': '2026-03-09',
  'appointment.date': '2026-02-18',
  'rate.effective_date': '2026-04-01',
}

/* ---- Rendering --------------------------------------------------------- */

export type Segment =
  | { kind: 'text'; text: string }
  | { kind: 'field'; key: string; value: string; known: boolean }
  | { kind: 'required'; block: RequiredBlock; text: string }

export function fill(text: string, ctx: MergeContext): string {
  return text.replace(TOKEN, (_, k: string) => ctx[k] ?? `{{${k}}}`)
}

/** Split text into literal runs, merge fields and required blocks, for a preview that shows which is which. */
export function segments(text: string, ctx: MergeContext, template: Template, lang: Lang): Segment[] {
  const out: Segment[] = []
  let last = 0
  for (const m of text.matchAll(TOKEN)) {
    if (m.index! > last) out.push({ kind: 'text', text: text.slice(last, m.index) })
    const key = m[1]
    if (key.startsWith('required.')) {
      const block = template.required?.find((b) => `required.${b.key}` === key)
      if (block) out.push({ kind: 'required', block, text: fill(block.text[lang] ?? block.text.en, ctx) })
      else out.push({ kind: 'field', key, value: `{{${key}}}`, known: false })
    } else {
      out.push({ kind: 'field', key, value: ctx[key] ?? `{{${key}}}`, known: FIELD.has(key) })
    }
    last = m.index! + m[0].length
  }
  if (last < text.length) out.push({ kind: 'text', text: text.slice(last) })
  return out
}

export function renderPlain(text: string, ctx: MergeContext, template: Template, lang: Lang): string {
  return segments(text, ctx, template, lang)
    .map((s) => (s.kind === 'text' ? s.text : s.kind === 'field' ? s.value : s.text))
    .join('')
}

/* ---- Text messages ----------------------------------------------------- */

export const SMS_OPT_OUT: Record<Lang, string> = {
  en: 'Reply STOP to opt out.',
  es: 'Responda STOP para cancelar.',
}

const GSM =
  '@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !"#¤%&\'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà'
const GSM_EXT = '^{}\\[~]|€'

export type SmsShape = { length: number; segments: number; unicode: boolean; culprit: string | null; text: string }

/**
 * How a text message will actually travel. One accented character outside
 * the GSM alphabet drops every segment from 160 characters to 70, which
 * doubles what the utility pays per message — so the editor names the
 * character rather than just the count.
 */
export function smsShape(body: string, lang: Lang): SmsShape {
  const text = `${body.trim()} ${SMS_OPT_OUT[lang]}`
  let length = 0
  let culprit: string | null = null
  for (const ch of text) {
    if (GSM.includes(ch)) length += 1
    else if (GSM_EXT.includes(ch)) length += 2
    else {
      culprit ??= ch
      length += 1
    }
  }
  const unicode = culprit !== null
  const len = unicode ? [...text].length : length
  const segments = unicode ? (len <= 70 ? 1 : Math.ceil(len / 67)) : len <= 160 ? 1 : Math.ceil(len / 153)
  return { length: len, segments, unicode, culprit, text }
}

/* ---- Checks ------------------------------------------------------------ */

export type ContentIssue = { level: 'error' | 'warning'; text: string }

/**
 * What a template must satisfy to be saved, from the editor or the assistant
 * alike. Required text cannot be removed; an unknown merge field cannot be
 * sent; a subject is required where the channel has one.
 */
export function checkContent(template: Template, channel: Channel, lang: Lang, c: ChannelContent): ContentIssue[] {
  const issues: ContentIssue[] = []
  if (!c.body.trim()) issues.push({ level: 'error', text: 'The message is empty.' })
  if (channel !== 'sms' && !c.subject?.trim())
    issues.push({ level: 'error', text: channel === 'email' ? 'An email needs a subject line.' : 'A letter needs a heading.' })

  const all = `${c.subject ?? ''}\n${c.body}`
  for (const m of all.matchAll(TOKEN)) {
    const key = m[1]
    if (key.startsWith('required.')) {
      if (!template.required?.some((b) => `required.${b.key}` === key))
        issues.push({ level: 'error', text: `{{${key}}} is not required text on this template.` })
    } else if (!FIELD.has(key)) {
      issues.push({ level: 'error', text: `{{${key}}} is not a merge field. Pick one from the list.` })
    }
  }
  for (const b of template.required ?? []) {
    if (channel === 'sms') continue
    if (!c.body.includes(`{{required.${b.key}}}`))
      issues.push({ level: 'error', text: `${b.label} (${b.citation}) must stay in this ${channel === 'letter' ? 'letter' : 'message'}.` })
  }
  if (/\{\{(?![^}]*\}\})/.test(all) || /(?<!\{)\{(?!\{)[^}]*\}\}/.test(all))
    issues.push({ level: 'error', text: 'A merge field is missing a brace.' })

  if (channel === 'sms') {
    /* Measured with sample values in the fields, which is closer to what sends than the raw tokens. */
    const shape = smsShape(fill(c.body, SAMPLES), lang)
    if (shape.segments > 3) issues.push({ level: 'error', text: `This text would send as ${shape.segments} messages. Keep it to three or fewer.` })
    else if (shape.segments > 1)
      issues.push({
        level: 'warning',
        text: `Sends as ${shape.segments} messages${shape.unicode ? ` — “${shape.culprit}” forces Unicode, which cuts each message to 70 characters` : ''}.`,
      })
    if (/stop to/i.test(c.body)) issues.push({ level: 'warning', text: 'The opt-out line is added automatically — you do not need to write it.' })
  }
  return issues
}

export const fieldByKey = FIELD
