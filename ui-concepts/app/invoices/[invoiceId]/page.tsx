import Link from 'next/link'
import type { Route } from 'next'
import { notFound } from 'next/navigation'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { BillDocument } from '@/components/bills/BillDocument'
import { EditInvoice, HoldNote, InvoiceEditedNote } from '@/components/bills/InvoiceEdit'
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
import { customerName, isIssued } from '@/schemas/models'
import type { Invoice, InvoiceLine } from '@/schemas/models'
import { date, money, rate as fmtRate, rateInUnit, factor, stamp } from '@/lib/format'

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
        back={{ href: '/invoices', label: 'Bills' }}
        title={<span className="ident text-h1">{invoice.invoice_number}</span>}
        meta={
          <>
            {customer ? customerName(customer) : '—'} · {invoice.billing_period} ·{' '}
            {date(invoice.period_start)} → {date(invoice.period_end)}
            <InvoiceEditedNote id={invoice.id} />
          </>
        }
        actions={
          <>
            <StateFlag tone={tone}>{humanize(invoice.status)}</StateFlag>
            <PayBill invoice={invoice} replacedById={replacedBy?.id ?? null} />
            <Button>Print</Button>
            {invoice.status === 'void' ? null : isIssued(invoice) ? (
              <Link href={`/invoices/${invoice.id}/rebill`}>
                <Button variant="danger">Void &amp; rebill</Button>
              </Link>
            ) : (
              <Button variant="primary">Issue</Button>
            )}
            <EditInvoice invoice={invoice} runNumber={run?.run_number ?? null} />
          </>
        }
      />

      {/* Lineage is chrome, not a badge. */}
      {(replaces || replacedBy || invoice.held_at) && (
        <div className="px-5 py-3 border-b border-rule-hair bg-surface space-y-2">
          {replaces ? (
            <StateBlock tone="superseded">
              <p className="text-data text-ink-primary">
                This correction replaces{' '}
                <Link
                  href={`/invoices/${replaces.id}`}
                  className="ident text-accent-text hover:text-accent-text-hover underline"
                >
                  {replaces.invoice_number}
                </Link>
                , voided {stamp(replaces.voided_at)} for{' '}
                <em>{humanize(replaces.void_reason_code ?? '')}</em>.{' '}
                <Link
                  href={`/invoices/${invoice.id}/diff`}
                  className="text-accent-text hover:text-accent-text-hover underline"
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
                  className="ident text-accent-text hover:text-accent-text-hover underline"
                >
                  {replacedBy.invoice_number}
                </Link>
                .{' '}
                <Link
                  href={`/invoices/${replacedBy.id}/diff`}
                  className="text-accent-text hover:text-accent-text-hover underline"
                >
                  Compare them
                </Link>
                . Only one live rebill is permitted per lineage — void that correction before
                correcting again.
              </p>
            </StateBlock>
          ) : null}

          <HoldNote invoice={invoice} />
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

/** Why this bill cannot take a payment, or null when it can. */
function unpayableBecause(invoice: Invoice, replacedById: string | null): string | null {
  if (invoice.status === 'void') return replacedById ? 'Void — pay the bill that replaced it' : 'Void — nothing is owed on it'
  if (invoice.status === 'write_off') return 'Written off'
  if (invoice.status === 'held') return 'Held — it must be released and sent before it can be paid'
  if (!isIssued(invoice)) return 'Not issued yet — nothing is owed until the bill is sent'
  if (Number(invoice.balance) <= 0) return 'Paid in full'
  return null
}

/**
 * Take a payment against this bill. Opens the add-payment page with the
 * account found and this bill first in line. Only an issued, live bill with
 * money owing can be paid; otherwise the button stays and says why not.
 */
function PayBill({ invoice, replacedById }: { invoice: Invoice; replacedById: string | null }) {
  const why = unpayableBecause(invoice, replacedById)
  if (why) return <Button disabled title={why}>Pay bill</Button>
  return (
    <Link href={`/payments/new?invoice=${invoice.id}` as Route}>
      <Button variant="primary" title={`Take a payment — ${money(invoice.balance)} open`}>
        Pay bill · {money(invoice.balance)}
      </Button>
    </Link>
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
          <p className="field-label mb-1.5">Pricing world</p>
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
        <p className="field-label mb-2">Derivation · {gasLine?.description}</p>
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
        <p className="field-label mb-2">Line provenance</p>
        <FieldGrid cols={2}>
          <Field label="Rate schedule">
            <span className="ident">{gasLine?.rate_schedule_code ?? '—'}</span>
          </Field>
          <Field label="Rate item">
            <Link href="/rates" className="ident text-accent-text hover:text-accent-text-hover underline">
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
        <p className="field-label mb-2">Tax basis</p>
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
          <p className="field-label mb-2">Why there is no edit button</p>
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
