/**
 * Fixture invariant audit.
 *
 * Every check here is an identity the UI DISPLAYS but nothing enforces. The
 * class of bug this exists to catch is the one that stays invisible while a
 * coefficient happens to be 1: the bill's derivation rail multiplied by the
 * meter multiplier twice and looked correct on every account until a 1.5-inch
 * meter with a multiplier of 2.0000 arrived.
 *
 * Run: node --experimental-strip-types scripts/audit-fixtures.mjs
 */
import { customers, locations, meters, serviceLinks, customerById, locationById, meterById } from '../fixtures/accounts.ts'
import { readings } from '../fixtures/reads.ts'
import { invoices, lines, runs, linesByInvoiceId, arAging, portlets, rateCard } from '../fixtures/billing.ts'
import { exceptions } from '../fixtures/exceptions.ts'
import { worklist, BYPASSES, reconnectQueue, stayedAccounts, evaluate } from '../fixtures/collections.ts'
import { pgaVersions, r1Items, g1Items, rateSchedules, versionAsOf } from '../fixtures/rates.ts'
import { backfillExposure } from '../fixtures/pga.ts'
import { seedFavorites } from '../fixtures/favorites.ts'
import { LISTS, applyFilters, isFiltered } from '../lib/views.ts'
import { baseline as sandboxBaseline, billFor, currentCard } from '../fixtures/tariff.ts'

const findings = []
const fail = (area, id, msg) => findings.push({ area, id, msg })
const n = (v) => (v === null || v === undefined ? null : Number(v))
const close = (a, b, tol = 0.011) => Math.abs(a - b) <= tol
/** Exact to the cent — for identities between figures that are already rounded. */
const exact = (a, b) => Math.round(a * 100) === Math.round(b * 100)
const daysBetween = (a, b) => Math.round((Date.parse(`${b}T00:00:00Z`) - Date.parse(`${a}T00:00:00Z`)) / 86400000)

/* ---- Referential integrity -------------------------------------------- */
for (const l of serviceLinks) {
  if (!customerById.get(l.customerId)) fail('links', l.customerId, 'serviceLink customer does not exist')
  if (!locationById.get(l.locationId)) fail('links', l.locationId, 'serviceLink location does not exist')
  if (!meterById.get(l.meterId)) fail('links', l.meterId, 'serviceLink meter does not exist')
}
for (const c of customers) if (!serviceLinks.some((l) => l.customerId === c.id)) fail('links', c.id, 'customer has no service link')
for (const loc of locations) if (!serviceLinks.some((l) => l.locationId === loc.id)) fail('links', loc.id, 'location is orphaned')
for (const m of meters) if (!serviceLinks.some((l) => l.meterId === m.id)) fail('links', m.id, 'meter is orphaned')
for (const r of readings) if (!meterById.get(r.meter_id)) fail('reads', r.id, 'reading points at a missing meter')
for (const i of invoices) {
  if (!customerById.get(i.customer_id)) fail('invoices', i.id, 'invoice customer does not exist')
  if (!locationById.get(i.location_id)) fail('invoices', i.id, 'invoice location does not exist')
  if (!runs.some((r) => r.id === i.billing_run_id)) fail('invoices', i.id, `billing run ${i.billing_run_id} does not exist`)
  if (i.replaces_invoice_id && !invoices.some((x) => x.id === i.replaces_invoice_id)) fail('invoices', i.id, 'replaces a missing invoice')
}
for (const l of lines) if (!invoices.some((i) => i.id === l.invoice_id)) fail('lines', l.id, 'line points at a missing invoice')

/* ---- Meter reading arithmetic ----------------------------------------- */
for (const r of readings) {
  const meter = meterById.get(r.meter_id)
  const raw = n(r.reading_value) - n(r.previous_value)
  const mult = n(r.gas_meter_factor) ?? 1
  /* A wrapped register reads lower than its predecessor; the fixture models
     the un-corrected case deliberately, so only flag unwrapped rows. */
  if (raw >= 0 && !close(raw * mult, n(r.consumption), 0.02))
    fail('reads', r.id, `(${raw} raw × ${mult} multiplier) = ${(raw * mult).toFixed(2)} but consumption says ${r.consumption}`)
  if (meter && n(meter.multiplier) !== mult)
    fail('reads', r.id, `gas_meter_factor ${mult} disagrees with meter ${meter.meter_number} multiplier ${meter.multiplier}`)
  if (meter && n(meter.gas_btu_factor) !== n(r.gas_btu_factor))
    fail('reads', r.id, `BTU factor ${r.gas_btu_factor} disagrees with meter ${meter.gas_btu_factor}`)
  if (r.gas_therms !== null && r.gas_pressure_corrected_volume !== null) {
    const t = n(r.gas_pressure_corrected_volume) * n(r.gas_btu_factor)
    if (!close(t, n(r.gas_therms), 0.02))
      fail('reads', r.id, `${r.gas_pressure_corrected_volume} × ${r.gas_btu_factor} = ${t.toFixed(2)} but gas_therms says ${r.gas_therms}`)
  }
  const d = daysBetween(r.previous_reading_date, r.reading_date)
  if (d !== r.days_in_period) fail('reads', r.id, `${r.previous_reading_date} → ${r.reading_date} is ${d} days but days_in_period says ${r.days_in_period}`)
  if (r.consumption_same_period_last_year && r.consumption_pct_vs_typical !== null && n(r.consumption) >= 0) {
    const pct = ((n(r.consumption) - n(r.consumption_same_period_last_year)) / n(r.consumption_same_period_last_year)) * 100
    if (!close(pct, n(r.consumption_pct_vs_typical), 0.6))
      fail('reads', r.id, `vs last year is ${pct.toFixed(1)}% but consumption_pct_vs_typical says ${r.consumption_pct_vs_typical}%`)
  }
  if (r.is_estimated && !r.estimation_reason) fail('reads', r.id, 'estimated read carries no estimation_reason')
  if (!r.is_estimated && r.estimation_reason) fail('reads', r.id, 'actual read carries an estimation_reason')
}

/* ---- Invoice arithmetic ------------------------------------------------ */
for (const inv of invoices) {
  const ls = linesByInvoiceId(inv.id)
  if (!ls.length) { fail('invoices', inv.id, 'invoice has no line items'); continue }
  const charges = ls.filter((l) => l.display_group !== 'taxes_fees').reduce((a, l) => a + n(l.amount), 0)
  const taxes = ls.filter((l) => l.display_group === 'taxes_fees').reduce((a, l) => a + n(l.amount), 0)
  if (!exact(charges, n(inv.total_charges))) fail('invoices', inv.id, `lines total ${charges.toFixed(2)} but total_charges says ${inv.total_charges}`)
  if (!exact(taxes, n(inv.total_taxes))) fail('invoices', inv.id, `tax lines total ${taxes.toFixed(2)} but total_taxes says ${inv.total_taxes}`)
  const tb = inv.tax_breakdown.reduce((a, x) => a + n(x.amount), 0)
  if (!exact(tb, n(inv.total_taxes))) fail('invoices', inv.id, `tax_breakdown totals ${tb.toFixed(2)} but total_taxes says ${inv.total_taxes}`)
  for (const t of inv.tax_breakdown) {
    const expect = n(t.basis) * n(t.rate)
    if (!close(expect, n(t.amount))) fail('invoices', inv.id, `${t.label}: ${t.basis} × ${t.rate} = ${expect.toFixed(2)} but amount says ${t.amount}`)
  }
  const due = n(inv.total_charges) - n(inv.total_credits) + n(inv.total_taxes) + n(inv.total_adjustments) + n(inv.previous_balance)
  if (!exact(due, n(inv.amount_due))) fail('invoices', inv.id, `charges − credits + taxes + adjustments + previous = ${due.toFixed(2)} but amount_due says ${inv.amount_due}`)
  if (inv.status !== 'void' && !exact(n(inv.amount_due) - n(inv.amount_paid), n(inv.balance)))
    fail('invoices', inv.id, `amount_due − amount_paid = ${(n(inv.amount_due) - n(inv.amount_paid)).toFixed(2)} but balance says ${inv.balance}`)
  if (daysBetween(inv.period_start, inv.period_end) <= 0) fail('invoices', inv.id, 'period_end is not after period_start')
  const est = ls.some((l) => l.description?.toLowerCase().includes('estimat'))
  if (inv.has_estimated_reads && inv.estimated_read_count < 1) fail('invoices', inv.id, 'has_estimated_reads is true but the count is zero')
}

/* ---- Invoice line arithmetic ------------------------------------------ */
for (const l of lines) {
  if (l.usage_quantity !== null && l.rate !== null) {
    const expect = n(l.usage_quantity) * n(l.rate)
    if (!close(expect, n(l.amount), 0.011)) fail('lines', l.id, `${l.usage_quantity} × ${l.rate} = ${expect.toFixed(2)} but amount says ${l.amount}`)
  }
  if (l.gas_ccf_used !== null) {
    const t = n(l.gas_ccf_used) * (n(l.gas_meter_factor) ?? 1) * (n(l.gas_btu_factor) ?? 1)
    if (!close(t, n(l.gas_therms_billed), 0.02))
      fail('lines', l.id, `${l.gas_ccf_used} Ccf × ${l.gas_meter_factor} × ${l.gas_btu_factor} = ${t.toFixed(2)} but gas_therms_billed says ${l.gas_therms_billed}`)
  }
  if (l.is_taxable && !exact(n(l.taxable_amount), n(l.amount)))
    fail('lines', l.id, `taxable line: taxable_amount ${l.taxable_amount} does not equal amount ${l.amount}`)
  if (!l.is_taxable && n(l.taxable_amount) !== 0)
    fail('lines', l.id, `non-taxable line carries taxable_amount ${l.taxable_amount}`)
  if (l.days_covered > l.days_in_period) fail('lines', l.id, 'days_covered exceeds days_in_period')
  const inv = invoices.find((i) => i.id === l.invoice_id)
  if (inv && (l.coverage_start < inv.period_start || l.coverage_end > inv.period_end))
    fail('lines', l.id, 'line coverage falls outside the invoice period')
}
/* Tiered blocks must add up to the volume the commodity line priced. */
for (const inv of invoices) {
  const ls = linesByInvoiceId(inv.id)
  const tiers = ls.filter((l) => l.tier_label?.startsWith('Block'))
  const commodity = ls.find((l) => l.charge_type === 'pga')
  if (tiers.length && commodity) {
    const sum = tiers.reduce((a, l) => a + n(l.usage_quantity), 0)
    if (!close(sum, n(commodity.usage_quantity), 0.02))
      fail('lines', inv.id, `tier quantities sum to ${sum.toFixed(2)} th but the commodity line priced ${commodity.usage_quantity} th`)
  }
}

/* ---- Lifecycle rules --------------------------------------------------- */
for (const inv of invoices) {
  if (inv.status === 'void' && (!inv.voided_at || !inv.void_reason_code)) fail('lifecycle', inv.id, 'void invoice missing voided_at or void_reason_code')
  if (inv.status !== 'void' && inv.voided_at) fail('lifecycle', inv.id, 'non-void invoice carries voided_at')
  if (inv.status === 'held' && (!inv.held_at || !inv.hold_reason)) fail('lifecycle', inv.id, 'held invoice missing held_at or hold_reason')
  if (inv.status === 'draft' && inv.first_issued_at) fail('lifecycle', inv.id, 'draft invoice carries first_issued_at — an issued bill is immutable')
  if (inv.invoice_type === 'correction' && !inv.replaces_invoice_id) fail('lifecycle', inv.id, 'correction invoice replaces nothing')
  if (inv.sent_at && !inv.first_issued_at) fail('lifecycle', inv.id, 'invoice was sent but has no first_issued_at')
}
/* AC: one live rebill per lineage. */
const lineage = new Map()
for (const inv of invoices.filter((i) => i.replaces_invoice_id)) {
  const live = inv.status !== 'void'
  if (!live) continue
  const k = inv.replaces_invoice_id
  if (lineage.has(k)) fail('lifecycle', k, `more than one live rebill: ${lineage.get(k)} and ${inv.id}`)
  lineage.set(k, inv.id)
}
for (const r of runs) {
  const seq = [r.started_at, r.completed_at, r.approved_at, r.posted_at].filter(Boolean).map(Date.parse)
  for (let i = 1; i < seq.length; i += 1) if (seq[i] < seq[i - 1]) fail('runs', r.id, 'run timestamps are out of order')
  if (!r.valid_at || !r.recorded_at) fail('runs', r.id, 'run has no bi-temporal coordinate pair')
  if (r.is_dry_run && r.posted_at) fail('runs', r.id, 'a dry run has a posted_at')
}

/* ---- Rate version chains ----------------------------------------------- */
const allVersions = [...pgaVersions, ...r1Items, ...g1Items]
const byId = new Map(allVersions.map((v) => [v.id, v]))
for (const v of allVersions) {
  if (v.effective_to && v.effective_from > v.effective_to) fail('rates', v.id, 'effective_from is after effective_to')
  if (v.recorded_until && v.recorded_from > v.recorded_until) fail('rates', v.id, 'recorded_from is after recorded_until')
  if (v.change_type !== 'initial' && !v.supersedes_id) fail('rates', v.id, `change_type ${v.change_type} but supersedes nothing`)
  if (v.change_type === 'initial' && v.supersedes_id) fail('rates', v.id, 'initial version supersedes something')
  if (!v.change_reason) fail('rates', v.id, 'version carries no change_reason')
  /* A supersedes_id pointing outside the loaded set is fine only when the
     predecessor is genuinely not modelled; flag same-code dangles. */
  if (v.supersedes_id && byId.has(v.supersedes_id) && byId.get(v.supersedes_id).item_code !== v.item_code)
    fail('rates', v.id, `supersedes ${v.supersedes_id}, which is a different item_code`)
}
/* No coordinate may resolve to two versions of one item. */
const codes = [...new Set(allVersions.map((v) => v.item_code))]
for (const code of codes) {
  const vs = allVersions.filter((v) => v.item_code === code)
  for (const a of vs) for (const b of vs) {
    if (a.id >= b.id) continue
    const validOverlap = a.effective_from <= (b.effective_to ?? '9999') && b.effective_from <= (a.effective_to ?? '9999')
    const recOverlap = a.recorded_from <= (b.recorded_until ?? '9999') && b.recorded_from <= (a.recorded_until ?? '9999')
    if (validOverlap && recOverlap && a.recorded_from === b.recorded_from)
      fail('rates', code, `${a.id} and ${b.id} are both standing at the same coordinate`)
  }
}
/* Every rate an invoice line cites must exist as a version. */
const versionCodes = new Set(allVersions.map((v) => v.item_code))
for (const l of lines) {
  if (l.rate_item_code && !versionCodes.has(l.rate_item_code))
    fail('lines', l.id, `cites rate item ${l.rate_item_code}, which has no version in the rate fixtures`)
  if (l.rate_schedule_code && !rateSchedules.some((s) => s.code === l.rate_schedule_code))
    fail('lines', l.id, `cites schedule ${l.rate_schedule_code}, which does not exist`)
}

/* ---- Exceptions and collections ---------------------------------------- */
for (const e of exceptions) {
  if (e.customer_id && !customerById.get(e.customer_id)) fail('exceptions', e.id, 'points at a missing customer')
  if (e.status === 'resolved' && !e.resolved_at) fail('exceptions', e.id, 'resolved exception has no resolved_at')
  if (e.status === 'snoozed' && !e.snoozed_until) fail('exceptions', e.id, 'snoozed exception has no snoozed_until')
}
for (const w of worklist) {
  if (w.customerId && !customerById.get(w.customerId)) fail('collections', w.id, 'points at a missing customer')
  for (const b of w.bypasses) if (!BYPASSES[b.code]) fail('collections', w.id, `unknown bypass code ${b.code}`)
  const v = evaluate(w)
  if (v.eligible && w.bypasses.length) fail('collections', w.id, 'eligible despite carrying bypass conditions')
  if (!v.eligible && !w.bypasses.length) fail('collections', w.id, 'blocked with no bypass condition to explain it')
  if (w.disputed && n(w.disputed) > n(w.balance)) fail('collections', w.id, 'disputed amount exceeds the balance')
}
for (const r of reconnectQueue) {
  if (r.paidAt && Date.parse(r.paidAt) < Date.parse(r.disconnectedAt)) fail('collections', r.id, 'paid before it was disconnected')
  if (Date.parse(r.slaDueAt) < Date.parse(r.paidAt ?? r.disconnectedAt)) fail('collections', r.id, 'SLA due before the clock started')
}
for (const s of stayedAccounts) {
  const d = daysBetween(s.petitionDate, s.assuranceDeadline)
  if (d !== 20) fail('collections', s.id, `§366(b) deadline is ${d} days after the petition, not 20`)
}

/* ---- Dashboard aggregates ---------------------------------------------- */
const arTotal = arAging.reduce((a, b) => a + n(b.amount), 0)
if (arTotal <= 0) fail('dashboard', 'arAging', 'AR buckets do not total a positive figure')
for (const p of portlets) if (p.more < 0) fail('dashboard', p.tier, 'negative overflow count')
/* T8-8: the rate card reads as-billed from the lines of the last posted run. */
const postedRun = runs.find((r) => r.run_number === rateCard.lastPostedRun.split(' · ')[0])
if (!postedRun) fail('dashboard', 'rateCard', `lastPostedRun ${rateCard.lastPostedRun} matches no run in the fixtures`)
for (const row of rateCard.rows) {
  if (row.asBilled === null) continue
  const cited = lines.filter((l) => l.rate_item_code === row.itemCode)
  if (cited.length && !cited.some((l) => close(n(l.rate), n(row.asBilled), 1e-9)))
    fail('dashboard', row.itemCode, `rate card says as-billed ${row.asBilled} but no invoice line carries that rate (lines have ${[...new Set(cited.map((l) => l.rate))].join(', ')})`)
}

/* ---- Cross-fixture narrative ------------------------------------------
   Numbers a screen states in prose still have to agree with the rows behind
   them. These are the identities no schema constraint would ever catch. */
const janRun = runs.find((r) => r.id === 'run-2026-01-04')
if (janRun) {
  if (backfillExposure.billsIssued !== janRun.total_invoices)
    fail('narrative', 'pga', `exposure claims ${backfillExposure.billsIssued} bills but ${janRun.run_number} issued ${janRun.total_invoices}`)
  const split = backfillExposure.billsOverThreshold + backfillExposure.billsUnderThreshold
  if (split !== backfillExposure.billsIssued)
    fail('narrative', 'pga', `threshold split totals ${split}, not ${backfillExposure.billsIssued}`)
  if (backfillExposure.remainingBills !== backfillExposure.billsOverThreshold - backfillExposure.rebilled)
    fail('narrative', 'pga', 'remaining rebills do not equal those over threshold minus those already done')
}
{
  const total = n(backfillExposure.gasDelta) + n(backfillExposure.taxDelta)
  if (!close(total, n(backfillExposure.totalCredit), 0.02))
    fail('narrative', 'pga', `gas ${backfillExposure.gasDelta} + tax ${backfillExposure.taxDelta} = ${total.toFixed(2)} but totalCredit says ${backfillExposure.totalCredit}`)
  if (!close(n(backfillExposure.totalCredit) - n(backfillExposure.creditIssued), n(backfillExposure.remainingCredit), 0.02))
    fail('narrative', 'pga', 'remaining credit does not equal total minus what was already issued')
  const implied = n(backfillExposure.therms) * n(backfillExposure.deltaFactor)
  if (!close(implied, n(backfillExposure.gasDelta), 0.5))
    fail('narrative', 'pga', `${backfillExposure.therms} th × ${backfillExposure.deltaFactor} = ${implied.toFixed(2)} but gasDelta says ${backfillExposure.gasDelta}`)
  if (!close(n(backfillExposure.billedFactor) - n(backfillExposure.filedFactor), n(backfillExposure.deltaFactor), 1e-6))
    fail('narrative', 'pga', 'deltaFactor is not the difference between the billed and filed factors')
}
/* A run cannot report fewer exceptions than the queue actually holds. */
{
  const open = exceptions.filter((e) => e.status !== 'resolved' && e.status !== 'false_positive')
  const run = runs.find((r) => r.id === 'run-2026-02-04')
  if (run && run.total_exceptions < open.length)
    fail('narrative', 'queue', `${run.run_number} reports ${run.total_exceptions} exceptions but ${open.length} open ones are modelled`)
}
/* Every favorite must point at a destination that exists. */
for (const f of seedFavorites) {
  if (f.kind === 'report') { fail('favorites', f.id, 'report favorite exists but no report is built'); continue }
  if (!LISTS[f.list]) fail('favorites', f.id, `points at unknown list ${f.list}`)
  if (f.kind === 'named_view' && !isFiltered(f.filters))
    fail('favorites', f.id, 'saved view carries no filters — it is the plain list')
  if (f.kind === 'named_view' && applyFilters(exceptions, f.filters, 'Dana Pearce').length === 0)
    fail('favorites', f.id, `saved view "${f.name}" matches nothing in the fixtures`)
}

/* The sandbox's baseline cycle must be a run that exists, with its counts. */
const sbRun = runs.find((r) => r.run_number === sandboxBaseline.runNumber)
if (!sbRun) fail('narrative', 'sandbox', `baseline cites ${sandboxBaseline.runNumber}, which is not a run`)
else {
  if (sbRun.total_invoices !== sandboxBaseline.accountsInCycle)
    fail('narrative', 'sandbox', `baseline says ${sandboxBaseline.accountsInCycle} in cycle but ${sbRun.run_number} billed ${sbRun.total_invoices}`)
  if (sbRun.period_start !== sandboxBaseline.periodStart || sbRun.period_end !== sandboxBaseline.periodEnd)
    fail('narrative', 'sandbox', 'baseline period does not match the run it names')
}
if (sandboxBaseline.accountsOnSchedule + sandboxBaseline.accountsOtherSchedules !== sandboxBaseline.accountsInCycle)
  fail('narrative', 'sandbox', 'on-schedule plus out-of-scope accounts do not total the cycle')
/* The calculator must still reproduce the bill it was built against. */
{
  const inv = invoices.find((i) => i.id === 'inv-0001')
  const b = billFor(226.01, currentCard)
  if (!close(b.charges, n(inv.total_charges)) || !close(b.tax, n(inv.total_taxes)))
    fail('narrative', 'tariff', `card reproduces ${b.charges.toFixed(2)}/${b.tax.toFixed(2)} but ${inv.invoice_number} is ${inv.total_charges}/${inv.total_taxes}`)
}

/* ---- Report ------------------------------------------------------------ */
const byArea = {}
for (const f of findings) (byArea[f.area] ??= []).push(f)
if (!findings.length) {
  console.log('All fixture invariants hold.')
} else {
  console.log(`${findings.length} finding${findings.length === 1 ? '' : 's'}\n`)
  for (const [area, fs] of Object.entries(byArea)) {
    console.log(`── ${area} (${fs.length})`)
    for (const f of fs) console.log(`   ${f.id.padEnd(12)} ${f.msg}`)
    console.log()
  }
}
process.exit(findings.length ? 1 : 0)
