'use client'

import { useState } from 'react'
import Link from 'next/link'
import type { Route } from 'next'
import {
  explanationCopy,
  formatCents,
  formatSigned,
  type Explanation,
  type Lang,
  type Basis,
} from '@/lib/bill-explain'
import { Waterfall } from '@/components/charts/Waterfall'
import { UsageWeather, type UsagePoint } from '@/components/charts/UsageWeather'
import { Panel, PanelHeader, Button } from '@/components/ui/Panel'
import { Collapsible } from '@/components/ui/Collapsible'
import { StateBlock, StateFlag } from '@/components/ui/State'
import { Chip, Group } from '@/components/ui/Chip'
import { money, rate as fmtRate } from '@/lib/format'
import { tenant } from '@/fixtures/tenant'

/**
 * The bill explanation, as the CSR works it.
 *
 * Left: the explanation in the customer's language, exactly as the portal
 * shows it, so the CSR and the caller are reading the same sentences. Right:
 * the arithmetic behind it and what to offer. Every figure on the left is a
 * step in an exact re-pricing — they add to the real difference to the cent,
 * which is what lets the CSR say "that's all of it" and be right.
 */

export type DriverTitle = Record<string, [string, string]>

/** Step labels for the bridge, in both languages, in the order the engine prices them. */
export const STEP_LABEL: DriverTitle = {
  weather: ['Weather', 'Clima'],
  usage: ['Usage beyond weather', 'Uso más allá del clima'],
  gas_cost: ['Gas cost', 'Costo del gas'],
  wna: ['Weather adjustment', 'Ajuste por clima'],
  rates: ['Rates and charges', 'Tarifas y cargos'],
  taxes: ['Taxes and fees', 'Impuestos y cuotas'],
  rounding: ['Rounding', 'Redondeo'],
}

export function bridgeSteps(e: Explanation, lang: Lang) {
  return e.drivers
    .filter((d) => d.cents !== 0)
    .map((d) => ({ label: STEP_LABEL[d.key][lang === 'es' ? 1 : 0], cents: d.cents }))
}

export function ExplainView({
  year,
  month,
  points,
  customerId,
  customerName: name,
  amountDue,
  previousBalance,
  budgetCents,
  invoiceId,
}: {
  year: Explanation | null
  month: Explanation | null
  points: { label: string; therms: number; hdd: number; estimated: boolean }[]
  customerId: string
  customerName: string
  amountDue: string
  previousBalance: string
  budgetCents: number
  invoiceId: string
}) {
  const [basis, setBasis] = useState<Basis>(year ? 'year' : 'month')
  const [lang, setLang] = useState<Lang>('en')
  const e = basis === 'year' ? year : month

  if (!e)
    return (
      <StateBlock tone="info">
        <p className="text-data text-ink-primary">
          There is no earlier bill on this account to compare with — the first bill after move-in has nothing to explain against.
        </p>
      </StateBlock>
    )

  const copy = explanationCopy(e, lang)
  const es = lang === 'es'
  const priorLabel = e.prior.billing_period
  const marked: UsagePoint[] = points.map((p) => ({
    ...p,
    mark: p.label === e.period ? 'current' : p.label === priorLabel ? 'compare' : undefined,
  }))
  const { prior: A, current: B } = e.sheets
  const prev = Number(previousBalance)

  return (
    <div className="grid grid-cols-1 xl:grid-cols-[minmax(0,1.25fr)_minmax(0,1fr)] gap-5">
      <div className="space-y-5 min-w-0">
        <Panel>
          <div className="flex flex-wrap items-center justify-between gap-3 border-b border-rule-hair px-4 py-2.5">
            <Group label="Compare with">
              <Chip on={basis === 'year'} onClick={() => setBasis('year')}>
                Same month last year
              </Chip>
              <Chip on={basis === 'month'} onClick={() => setBasis('month')}>
                Last month
              </Chip>
            </Group>
            <Group label="Language">
              <Chip on={lang === 'en'} onClick={() => setLang('en')}>
                English
              </Chip>
              <Chip on={lang === 'es'} onClick={() => setLang('es')}>
                Español
              </Chip>
            </Group>
          </div>
          <div className="px-5 py-5">
            <h2 className="text-h1 text-ink-primary">{copy.headline}</h2>
            <p className="mt-1.5 text-body text-ink-secondary">{copy.summary}</p>
            <div className="mt-5">
              <Waterfall
                start={{ label: es ? `${priorLabel} (antes)` : priorLabel, cents: e.priorCents }}
                steps={bridgeSteps(e, lang)}
                end={{ label: e.period, cents: e.currentCents }}
              />
            </div>
            <p className="mt-3 text-micro text-ink-tertiary">
              {es
                ? 'Cargos y impuestos del periodo; el saldo anterior no es parte del cambio.'
                : 'Charges and taxes for the period; any previous balance is not part of the change.'}
            </p>
          </div>
        </Panel>

        <Panel>
          <PanelHeader title="What to say" meta="A talk track — the caller sees the same explanation in the portal" />
          <ol className="list-decimal pl-9 pr-4 py-3 space-y-1.5 text-data text-ink-secondary">
            <li>
              “{explanationCopy(e, 'en').headline} {explanationCopy(e, 'en').summary.split('. ')[0]}.”
            </li>
            {e.weather.current && e.weather.prior && e.weather.current.hdd > e.weather.prior.hdd ? (
              <li>
                “It was {Math.round(((e.weather.current.hdd - e.weather.prior.hdd) / e.weather.prior.hdd) * 100)}% colder than{' '}
                {basis === 'year' ? 'last year' : 'last month'}, and gas heating follows the cold — your usage line tracks the
                weather line on the chart.”
              </li>
            ) : null}
            {e.usageFlag ? (
              <li>
                “Even allowing for the cold, you used about {Math.round(e.therms.beyondWeather)} therms more than usual. Has anything
                changed — thermostat, a new appliance, guests? We can send someone to do a free safety check.”
              </li>
            ) : null}
            <li>
              “If this bill is hard right now, budget billing would make it about {formatCents(budgetCents)} every month, or we can
              spread this one out.”
            </li>
          </ol>
        </Panel>

        <Collapsible
          title={es ? 'Cada causa, en palabras' : 'Each cause, in words'}
          n={copy.drivers.length}
          summary={es ? 'De mayor a menor — lo que el cliente lee en el portal' : 'Largest first — what the customer reads in the portal'}
        >
          <ul className="divide-y divide-rule-hair">
            {copy.drivers.map((d) => (
              <li key={d.key} className="flex items-start gap-4 px-4 py-3">
                <span
                  className={`w-24 shrink-0 text-right figures text-h3 ${d.cents > 0 ? 'text-exception-warning-text' : 'text-money-credit'}`}
                >
                  {formatSigned(d.cents)}
                </span>
                <div className="min-w-0">
                  <p className="text-data font-medium text-ink-primary">{d.title}</p>
                  <p className="text-data text-ink-secondary mt-0.5 leading-relaxed">{d.body}</p>
                </div>
              </li>
            ))}
          </ul>
        </Collapsible>
      </div>

      <div className="space-y-5 min-w-0">
        {prev > 0 ? (
          <StateBlock tone="warning">
            <p className="text-data text-ink-primary">
              <strong className="font-semibold">Amount due is {money(amountDue)}</strong> — it includes {money(prev)} still unpaid from
              the previous bill. That balance is not part of this change; say so before the caller adds it up.
            </p>
          </StateBlock>
        ) : null}


        <Panel>
          <PanelHeader title="What to offer" />
          <ul className="divide-y divide-rule-hair">
            <Offer
              title="Budget billing"
              detail={`About ${formatCents(budgetCents)} a month, from the last twelve bills, settled once a year.`}
              href="/communications/budget-billing-offer"
            />
            <Offer title="Payment arrangement" detail="Spread this bill over the next few without collection activity." href="/communications/payment-arrangement" />
            {e.usageFlag ? (
              <Offer
                title="Free safety check"
                detail={`${Math.round(e.therms.beyondWeather)} therms beyond the weather. Usually a thermostat or appliance; occasionally a leak.`}
                href="/communications/gas-safety"
                flag
              />
            ) : null}
            <Offer title="Energy assistance referral" detail="Local agencies; a pledge pauses collections while it is processed." href="/communications/cold-weather-protections" />
          </ul>
          <div className="flex flex-wrap gap-2 border-t border-rule-hair px-4 py-3">
            <Link href={`/portal/bills/${invoiceId}` as Route}>
              <Button>See the customer’s view</Button>
            </Link>
            <Link href={'/communications/bill-explained' as Route}>
              <Button>Email this explanation</Button>
            </Link>
            <Link href={`/customers/${customerId}` as Route}>
              <Button variant="quiet">{name}’s account</Button>
            </Link>
          </div>
          <p className="px-4 pb-3 text-micro text-ink-tertiary">
            Emergency line for anything that smells like gas: {tenant.emergencyPhone}.
          </p>
        </Panel>

        <Panel>
          <PanelHeader title="Usage and weather" meta={`${points.length} bill periods · zone heating degree days`} />
          <div className="px-4 py-4">
            <UsageWeather
              points={marked}
              labels={{ therms: 'Therms billed', hdd: 'Heating degree days', current: e.period, compare: priorLabel }}
            />
          </div>
        </Panel>

        <Collapsible title="Show the math" summary="Therms, degree days and every rate, both bills — one change at a time">
          <table className="w-full text-data">
            <thead>
              <tr className="border-b border-rule-solid">
                <th className="field-label bg-surface-sunken px-cell-x py-2 text-left"> </th>
                <th className="field-label bg-surface-sunken px-cell-x py-2 text-right">{priorLabel}</th>
                <th className="field-label bg-surface-sunken px-cell-x py-2 text-right">{e.period}</th>
              </tr>
            </thead>
            <tbody className="[&_td]:px-cell-x [&_td]:py-1.5 [&_tr]:border-b [&_tr]:border-rule-hair">
              <Line label="Therms billed" a={e.therms.prior.toFixed(2)} b={e.therms.current.toFixed(2)} />
              <Line label="… the weather alone predicts" a="" b={e.therms.expected.toFixed(2)} hint />
              <Line label="Heating degree days" a={String(e.weather.prior?.hdd ?? '—')} b={String(e.weather.current?.hdd ?? '—')} />
              <Line label="Normal degree days" a={String(e.weather.prior?.normal ?? '—')} b={String(e.weather.current?.normal ?? '—')} hint />
              <Line label="Base load (summer)" a={`${e.baseLoad.toFixed(1)} th`} b="" hint />
              <Line label="Gas cost (PGA) / th" a={fmtRate(A.pga)} b={fmtRate(B.pga)} />
              <Line label="Weather adjustment / th" a={A.wna ? fmtRate(A.wna) : '—'} b={B.wna ? fmtRate(B.wna) : '—'} />
              <Line label="Customer charge" a={money(A.customerCharge)} b={money(B.customerCharge)} />
              <Line label={`Distribution, first ${B.blockLimit} th`} a={fmtRate(A.block1)} b={fmtRate(B.block1)} />
              <Line label="Distribution, beyond" a={fmtRate(A.block2)} b={fmtRate(B.block2)} />
              <Line label="GRIP rider / th" a={A.grip ? fmtRate(A.grip) : '—'} b={B.grip ? fmtRate(B.grip) : '—'} />
              <Line label="Charges and taxes" a={formatCents(e.priorCents)} b={formatCents(e.currentCents)} strong />
            </tbody>
          </table>
          <p className="px-4 py-3 text-micro text-ink-secondary leading-relaxed">
            Starting from the {priorLabel} bill, the engine re-prices it at the volume the weather predicts, then at the volume
            used, then swaps in this period’s gas cost, weather adjustment, and each base rate in turn. Every step is priced line by
            line and rounded the way the biller writes lines, so the steps add to the real difference —{' '}
            <strong className="text-ink-primary font-semibold">{formatSigned(e.delta)}</strong> — to the cent. It reproduces every
            issued bill in the system exactly.
          </p>
        </Collapsible>
      </div>
    </div>
  )
}

function Line({ label, a, b, hint = false, strong = false }: { label: string; a: string; b: string; hint?: boolean; strong?: boolean }) {
  return (
    <tr>
      <td className={`${hint ? 'text-ink-tertiary text-micro' : 'text-ink-secondary'} ${strong ? 'font-medium text-ink-primary' : ''}`}>{label}</td>
      <td className={`figures ${strong ? 'font-medium text-ink-primary' : 'text-ink-secondary'}`}>{a}</td>
      <td className={`figures ${strong ? 'font-medium text-ink-primary' : 'text-ink-primary'}`}>{b}</td>
    </tr>
  )
}

function Offer({ title, detail, href, flag = false }: { title: string; detail: string; href: string; flag?: boolean }) {
  return (
    <li className="flex items-start justify-between gap-4 px-4 py-2.5">
      <div>
        <p className="text-data text-ink-primary flex items-center gap-2">
          {title}
          {flag ? <StateFlag tone="warning">Suggested</StateFlag> : null}
        </p>
        <p className="text-micro text-ink-secondary mt-0.5">{detail}</p>
      </div>
      <Link href={href as Route} className="shrink-0 text-micro text-accent-text underline">
        Letter
      </Link>
    </li>
  )
}
