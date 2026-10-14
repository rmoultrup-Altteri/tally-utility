import type { BillingRun, Invoice, RateItemVersion } from '@/schemas/models'
import { invoices, invoiceById, linesByInvoiceId, runs } from '@/fixtures/billing'
import { g1Items, pgaVersions, priorVersions, r1Items, versionAsOf } from '@/fixtures/rates'
import { asOf } from '@/fixtures/tenant'
import { priceAt, sheetFrom, thermsOn, type PriceSheet } from '@/lib/bill-explain'

/**
 * Void and rebill a whole run.
 *
 * The single-bill correction (`/invoices/…/rebill`) is the same election made
 * once; this is it made for every bill a run issued, because when a run used
 * the wrong rate it used it on every bill. The rules do not loosen at scale:
 *
 * - Only issued bills can be voided. A run still in review has issued
 *   nothing, so the remedy there is to cancel and rerun, not to void.
 * - The rebill sits on a correction run and carries one run-level rate mode,
 *   `historical` or `current`. `custom` is per-target only (AC-31), so a batch
 *   cannot offer it.
 * - A lookup that finds no version at the coordinate stops that bill. It
 *   never reaches for a neighbouring month — the carry-forward is the defect
 *   the January correction exists to fix.
 *
 * Repricing reads each bill's own lines back into a price sheet and swaps in
 * the elected PGA and WNA, then prices it with the same `priceAt` the bill
 * explanation uses. Nothing else in the tariff moves between a period and its
 * correction in these fixtures; the audit holds the batch price of
 * INV-2026-01-004913 to the correction it actually received.
 */

export type BatchMode = 'historical' | 'current'

/** Why a run can or cannot be voided and rebilled. */
export function runEligibility(run: BillingRun): { ok: boolean; reason: string } {
  if (run.is_dry_run) return { ok: false, reason: 'A dry run issued nothing, so there is nothing to void.' }
  if (run.status === 'cancelled') return { ok: false, reason: 'This run was cancelled and issued nothing.' }
  if (run.status !== 'posted')
    return {
      ok: false,
      reason: 'Nothing in this run has been issued yet. Cancel it and run it again instead of voiding.',
    }
  return { ok: true, reason: 'Void the bills this run issued and rebill them on a correction run' }
}

/* ---- Lineage ----------------------------------------------------------- */

/** Correction bills that replace a bill, keyed by the bill they replace. */
const replacedBy = new Map<string, Invoice>(
  invoices.filter((i) => i.replaces_invoice_id).map((i) => [i.replaces_invoice_id!, i]),
)

export const replacementOf = (invoiceId: string) => replacedBy.get(invoiceId) ?? null

/** The posted correction runs that replaced bills from this run. */
export function correctionsOf(runId: string): { run: BillingRun; bills: Invoice[] }[] {
  const out = new Map<string, { run: BillingRun; bills: Invoice[] }>()
  for (const inv of invoices) {
    if (inv.billing_run_id !== runId) continue
    const rebill = replacedBy.get(inv.id)
    if (!rebill?.billing_run_id) continue
    const run = runs.find((r) => r.id === rebill.billing_run_id)
    if (!run) continue
    const entry = out.get(run.id) ?? { run, bills: [] }
    entry.bills.push(rebill)
    out.set(run.id, entry)
  }
  return [...out.values()]
}

/** For a correction run, the runs whose bills it replaced. */
export function correctedRuns(runId: string): BillingRun[] {
  const ids = new Set(
    invoices
      .filter((i) => i.billing_run_id === runId && i.replaces_invoice_id)
      .map((i) => invoiceById.get(i.replaces_invoice_id!)?.billing_run_id)
      .filter((id): id is string => !!id),
  )
  return runs.filter((r) => ids.has(r.id))
}

/* ---- Targets ----------------------------------------------------------- */

export type Target = {
  invoice: Invoice
  /** Set when the bill cannot be part of a batch, with the reason in a sentence. */
  excluded: string | null
}

/** The bills a run issued, each marked with whether a batch can take it. */
export function runTargets(run: BillingRun): Target[] {
  return invoices
    .filter((i) => i.billing_run_id === run.id)
    .map((invoice) => {
      let excluded: string | null = null
      if (invoice.status === 'void') {
        const rebill = replacedBy.get(invoice.id)
        excluded = rebill ? `Already voided and replaced by ${rebill.invoice_number}` : 'Already voided'
      } else if (!invoice.first_issued_at) {
        excluded = 'Never issued'
      }
      return { invoice, excluded }
    })
}

/* ---- Pricing ----------------------------------------------------------- */

const SCHEDULE_ITEMS: Record<string, { wna: string; versions: RateItemVersion[] }> = {
  'R-1': { wna: 'WNA-RES', versions: [...r1Items, ...priorVersions] },
  'G-1': { wna: 'WNA-GS', versions: [...g1Items, ...priorVersions] },
}

/** The coordinate a mode prices a bill at. The correction runs now, so it sees everything recorded by now. */
export function coordinateFor(invoice: Invoice, mode: BatchMode) {
  return {
    validAt: mode === 'historical' ? invoice.period_end : asOf.validAt,
    recordedAt: asOf.recordedAt,
  }
}

export type Elected = {
  pga: RateItemVersion | null
  /** Null outside the heating season: WNA is a seasonal rider and absent is its zero. */
  wna: RateItemVersion | null
}

export function electedVersions(schedule: string, validAt: string, recordedAt: string): Elected {
  const items = SCHEDULE_ITEMS[schedule]
  return {
    pga: versionAsOf(pgaVersions, validAt, recordedAt),
    wna: items ? versionAsOf(items.versions.filter((v) => v.item_code === items.wna), validAt, recordedAt) : null,
  }
}

export type Repriced = {
  invoice: Invoice
  schedule: string
  therms: number
  asBilled: PriceSheet
  elected: Elected
  /** Cents. */
  before: number
  /** Cents; null when no PGA version covers the coordinate and the bill would stop. */
  after: number | null
  paid: number
  /** What the replacement leaves owing, or a credit when negative. */
  newBalance: number | null
}

const cents = (v: string) => Math.round(Number(v) * 100)

export function reprice(invoice: Invoice, mode: BatchMode): Repriced {
  const lines = linesByInvoiceId(invoice.id)
  const asBilled = sheetFrom(lines)
  const therms = thermsOn(lines)
  const { validAt, recordedAt } = coordinateFor(invoice, mode)
  const elected = electedVersions(asBilled.schedule, validAt, recordedAt)
  const before = priceAt(therms, asBilled).total
  const after = elected.pga
    ? priceAt(therms, { ...asBilled, pga: Number(elected.pga.rate), wna: elected.wna ? Number(elected.wna.rate) : 0 }).total
    : null
  const paid = cents(invoice.amount_paid)
  return {
    invoice,
    schedule: asBilled.schedule,
    therms,
    asBilled,
    elected,
    before,
    after,
    paid,
    newBalance: after === null ? null : after - paid,
  }
}

/** A rate the election changes, stated once per schedule rather than once per bill. */
export type RateChange = {
  item: string
  schedule: string
  from: number
  to: number | null
  version: RateItemVersion | null
}

export function rateChanges(priced: Repriced[]): RateChange[] {
  const seen = new Map<string, RateChange>()
  for (const p of priced) {
    const pga: RateChange = { item: 'PGA', schedule: p.schedule, from: p.asBilled.pga, to: p.elected.pga ? Number(p.elected.pga.rate) : null, version: p.elected.pga }
    const wna: RateChange = { item: 'WNA', schedule: p.schedule, from: p.asBilled.wna, to: p.elected.wna ? Number(p.elected.wna.rate) : 0, version: p.elected.wna }
    for (const c of [pga, wna]) {
      const key = `${c.item}:${c.item === 'PGA' ? '' : c.schedule}`
      if (!seen.has(key)) seen.set(key, c)
    }
  }
  return [...seen.values()]
}

/* ---- Numbering --------------------------------------------------------- */

/** Correction runs number within the month they run in: BR-2026-02-COR-1, -2, … */
export function nextCorrectionNumber(taken: string[]): string {
  const month = asOf.validAt.slice(0, 7)
  const prefix = `BR-${month}-COR-`
  const used = [...runs.map((r) => r.run_number), ...taken]
    .filter((n) => n.startsWith(prefix))
    .map((n) => Number(n.slice(prefix.length)))
  return `${prefix}${Math.max(0, ...used) + 1}`
}
