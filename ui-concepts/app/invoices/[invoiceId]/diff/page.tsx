import Link from 'next/link'
import { notFound } from 'next/navigation'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { Button, Panel, PanelHeader } from '@/components/ui/Panel'
import { StateBlock, StateFlag } from '@/components/ui/State'
import { Money } from '@/components/ui/Money'
import {
  inputSets,
  invoiceById,
  invoices,
  linesByInvoiceId,
  runs,
} from '@/fixtures/billing'
import type { PricingInput } from '@/fixtures/billing'
import { customerById } from '@/fixtures/accounts'
import { customerName } from '@/schemas/models'
import type { Invoice, InvoiceLine } from '@/schemas/models'
import { date, money, rateInUnit, stamp } from '@/lib/format'

/**
 * The correction diff.
 *
 * Every billing analyst in this market carries the same scar: a cancel-rebill
 * that produced a wrong number because the system priced a historical period
 * with today's rates. This screen is aimed directly at it.
 *
 * Two things have to be visible at once. First, the line-by-line delta, so the
 * money is explicit and balanced — the other half of the same fear is the
 * orphan GL transaction that audit finds a year later. Second, the *input set*
 * behind each side, every value with the date it was effective and the instant
 * it was recorded. That pair is what actually proves the rebill used the
 * original period's world, and it is the one claim a generic billing UI
 * cannot fake.
 */

export function generateStaticParams() {
  return invoices
    .filter((i) => i.replaces_invoice_id !== null)
    .map((i) => ({ invoiceId: i.id }))
}

export default async function DiffPage({ params }: PageProps<'/invoices/[invoiceId]/diff'>) {
  const { invoiceId } = await params
  const rebill = invoiceById.get(invoiceId)
  if (!rebill || !rebill.replaces_invoice_id) notFound()

  const original = invoiceById.get(rebill.replaces_invoice_id)
  if (!original) notFound()

  const customer = customerById.get(rebill.customer_id)
  const run = runs.find((r) => r.id === rebill.billing_run_id)

  const originalLines = linesByInvoiceId(original.id)
  const rebillLines = linesByInvoiceId(rebill.id)
  const delta = Number(rebill.amount_due) - Number(original.amount_due)

  /* Pair lines by rate item so a changed charge sits next to its predecessor. */
  /* Pair lines by rate item so a changed charge sits next to its predecessor. */
  const codes = [...new Set([...originalLines, ...rebillLines].map((l) => l.rate_item_code))]
  const pairs = codes.map((code) => ({
    code,
    before: originalLines.find((l) => l.rate_item_code === code) ?? null,
    after: rebillLines.find((l) => l.rate_item_code === code) ?? null,
  }))

  return (
    <AppShell current="Bills">
      <PageHeader
        title="Correction diff"
        meta={
          <>
            {customer ? customerName(customer) : '—'} · {original.billing_period} ·{' '}
            {date(original.period_start)} → {date(original.period_end)}
          </>
        }
        actions={
          <>
            <Link href={`/invoices/${rebill.id}`}>
              <Button variant="quiet">Open rebill</Button>
            </Link>
            <Button>Send replacement notice</Button>
          </>
        }
      />

      <div className="flex-1 overflow-auto">
        <div className="px-5 py-5 space-y-5">
          {/* The money, stated plainly and balanced. */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-px bg-rule-solid border border-rule-solid">
            <Side
              label="Voided original"
              invoice={original}
              tone="void"
              href={`/invoices/${original.id}`}
            />
            <Side
              label="Replacement"
              invoice={rebill}
              tone="approved"
              href={`/invoices/${rebill.id}`}
            />
            <div className="bg-surface-raised px-4 py-3">
              <p className="label-caps">Net adjustment to the account</p>
              <p className="text-figure mt-1">
                <Money value={String(delta)} />
              </p>
              <p className="text-micro text-ink-tertiary mt-1">
                {delta < 0 ? 'Credit to' : 'Additional charge to'} the customer. Posted to the
                ledger as an offsetting transaction — the original entry is never removed.
              </p>
            </div>
          </div>

          {run ? (
            <StateBlock tone="info">
              <p className="text-data text-ink-primary">
                This rebill was priced with rates in effect{' '}
                <strong className="font-semibold">{date(run.valid_at)}</strong> — the original
                service period, not today. The operator elected{' '}
                <em>historical</em> before the run, and that election is recorded against the
                correction target.
              </p>
            </StateBlock>
          ) : null}

          <Panel>
            <PanelHeader
              title="Line-by-line"
              meta="Unchanged lines are dimmed. The commodity rate moved; the franchise fee follows it, because it is a percentage of charges"
            />
            <div className="overflow-x-auto">
              <table className="w-full text-data">
                <caption className="sr-only">
                  Original and replacement invoice lines compared, with the amount difference
                </caption>
                <thead>
                  <tr className="border-b border-rule-heavy">
                    <th className="label-caps px-cell-x py-1.5 text-left">Charge</th>
                    <th className="label-caps px-cell-x py-1.5 text-right border-l border-rule-solid">
                      Original rate
                    </th>
                    <th className="label-caps px-cell-x py-1.5 text-right">Original amount</th>
                    <th className="label-caps px-cell-x py-1.5 text-right border-l border-rule-solid">
                      Rebill rate
                    </th>
                    <th className="label-caps px-cell-x py-1.5 text-right">Rebill amount</th>
                    <th className="label-caps px-cell-x py-1.5 text-right border-l border-rule-solid">
                      Difference
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {pairs.map(({ code, before, after }) => {
                    const changed = before?.amount !== after?.amount
                    const lineDelta = Number(after?.amount ?? 0) - Number(before?.amount ?? 0)
                    return (
                      <tr
                        key={code}
                        className={`border-b border-rule-hair ${
                          changed ? 'bg-exception-warning-wash' : 'bg-surface-raised opacity-70'
                        }`}
                      >
                        <td className="px-cell-x py-cell-y-compact">
                          <p className="text-ink-primary">
                            {after?.description ?? before?.description}
                          </p>
                          <p className="ident text-ink-tertiary">{code}</p>
                        </td>
                        <td className="px-cell-x py-cell-y-compact figures border-l border-rule-solid text-ink-secondary">
                          {before?.rate ? rateInUnit(before.rate, lineRateUnit(before)) : '—'}
                        </td>
                        <td className="px-cell-x py-cell-y-compact figures">
                          {before ? money(before.amount) : '—'}
                        </td>
                        <td className="px-cell-x py-cell-y-compact figures border-l border-rule-solid text-ink-secondary">
                          {after?.rate ? rateInUnit(after.rate, lineRateUnit(after)) : '—'}
                        </td>
                        <td className="px-cell-x py-cell-y-compact figures">
                          {after ? money(after.amount) : '—'}
                        </td>
                        <td className="px-cell-x py-cell-y-compact figures border-l border-rule-solid">
                          {changed ? (
                            <Money value={String(lineDelta)} />
                          ) : (
                            <>
                            <span aria-hidden className="text-ink-muted">·</span>
                            <span className="sr-only">No change</span>
                          </>
                          )}
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
                <tfoot>
                  <tr className="border-t-2 border-rule-heavy bg-surface-raised">
                    <td className="px-cell-x py-2 font-semibold text-ink-primary">Amount due</td>
                    <td className="border-l border-rule-solid" />
                    <td className="px-cell-x py-2 figures font-semibold">
                      {money(original.amount_due)}
                    </td>
                    <td className="border-l border-rule-solid" />
                    <td className="px-cell-x py-2 figures font-semibold">
                      {money(rebill.amount_due)}
                    </td>
                    <td className="px-cell-x py-2 figures font-semibold border-l border-rule-solid">
                      <Money value={String(delta)} />
                    </td>
                  </tr>
                </tfoot>
              </table>
            </div>
          </Panel>

          {/* The proof. Two input sets, side by side, each value dated twice. */}
          <Panel>
            <PanelHeader
              title="Input set behind each bill"
              meta="What each run actually resolved — valid time and transaction time"
            />
            <div className="grid grid-cols-1 md:grid-cols-2 divide-y md:divide-y-0 md:divide-x divide-rule-solid">
              <InputSet
                title="Voided original"
                inputs={inputSets[original.id] ?? []}
                compareTo={inputSets[rebill.id] ?? []}
              />
              <InputSet
                title="Replacement"
                inputs={inputSets[rebill.id] ?? []}
                compareTo={inputSets[original.id] ?? []}
              />
            </div>
            <div className="border-t border-rule-solid px-4 py-3">
              <p className="text-micro text-ink-secondary leading-relaxed">
                Only one input differs. The January PGA factor was recorded on 16 Feb — six weeks
                after the period it applies to — so the original run could not have seen it and
                priced the period with December&rsquo;s factor instead. The rebill, run after the
                factor was recorded, resolves the same valid-time coordinate to a different value.
                That is the entire correction.
              </p>
            </div>
          </Panel>

          <Panel>
            <PanelHeader title="Before this can post" />
            <ul className="divide-y divide-rule-hair">
              <Check done label="Backbilling cap" detail="Texas 12-month look-back — period is 1 month old" />
              <Check done label="Void reason recorded" detail="Wrong rate, with notes, by D. Pearce" />
              <Check done label="Rate-date election recorded" detail="Historical, elected before the run" />
              <Check done label="Ledger balanced" detail="Offsetting entry posted; no orphan transaction" />
              <Check label="Supervisor approval" detail="Required for corrections over $50.00" />
              <Check label="Replacement notice sent" detail="Regulated language: this bill replaces the bill dated 16 Jan 2026" />
            </ul>
          </Panel>
        </div>
      </div>
    </AppShell>
  )
}

function lineRateUnit(line: InvoiceLine): string | null {
  return line.charge_type === 'franchise_fee' || line.charge_type === 'tax' ? 'percent' : null
}

function Side({
  label,
  invoice,
  tone,
  href,
}: {
  label: string
  invoice: Invoice
  tone: 'void' | 'approved'
  href: string
}) {
  return (
    <div className="bg-surface-raised px-4 py-3">
      <div className="flex items-center justify-between gap-2">
        <p className="label-caps">{label}</p>
        <StateFlag tone={tone}>{invoice.status}</StateFlag>
      </div>
      <p className="text-figure mt-1">{money(invoice.amount_due)}</p>
      <Link
        href={href as never}
        className="ident text-accent-text hover:text-accent-text-hover underline mt-1 inline-block"
      >
        {invoice.invoice_number}
      </Link>
      <p className="text-micro text-ink-tertiary mt-0.5">
        {invoice.voided_at ? `Voided ${stamp(invoice.voided_at)}` : `Issued ${stamp(invoice.first_issued_at)}`}
      </p>
    </div>
  )
}

function InputSet({
  title,
  inputs,
  compareTo,
}: {
  title: string
  inputs: PricingInput[]
  compareTo: PricingInput[]
}) {
  return (
    <div className="px-4 py-4">
      <p className="label-caps mb-2">{title}</p>
      <dl className="divide-y divide-rule-hair border-y border-rule-hair">
        {inputs.map((input) => {
          const other = compareTo.find((c) => c.label === input.label)
          const differs = other && other.value !== input.value
          return (
            <div
              key={input.label}
              className={`py-2 ${differs ? 'bg-exception-warning-wash -mx-4 px-4' : ''}`}
            >
              <div className="flex items-baseline justify-between gap-4">
                <dt className="text-micro text-ink-secondary">{input.label}</dt>
                <dd
                  className={`text-data figures ${
                    differs ? 'text-exception-warning-text font-medium' : 'text-ink-primary'
                  }`}
                >
                  {input.value}
                </dd>
              </div>
              <p className="text-micro text-ink-tertiary mt-0.5">
                effective {date(input.effectiveFrom)} · recorded {stamp(input.recordedAt)}
              </p>
            </div>
          )
        })}
      </dl>
    </div>
  )
}

function Check({
  label,
  detail,
  done = false,
}: {
  label: string
  detail: string
  done?: boolean
}) {
  return (
    <li className="flex items-baseline gap-3 px-4 py-2.5">
      <span
        className={`ident flex h-4 w-4 shrink-0 items-center justify-center rounded-xs ${
          done
            ? 'bg-exception-cleared-wash text-exception-cleared-text'
            : 'bg-surface-inset text-ink-tertiary'
        }`}
        aria-label={done ? 'Complete' : 'Outstanding'}
      >
        {done ? '✓' : ''}
      </span>
      <span className={`text-data ${done ? 'text-ink-primary' : 'text-ink-secondary'}`}>
        {label}
      </span>
      <span className="text-micro text-ink-tertiary ml-auto text-right">{detail}</span>
    </li>
  )
}
