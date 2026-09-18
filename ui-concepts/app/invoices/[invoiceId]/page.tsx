import { Fragment } from 'react'
import Link from 'next/link'
import { notFound } from 'next/navigation'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { Button, Field, FieldGrid, Panel, PanelHeader } from '@/components/ui/Panel'
import { StateFlag, StateBlock, invoiceTone, humanize } from '@/components/ui/State'
import { Money, Nil } from '@/components/ui/Money'
import {
  invoiceById,
  invoices,
  linesByInvoiceId,
  runs,
} from '@/fixtures/billing'
import { customerById, locationById, serviceLinks, meterById } from '@/fixtures/accounts'
import { tenant } from '@/fixtures/tenant'
import { customerName, isIssued } from '@/schemas/models'
import type { Invoice, InvoiceLine } from '@/schemas/models'
import { date, money, rate as fmtRate, rateInUnit, factor, stamp, days } from '@/lib/format'

/**
 * The bill.
 *
 * Rendered as the artifact rather than as a representation of it: fixed
 * measure, print units, serif, square corners, accounting rules. The same
 * layout is what the customer receives in the mail, which is what makes CSR
 * phone support work — both parties are looking at the same object.
 *
 * The inspector rail beside it is the product's signature move. Every line
 * carries its full derivation — Ccf → meter factor → BTU factor → therms →
 * rate → amount — plus the rate version that priced it and the coordinate the
 * run resolved. No legacy CIS explains its own arithmetic.
 */

export function generateStaticParams() {
  return invoices.map((i) => ({ invoiceId: i.id }))
}

export default async function InvoicePage({
  params,
}: PageProps<'/invoices/[invoiceId]'>) {
  const { invoiceId } = await params
  const invoice = invoiceById.get(invoiceId)
  if (!invoice) notFound()

  const lines = linesByInvoiceId(invoice.id)
  const customer = customerById.get(invoice.customer_id)
  const location = locationById.get(invoice.location_id)
  const run = runs.find((r) => r.id === invoice.billing_run_id)
  const replaces = invoice.replaces_invoice_id
    ? invoiceById.get(invoice.replaces_invoice_id)
    : null
  const replacedBy = invoices.find((i) => i.replaces_invoice_id === invoice.id) ?? null
  const tone = invoiceTone(invoice.status)

  return (
    <AppShell current="Bills">
      <PageHeader
        title={<span className="ident text-h1">{invoice.invoice_number}</span>}
        meta={
          <>
            {customer ? customerName(customer) : '—'} · {invoice.billing_period} ·{' '}
            {date(invoice.period_start)} → {date(invoice.period_end)}
          </>
        }
        actions={
          <>
            <StateFlag tone={tone}>{humanize(invoice.status)}</StateFlag>
            <Button>Print</Button>
            {invoice.status === 'void' ? null : isIssued(invoice) ? (
              <Link href={`/invoices/${invoice.id}/rebill`}>
                <Button variant="danger">Void &amp; rebill</Button>
              </Link>
            ) : (
              <Button variant="primary">Issue</Button>
            )}
          </>
        }
      />

      {/* Lineage is chrome, not a badge. */}
      {(replaces || replacedBy || invoice.held_at) && (
        <div className="px-5 py-3 border-b border-rule-solid bg-surface space-y-2">
          {replaces ? (
            <StateBlock tone="superseded">
              <p className="text-data text-ink-primary">
                This correction replaces{' '}
                <Link
                  href={`/invoices/${replaces.id}`}
                  className="ident text-accent hover:text-accent-hover underline"
                >
                  {replaces.invoice_number}
                </Link>
                , voided {stamp(replaces.voided_at)} for{' '}
                <em>{humanize(replaces.void_reason_code ?? '')}</em>.{' '}
                <Link
                  href={`/invoices/${invoice.id}/diff`}
                  className="text-accent hover:text-accent-hover underline"
                >
                  Compare them
                </Link>
                .
              </p>
            </StateBlock>
          ) : null}

          {replacedBy ? (
            <StateBlock tone="void">
              <p className="text-data text-ink-primary">
                Superseded by{' '}
                <Link
                  href={`/invoices/${replacedBy.id}`}
                  className="ident text-accent hover:text-accent-hover underline"
                >
                  {replacedBy.invoice_number}
                </Link>
                .{' '}
                <Link
                  href={`/invoices/${replacedBy.id}/diff`}
                  className="text-accent hover:text-accent-hover underline"
                >
                  Compare them
                </Link>
                . Only one live rebill is permitted per lineage — void that correction before
                correcting again.
              </p>
            </StateBlock>
          ) : null}

          {invoice.held_at ? (
            <StateBlock tone="held">
              <p className="text-data text-ink-primary">
                <strong className="font-semibold">Held {stamp(invoice.held_at)}.</strong>{' '}
                {invoice.hold_reason}
              </p>
              <p className="text-micro text-ink-secondary mt-1">
                A person stopped this bill and a person must release it. It cannot be sent while the
                blocking exception stands.
              </p>
            </StateBlock>
          ) : null}
        </div>
      )}

      <div className="flex-1 min-h-0 grid grid-cols-1 xl:grid-cols-[minmax(0,1fr)_24rem] overflow-auto">
        <div className="min-w-0 p-6 flex justify-center bg-surface-sunken">
          <BillDocument
            invoice={invoice}
            lines={lines}
            customerLabel={customer ? customerName(customer) : '—'}
            addressLines={
              location
                ? [location.address, `${location.city}, ${location.state} ${location.zip}`]
                : []
            }
          />
        </div>

        <Inspector invoice={invoice} lines={lines} run={run} />
      </div>
    </AppShell>
  )
}

/** The printed object. Print units, serif, accounting rules, white stock. */
function BillDocument({
  invoice,
  lines,
  customerLabel,
  addressLines,
}: {
  invoice: Invoice
  lines: InvoiceLine[]
  customerLabel: string
  addressLines: string[]
}) {
  const voided = invoice.status === 'void'
  const groups = ['base_charges', 'usage_charges', 'adjustments', 'riders', 'taxes_fees'] as const
  const GROUP_LABEL: Record<string, string> = {
    base_charges: 'Base charges',
    usage_charges: 'Gas usage',
    adjustments: 'Adjustments',
    riders: 'Riders and surcharges',
    taxes_fees: 'Taxes and fees',
  }

  return (
    <article
      className="stock relative w-full max-w-[8.5in] border border-rule-solid px-10 py-9 text-doc"
      style={{ fontFamily: 'var(--font-doc)' }}
    >
      {voided ? (
        <div
          aria-hidden
          className="pointer-events-none absolute inset-0 flex items-center justify-center"
        >
          <span className="text-[7rem] font-bold tracking-[0.2em] text-state-void-text opacity-15 -rotate-12">
            VOID
          </span>
        </div>
      ) : null}

      <header className="flex items-start justify-between gap-8 pb-4 border-b-2 border-rule-doc">
        <div>
          <h2 className="text-doc-h font-semibold tracking-tight">{tenant.name}</h2>
          <p className="text-[9pt] leading-[13pt] opacity-70 mt-0.5">
            P.O. Box 1000 · Bryan, TX 77805
            <br />
            (979) 555-0100 · brazosvalleygas.example.com
          </p>
        </div>
        <div className="text-right">
          <p className="label-caps" style={{ fontFamily: 'var(--font-sans)' }}>
            Statement
          </p>
          <p className="ident text-[11pt] mt-0.5">{invoice.invoice_number}</p>
          <p className="text-[9pt] opacity-70 mt-1">Issued {date(invoice.invoice_date)}</p>
        </div>
      </header>

      <div className="grid grid-cols-2 gap-8 py-4 border-b border-rule-doc">
        <div>
          <p className="label-caps mb-1" style={{ fontFamily: 'var(--font-sans)' }}>
            Service to
          </p>
          <p className="font-semibold">{customerLabel}</p>
          {addressLines.map((l) => (
            <p key={l} className="opacity-80">
              {l}
            </p>
          ))}
        </div>
        <div className="text-right">
          <Line label="Service period">
            {date(invoice.period_start)} – {date(invoice.period_end)}
          </Line>
          <Line label="Days billed">{days(invoice.period_start, invoice.period_end)}</Line>
          <Line label="Payment due">{date(invoice.due_date)}</Line>
        </div>
      </div>

      <table className="w-full my-4">
        <thead>
          <tr className="border-b border-rule-doc">
            <th className="text-left py-1 font-semibold">Description</th>
            <th className="text-right py-1 font-semibold w-28">Quantity</th>
            <th className="text-right py-1 font-semibold w-28">Rate</th>
            <th className="text-right py-1 font-semibold w-24">Amount</th>
          </tr>
        </thead>
        <tbody>
          {groups.map((group) => {
            const groupLines = lines.filter((l) => l.display_group === group)
            if (groupLines.length === 0) return null
            return (
              <Fragment key={group}>
                <tr>
                  <td colSpan={4} className="pt-3 pb-1">
                    <span
                      className="label-caps"
                      style={{ fontFamily: 'var(--font-sans)' }}
                    >
                      {GROUP_LABEL[group]}
                    </span>
                  </td>
                </tr>
                {groupLines.map((l) => (
                  <tr key={l.id} className="border-b border-rule-hair">
                    <td className="py-1 pr-4">
                      {l.description}
                      {l.tier_label ? (
                        <span className="opacity-60 text-[9pt]"> · {l.tier_label}</span>
                      ) : null}
                    </td>
                    <td className="py-1 text-right tabular-nums">
                      {l.usage_quantity
                        ? `${Number(l.usage_quantity).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })} ${l.usage_unit ?? ''}`
                        : '—'}
                    </td>
                    <td className="py-1 text-right tabular-nums">
                      {l.rate ? rateInUnit(l.rate, lineRateUnit(l)) : '—'}
                    </td>
                    <td className="py-1 text-right tabular-nums">{money(l.amount)}</td>
                  </tr>
                ))}
              </Fragment>
            )
          })}
        </tbody>
      </table>

      <div className="flex justify-end">
        <table className="w-72">
          <tbody>
            <TotalRow label="Previous balance" value={invoice.previous_balance} />
            <TotalRow label="Current charges" value={invoice.total_charges} rule />
            <TotalRow label="Taxes and fees" value={invoice.total_taxes} />
            {Number(invoice.total_credits) !== 0 ? (
              <TotalRow label="Credits" value={invoice.total_credits} />
            ) : null}
            <tr className="rule-total">
              <td className="py-1.5 font-semibold">Amount due</td>
              <td className="py-1.5 text-right font-semibold tabular-nums">
                {money(invoice.amount_due)}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      {invoice.has_estimated_reads ? (
        <p className="mt-5 pt-3 border-t border-rule-hair text-[9pt] leading-[13pt] opacity-80">
          <strong>Estimated reading.</strong> {invoice.estimated_read_count} reading on this
          statement was estimated because the meter could not be accessed. Your next actual reading
          will true up the difference.
        </p>
      ) : null}

      <p className="mt-3 text-[8.5pt] leading-[12pt] opacity-70">
        Questions about this bill? Call (979) 555-0100 within 30 days. If you cannot pay in full,
        payment arrangements and energy assistance referrals are available — ask for the billing
        office. Service will not be disconnected for non-payment without written notice.
      </p>
    </article>
  )
}

/**
 * A franchise fee or tax line quotes a percentage of a base, not a per-unit
 * price. Showing 0.04 as $0.04000 on a bill a customer reads is simply wrong.
 */
function lineRateUnit(line: InvoiceLine): string | null {
  return line.charge_type === 'franchise_fee' || line.charge_type === 'tax' ? 'percent' : null
}

function Line({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <p className="flex justify-between gap-6">
      <span className="opacity-70">{label}</span>
      <span className="tabular-nums">{children}</span>
    </p>
  )
}

function TotalRow({
  label,
  value,
  rule = false,
}: {
  label: string
  value: string
  rule?: boolean
}) {
  return (
    <tr className={rule ? 'rule-subtotal' : ''}>
      <td className="py-1 opacity-80">{label}</td>
      <td className="py-1 text-right tabular-nums">{money(value)}</td>
    </tr>
  )
}

/**
 * The derivation rail. This is what a CSR reads aloud when a customer asks why
 * the bill doubled, and what an auditor reads when the PUC asks the same thing
 * three years later.
 */
function Inspector({
  invoice,
  lines,
  run,
}: {
  invoice: Invoice
  lines: InvoiceLine[]
  run: (typeof runs)[number] | undefined
}) {
  const gasLine = lines.find((l) => l.charge_type === 'pga') ?? lines[0]
  const link = serviceLinks.find((l) => l.locationId === invoice.location_id)
  const meter = link ? meterById.get(link.meterId) : undefined

  return (
    <aside className="min-w-0 border-l border-rule-solid bg-surface overflow-auto">
      {/* The pricing world, stated in words. Reproducibility is only worth
          something if the analyst can see which world they are standing in. */}
      {run ? (
        <div className="px-4 py-3 border-b border-rule-solid bg-surface-raised">
          <p className="label-caps mb-1.5">Pricing world</p>
          <p className="text-data text-ink-primary">
            {invoice.invoice_type === 'correction'
              ? `Priced with rates in effect ${date(run.valid_at)} — the original period.`
              : `Priced with rates in effect ${date(run.valid_at)}.`}
          </p>
          <p className="text-micro text-ink-tertiary mt-1">
            Coordinate resolved once for run{' '}
            <span className="ident">{run.run_number}</span> and passed to every rate lookup:
            valid at {date(run.valid_at)}, recorded at {stamp(run.recorded_at)}.
          </p>
        </div>
      ) : null}

      <div className="px-4 py-4 border-b border-rule-hair">
        <p className="label-caps mb-2">Derivation · {gasLine?.description}</p>
        {gasLine?.gas_ccf_used ? (
          <ol className="space-y-0 border-y border-rule-hair divide-y divide-rule-hair">
            <Step label="Metered volume" value={`${gasLine.gas_ccf_used} Ccf`} note="end read − start read" />
            <Step
              label="× Meter multiplier"
              value={factor(gasLine.gas_meter_factor ?? '1')}
              note={meter ? `meter ${meter.meter_number}` : undefined}
            />
            <Step
              label="× BTU factor"
              value={factor(gasLine.gas_btu_factor ?? '1')}
              note="zone heating value for the period"
            />
            <Step
              label="= Billed therms"
              value={`${gasLine.gas_therms_billed} th`}
              emphasis
            />
            <Step
              label="× Commodity rate"
              value={fmtRate(gasLine.gas_commodity_rate ?? gasLine.rate ?? '0')}
              note={gasLine.rate_item_code ?? undefined}
            />
            <Step label="= Amount" value={money(gasLine.amount)} emphasis />
          </ol>
        ) : (
          <Nil />
        )}
      </div>

      <div className="px-4 py-4 border-b border-rule-hair">
        <p className="label-caps mb-2">Line provenance</p>
        <FieldGrid cols={2}>
          <Field label="Rate schedule">
            <span className="ident">{gasLine?.rate_schedule_code ?? '—'}</span>
          </Field>
          <Field label="Rate item">
            <Link href="/rates" className="ident text-accent hover:text-accent-hover underline">
              {gasLine?.rate_item_code ?? '—'}
            </Link>
          </Field>
          <Field label="Coverage">
            {gasLine?.coverage_start ? (
              <>
                {date(gasLine.coverage_start)} → {date(gasLine.coverage_end)}
              </>
            ) : (
              '—'
            )}
          </Field>
          <Field label="Days covered">
            {gasLine?.days_covered} of {gasLine?.days_in_period}
          </Field>
        </FieldGrid>
      </div>

      <div className="px-4 py-4 border-b border-rule-hair">
        <p className="label-caps mb-2">Tax basis</p>
        <table className="w-full text-data">
          <tbody className="divide-y divide-rule-hair border-y border-rule-hair">
            {invoice.tax_breakdown.map((t) => (
              <tr key={t.label}>
                <td className="py-1.5 pr-3 text-ink-secondary text-micro">{t.label}</td>
                <td className="py-1.5 figures text-ink-tertiary text-micro">
                  {rateInUnit(t.rate, 'percent')}
                </td>
                <td className="py-1.5 figures">
                  <Money value={t.amount} />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {isIssued(invoice) ? (
        <div className="px-4 py-4">
          <p className="label-caps mb-2">Why there is no edit button</p>
          <p className="text-micro text-ink-secondary leading-relaxed">
            This bill was issued {stamp(invoice.first_issued_at)}. Its content is frozen — the
            database rejects any change to the amounts, dates or lines. A correction is a new
            document: void this bill, then rebill the same period through a correction run.
          </p>
        </div>
      ) : null}
    </aside>
  )
}

function Step({
  label,
  value,
  note,
  emphasis = false,
}: {
  label: string
  value: string
  note?: string
  emphasis?: boolean
}) {
  return (
    <li className="flex items-baseline justify-between gap-4 py-1.5">
      <div className="min-w-0">
        <p className={`text-data ${emphasis ? 'text-ink-primary font-medium' : 'text-ink-secondary'}`}>
          {label}
        </p>
        {note ? <p className="text-micro text-ink-tertiary">{note}</p> : null}
      </div>
      <span className={`figures ${emphasis ? 'text-ink-primary font-medium' : 'text-ink-secondary'}`}>
        {value}
      </span>
    </li>
  )
}
