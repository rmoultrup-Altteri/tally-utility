'use client'

import { Fragment } from 'react'
import { tenant } from '@/fixtures/tenant'
import type { Invoice, InvoiceLine } from '@/schemas/models'
import { date, days, money, rateInUnit } from '@/lib/format'
import { useInvoice } from '@/lib/edits-store'
/** The printed object. Print units, serif, accounting rules, white stock. */
export function BillDocument({
  invoice: base,
  lines,
  customerLabel,
  addressLines,
}: {
  invoice: Invoice
  lines: InvoiceLine[]
  customerLabel: string
  addressLines: string[]
}) {
  /* Dates on a draft can be edited before it is issued; read them as edited. */
  const invoice = useInvoice(base)
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
          <p className="field-label" style={{ fontFamily: 'var(--font-sans)' }}>
            Statement
          </p>
          <p className="ident text-[11pt] mt-0.5">{invoice.invoice_number}</p>
          <p className="text-[9pt] opacity-70 mt-1">Issued {date(invoice.invoice_date)}</p>
        </div>
      </header>

      <div className="grid grid-cols-2 gap-8 py-4 border-b border-rule-doc">
        <div>
          <p className="field-label mb-1" style={{ fontFamily: 'var(--font-sans)' }}>
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
                      className="field-label"
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
