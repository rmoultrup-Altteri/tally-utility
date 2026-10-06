import type { Exception } from '@/schemas/models'

/**
 * Named views, and the favorites that point at them (T8-2).
 *
 * The ruling is narrow on purpose: favorites cover reports, record lists and
 * saved searches ONLY. An individual customer, meter, location or invoice is
 * not favoritable, and there is no recents list. The reasoning is lifespan —
 * a report stays useful for years, a customer record for the length of one
 * call — so record-level starring accumulates entries nobody grooms and the
 * feature dies of noise.
 *
 * That exclusion is enforced here by SHAPE rather than by convention. There is
 * no `entity_type` / `entity_id` pair anywhere in this file. A polymorphic
 * favorite would reopen record-level the first time someone wrote a row with
 * `entity_type = 'customer'`, and no code review catches that reliably; a
 * target union with no slot for a record id catches it at compile time.
 *
 * T8-2 also collapses "saved search" and "saved filtered view" into one
 * concept, which given T8-1 they are: filtering lives on record-list pages as
 * column filters, so a saved search IS a list plus its filter state. There is
 * one `named_view` here, not two objects.
 */

/** Every record list a favorite may point at. */
export const LISTS = {
  exceptions: { label: 'Pre-mail exceptions', href: '/' },
  reads: { label: 'Read validation', href: '/reads' },
  collections: { label: 'Collections worklist', href: '/collections' },
} as const

export type ListKey = keyof typeof LISTS

/**
 * Reports are favoritable under the ruling. The registry holds only the key
 * and label; the report bodies live in `fixtures/reports.ts`, typed against
 * these keys so a favorite can never point at a report that does not exist.
 */
export const REPORTS = {
  ar_aging: { label: 'AR aging' },
  payment_plans: { label: 'Payment plans and progress' },
  revenue_by_type: { label: 'Revenue by customer type' },
  cash_by_type_item: { label: 'Cash collected by customer type and item' },
  gl_journal: { label: 'General ledger journal entries' },
  read_exceptions: { label: 'Meter read exceptions' },
  zero_reads: { label: 'Zero reads' },
  high_low_reads: { label: 'High / low reads' },
  wna: { label: 'Degree-day weather normalization' },
  deposit_refunds: { label: 'Deposit refunds' },
  franchise_fees: { label: 'Municipal franchise fees' },
  state_gross_receipts: { label: 'State gross receipts and sales tax' },
  rrc_annual: { label: 'RRC annual report' },
  rrc_audit: { label: 'RRC gas utility tax audit' },
} as const
export type ReportKey = keyof typeof REPORTS

export const reportFavoriteId = (report: ReportKey) => `report:${report}`

/* ---- Exception queue filters ------------------------------------------ */

export const SEVERITIES = ['critical', 'high', 'medium', 'low'] as const
export const STATUSES = ['open', 'acknowledged', 'investigating', 'locked_gate', 'snoozed'] as const
export const ASSIGNEES = ['anyone', 'unassigned', 'me'] as const

export type Severity = (typeof SEVERITIES)[number]
export type Status = (typeof STATUSES)[number]
export type Assignee = (typeof ASSIGNEES)[number]

export type QueueFilters = {
  severity: Severity[]
  status: Status[]
  /** Undefined means "either"; true means delivery-blocking only. */
  blocking?: boolean
  assignee: Assignee
}

export const EMPTY_FILTERS: QueueFilters = { severity: [], status: [], assignee: 'anyone' }

export const isFiltered = (f: QueueFilters) =>
  f.severity.length > 0 || f.status.length > 0 || f.blocking !== undefined || f.assignee !== 'anyone'

/**
 * Filter state lives in the URL, so a view is a link — shareable, bookmarkable,
 * and survivable across a reload. That is also what makes a saved view storable
 * as data rather than as a snapshot of component state.
 */
export function parseFilters(params: Record<string, string | string[] | undefined>): QueueFilters {
  const one = (k: string) => {
    const v = params[k]
    return Array.isArray(v) ? v[0] : v
  }
  const list = <T extends string>(k: string, allowed: readonly T[]): T[] =>
    (one(k) ?? '')
      .split(',')
      .map((s) => s.trim())
      .filter((s): s is T => (allowed as readonly string[]).includes(s))

  const blocking = one('blocking')
  const assignee = one('assignee')
  return {
    severity: list('severity', SEVERITIES),
    status: list('status', STATUSES),
    blocking: blocking === '1' ? true : blocking === '0' ? false : undefined,
    assignee: (ASSIGNEES as readonly string[]).includes(assignee ?? '')
      ? (assignee as Assignee)
      : 'anyone',
  }
}

export function serializeFilters(f: QueueFilters): string {
  const p = new URLSearchParams()
  if (f.severity.length) p.set('severity', f.severity.join(','))
  if (f.status.length) p.set('status', f.status.join(','))
  if (f.blocking !== undefined) p.set('blocking', f.blocking ? '1' : '0')
  if (f.assignee !== 'anyone') p.set('assignee', f.assignee)
  const q = p.toString()
  return q ? `?${q}` : ''
}

export function applyFilters(rows: Exception[], f: QueueFilters, me: string): Exception[] {
  return rows.filter((e) => {
    if (f.severity.length && !f.severity.includes(e.severity as Severity)) return false
    if (f.status.length && !f.status.includes(e.status as Status)) return false
    if (f.blocking !== undefined && e.blocks_delivery !== f.blocking) return false
    if (f.assignee === 'unassigned' && e.assigned_to !== null) return false
    if (f.assignee === 'me' && e.assigned_to !== me) return false
    return true
  })
}

/** A one-line description of what a view is showing, for the favorites list. */
export function describeFilters(f: QueueFilters): string {
  const parts: string[] = []
  if (f.blocking === true) parts.push('blocking delivery')
  if (f.blocking === false) parts.push('not blocking')
  if (f.severity.length) parts.push(f.severity.join(' + '))
  if (f.status.length) parts.push(f.status.map((s) => s.replace(/_/g, ' ')).join(' + '))
  if (f.assignee === 'unassigned') parts.push('unassigned')
  if (f.assignee === 'me') parts.push('assigned to me')
  return parts.length ? parts.join(' · ') : 'no filters'
}

/* ---- Favorites --------------------------------------------------------- */

/**
 * The favorite union. Note what is absent: no entity id, no entity type, no
 * free-form target string. The three variants are the three grains the ruling
 * allows, and there is nowhere to put a customer.
 */
export type Favorite =
  | { id: string; kind: 'record_list'; list: ListKey }
  | { id: string; kind: 'named_view'; list: ListKey; name: string; filters: QueueFilters }
  | { id: string; kind: 'report'; report: ReportKey }

export function favoriteHref(f: Favorite): string {
  switch (f.kind) {
    case 'record_list':
      return LISTS[f.list].href
    case 'named_view':
      return `${LISTS[f.list].href}${serializeFilters(f.filters)}`
    case 'report':
      return `/reports/${f.report}`
  }
}

export function favoriteLabel(f: Favorite): string {
  switch (f.kind) {
    case 'record_list':
      return LISTS[f.list].label
    case 'named_view':
      return f.name
    case 'report':
      return REPORTS[f.report].label
  }
}

/** The hover text for a favorite — total over the union, so a new kind breaks the build. */
export function favoriteHint(f: Favorite): string {
  switch (f.kind) {
    case 'record_list':
      return LISTS[f.list].label
    case 'named_view':
      return `${LISTS[f.list].label} — ${describeFilters(f.filters)}`
    case 'report':
      return `Report — ${REPORTS[f.report].label}`
  }
}

/** Stable identity for a list favorite, so the star can toggle it. */
export const listFavoriteId = (list: ListKey) => `list:${list}`
