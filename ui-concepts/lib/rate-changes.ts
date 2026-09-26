import type { RateItemVersion } from '@/schemas/models'
import type { CalculationType, DisplayGroup, RateUnit } from '@/schemas/enums'
import { versionAsOf } from '@/fixtures/rates'
import { date, money, rateInUnit } from '@/lib/format'
import { rateUnitLabel } from '@/lib/vocabulary'

/**
 * Turning what an analyst typed into rate versions.
 *
 * Reference data is close-then-insert: a new rate never overwrites the old
 * one. It closes the standing version the day before the new one starts and
 * inserts a successor that cites it, with a change type and a reason. This
 * module holds that arithmetic so the editor only has to collect input.
 */

/** One billed item and every version of it the tenant has recorded. */
export type CatalogItem = {
  /** Stable key for the row — the item code, or a local key for an item not yet recorded. */
  key: string
  code: string
  name: string
  group: DisplayGroup
  calculation: CalculationType
  unit: RateUnit
  schedules: string[]
  versions: RateItemVersion[]
}

/** What an analyst typed against one row. The rate is in the unit the row displays: percent as percent. */
export type Draft = { rate: string; from: string; to: string }

export type Coordinate = { validAt: string; recordedAt: string }

export type Check = { level: 'error' | 'warning'; text: string }

export function addDays(isoDate: string, n: number): string {
  const d = new Date(`${isoDate}T00:00:00Z`)
  d.setUTCDate(d.getUTCDate() + n)
  return d.toISOString().slice(0, 10)
}

export function monthStart(isoDate: string, offset = 0): string {
  const [y, m] = isoDate.split('-').map(Number)
  return new Date(Date.UTC(y, m - 1 + offset, 1)).toISOString().slice(0, 10)
}

export function monthEnd(isoDate: string): string {
  const [y, m] = isoDate.split('-').map(Number)
  return new Date(Date.UTC(y, m, 0)).toISOString().slice(0, 10)
}

/** Scheduled versions a draft's span covers — those it withdraws when recorded. */
function overlapped(item: CatalogItem, draft: Draft, at: Coordinate): RateItemVersion[] {
  return scheduled(item, at).filter((v) => v.effective_from >= draft.from && (!draft.to || v.effective_from <= draft.to))
}

/** Live versions only — a withdrawn schedule stays on record but is not in force. */
const live = (item: CatalogItem) => item.versions.filter((v) => v.recorded_until === null)

export function standing(item: CatalogItem, at: Coordinate): RateItemVersion | null {
  return versionAsOf(item.versions, at.validAt, at.recordedAt)
}

/** Versions that start after the as-of date: recorded, but not yet pricing anything. */
export function scheduled(item: CatalogItem, at: Coordinate): RateItemVersion[] {
  return live(item)
    .filter((v) => v.effective_from > at.validAt)
    .sort((a, b) => a.effective_from.localeCompare(b.effective_from))
}

/** The rate as the analyst sees it: a franchise fee stored 0.04 is typed and shown as 4. */
export function toDisplay(stored: string, unit: RateUnit): string {
  const n = Number(stored)
  return unit === 'percent' ? String(Number((n * 100).toFixed(4))) : String(Number(n.toFixed(6)))
}

const DECIMAL = /^-?(\d+\.?\d*|\.\d+)$/

/** Parse typed input to the stored six-place decimal, or null if it is not a number. */
export function toStored(typed: string, unit: RateUnit): string | null {
  const t = typed.trim()
  if (!DECIMAL.test(t)) return null
  const places = (t.split('.')[1] ?? '').length
  if (places > (unit === 'percent' ? 4 : 6)) return null
  const n = Number(t) / (unit === 'percent' ? 100 : 1)
  return n.toFixed(6)
}

/**
 * A rate in its unit. A monthly or flat charge that is whole cents reads as
 * money ($48.00/month); anything finer keeps full precision, because rounding
 * a rate for tidiness is how disputes start.
 */
export function formatRate(stored: string, unit: RateUnit): string {
  const cents = (unit === 'per_month' || unit === 'flat' || unit === 'per_year') && Number.isInteger(Math.round(Number(stored) * 1e6) / 1e4)
  return `${cents ? money(stored) : rateInUnit(stored, unit)}${rateUnitLabel(unit)}`
}

/** Everything wrong with, or worth knowing about, one draft before it is recorded. */
export function checkDraft(item: CatalogItem, draft: Draft, at: Coordinate, isNew: boolean): Check[] {
  const checks: Check[] = []
  const stored = toStored(draft.rate, item.unit)
  if (!draft.rate.trim()) checks.push({ level: 'error', text: 'Enter a rate.' })
  else if (stored === null)
    checks.push({
      level: 'error',
      text: item.unit === 'percent' ? 'Rate must be a number with at most 4 decimal places.' : 'Rate must be a number with at most 6 decimal places.',
    })
  if (!draft.from) checks.push({ level: 'error', text: 'Choose the date this rate takes effect.' })
  if (draft.to && draft.from && draft.to < draft.from) checks.push({ level: 'error', text: 'The end date is before the start date.' })
  if (isNew) {
    if (!item.name.trim()) checks.push({ level: 'error', text: 'Name the item — it prints on the bill.' })
    if (!/^[A-Z0-9][A-Z0-9-]*$/.test(item.code)) checks.push({ level: 'error', text: 'Item code: capital letters, digits and hyphens only.' })
    if (item.schedules.length === 0) checks.push({ level: 'error', text: 'Pick at least one schedule it applies to.' })
  }
  if (!draft.from) return checks

  const current = standing(item, at)
  if (current && draft.from <= current.effective_from)
    checks.push({
      level: 'error',
      text: `Must start after the current version does (${date(current.effective_from)}). Replacing a version from its first day is a correction, not a new rate.`,
    })
  if (draft.from <= at.validAt)
    checks.push({
      level: 'warning',
      text: `Backdated: takes effect ${date(draft.from)}, on or before today. Draft bills in the open run re-price; issued bills for service from that date are flagged for correction.`,
    })
  for (const v of overlapped(item, draft, at))
    checks.push({
      level: 'warning',
      text: `Withdraws the scheduled ${formatRate(v.rate, item.unit)} from ${date(v.effective_from)}. It stays on record, marked withdrawn.`,
    })
  if (draft.to && !scheduled(item, at).some((v) => v.effective_from > draft.to))
    checks.push({ level: 'warning', text: `Nothing is billed for this item after ${date(draft.to)} unless another rate is added.` })
  if (current && stored !== null && stored === current.rate && !draft.to)
    checks.push({ level: 'warning', text: 'Same as the current rate — this records a version that changes nothing.' })
  return checks
}

/** What one recorded draft does to the version chain, in words, for the review list. */
export function describeChange(item: CatalogItem, draft: Draft, at: Coordinate): string {
  const current = standing(item, at)
  const stored = toStored(draft.rate, item.unit) ?? '0'
  const span = draft.to ? `${date(draft.from)} – ${date(draft.to)}` : `from ${date(draft.from)}`
  if (!current) return `New: ${formatRate(stored, item.unit)} ${span}`
  const closes = current.effective_to === null || current.effective_to >= draft.from
  const tail = closes
    ? `current version closes ${date(addDays(draft.from, -1))}`
    : `follows the current version, which ends ${date(current.effective_to!)}`
  return `${formatRate(current.rate, item.unit)} → ${formatRate(stored, item.unit)} ${span} · ${tail}`
}

/**
 * Apply one draft to an item's version chain: close what it overlaps, withdraw
 * schedules it replaces, insert the successor. Returns a new array — the input
 * is not mutated.
 */
export function applyDraft(
  item: CatalogItem,
  draft: Draft,
  at: Coordinate,
  meta: { reason: string; citation: string; by: string; seq: number },
): RateItemVersion[] {
  const current = standing(item, at)
  const withdrawn = new Set(overlapped(item, draft, at).map((v) => v.id))
  const closeOn = addDays(draft.from, -1)
  const next = item.versions.map((v) => {
    if (withdrawn.has(v.id)) return { ...v, recorded_until: at.recordedAt }
    if (current && v.id === current.id && (v.effective_to === null || v.effective_to >= draft.from))
      return { ...v, effective_to: closeOn }
    return v
  })
  next.push({
    id: `${item.code.toLowerCase()}-local-${meta.seq}`,
    item_code: item.code,
    item_name: item.name,
    display_group: item.group,
    calculation_type: item.calculation,
    rate: toStored(draft.rate, item.unit)!,
    rate_unit: item.unit,
    effective_from: draft.from,
    effective_to: draft.to || null,
    recorded_from: at.recordedAt,
    recorded_until: null,
    supersedes_id: current?.id ?? null,
    change_type: !current && item.versions.length === 0 ? 'initial' : draft.from <= at.validAt ? 'backfill' : 'succession',
    change_reason: meta.reason,
    regulatory_reference: meta.citation || null,
    changed_by: meta.by,
  })
  return next
}

/**
 * The rates bills actually carried, by item code and bill month (`YYYY-MM`,
 * from the service period's end), with how many bills carried each one.
 */
export type BilledRates = Record<string, Record<string, { rate: string; bills: number }[]>>

/**
 * The tariff rate for a month: the live version in effect on the 1st, as the
 * database knows it now. Not the as-of lookup — this answers "what was the
 * rate", and a late-recorded version is still the rate that month.
 */
export function tariffOn(item: CatalogItem, day: string): RateItemVersion | null {
  const covering = live(item).filter((v) => v.effective_from <= day && (v.effective_to === null || v.effective_to >= day))
  if (covering.length === 0) return null
  return covering.reduce((a, v) => (v.recorded_from > a.recorded_from ? v : a))
}
