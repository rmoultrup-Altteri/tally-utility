'use client'

import { Fragment, useMemo, useState, type ReactNode } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import { CLASSES, presentRates, rateCase, type ClassKey } from '@/fixtures/rate-case'
import { templateById, type Lang } from '@/fixtures/templates'
import { tenant } from '@/fixtures/tenant'
import {
  TEST_YEAR,
  TYPICAL_USAGE,
  averageCustomer,
  billAt,
  changedItems,
  currentPga,
  determinants,
  januaryImpact,
  presentRevenue,
  revenue,
  revenueRequirement,
  targets,
  type Designs,
} from '@/lib/rate-case'
import { contextFor, longDate } from '@/lib/templates'
import { useTemplate } from '@/lib/templates-store'
import { useAccess } from '@/lib/access'
import { activeUserName } from '@/lib/session'
import { MessagePreview } from '@/components/communications/MessagePreview'
import { Panel, PanelHeader, Button } from '@/components/ui/Panel'
import { StateBlock, StateFlag } from '@/components/ui/State'
import { Chip, Group } from '@/components/ui/Chip'
import { count, date, rate as fmtRate } from '@/lib/format'
import { CheckRow, TOLERANCE, usd0, usd2 } from '@/components/rate-case/shared'

const c2 = (cents: number) => usd2(cents / 100)
const signedC = (cents: number) => `${cents < 0 ? '−' : '+'}${c2(Math.abs(cents))}`

/* ---- Step 3: bill impacts ---------------------------------------------- */

const BUCKETS = [
  { label: 'down', test: (d: number) => d < -50 },
  { label: 'within ±$0.50', test: (d: number) => d >= -50 && d <= 50 },
  { label: '+$0.50 to $2', test: (d: number) => d > 50 && d < 200 },
  { label: '+$2 to $5', test: (d: number) => d >= 200 && d < 500 },
  { label: '+$5 to $10', test: (d: number) => d >= 500 && d < 1000 },
  { label: 'up over $10', test: (d: number) => d >= 1000 },
]

export function BillImpacts({ designs }: { designs: Designs }) {
  const [klass, setKlass] = useState<ClassKey>('R-1')
  const d = designs[klass]
  const now = presentRates[klass]
  const avg = useMemo(() => averageCustomer(klass, d), [klass, d])
  const jan = useMemo(() => januaryImpact(klass, d), [klass, d])
  const buckets = BUCKETS.map((b) => ({ label: b.label, n: jan.deltas.filter(b.test).length }))
  const peak = Math.max(...buckets.map((b) => b.n), 1)
  const up = jan.deltas.filter((x) => x > 0).length
  const n = jan.deltas.length
  const pctUp = (x: number) => `${((x / n) * 100).toFixed(1)}%`
  const avgPct = avg.present ? ((avg.proposed - avg.present) / avg.present) * 100 : 0
  const franchise = Math.round((revenue(klass, d).total - presentRevenue[klass].total) * 0.04)
  const medianPct = [...jan.pcts].sort((a, b) => a - b)[Math.floor(n / 2)] * 100

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between gap-3">
        <Group label="Schedule">
          {CLASSES.map((c) => (
            <Chip key={c.key} on={klass === c.key} onClick={() => setKlass(c.key)}>
              {c.key} · {c.name}
            </Chip>
          ))}
        </Group>
        <p className="text-micro text-ink-tertiary">
          Whole bills: gas cost at today’s {fmtRate(currentPga)} PGA, riders and taxes included; weather adjustment excluded.
        </p>
      </div>

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-px overflow-clip rounded-md bg-rule-hair border border-rule-hair shadow-panel">
        <Stat label="Average customer, a month" sub={`${count(Math.round(avg.annualTherms))} therms a year`}>
          {signedC(avg.monthlyChange)}
        </Stat>
        <Stat label="Average annual bill" sub={`${c2(avg.present)} today`}>
          {c2(avg.proposed)}
        </Stat>
        <Stat label="Whole-bill increase" sub="Average customer, all twelve months">
          +{avgPct.toFixed(1)}%
        </Stat>
        <Stat label={`January bills that rise`} sub={`Median +${medianPct.toFixed(1)}% · ${count(n)} accounts in cycle 04`}>
          {pctUp(up)}
        </Stat>
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-2 gap-5">
        <Panel>
          <PanelHeader title="Typical bills" meta="Schedule D · one month at each usage" />
          <table className="w-full text-data">
            <thead>
              <tr className="border-b border-rule-solid">
                {['Therms', 'Present', 'Proposed', 'Change', '%'].map((h, i) => (
                  <th key={h} className={`field-label bg-surface-sunken px-cell-x py-2 ${i ? 'text-right' : 'text-left'}`}>
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {TYPICAL_USAGE[klass].map((t) => {
                const a = billAt(klass, t, now).total
                const b = billAt(klass, t, d).total
                return (
                  <tr key={t} className="border-b border-rule-hair">
                    <td className="px-cell-x py-1.5 figures text-left text-ink-primary">{count(t)}</td>
                    <td className="px-cell-x py-1.5 figures text-ink-secondary">{c2(a)}</td>
                    <td className="px-cell-x py-1.5 figures text-ink-primary">{c2(b)}</td>
                    <td className={`px-cell-x py-1.5 figures ${b > a ? 'text-exception-warning-text' : 'text-money-credit'}`}>{signedC(b - a)}</td>
                    <td className="px-cell-x py-1.5 figures text-ink-tertiary">{a ? `${(((b - a) / a) * 100).toFixed(1)}%` : '—'}</td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </Panel>

        <Panel>
          <PanelHeader title="Distribution of January bills" meta={`${count(n)} accounts · one winter cycle of actual volumes`} />
          <div className="px-4 py-4 space-y-1.5">
            {buckets.map((b) => (
              <div key={b.label} className="flex items-center gap-3">
                <span className="w-28 shrink-0 text-right text-micro text-ink-secondary">{b.label}</span>
                <span className="h-5 flex-1 rounded-xs bg-surface-inset">
                  <span
                    className={`block h-full rounded-xs ${b.label === 'down' ? 'bg-exception-cleared-rail' : b.label.startsWith('within') ? 'bg-exception-snoozed-rail' : 'bg-exception-warning-rail'}`}
                    style={{ width: `${(b.n / peak) * 100}%` }}
                  />
                </span>
                <span className="w-14 shrink-0 figures text-data text-ink-primary">{count(b.n)}</span>
                <span className="w-12 shrink-0 text-right text-micro text-ink-tertiary">{pctUp(b.n)}</span>
              </div>
            ))}
          </div>
          <p className="border-t border-rule-hair px-4 py-3 text-micro text-ink-secondary">
            {jan.breakEven !== null
              ? `Break-even at ${jan.breakEven} therms: customers below it pay more, above it pay less, because the design moves recovery onto the customer charge.`
              : 'Every bill rises — the design raises the customer charge and the volumetric rates together, so there is no break-even. Low-use customers see the largest percentage change.'}
          </p>
        </Panel>
      </div>

      <Panel>
        <PanelHeader title="What the rehearsal checked" meta="Including the checks that found nothing" />
        <div className="divide-y divide-rule-hair">
          <CheckRow
            tone={jan.zeroUsage !== 0 ? 'warning' : 'cleared'}
            title="Zero-usage accounts"
            finding={
              jan.zeroUsage !== 0
                ? `${count(jan.sample.filter((t) => t === 0).length)} accounts drew no gas in January and still move by ${c2(jan.zeroUsage)} a month, because the customer charge moves.`
                : 'Accounts with no usage are unaffected — the customer charge did not move.'
            }
          />
          <CheckRow
            tone="warning"
            title="City franchise revenue"
            finding={`Franchise fees are 4% of charges, so the cities’ receipts rise about ${usd0(franchise)} a year with this schedule. Worth a word with Bryan, College Station and Navasota before the order, not after.`}
          />
          <CheckRow
            tone={avgPct > 10 ? 'critical' : 'cleared'}
            title="Rate shock"
            finding={
              avgPct > 10
                ? `The average whole bill rises ${avgPct.toFixed(1)}%. Above 10%, staff will ask about a phase-in.`
                : `The average whole bill rises ${avgPct.toFixed(1)}% — under the 10% that usually draws a phase-in question.`
            }
          />
          <CheckRow
            tone="info"
            title="Gas cost"
            finding={`Gas cost is a pass-through and is not part of the case. These bills use today’s ${fmtRate(currentPga)} PGA so the totals look like real bills; a change in the PGA moves both columns equally.`}
          />
        </div>
      </Panel>
    </div>
  )
}

/* ---- Step 4: the filing package ---------------------------------------- */

type Exhibit = 'A' | 'B' | 'C' | 'D' | 'E' | 'notice'

const EXHIBITS: { key: Exhibit; title: string; detail: string }[] = [
  { key: 'A', title: 'Schedule A — Revenue requirement', detail: 'Cost of service and the increase' },
  { key: 'B', title: 'Schedule B — Billing determinants', detail: 'Test-year bills and therms, by month' },
  { key: 'C', title: 'Schedule C — Proof of revenue', detail: 'Determinants × present and proposed rates' },
  { key: 'D', title: 'Schedule D — Typical bills', detail: 'Present and proposed, by usage' },
  { key: 'E', title: 'Schedule E — Tariff sheets, redlined', detail: 'Rate schedules R-1 and G-1' },
  { key: 'notice', title: 'Customer notice', detail: 'From the communications library' },
]

export function FilingPackage({ designs, share }: { designs: Designs; share: number }) {
  const [ex, setEx] = useState<Exhibit>('C')
  const [lang, setLang] = useState<Lang>('en')
  const avg = averageCustomer('R-1', designs['R-1'])
  const notice = templateById.get('rate-change-notice')!
  const { content } = useTemplate(notice)
  const ctx = useMemo(
    () =>
      contextFor('cus-0001', lang, {
        'rate.effective_date': longDate(rateCase.effectiveDate, lang),
        'rate.typical_change': c2(avg.monthlyChange),
        'rate.docket': rateCase.docket,
      }),
    [lang, avg.monthlyChange],
  )

  return (
    <div className="grid grid-cols-1 xl:grid-cols-[18rem_minmax(0,1fr)] gap-5">
      <Panel>
        <PanelHeader title="Filing package" meta="Generated from the bills" />
        <ul className="divide-y divide-rule-hair">
          {EXHIBITS.map((e) => (
            <li key={e.key}>
              <button
                type="button"
                onClick={() => setEx(e.key)}
                className={`w-full px-4 py-2.5 text-left ${ex === e.key ? 'bg-accent-wash' : 'hover:bg-surface-sunken'}`}
              >
                <p className={`text-data ${ex === e.key ? 'text-accent-text font-medium' : 'text-ink-primary'}`}>{e.title}</p>
                <p className="text-micro text-ink-tertiary">{e.detail}</p>
              </button>
            </li>
          ))}
        </ul>
        <div className="border-t border-rule-hair px-4 py-3 space-y-2">
          <Button variant="primary" disabled title="PDF and Excel export arrive with the API">
            Export filing package
          </Button>
          <p className="text-micro text-ink-tertiary">
            Every figure is live: change the allocation or a rate and the schedules, the redline and the notice follow.
          </p>
        </div>
      </Panel>

      <div className="min-w-0 bg-surface-sunken rounded-md border border-rule-hair p-5 flex justify-center">
        {ex === 'notice' ? (
          <div className="w-full max-w-[8.5in] space-y-3">
            <div className="flex items-center justify-between gap-3">
              <Group label="Language">
                <Chip on={lang === 'en'} onClick={() => setLang('en')}>
                  English
                </Chip>
                <Chip on={lang === 'es'} onClick={() => setLang('es')}>
                  Español
                </Chip>
              </Group>
              <Link href={'/communications/rate-change-notice' as Route} className="text-micro text-accent-text underline">
                Edit the notice template
              </Link>
            </div>
            {content.letter?.[lang] ? (
              <MessagePreview
                template={notice}
                channel="letter"
                lang={lang}
                content={content.letter[lang]!}
                ctx={ctx}
                to={{ name: 'Marisol Herrera', email: null, phone: null, address: '1418 Ashburn St, Bryan, TX 77803' }}
              />
            ) : null}
            <p className="text-micro text-ink-tertiary">
              The typical change — {c2(avg.monthlyChange)} a month — is the average residential customer’s, across the whole test year,
              computed above. Change the design and the notice changes with it.
            </p>
          </div>
        ) : (
          <Sheet title={EXHIBITS.find((e) => e.key === ex)!.title}>
            {ex === 'A' ? <ScheduleA /> : null}
            {ex === 'B' ? <ScheduleB /> : null}
            {ex === 'C' ? <ScheduleC designs={designs} share={share} /> : null}
            {ex === 'D' ? <ScheduleD designs={designs} /> : null}
            {ex === 'E' ? <ScheduleE designs={designs} /> : null}
          </Sheet>
        )}
      </div>
    </div>
  )
}

/** An exhibit page: the same white stock and serif as the bill, because it is the same kind of object. */
function Sheet({ title, children }: { title: string; children: ReactNode }) {
  return (
    <article className="stock w-full max-w-[8.5in] border border-rule-solid px-9 py-8 text-doc" style={{ fontFamily: 'var(--font-doc)' }}>
      <header className="flex items-start justify-between gap-6 border-b-2 border-rule-doc pb-3 mb-4">
        <div>
          <p className="text-[9pt] opacity-70">{tenant.name}</p>
          <h3 className="text-doc-h font-semibold">{title}</h3>
        </div>
        <div className="text-right text-[9pt] opacity-70">
          <p>{rateCase.docket}</p>
          <p>{rateCase.testYear}</p>
        </div>
      </header>
      {children}
      <p className="mt-6 border-t border-rule-hair pt-2 text-[8pt] opacity-60">
        Prepared from the system of record. Figures are computed from issued bills and the rates proposed in this filing.
      </p>
    </article>
  )
}

const T = ({ children }: { children: ReactNode }) => <table className="w-full tabular-nums">{children}</table>
const H = ({ cols }: { cols: string[] }) => (
  <thead>
    <tr className="border-b border-rule-doc">
      {cols.map((c, i) => (
        <th key={c} className={`py-1 font-semibold ${i ? 'text-right' : 'text-left'}`}>
          {c}
        </th>
      ))}
    </tr>
  </thead>
)
const R = ({ cells, total = false }: { cells: ReactNode[]; total?: boolean }) => (
  <tr className={total ? 'rule-total' : 'border-b border-rule-hair'}>
    {cells.map((c, i) => (
      <td key={i} className={`py-1 ${i ? 'text-right' : ''} ${total ? 'font-semibold' : ''}`}>
        {c}
      </td>
    ))}
  </tr>
)

function ScheduleA() {
  const rr = revenueRequirement()
  return (
    <T>
      <H cols={['', 'Test year']} />
      <tbody>
        {rr.rows.map((r) => (
          <R key={r.label} cells={[r.label, usd0(r.amount)]} />
        ))}
        <R cells={['Total cost of service', usd0(rr.costOfService)]} />
        <R cells={['Less other operating revenue', `(${usd0(rr.otherRevenue)})`]} />
        <R cells={['Base-rate revenue requirement', usd0(rr.requirement)]} />
        <R cells={['Revenue at present rates', usd0(rr.present)]} />
        <R total cells={['Revenue deficiency', usd0(rr.increase)]} />
      </tbody>
    </T>
  )
}

function ScheduleB() {
  return (
    <T>
      <H cols={['Bill month', 'R-1 bills', 'R-1 therms', 'G-1 bills', 'G-1 therms']} />
      <tbody>
        {TEST_YEAR.map((m, i) => {
          const r = determinants['R-1'].months[i]
          const g = determinants['G-1'].months[i]
          return <R key={m} cells={[m, count(r.bills), count(r.block1 + r.block2), count(g.bills), count(g.block1 + g.block2)]} />
        })}
        <R
          total
          cells={[
            'Test year',
            count(determinants['R-1'].bills),
            count(determinants['R-1'].therms),
            count(determinants['G-1'].bills),
            count(determinants['G-1'].therms),
          ]}
        />
      </tbody>
    </T>
  )
}

function ScheduleC({ designs, share }: { designs: Designs; share: number }) {
  const t = targets(share)
  return (
    <T>
      <H cols={['Schedule / component', 'Units', 'Present rate', 'Present revenue', 'Proposed rate', 'Proposed revenue']} />
      <tbody>
        {CLASSES.map((c) => {
          const det = determinants[c.key]
          const a = presentRates[c.key]
          const b = designs[c.key]
          const ra = presentRevenue[c.key]
          const rb = revenue(c.key, b)
          return (
            <Fragment key={c.key}>
              <tr>
                <td colSpan={6} className="pt-3 pb-1 font-semibold">
                  {c.key} — {c.name}
                </td>
              </tr>
              <R cells={['Customer charge', `${count(det.bills)} bills`, usd2(a.cc), usd0(ra.customer), usd2(b.cc), usd0(rb.customer)]} />
              <R cells={[`First ${c.blockLimit} therms`, `${count(det.block1)} th`, fmtRate(a.r1), usd0(ra.block1), fmtRate(b.r1), usd0(rb.block1)]} />
              <R cells={[`Over ${c.blockLimit} therms`, `${count(det.block2)} th`, fmtRate(a.r2), usd0(ra.block2), fmtRate(b.r2), usd0(rb.block2)]} />
              <R cells={[`Total ${c.key}`, '', '', usd0(ra.total), `target ${usd0(t[c.key])}`, usd0(rb.total)]} />
            </Fragment>
          )
        })}
        <R
          total
          cells={[
            'System',
            '',
            '',
            usd0(presentRevenue['R-1'].total + presentRevenue['G-1'].total),
            `+${usd0(revenue('R-1', designs['R-1']).total + revenue('G-1', designs['G-1']).total - presentRevenue['R-1'].total - presentRevenue['G-1'].total)}`,
            usd0(revenue('R-1', designs['R-1']).total + revenue('G-1', designs['G-1']).total),
          ]}
        />
      </tbody>
    </T>
  )
}

function ScheduleD({ designs }: { designs: Designs }) {
  return (
    <>
      {CLASSES.map((c) => (
        <div key={c.key} className="mb-5">
          <p className="font-semibold mb-1">
            {c.key} — {c.name}
          </p>
          <T>
            <H cols={['Therms / month', 'Present bill', 'Proposed bill', 'Change', 'Percent']} />
            <tbody>
              {TYPICAL_USAGE[c.key].map((t) => {
                const a = billAt(c.key, t, presentRates[c.key]).total
                const b = billAt(c.key, t, designs[c.key]).total
                return <R key={t} cells={[count(t), c2(a), c2(b), signedC(b - a), a ? `${(((b - a) / a) * 100).toFixed(1)}%` : '—']} />
              })}
            </tbody>
          </T>
        </div>
      ))}
      <p className="text-[9pt] opacity-70">
        Bills include gas cost at {fmtRate(currentPga)} per therm, the pipeline safety fee, the GRIP rider, and franchise fees and taxes
        for a customer inside Bryan city limits. The weather normalization adjustment is excluded.
      </p>
    </>
  )
}

function ScheduleE({ designs }: { designs: Designs }) {
  return (
    <>
      {CLASSES.map((c) => {
        const a = presentRates[c.key]
        const b = designs[c.key]
        const line = (label: string, from: string, to: string, unit: string) => (
          <p className="py-1 border-b border-rule-hair flex justify-between gap-6">
            <span>{label}</span>
            <span className="tabular-nums">
              {from !== to ? (
                <>
                  <del className="opacity-60">{from}</del>{' '}
                  <ins className="underline decoration-2 underline-offset-2">{to}</ins>
                </>
              ) : (
                from
              )}{' '}
              {unit}
            </span>
          </p>
        )
        return (
          <section key={c.key} className="mb-6">
            <p className="font-semibold">
              Rate Schedule {c.key} — {c.name}
            </p>
            <p className="text-[9pt] opacity-70 mb-2">Effective for bills rendered on and after {date(rateCase.effectiveDate)}.</p>
            {line('Customer charge', usd2(a.cc), usd2(b.cc), 'per month')}
            {line(`Distribution charge, first ${c.blockLimit} therms`, fmtRate(a.r1), fmtRate(b.r1), 'per therm')}
            {line(`Distribution charge, over ${c.blockLimit} therms`, fmtRate(a.r2), fmtRate(b.r2), 'per therm')}
            <p className="mt-2 text-[9pt] opacity-70">
              Purchased gas adjustment, weather normalization adjustment, GRIP and the pipeline safety fee apply as provided in their
              own riders and are unchanged by this filing.
            </p>
          </section>
        )
      })}
    </>
  )
}

/* ---- Step 5: implement -------------------------------------------------- */

export function Implement({ designs, balanced }: { designs: Designs; balanced: boolean }) {
  const { can } = useAccess()
  const [effective, setEffective] = useState<string>(rateCase.effectiveDate)
  const [reason, setReason] = useState('Rates per settlement in RRC GUD-11042')
  const [submitted, setSubmitted] = useState<{ by: string; at: string } | null>(null)
  const items = changedItems(designs)
  const order = rateCase.milestones.find((m) => m.key === 'order')!
  const firstOfMonth = effective.endsWith('-01')
  const afterOrder = effective > order.date
  const ok = balanced && firstOfMonth && afterOrder && reason.trim().length >= 12 && can('rate.edit')

  return (
    <div className="space-y-5">
      <StateBlock tone={order.done ? 'cleared' : 'pending'}>
        <p className="text-data text-ink-primary">
          <strong className="font-semibold">
            {order.done ? 'The final order is recorded.' : `The final order is expected ${date(order.date)}.`}
          </strong>{' '}
          Stage the rate versions now; they are approved by a second person and post as ordinary date-effective versions — each closes the
          standing rate and inserts its successor with the docket and the reason, so every bill already issued still reproduces against
          the rates that priced it.
        </p>
      </StateBlock>

      <Panel>
        <PanelHeader title="Rate versions to create" meta={`${items.length} items across ${CLASSES.length} schedules`} />
        <table className="w-full text-data">
          <thead>
            <tr className="border-b border-rule-solid">
              {['Schedule', 'Rate item', 'Standing', 'New', 'Effective'].map((h, i) => (
                <th key={h} className={`field-label bg-surface-sunken px-cell-x py-2 ${i >= 2 ? 'text-right' : 'text-left'}`}>
                  {h}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {items.map((it) => (
              <tr key={it.code} className="border-b border-rule-hair">
                <td className="px-cell-x py-1.5">
                  <span className="ident">{it.klass}</span>
                </td>
                <td className="px-cell-x py-1.5">
                  <p className="text-ink-primary">{it.label}</p>
                  <p className="ident text-ink-tertiary">{it.code}</p>
                </td>
                <td className="px-cell-x py-1.5 figures">
                  <span className="struck">{it.unit === 'month' ? usd2(it.from) : fmtRate(it.from)}</span>
                </td>
                <td className="px-cell-x py-1.5 figures text-ink-primary font-medium">{it.unit === 'month' ? usd2(it.to) : fmtRate(it.to)}</td>
                <td className="px-cell-x py-1.5 figures text-ink-secondary">{date(effective)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </Panel>

      <Panel>
        <PanelHeader title="Before it posts" />
        <div className="divide-y divide-rule-hair">
          <CheckRow tone={balanced ? 'cleared' : 'critical'} title="Proof of revenue" finding={balanced ? `Each schedule collects its target within ${usd0(TOLERANCE)}.` : 'A schedule is off its target — balance it in Allocation and rate design.'} />
          <CheckRow
            tone={firstOfMonth ? 'cleared' : 'critical'}
            title="Effective date"
            finding={firstOfMonth ? `${date(effective)} starts a billing month, so no bill straddles the change.` : `${date(effective)} falls mid-month; cycles crossing it would bill in two prorated segments.`}
          />
          <CheckRow
            tone={afterOrder ? 'cleared' : 'critical'}
            title="After the order"
            finding={afterOrder ? `After the expected order date, ${date(order.date)}.` : 'Rates cannot take effect before the Commission orders them.'}
          />
          <CheckRow tone="cleared" title="Customer notice" finding={`Mailed ${date(rateCase.milestones.find((m) => m.key === 'notice')!.date)} in English and Spanish, from the communications library.`} />
          <CheckRow tone="info" title="Two people" finding="The person who stages the rates cannot approve them. A billing supervisor approves." />
        </div>
      </Panel>

      <Panel>
        <div className="px-4 py-4 grid grid-cols-1 md:grid-cols-3 gap-4">
          <div>
            <label htmlFor="rc-eff" className="field-label mb-1 block">
              Effective from
            </label>
            <input
              id="rc-eff"
              type="date"
              value={effective}
              onChange={(e) => setEffective(e.target.value)}
              className="w-full rounded-sm border border-rule-solid bg-surface-raised px-2 py-1 text-data text-ink-primary"
            />
          </div>
          <div className="md:col-span-2">
            <label htmlFor="rc-reason" className="field-label mb-1 block">
              Change reason — recorded on every version
            </label>
            <input
              id="rc-reason"
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              className="w-full rounded-sm border border-rule-solid bg-surface-raised px-2 py-1 text-data text-ink-primary"
            />
          </div>
        </div>
        <div className="flex items-center justify-between gap-4 border-t border-rule-hair bg-surface px-4 py-3">
          {submitted ? (
            <p className="text-data text-exception-cleared-text">
              Staged by {submitted.by}, {date(submitted.at.slice(0, 10))} — waiting on a billing supervisor’s approval.
            </p>
          ) : (
            <p className="text-micro text-ink-secondary">{can('rate.edit') ? 'Nothing posts until a second person approves.' : 'Your role cannot edit rates.'}</p>
          )}
          <Button variant="primary" disabled={!ok || !!submitted} onClick={() => setSubmitted({ by: activeUserName(), at: new Date().toISOString() })}>
            Submit {items.length} versions for approval
          </Button>
        </div>
      </Panel>
    </div>
  )
}

function Stat({ label, sub, children }: { label: string; sub: string; children: ReactNode }) {
  return (
    <div className="bg-surface-raised px-4 py-3">
      <p className="field-label">{label}</p>
      <p className="text-figure text-ink-primary mt-1">{children}</p>
      <p className="text-micro text-ink-tertiary mt-0.5">{sub}</p>
    </div>
  )
}
