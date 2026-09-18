import Link from 'next/link'
import { notFound } from 'next/navigation'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { Button, Field, FieldGrid, Panel, PanelHeader } from '@/components/ui/Panel'
import { Rail, StateBlock, StateFlag, invoiceTone, humanize } from '@/components/ui/State'
import { Money, Quantity } from '@/components/ui/Money'
import { Table, HeadRow, Th, Row, Td, RailCell } from '@/components/table/Table'
import { customers, customerById, locationById, meterById, serviceLinks } from '@/fixtures/accounts'
import { readings } from '@/fixtures/reads'
import { invoices } from '@/fixtures/billing'
import { exceptions } from '@/fixtures/exceptions'
import { customerName } from '@/schemas/models'
import { date, dateShort, money } from '@/lib/format'

/**
 * Customer 360 — the CSR's ninety seconds.
 *
 * "Why is my bill so high" is the call, and it spikes in January. Everything
 * needed to answer it is on one screen: the account, the premise, the meter,
 * the bills, the ledger, and the usage-against-temperature overlay that lets a
 * CSR walk the customer through the answer rather than argue about it.
 */

export function generateStaticParams() {
  return customers.map((c) => ({ customerId: c.id }))
}

/**
 * Thirteen bill periods of billed therms against heating degree days.
 *
 * The x-axis is labelled with READ DATES, not month names. Gas bill periods run
 * 28–33 days and wobble by a few days with the route schedule, so HDD has to be
 * computed over each actual read window — labelling these "Feb" would quietly
 * assert a calendar month that was never billed.
 */
const USAGE_HISTORY = [
  { readDate: '2025-02-12', therms: 142, hdd: 441, estimated: false },
  { readDate: '2025-03-13', therms: 88, hdd: 291, estimated: false },
  { readDate: '2025-04-11', therms: 49, hdd: 132, estimated: false },
  { readDate: '2025-05-13', therms: 31, hdd: 38, estimated: false },
  { readDate: '2025-06-12', therms: 22, hdd: 2, estimated: false },
  { readDate: '2025-07-14', therms: 20, hdd: 0, estimated: true },
  { readDate: '2025-08-12', therms: 21, hdd: 0, estimated: false },
  { readDate: '2025-09-11', therms: 24, hdd: 9, estimated: false },
  { readDate: '2025-10-14', therms: 44, hdd: 96, estimated: false },
  { readDate: '2025-11-12', therms: 97, hdd: 322, estimated: false },
  { readDate: '2025-12-11', therms: 158, hdd: 486, estimated: false },
  { readDate: '2026-01-13', therms: 171, hdd: 529, estimated: false },
  { readDate: '2026-02-12', therms: 226, hdd: 612, estimated: false },
]

/**
 * Therms per heating degree day — the number that actually answers "why is my
 * bill so high." It separates "it was colder" from "your house changed," which
 * is the distinction the customer is really asking about.
 */
function thermsPerHdd(therms: number, hdd: number): number | null {
  return hdd > 0 ? therms / hdd : null
}

export default async function CustomerPage({
  params,
}: PageProps<'/customers/[customerId]'>) {
  const { customerId } = await params
  const customer = customerById.get(customerId)
  if (!customer) notFound()

  const link = serviceLinks.find((l) => l.customerId === customer.id)
  const location = link ? locationById.get(link.locationId) : undefined
  const meter = link ? meterById.get(link.meterId) : undefined
  const read = readings.find((r) => r.meter_id === link?.meterId)
  const bills = invoices.filter((i) => i.customer_id === customer.id)
  const openOnAccount = exceptions.filter(
    (e) => e.customer_id === customer.id && e.status !== 'resolved',
  )

  return (
    <AppShell current="Accounts">
      <PageHeader
        title={customerName(customer)}
        meta={
          <>
            <span className="ident">{customer.customer_number}</span> ·{' '}
            {humanize(customer.customer_type)} · customer since {date(customer.move_in_date)}
          </>
        }
        actions={
          <>
            <Button>Log interaction</Button>
            <Button>Take payment</Button>
            <Button variant="primary">New service order</Button>
          </>
        }
      />

      {/* Protections and holds come first. A CSR must never miss these. */}
      {(customer.do_not_disconnect || customer.billing_hold) && (
        <div className="px-5 py-3 border-b border-rule-solid bg-surface space-y-2">
          {customer.do_not_disconnect ? (
            <StateBlock tone="critical">
              <p className="text-data text-ink-primary">
                <strong className="font-semibold">Do not disconnect.</strong>{' '}
                {humanize(customer.disconnect_protection_type ?? '')} on file, expires{' '}
                {date(customer.disconnect_protection_expiry)}. Collections activity on this account
                is suspended until then.
              </p>
            </StateBlock>
          ) : null}
          {customer.billing_hold ? (
            <StateBlock tone="held">
              <p className="text-data text-ink-primary">
                <strong className="font-semibold">Billing hold.</strong>{' '}
                {customer.billing_hold_reason}
              </p>
            </StateBlock>
          ) : null}
        </div>
      )}

      <div className="flex-1 overflow-auto">
        <div className="px-5 py-5 space-y-5">
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-5">
            <Panel className="lg:col-span-2">
              <PanelHeader title="Account" />
              <div className="px-4 py-4">
                <FieldGrid cols={4}>
                  <Field label="Status">
                    <StateFlag tone={customer.status === 'active' ? 'approved' : 'failed'}>
                      {humanize(customer.status)}
                    </StateFlag>
                  </Field>
                  <Field label="Balance">
                    <Money value={customer.balance} arrears={customer.status === 'collections'} />
                  </Field>
                  <Field label="Deposit held">
                    <Money value={customer.deposit_amount} />
                  </Field>
                  <Field label="Tax exempt">{customer.is_tax_exempt ? 'Yes' : 'No'}</Field>
                  <Field label="Phone">{customer.phone ?? '—'}</Field>
                  <Field label="Email">{customer.email ?? '—'}</Field>
                  <Field label="Premise">
                    {location ? (
                      <>
                        {location.address}
                        <br />
                        <span className="text-ink-secondary">
                          {location.city}, {location.state} {location.zip}
                        </span>
                      </>
                    ) : (
                      '—'
                    )}
                  </Field>
                  <Field
                    label="Franchise city"
                    hint={
                      location?.inside_city_limits
                        ? 'Inside city limits — franchise fee applies'
                        : 'Outside city limits — no franchise fee'
                    }
                  >
                    {location?.franchise_city ?? 'None'}
                  </Field>
                </FieldGrid>
              </div>
            </Panel>

            <Panel>
              <PanelHeader title="Meter" meta={meter?.route_id ?? undefined} />
              <div className="px-4 py-4">
                <FieldGrid cols={2}>
                  <Field label="Meter">
                    <span className="ident">{meter?.meter_number ?? '—'}</span>
                  </Field>
                  <Field label="Read type">{humanize(meter?.read_type ?? '')}</Field>
                  <Field label="Multiplier">{meter?.multiplier ?? '—'}</Field>
                  <Field label="BTU factor">{meter?.gas_btu_factor ?? '—'}</Field>
                  <Field label="Last read">{read ? date(read.reading_date) : '—'}</Field>
                  <Field
                    label="Estimates in a row"
                    hint={
                      (meter?.consecutive_estimate_count ?? 0) >= 3
                        ? 'At the Texas cap'
                        : undefined
                    }
                  >
                    <span
                      className={
                        (meter?.consecutive_estimate_count ?? 0) >= 3
                          ? 'text-exception-critical-text font-medium'
                          : ''
                      }
                    >
                      {meter?.consecutive_estimate_count ?? 0}
                    </span>
                  </Field>
                </FieldGrid>
              </div>
            </Panel>
          </div>

          {/* The de-escalation prop. Usage against the weather that drove it. */}
          <Panel>
            <PanelHeader
              title="Usage and weather"
              meta="Billed therms against heating degree days · 13 bill periods"
            />
            <UsageChart />
          </Panel>

          {openOnAccount.length > 0 ? (
            <Panel>
              <PanelHeader
                title="Open exceptions"
                meta={`${openOnAccount.length} on this account`}
              />
              <ul className="divide-y divide-rule-hair">
                {openOnAccount.map((e) => (
                  <li key={e.id} className="flex items-baseline gap-3 px-4 py-2.5">
                    <StateFlag tone={e.severity === 'critical' ? 'critical' : 'warning'}>
                      {e.severity}
                    </StateFlag>
                    <span className="text-data text-ink-primary">{e.description}</span>
                    <Link href="/" className="ml-auto text-micro text-accent-text underline">
                      Open in queue
                    </Link>
                  </li>
                ))}
              </ul>
            </Panel>
          ) : null}

          <Panel>
            <PanelHeader title="Bills" meta="Void bills stay on the account permanently" />
            <Table caption="Bills issued to this account">
              <thead>
                <HeadRow>
                  <Th width="3px"> </Th>
                  <Th>Invoice</Th>
                  <Th>Period</Th>
                  <Th>Issued</Th>
                  <Th>Due</Th>
                  <Th align="right">Amount</Th>
                  <Th align="right">Balance</Th>
                  <Th>Status</Th>
                </HeadRow>
              </thead>
              <tbody>
                {bills.map((inv) => {
                  const tone = inv.held_at ? 'held' : invoiceTone(inv.status)
                  const voided = inv.status === 'void'
                  return (
                    <Row key={inv.id} muted={voided}>
                      <RailCell>
                        <Rail tone={tone} />
                      </RailCell>
                      <Td>
                        <Link
                          href={`/invoices/${inv.id}`}
                          className={`ident underline ${voided ? 'struck' : 'text-accent-text hover:text-accent-text-hover'}`}
                        >
                          {inv.invoice_number}
                        </Link>
                        {inv.replaces_invoice_id ? (
                          <p className="text-micro text-ink-tertiary">correction</p>
                        ) : null}
                      </Td>
                      <Td>{inv.billing_period}</Td>
                      <Td>{dateShort(inv.invoice_date)}</Td>
                      <Td>{dateShort(inv.due_date)}</Td>
                      <Td align="right">
                        <Money value={inv.amount_due} />
                      </Td>
                      <Td align="right">
                        <Money value={inv.balance} />
                      </Td>
                      <Td>
                        <StateFlag tone={tone}>{humanize(inv.status)}</StateFlag>
                      </Td>
                    </Row>
                  )
                })}
              </tbody>
            </Table>
          </Panel>
        </div>
      </div>
    </AppShell>
  )
}

/**
 * Usage against the weather that drove it.
 *
 * The CSR's de-escalation prop: when a customer sees consumption track heating
 * degree days, the call usually ends. Gas load slopes up to the LEFT — colder
 * means more — which is the opposite of an electric summer peak, so the copy
 * must never be borrowed from an electric template.
 */
function UsageChart() {
  const maxTherms = Math.max(...USAGE_HISTORY.map((d) => d.therms))
  const maxHdd = Math.max(...USAGE_HISTORY.map((d) => d.hdd))
  const width = 760
  const height = 150
  const step = width / USAGE_HISTORY.length

  const current = USAGE_HISTORY[USAGE_HISTORY.length - 1]
  const yearAgo = USAGE_HISTORY[0]
  const nowRatio = thermsPerHdd(current.therms, current.hdd)
  const thenRatio = thermsPerHdd(yearAgo.therms, yearAgo.hdd)
  const efficiency =
    nowRatio && thenRatio ? Math.round(((thenRatio - nowRatio) / thenRatio) * 100) : null

  const linePoints = USAGE_HISTORY.map((d, i) => {
    const x = i * step + step / 2
    const y = height - (d.hdd / maxHdd) * height * 0.9
    return `${x},${y}`
  }).join(' ')

  return (
    <div>
      {/* The headline insight, in therms per degree day. */}
      <div className="border-b border-rule-hair px-4 py-3">
        <p className="text-body text-ink-primary">
          This bill: <strong className="font-semibold">{current.therms} therms</strong> over{' '}
          <strong className="font-semibold">{current.hdd} HDD</strong> ={' '}
          <span className="figures">{nowRatio?.toFixed(2)}</span> therms/HDD. Same period last year:{' '}
          {yearAgo.therms} over {yearAgo.hdd} ={' '}
          <span className="figures">{thenRatio?.toFixed(2)}</span>.
        </p>
        {efficiency !== null ? (
          <p className="text-data text-ink-secondary mt-1 leading-relaxed">
            {efficiency > 0 ? (
              <>
                This home used <strong className="font-semibold">{efficiency}% less</strong> gas per
                degree of heating need than a year ago. The bill is higher because it was colder, not
                because the home got less efficient.
              </>
            ) : (
              <>
                Consumption is up {Math.round(((current.therms - yearAgo.therms) / yearAgo.therms) * 100)}%,
                and it was {Math.round(((current.hdd - yearAgo.hdd) / yearAgo.hdd) * 100)}% colder —
                but the home also used{' '}
                <strong className="font-semibold">{Math.abs(efficiency)}% more</strong> gas per degree
                of heating need. Weather explains most of this bill; it does not explain all of it,
                which is why the exception is still open.
              </>
            )}
          </p>
        ) : null}
      </div>

      <div className="px-4 py-4">
        <svg
          viewBox={`0 0 ${width} ${height + 28}`}
          className="w-full h-44"
          role="img"
          aria-label="Billed therms per bill period shown against heating degree days for the same read window"
        >
          <defs>
            {/* Estimated periods are hatched — never silently identical to actual. */}
            <pattern id="estimated" width="6" height="6" patternTransform="rotate(45)" patternUnits="userSpaceOnUse">
              <rect width="6" height="6" className="fill-read-estimated-wash" />
              <line x1="0" y1="0" x2="0" y2="6" strokeWidth="3" className="stroke-read-estimated-rail" />
            </pattern>
          </defs>

          {USAGE_HISTORY.map((d, i) => {
            const h = (d.therms / maxTherms) * height * 0.9
            const latest = i === USAGE_HISTORY.length - 1
            return (
              <g key={d.readDate}>
                <rect
                  x={i * step + step * 0.18}
                  y={height - h}
                  width={step * 0.64}
                  height={h}
                  fill={d.estimated ? 'url(#estimated)' : undefined}
                  className={
                    d.estimated
                      ? ''
                      : latest
                        ? 'fill-exception-warning-rail'
                        : 'fill-surface-inset'
                  }
                />
                {d.estimated ? (
                  <text
                    x={i * step + step / 2}
                    y={height - h - 4}
                    textAnchor="middle"
                    className="fill-read-estimated-text font-semibold"
                    style={{ fontSize: '9px' }}
                  >
                    E
                  </text>
                ) : null}
              </g>
            )
          })}

          <polyline
            points={linePoints}
            fill="none"
            strokeWidth={1.5}
            className="stroke-exception-info-rail"
          />

          {USAGE_HISTORY.map((d, i) =>
            i % 2 === 0 || i === USAGE_HISTORY.length - 1 ? (
              <text
                key={d.readDate}
                x={i * step + step / 2}
                y={height + 18}
                textAnchor="middle"
                className="fill-ink-tertiary"
                style={{ fontSize: '9px' }}
              >
                {dateShort(d.readDate)}
              </text>
            ) : null,
          )}
        </svg>

        <div className="flex items-center gap-5 mt-2 flex-wrap">
          <span className="flex items-center gap-1.5 text-micro text-ink-secondary">
            <span className="inline-block h-2.5 w-2.5 bg-exception-warning-rail" /> Billed therms
          </span>
          <span className="flex items-center gap-1.5 text-micro text-ink-secondary">
            <span className="inline-block h-0.5 w-4 bg-exception-info-rail" /> Heating degree days
          </span>
          <span className="flex items-center gap-1.5 text-micro text-ink-secondary">
            <span className="inline-block h-2.5 w-2.5 border border-read-estimated-rail bg-read-estimated-wash" />{' '}
            Estimated read
          </span>
          <span className="text-micro text-ink-tertiary ml-auto">
            Labelled by read date — bill periods run 28–33 days, so HDD is computed per read window
          </span>
        </div>
      </div>
    </div>
  )
}
