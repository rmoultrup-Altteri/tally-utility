'use client'

import { useMemo, useState } from 'react'
import { CLASSES, presentRates, rateCase, type ClassKey } from '@/fixtures/rate-case'
import {
  determinants,
  presentRevenue,
  revenue,
  revenueRequirement,
  settledDesigns,
  solveCustomerCharge,
  solveVolumetric,
  targets,
  type Design,
  type Designs,
} from '@/lib/rate-case'
import { Panel, PanelHeader, Button } from '@/components/ui/Panel'
import { StateFlag } from '@/components/ui/State'
import { Chip } from '@/components/ui/Chip'
import { count, date, rate as fmtRate } from '@/lib/format'
import { BillImpacts, FilingPackage, Implement } from '@/components/rate-case/RateCaseOutputs'
import { TOLERANCE, usd0, usd2 } from '@/components/rate-case/shared'

/**
 * The rate case toolkit.
 *
 * The old sandbox let an analyst move a rate and see who it moved. A rate case
 * asks the harder version of that question, end to end: what revenue does the
 * utility need, how is it split between classes, what rates collect exactly
 * that from a year of real volumes, what does it do to a typical bill, and
 * what goes in the filing. Small gas systems pay a consultant five figures for
 * that spreadsheet. Here it is one screen, computed from the system's own bills,
 * and the rates it produces post as ordinary date-effective versions.
 */

type Step = 'requirement' | 'design' | 'impacts' | 'filing' | 'implement'

const STEPS: { key: Step; label: string }[] = [
  { key: 'requirement', label: 'Revenue requirement' },
  { key: 'design', label: 'Allocation and rate design' },
  { key: 'impacts', label: 'Bill impacts' },
  { key: 'filing', label: 'Filing package' },
  { key: 'implement', label: 'Implement' },
]

export function RateCaseToolkit() {
  const [step, setStep] = useState<Step>('design')
  const [share, setShare] = useState<number>(rateCase.settledAllocation['R-1'])
  const [designs, setDesigns] = useState<Designs>(settledDesigns)

  const t = useMemo(() => targets(share), [share])
  const rev = { 'R-1': revenue('R-1', designs['R-1']), 'G-1': revenue('G-1', designs['G-1']) }
  const gap = { 'R-1': rev['R-1'].total - t['R-1'], 'G-1': rev['G-1'].total - t['G-1'] }
  const balanced = Math.abs(gap['R-1']) <= TOLERANCE && Math.abs(gap['G-1']) <= TOLERANCE

  const status: Record<Step, 'done' | 'attention' | null> = {
    requirement: 'done',
    design: balanced ? 'done' : 'attention',
    impacts: balanced ? 'done' : null,
    filing: balanced ? 'done' : null,
    implement: null,
  }

  return (
    <div className="space-y-5">
      <CaseHeader />

      <nav aria-label="Rate case steps" className="flex flex-wrap gap-1 rounded-md border border-rule-hair bg-surface-raised p-1 shadow-panel">
        {STEPS.map((s, i) => (
          <button
            key={s.key}
            type="button"
            aria-current={step === s.key ? 'step' : undefined}
            onClick={() => setStep(s.key)}
            className={`flex flex-1 min-w-36 items-center gap-2 rounded-sm px-3 py-2 text-left transition-colors duration-fast ${
              step === s.key ? 'bg-accent-wash text-accent-text' : 'text-ink-secondary hover:bg-surface-sunken hover:text-ink-primary'
            }`}
          >
            <span
              className={`flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-micro font-medium ${
                status[s.key] === 'done'
                  ? 'bg-exception-cleared-rail text-ink-inverse'
                  : status[s.key] === 'attention'
                    ? 'bg-exception-warning-rail text-ink-inverse'
                    : 'border border-rule-solid text-ink-tertiary'
              }`}
            >
              {status[s.key] === 'done' ? '✓' : i + 1}
            </span>
            <span className="text-data font-medium">{s.label}</span>
          </button>
        ))}
      </nav>

      {step === 'requirement' ? <Requirement /> : null}
      {step === 'design' ? (
        <RateDesign share={share} setShare={setShare} designs={designs} setDesigns={setDesigns} t={t} />
      ) : null}
      {step === 'impacts' ? <BillImpacts designs={designs} /> : null}
      {step === 'filing' ? <FilingPackage designs={designs} share={share} /> : null}
      {step === 'implement' ? <Implement designs={designs} balanced={balanced} /> : null}

      <div className="flex justify-between">
        <Button
          variant="quiet"
          disabled={step === STEPS[0].key}
          onClick={() => setStep(STEPS[Math.max(0, STEPS.findIndex((s) => s.key === step) - 1)].key)}
        >
          ← Previous
        </Button>
        <Button
          disabled={step === 'implement'}
          onClick={() => setStep(STEPS[Math.min(STEPS.length - 1, STEPS.findIndex((s) => s.key === step) + 1)].key)}
        >
          Next →
        </Button>
      </div>
    </div>
  )
}

/* ---- The case ---------------------------------------------------------- */

function CaseHeader() {
  const next = rateCase.milestones.find((m) => !m.done)
  return (
    <Panel>
      <div className="flex flex-wrap items-start justify-between gap-4 px-5 py-4">
        <div>
          <p className="field-label">
            <span className="ident">{rateCase.docket}</span> · {rateCase.testYear}
          </p>
          <h2 className="text-h2 text-ink-primary mt-0.5">{rateCase.title}</h2>
          <p className="text-micro text-ink-tertiary mt-1 max-w-2xl">{rateCase.scope}</p>
        </div>
        <div className="text-right">
          <p className="field-label">Settled increase</p>
          <p className="text-figure text-ink-primary">{usd0(rateCase.requestedIncrease)}</p>
          <StateFlag tone="pending">Settled · awaiting final order</StateFlag>
        </div>
      </div>
      <ol className="grid grid-cols-2 md:grid-cols-6 border-t border-rule-hair">
        {rateCase.milestones.map((m) => (
          <li
            key={m.key}
            title={m.detail}
            className={`relative px-4 py-3 ${m.key === next?.key ? 'bg-accent-wash' : ''} border-r border-rule-hair last:border-r-0`}
          >
            <span className="flex items-center gap-1.5">
              <span
                aria-hidden
                className={`h-2 w-2 rounded-full ${m.done ? 'bg-exception-cleared-rail' : m.key === next?.key ? 'bg-accent' : 'bg-rule-solid'}`}
              />
              <span className={`text-micro ${m.done ? 'text-ink-secondary' : 'text-ink-primary font-medium'}`}>{m.label}</span>
            </span>
            <span className="mt-0.5 block text-micro text-ink-tertiary">
              {date(m.date)}
              {m.done ? '' : ' · expected'}
            </span>
          </li>
        ))}
      </ol>
    </Panel>
  )
}

/* ---- Step 1 ------------------------------------------------------------ */

function Requirement() {
  const rr = revenueRequirement()
  return (
    <div className="grid grid-cols-1 xl:grid-cols-[minmax(0,1fr)_minmax(0,1.1fr)] gap-5">
      <Panel>
        <PanelHeader title="Revenue requirement" meta="Schedule A · test year" />
        <table className="w-full text-data">
          <tbody className="[&_td]:px-4 [&_td]:py-2 [&_tr]:border-b [&_tr]:border-rule-hair">
            {rr.rows.map((r) => (
              <tr key={r.label}>
                <td>
                  <p className="text-ink-primary">{r.label}</p>
                  <p className="text-micro text-ink-tertiary">{r.note}</p>
                </td>
                <td className="figures text-ink-primary">{usd0(r.amount)}</td>
              </tr>
            ))}
            <tr className="bg-surface">
              <td className="font-medium text-ink-primary">Cost of service</td>
              <td className="figures font-medium text-ink-primary">{usd0(rr.costOfService)}</td>
            </tr>
            <tr>
              <td className="text-ink-secondary">Less other operating revenue (fees, service charges)</td>
              <td className="figures text-ink-secondary">({usd0(rr.otherRevenue)})</td>
            </tr>
            <tr className="bg-surface">
              <td className="font-medium text-ink-primary">Base-rate revenue requirement</td>
              <td className="figures font-medium text-ink-primary">{usd0(rr.requirement)}</td>
            </tr>
            <tr>
              <td className="text-ink-secondary">Revenue at present rates</td>
              <td className="figures text-ink-secondary">{usd0(rr.present)}</td>
            </tr>
            <tr className="border-b-0">
              <td className="font-semibold text-ink-primary">Increase required</td>
              <td className="figures font-semibold text-ink-primary">
                {usd0(rr.increase)}{' '}
                <span className="text-micro text-ink-tertiary">({((rr.increase / rr.present) * 100).toFixed(2)}%)</span>
              </td>
            </tr>
          </tbody>
        </table>
      </Panel>

      <Panel>
        <PanelHeader title="Billing determinants" meta="Schedule B · from this system's own bills" />
        <div className="divide-y divide-rule-hair">
          {CLASSES.map((c) => {
            const d = determinants[c.key]
            const peak = Math.max(...d.months.map((m) => m.block1 + m.block2))
            return (
              <div key={c.key} className="px-4 py-3">
                <div className="flex items-baseline justify-between gap-3">
                  <p className="text-data font-medium text-ink-primary">
                    <span className="ident">{c.key}</span> · {c.name}
                  </p>
                  <p className="text-micro text-ink-tertiary">{count(c.systemAccounts)} accounts</p>
                </div>
                <dl className="mt-2 grid grid-cols-4 gap-3">
                  <Mini label="Bills">{count(d.bills)}</Mini>
                  <Mini label={`First ${c.blockLimit} th`}>{count(d.block1)}</Mini>
                  <Mini label="Beyond">{count(d.block2)}</Mini>
                  <Mini label="Present revenue">{usd0(presentRevenue[c.key].total)}</Mini>
                </dl>
                <div className="mt-3 flex h-12 items-end gap-1" aria-label={`${c.key} therms by month across the test year`}>
                  {d.months.map((m) => (
                    <div key={m.month} className="flex flex-1 flex-col items-center gap-0.5">
                      <span
                        className="w-full rounded-xs bg-exception-info-rail/70"
                        style={{ height: `${((m.block1 + m.block2) / peak) * 40}px` }}
                        title={`${m.month}: ${count(m.block1 + m.block2)} therms`}
                      />
                      <span className="text-[9px] text-ink-tertiary">{m.month.slice(0, 1)}</span>
                    </div>
                  ))}
                </div>
              </div>
            )
          })}
        </div>
        <p className="border-t border-rule-hair px-4 py-3 text-micro text-ink-secondary leading-relaxed">
          Twelve months of actual volumes: the locked January cycle carried across the test year by the seasonal shape of issued bills,
          and scaled from cycle 04 to every account on the system. No forecast and no average customer — the same population the bills
          came from, so a proof of revenue here is a proof against what was actually billed.
        </p>
      </Panel>
    </div>
  )
}

function Mini({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="min-w-0">
      <dt className="field-label">{label}</dt>
      <dd className="figures text-left text-data text-ink-primary">{children}</dd>
    </div>
  )
}

/* ---- Step 2 ------------------------------------------------------------ */

function RateDesign({
  share,
  setShare,
  designs,
  setDesigns,
  t,
}: {
  share: number
  setShare: (n: number) => void
  designs: Designs
  setDesigns: (fn: (d: Designs) => Designs) => void
  t: Record<ClassKey, number>
}) {
  const inc = { 'R-1': t['R-1'] - presentRevenue['R-1'].total, 'G-1': t['G-1'] - presentRevenue['G-1'].total }
  /* Determinants are the analyst's check, not the decision; they stay out of the way until asked for. */
  const [showDet, setShowDet] = useState(false)
  const settled = Math.abs(share - rateCase.settledAllocation['R-1']) < 1e-9

  return (
    <div className="space-y-5">
      <Panel>
        <PanelHeader
          title="Class allocation"
          meta="How the increase is split between schedules"
          actions={
            settled ? (
              <StateFlag tone="cleared">As settled</StateFlag>
            ) : (
              <Button onClick={() => setShare(rateCase.settledAllocation['R-1'])}>Reset to the settlement</Button>
            )
          }
        />
        <div className="px-4 py-4">
          <label htmlFor="alloc" className="sr-only">
            Residential share of the increase
          </label>
          <input
            id="alloc"
            type="range"
            min={0.5}
            max={0.95}
            step={0.01}
            value={share}
            onChange={(e) => setShare(Number(e.target.value))}
            className="w-full accent-[var(--color-accent)]"
          />
          <div className="mt-2 grid grid-cols-2 gap-4">
            {CLASSES.map((c) => (
              <div key={c.key} className="rounded-sm border border-rule-hair bg-surface px-3 py-2">
                <p className="field-label">
                  <span className="ident">{c.key}</span> · {Math.round((c.key === 'R-1' ? share : 1 - share) * 100)}% of the increase
                </p>
                <p className="text-h2 text-ink-primary figures text-left">{usd0(inc[c.key])}</p>
                <p className="text-micro text-ink-tertiary">
                  +{((inc[c.key] / presentRevenue[c.key].total) * 100).toFixed(2)}% on {usd0(presentRevenue[c.key].total)} present revenue
                </p>
              </div>
            ))}
          </div>
          <p className="mt-3 text-micro text-ink-secondary">
            A class cost-of-service study would put residential near 84% of the cost to serve; the settlement moved part of that onto
            general service to limit the residential increase. Move the split and every target, rate and bill below follows.
          </p>
        </div>
      </Panel>

      <div className="flex justify-end">
        <Chip on={showDet} onClick={() => setShowDet(!showDet)}>
          Show billing determinants
        </Chip>
      </div>

      <div className="grid grid-cols-1 2xl:grid-cols-2 gap-5">
        {CLASSES.map((c) => (
          <ClassDesign
            key={c.key}
            showDet={showDet}
            klass={c.key}
            design={designs[c.key]}
            target={t[c.key]}
            onChange={(d) => setDesigns((all) => ({ ...all, [c.key]: d }))}
          />
        ))}
      </div>
    </div>
  )
}

function ClassDesign({
  klass,
  design,
  target,
  onChange,
  showDet,
}: {
  showDet: boolean
  klass: ClassKey
  design: Design
  target: number
  onChange: (d: Design) => void
}) {
  const c = CLASSES.find((x) => x.key === klass)!
  const now = presentRates[klass]
  const det = determinants[klass]
  const rev = revenue(klass, design)
  const pres = presentRevenue[klass]
  const gap = rev.total - target
  const ok = Math.abs(gap) <= TOLERANCE
  const fixedNow = pres.customer / pres.total
  const fixedNext = rev.customer / rev.total

  const rows: { key: keyof Design; label: string; unit: string; step: number; det: number }[] = [
    { key: 'cc', label: 'Customer charge', unit: '/month', step: 0.25, det: det.bills },
    { key: 'r1', label: `Distribution, first ${c.blockLimit} th`, unit: '/therm', step: 0.0005, det: det.block1 },
    { key: 'r2', label: `Distribution, over ${c.blockLimit} th`, unit: '/therm', step: 0.0005, det: det.block2 },
  ]

  return (
    <Panel>
      <PanelHeader
        title={
          <>
            <span className="ident">{klass}</span> · {c.name}
          </>
        }
        meta={`Target ${usd0(target)}`}
        actions={ok ? <StateFlag tone="cleared">Balanced</StateFlag> : <StateFlag tone="warning">{gap > 0 ? 'Over' : 'Short'} by {usd0(Math.abs(gap))}</StateFlag>}
      />
      <table className="w-full text-data">
        <thead>
          <tr className="border-b border-rule-solid">
            {['Rate', 'Present', 'Proposed', 'Change', ...(showDet ? ['Determinant'] : []), 'Revenue'].map((h, i) => (
              <th key={h} className={`field-label bg-surface-sunken px-cell-x py-2 ${i ? 'text-right' : 'text-left'}`}>
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => {
            const a = now[r.key]
            const b = design[r.key]
            const diff = b - a
            const money = r.key === 'cc'
            return (
              <tr key={r.key} className="border-b border-rule-hair">
                <td className="px-cell-x py-1.5">
                  <p className="text-ink-primary">{r.label}</p>
                  <p className="ident text-ink-tertiary">{c.codes[rows.indexOf(r)]}</p>
                </td>
                <td className="px-cell-x py-1.5 figures text-ink-secondary">{money ? usd2(a) : fmtRate(a)}</td>
                <td className="px-cell-x py-1.5 text-right">
                  <label htmlFor={`${klass}-${r.key}`} className="sr-only">
                    {r.label} proposed
                  </label>
                  <input
                    id={`${klass}-${r.key}`}
                    type="number"
                    step={r.step}
                    min={0}
                    value={b}
                    onChange={(e) => onChange({ ...design, [r.key]: Number(e.target.value) })}
                    className="w-24 rounded-sm border border-rule-solid bg-surface-raised px-2 py-1 text-right text-data text-ink-primary"
                  />
                </td>
                <td className={`px-cell-x py-1.5 figures ${Math.abs(diff) < 1e-9 ? 'text-ink-tertiary' : diff > 0 ? 'text-exception-warning-text' : 'text-money-credit'}`}>
                  {Math.abs(diff) < 1e-9 ? '—' : `${diff > 0 ? '+' : '−'}${money ? usd2(Math.abs(diff)) : fmtRate(Math.abs(diff))}`}
                </td>
                {showDet ? (
                  <td className="px-cell-x py-1.5 figures text-ink-tertiary text-micro">
                    {count(r.det)} {r.key === 'cc' ? 'bills' : 'th'}
                  </td>
                ) : null}
                <td className="px-cell-x py-1.5 figures text-ink-primary">
                  {usd0(r.key === 'cc' ? rev.customer : r.key === 'r1' ? rev.block1 : rev.block2)}
                </td>
              </tr>
            )
          })}
          <tr className="bg-surface">
            <td className="px-cell-x py-2 font-medium text-ink-primary" colSpan={showDet ? 5 : 4}>
              Revenue at proposed rates{' '}
              <span className="text-micro font-normal text-ink-tertiary">· present {usd0(pres.total)}</span>
            </td>
            <td className="px-cell-x py-2 figures font-medium text-ink-primary">{usd0(rev.total)}</td>
          </tr>
        </tbody>
      </table>

      <div className="px-4 py-3 border-t border-rule-hair">
        <p className="field-label mb-1.5">Fixed-charge recovery</p>
        <div className="space-y-1">
          <Recovery label="Present" share={fixedNow} />
          <Recovery label="Proposed" share={fixedNext} />
        </div>
        <p className="mt-1.5 text-micro text-ink-tertiary">
          The share of base revenue collected through the customer charge. Higher is steadier revenue for the utility and a larger
          increase for low-use customers — the trade-off a commission asks about first.
        </p>
      </div>

      <div className="flex flex-wrap items-center gap-2 border-t border-rule-hair bg-surface px-4 py-3">
        <Button variant="primary" onClick={() => onChange(solveVolumetric(klass, target, design.cc))} title="Hold the customer charge; scale both blocks to the target">
          Solve volumetric rates
        </Button>
        <Button onClick={() => onChange(solveCustomerCharge(klass, target, design))} title="Hold the volumetric rates; solve the customer charge">
          Solve customer charge
        </Button>
        <Button variant="quiet" onClick={() => onChange(settledDesigns[klass])}>
          Settlement rates
        </Button>
        <span className="ml-auto text-micro text-ink-tertiary">
          Rates print to four decimals, so a solved design lands within a few hundred dollars of target, not on it.
        </span>
      </div>
    </Panel>
  )
}

function Recovery({ label, share }: { label: string; share: number }) {
  return (
    <div className="flex items-center gap-3">
      <span className="w-16 shrink-0 text-micro text-ink-secondary">{label}</span>
      <span className="relative h-3 flex-1 rounded-xs bg-surface-inset">
        <span className="absolute inset-y-0 left-0 rounded-xs bg-rule-heavy" style={{ width: `${share * 100}%` }} />
      </span>
      <span className="w-12 shrink-0 text-right figures text-micro text-ink-primary">{(share * 100).toFixed(1)}%</span>
    </div>
  )
}


