import { rateSchedules } from '@/fixtures/rates'
import { exceptions } from '@/fixtures/exceptions'
import { pipeline, worklist } from '@/fixtures/collections'
import { arAging, currentRun, revenue } from '@/fixtures/billing'
import { asOf, cycle } from '@/fixtures/tenant'
import { customerName } from '@/schemas/models'
import { date, money, rateInUnit } from '@/lib/format'
import type { StreamEvent } from './protocol'
import { getAccount, getInvoice, listRates, queryRecords, searchTenant, type TenantView } from './tenant-data'

/**
 * The assistant without a model: plain questions about the stored records,
 * answered by pattern from the same read-only tools the model calls.
 *
 * The route falls back to this when there are no Anthropic credentials (or
 * when ASSISTANT_MODE=local), so the chat works on a laptop with no key. It
 * recognises a handful of question shapes — balances over an amount, rates on
 * a schedule, the PGA, an account or bill, counts, exceptions, collections,
 * the run — and says plainly what it cannot do: the web, imports and
 * template drafting need the model.
 */

type Send = (e: StreamEvent) => void

const SETUP = 'Set `ANTHROPIC_API_KEY` in `ui-concepts/.env.local` and restart `pnpm dev` to turn on the full assistant.'

const CLOSED = new Set(['resolved', 'false_positive'])

const humanize = (s: string) => s.replace(/_/g, ' ')

/** "$1,000", "1000", "1.5k", "$2,500.50" → a number. */
function amountIn(text: string): number | null {
  const m = text.match(/\$\s*([\d,]+(?:\.\d+)?)\s*(k)?\b|\b([\d,]+(?:\.\d+)?)\s*(k)?\s*(?:dollars|bucks)?\b/i)
  if (!m) return null
  const raw = (m[1] ?? m[3]).replace(/,/g, '')
  const n = Number(raw) * (m[2] || m[4] ? 1000 : 1)
  return Number.isFinite(n) ? n : null
}

/** "less than", "under", "below" flip the comparison; everything else reads as "more than". */
const BELOW = /\b(less than|under|below|at most|no more than)\b|</i

function scheduleIn(text: string) {
  const m = text.match(/\b([a-z]{1,3})\s*-?\s*(\d{1,2})\b/i)
  if (!m) return null
  const code = `${m[1].toUpperCase()}-${m[2]}`
  return rateSchedules.find((s) => s.code === code) ?? null
}

/* ---- Answers --------------------------------------------------------- */

function balances(view: TenantView, text: string, send: Send): string {
  const threshold = amountIn(text)
  const below = threshold !== null && BELOW.test(text)
  send({ type: 'activity', kind: 'tenant', label: 'Querying customers' })
  const rows = view.customers
    .filter((c) => {
      const b = Number(c.balance)
      if (threshold === null) return b > 0
      return below ? b < threshold : b > threshold
    })
    .sort((a, b) => Number(b.balance) - Number(a.balance))
  /* The collections worklist carries accounts the prototype does not model in full. */
  const extra = worklist
    .filter((w) => !w.customerId && (threshold === null ? Number(w.balance) > 0 : below ? Number(w.balance) < threshold : Number(w.balance) > threshold))
    .sort((a, b) => Number(b.balance) - Number(a.balance))

  const what = threshold === null ? 'with a balance' : `${below ? 'owing less than' : 'owing more than'} ${money(threshold)}`
  if (!rows.length && !extra.length) return `No accounts ${what}.`

  const out: string[] = []
  const total = rows.length + extra.length
  out.push(`**${total} account${total === 1 ? '' : 's'}** ${what}${threshold === null ? ', largest first' : ''}:`)
  out.push('')
  out.push('| Account | Number | Balance | Status |')
  out.push('|---|---|---|---|')
  for (const c of rows.slice(0, 25))
    out.push(`| [${customerName(c)}](/customers/${c.id}) | ${c.customer_number} | ${money(c.balance)} | ${humanize(c.status)} |`)
  for (const w of extra.slice(0, 25))
    out.push(`| [${w.name}](/collections) | ${w.accountNumber} | ${money(w.balance)} | collections · ${w.pastDueDays} days past due |`)
  const sum = queryRecords(view, {
    entity: 'customers',
    where: threshold === null ? { balance: '>0' } : { balance: `${below ? '<' : '>'}${threshold}` },
    sum: 'balance',
    limit: 1,
  })
  if ('sum' in sum && sum.sum && rows.length > 1) out.push('', `Modelled accounts total ${money(sum.sum.value)}.`)
  if (extra.length) out.push('', 'Accounts linked to Collections are on the worklist but not modelled as full customer records.')
  return out.join('\n')
}

function rates(view: TenantView, text: string, send: Send): string {
  const s = scheduleIn(text)
  if (!s) {
    return [
      `There are ${rateSchedules.length} rate schedules. Ask about one by code for the rates in force:`,
      '',
      ...rateSchedules.map((r) => `- **${r.code}** ${r.name}`),
    ].join('\n')
  }
  send({ type: 'activity', kind: 'tenant', label: `Reading rates on ${s.code}` })
  const r = listRates(view, s.code)
  if ('error' in r) return String(r.error)
  const sched = r.schedules[0]
  const out = [
    `**${sched.code} ${sched.name}** — in force on ${date(r.valid_at)} (tariff ${sched.tariff_number}, minimum bill ${money(sched.minimum_bill_amount ?? '0')}):`,
    '',
    '| Item | Rate | Effective |',
    '|---|---|---|',
  ]
  const later: string[] = []
  for (const i of sched.items) {
    if (!i.in_force) {
      out.push(`| ${i.item_name} | none in force | — |`)
    } else {
      out.push(`| ${i.item_name} | ${`${rateInUnit(i.in_force.rate, i.rate_unit)} ${unitLabel(i.rate_unit)}`.trim()} | ${date(i.in_force.effective_from)} |`)
    }
    for (const v of i.scheduled) later.push(`- ${i.item_name}: ${rateInUnit(v.rate, i.rate_unit)} from ${date(v.effective_from)}${v.change_reason ? ` — ${v.change_reason}` : ''}`)
  }
  if (later.length) out.push('', 'Scheduled:', ...later)
  out.push('', `See [Rates & tariffs](/rates).`)
  return out.join('\n')
}

function unitLabel(unit: string | null | undefined): string {
  switch (unit) {
    case 'per_therm':
      return '/ therm'
    case 'per_month':
      return '/ month'
    case 'percent':
      return ''
    default:
      return unit ? `/ ${humanize(unit).replace(/^per /, '')}` : ''
  }
}

function pga(view: TenantView, text: string, send: Send): string {
  send({ type: 'activity', kind: 'tenant', label: 'Reading rates on the PGA' })
  const r = listRates(view)
  if ('error' in r) return String(r.error)
  const item = r.schedules.flatMap((s) => s.items).find((i) => i.item_code === 'PGA-GAS')
  const out: string[] = []
  if (!item?.in_force) {
    out.push(`No purchased gas adjustment is in force on ${date(r.valid_at)}.`)
  } else {
    out.push(
      `We are billing a PGA of **${rateInUnit(item.in_force.rate, item.rate_unit)} per therm** for ${cycle.periodLabel}, effective ${date(item.in_force.effective_from)}${item.in_force.effective_to ? ` through ${date(item.in_force.effective_to)}` : ''}.`,
    )
    if (item.in_force.regulatory_reference) out.push(`Filed under ${item.in_force.regulatory_reference}.`)
    for (const v of item.scheduled) out.push(`Next: ${rateInUnit(v.rate, item.rate_unit)} from ${date(v.effective_from)}.`)
    out.push(`See the [PGA console](/rates/pga) for every factor on both time axes.`)
  }
  if (/henry hub|nymex|spot|market price|index price/i.test(text))
    out.push(
      '',
      `Henry Hub is a live market price, and it isn't in the stored records. Looking it up needs the web, which the offline assistant can't reach. ${SETUP}`,
    )
  return out.join('\n')
}

function account(view: TenantView, ref: string, send: Send): string {
  send({ type: 'activity', kind: 'tenant', label: `Reading account ${ref}` })
  const a = getAccount(view, ref)
  if ('error' in a) return String(a.error)
  const c = a.customer
  const out = [
    `**[${a.display_name}](${a.portal_link})** · ${c.customer_number} · ${humanize(c.customer_type)} · ${humanize(c.status)}`,
    '',
    `- Balance: **${money(c.balance)}**${c.billing_hold ? ` · billing hold (${c.billing_hold_reason})` : ''}`,
  ]
  for (const p of a.premises) {
    if (p.location) out.push(`- Service: ${p.location.address}, ${p.location.city}${p.meter ? ` · meter ${p.meter.meter_number}` : ''}`)
    if (p.latest_reading)
      out.push(`- Latest read: ${date(p.latest_reading.reading_date)}, ${p.latest_reading.consumption} ${p.latest_reading.consumption_unit}${p.latest_reading.is_estimated ? ' (estimated)' : ''}`)
  }
  const last = a.invoices[0]
  if (last) out.push(`- Latest bill: [${last.invoice_number}](/invoices/${last.id}) · ${last.billing_period} · ${money(last.amount_due)} · ${last.status}`)
  if (a.payments[0]) out.push(`- Last payment: ${money(a.payments[0].amount)} on ${date(a.payments[0].payment_date)} (${humanize(a.payments[0].method)})`)
  if (a.open_exceptions.length) out.push(`- Open exceptions: ${a.open_exceptions.map((e) => `${e.severity} — ${e.description}`).join('; ')}`)
  if (a.collections) out.push(`- On the collections worklist: ${a.collections.pastDueDays} days past due, ${humanize(a.collections.stage)}`)
  return out.join('\n')
}

function invoice(view: TenantView, ref: string, send: Send): string {
  send({ type: 'activity', kind: 'tenant', label: `Reading bill ${ref}` })
  const r = getInvoice(view, ref, true)
  if ('error' in r) return String(r.error)
  const i = r.invoice
  const c = view.customers.find((x) => x.id === i.customer_id)
  const out = [
    `**[${i.invoice_number}](${r.portal_link})** · ${c ? `[${customerName(c)}](/customers/${c.id})` : i.customer_id} · ${i.billing_period} · ${i.status}`,
    '',
    `Amount due **${money(i.amount_due)}**, paid ${money(i.amount_paid)}, balance ${money(i.balance)}. Dated ${date(i.invoice_date)}, due ${date(i.due_date)}.`,
  ]
  if (r.lines?.length) {
    out.push('', '| Line | Amount |', '|---|---|')
    for (const l of r.lines) out.push(`| ${l.description} | ${money(l.amount)} |`)
  }
  out.push('', `[Why this bill changed](/invoices/${i.id}/explain)`)
  return out.join('\n')
}

function who(view: TenantView, id: string | null): string {
  const c = id ? view.customers.find((x) => x.id === id) : undefined
  return c ? `[${customerName(c)}](/customers/${c.id})` : (id ?? '—')
}

function openExceptions(view: TenantView, send: Send): string {
  send({ type: 'activity', kind: 'tenant', label: 'Querying exceptions' })
  const open = exceptions.filter((e) => !CLOSED.has(e.status))
  const order = ['critical', 'high', 'medium', 'low']
  const counts = order.map((s) => `${open.filter((e) => e.severity === s).length} ${s}`).join(', ')
  const out = [
    `**${open.length} open exceptions** (${counts}); ${open.filter((e) => e.blocks_delivery).length} block delivery.`,
    '',
    '| Severity | What | Account |',
    '|---|---|---|',
  ]
  for (const e of [...open].sort((a, b) => order.indexOf(a.severity) - order.indexOf(b.severity)).slice(0, 10))
    out.push(`| ${e.severity} | ${e.description} | ${who(view, e.customer_id)} |`)
  out.push('', 'Work them from the [Exceptions](/) queue.')
  return out.join('\n')
}

function collections(send: Send): string {
  send({ type: 'activity', kind: 'tenant', label: 'Querying collections worklist' })
  const out = [
    `**${pipeline.total} accounts** in the collections pipeline; ${pipeline.noticesDueToday} notices due today, ${pipeline.eligibleWhenHoldLifts} eligible when the hold lifts.`,
    '',
    '| Account | Balance | Past due | Stage |',
    '|---|---|---|---|',
  ]
  for (const w of [...worklist].sort((a, b) => b.pastDueDays - a.pastDueDays).slice(0, 12))
    out.push(`| ${w.customerId ? `[${w.name}](/customers/${w.customerId})` : w.name} | ${money(w.balance)} | ${w.pastDueDays} days | ${humanize(w.stage)} |`)
  out.push('', 'See [Collections](/collections).')
  return out.join('\n')
}

function overview(text: string, send: Send): string {
  send({ type: 'activity', kind: 'tenant', label: 'Reading the billing overview' })
  const out: string[] = []
  if (/\b(run|cycle|bills?)\b/i.test(text) || !/revenue|collected|aging|receivable|\bar\b/i.test(text))
    out.push(
      `**${currentRun.run_number}** (${currentRun.billing_period}, ${date(currentRun.period_start)} → ${date(currentRun.period_end)}) is in **${currentRun.status}**: ${currentRun.total_invoices.toLocaleString('en-US')} bills for ${currentRun.total_locations.toLocaleString('en-US')} premises, ${money(currentRun.total_amount)}, ${currentRun.total_exceptions} exceptions, ${currentRun.total_estimated_reads} estimated reads. [Open the run](/runs/${currentRun.id}).`,
    )
  const aging = /aging|aged|receivable|\bar\b|past due|overdue/i.test(text)
  if (/revenue|collected|billed/i.test(text) || (!out.length && !aging))
    out.push(`${revenue.windowLabel}: billed ${money(revenue.billedNetOfVoids)} (prior month ${money(revenue.billedPriorMonthSameDay)}), collected ${money(revenue.collected)} (prior month ${money(revenue.collectedPriorMonthSameDay)}).`)
  if (aging) {
    if (!out.length) out.push(`Receivables aged by invoice, as of ${date(asOf.validAt)}:`)
    out.push('', '| Bucket | Amount | Accounts |', '|---|---|---|')
    for (const b of arAging) out.push(`| ${b.bucket} | ${money(b.amount)} | ${b.accounts.toLocaleString('en-US')} |`)
  }
  return out.join('\n')
}

const COUNTABLE: [RegExp, Parameters<typeof queryRecords>[1]['entity'], [string, string]][] = [
  [/\b(accounts?|customers?)\b/i, 'customers', ['account', 'accounts']],
  [/\bmeters?\b/i, 'meters', ['meter', 'meters']],
  [/\b(bills?|invoices?)\b/i, 'invoices', ['bill', 'bills']],
  [/\bpayments?\b/i, 'payments', ['payment', 'payments']],
  [/\b(reads?|readings?)\b/i, 'readings', ['read', 'reads']],
  [/\b(premises|locations?|addresses)\b/i, 'locations', ['service address', 'service addresses']],
]

const TYPES = ['residential', 'small_commercial', 'large_commercial', 'commercial', 'industrial', 'government', 'wholesale']

function count(view: TenantView, text: string, send: Send): string | null {
  const hit = COUNTABLE.find(([re]) => re.test(text))
  if (!hit) return null
  const [, entity, [one, many]] = hit
  const where: Record<string, string> = {}
  const lower = text.toLowerCase()
  if (entity === 'customers') {
    const t = TYPES.find((x) => lower.includes(x.replace('_', ' ')))
    if (t) where.customer_type = t === 'commercial' ? '~commercial' : t
    for (const s of ['active', 'inactive', 'collections', 'closed', 'deceased']) if (new RegExp(`\\b${s}\\b`).test(lower)) where.status = s
  }
  if (entity === 'invoices') {
    for (const s of ['draft', 'held', 'sent', 'paid', 'overdue', 'void', 'partial']) if (new RegExp(`\\b${s}\\b`).test(lower)) where.status = s
    if (/\bunpaid\b/.test(lower)) where.balance = '>0'
  }
  if (entity === 'readings' && /\bestimated?\b/.test(lower)) where.is_estimated = 'true'
  send({ type: 'activity', kind: 'tenant', label: `Querying ${many}` })
  const r = queryRecords(view, { entity, where, limit: 1 })
  if ('error' in r) return String(r.error)
  const filters = Object.entries(where).map(([k, v]) =>
    k === 'is_estimated' ? 'the read is estimated' : `${humanize(k)} ${String(v).replace(/^~/, 'includes ').replace(/^>/, 'over ')}`,
  )
  return `**${r.total_matching} ${r.total_matching === 1 ? one : many}**${filters.length ? ` where ${filters.join(' and ')}` : ''} in the records this prototype models.${entity === 'customers' || entity === 'meters' ? ` (The system serves far more; these are the accounts modelled in full.)` : ''}`
}

function search(view: TenantView, text: string, send: Send): string | null {
  const q = text
    .replace(/[?.!,]/g, ' ')
    .replace(/\b(who|what|where|is|are|the|a|an|for|of|me|show|find|look|up|lookup|account|customer|tell|about|on|please|can|you|get|pull)\b/gi, ' ')
    .replace(/\s+/g, ' ')
    .trim()
  if (!q || q.length < 3) return null
  send({ type: 'activity', kind: 'tenant', label: `Searching the account for “${q}”` })
  const r = searchTenant(view, q, 8)
  if (!r.total) return null
  const only = r.hits.length === 1 ? r.hits[0] : null
  if (only?.kind === 'customer') return account(view, only.id, send)
  if (only?.kind === 'invoice') return invoice(view, only.id, send)
  return [
    `${r.total} match${r.total === 1 ? '' : 'es'} for “${q}”:`,
    '',
    ...r.hits.map((h) => `- ${h.kind === 'customer' ? `[${h.label}](/customers/${h.id})` : h.kind === 'invoice' ? `[${h.label}](/invoices/${h.id})` : h.label} — ${h.kind} · ${h.detail}`),
  ].join('\n')
}

function help(): string {
  return [
    "I'm answering offline, from the records stored in this prototype, so I can only handle certain kinds of question. Try one of these:",
    '',
    '- Which accounts owe more than $1,000?',
    '- What rates are in force on R-1?',
    '- What PGA are we billing?',
    '- Show account 100-248193, or a customer name',
    '- Show bill INV-2026-02-004182',
    '- How many residential accounts are there?',
    '- What exceptions are open?',
    '- Who is in collections?',
    '- Where is the billing run? How is AR aging?',
    '',
    SETUP,
  ].join('\n')
}

/* ---- The turn -------------------------------------------------------- */

export function answerLocally(
  view: TenantView,
  message: { text: string; pathname: string; attachments: string[] },
  send: Send,
): string {
  const text = message.text.trim()
  send({ type: 'activity', kind: 'tenant', label: 'Answering offline from stored records' })

  if (message.attachments.length || /\bimport\b/i.test(text))
    return `Imports need the full assistant to map the file's columns to fields. ${SETUP}`
  if (/\b(template|letter|email|sms|text message|spanish)\b/i.test(text) && /\b(write|draft|edit|make|shorter|warmer|translate|check)\b/i.test(text))
    return `Drafting and editing templates needs the full assistant. ${SETUP}`

  /* Explicit references first: a bill number or an account number. */
  const inv = text.match(/\bINV-[\d-]+\b/i)
  if (inv) return invoice(view, inv[0].toUpperCase(), send)
  const acct = text.match(/\b\d{3}-\d{6}\b/)
  if (acct && !/\$/.test(text)) return account(view, acct[0], send)
  /* "this account" / "this bill" resolve from the page the operator is on. */
  if (/\bthis (account|customer)\b/i.test(text)) {
    const m = message.pathname.match(/^\/customers\/([^/]+)/)
    if (m) return account(view, m[1], send)
  }
  if (/\bthis (bill|invoice)\b/i.test(text)) {
    const m = message.pathname.match(/^\/invoices\/([^/]+)/)
    if (m) return invoice(view, m[1], send)
  }

  if (/\b(pga|purchased gas|gas cost|henry hub|nymex)\b/i.test(text)) return pga(view, text, send)
  if (/\b(rates?|tariffs?|charges?|schedules?)\b/i.test(text) && !/\b(owe|balance)\b/i.test(text)) return rates(view, text, send)
  if (/\b(owe|owes|owing|balance|balances|biggest debt)\b/i.test(text)) return balances(view, text, send)
  if (/\bexceptions?\b/i.test(text)) return openExceptions(view, send)
  if (/\b(collections?|disconnect|dunning|worklist)\b/i.test(text)) return collections(send)
  if (/\b(how many|count|number of|total number)\b/i.test(text)) {
    const c = count(view, text, send)
    if (c) return c
  }
  if (/\b(billing run|run|revenue|collected|aging|aged|receivables?|ar)\b/i.test(text)) return overview(text, send)

  return search(view, text, send) ?? help()
}

/**
 * True when the route should answer offline without trying the model at all.
 * Otherwise the route tries the model and falls back here only when it finds
 * no credentials, so an `ant auth login` profile still works without a key.
 */
export function localOnly(): boolean {
  return process.env.ASSISTANT_MODE === 'local'
}
