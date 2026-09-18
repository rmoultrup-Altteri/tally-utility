import Link from 'next/link'
import { notFound } from 'next/navigation'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { Button, Field, FieldGrid, Key } from '@/components/ui/Panel'
import { StateBlock, StateFlag, invoiceTone, humanize } from '@/components/ui/State'
import { Money } from '@/components/ui/Money'
import { correctionRun, invoiceById, invoices } from '@/fixtures/billing'
import { customerById } from '@/fixtures/accounts'
import { pgaVersions, versionAsOf } from '@/fixtures/rates'
import { asOf } from '@/fixtures/tenant'
import { customerName } from '@/schemas/models'
import { VoidReasonCode } from '@/schemas/enums'
import { date, rate as fmtRate, stamp } from '@/lib/format'

/**
 * Void and rebill.
 *
 * Not a button — a guided election, because the database refuses anything
 * less. A correction must sit on a correction run, carry `replaces_invoice_id`,
 * and have the operator's rate-date election recorded *first*. An off-run
 * manual rebill is rejected outright.
 *
 * The election is a genuine regulatory choice, so the screen shows what each
 * option actually prices at rather than asking the operator to hold two
 * versions of the tariff in their head.
 */

export function generateStaticParams() {
  return invoices.map((i) => ({ invoiceId: i.id }))
}

export default async function RebillPage({
  params,
}: PageProps<'/invoices/[invoiceId]/rebill'>) {
  const { invoiceId } = await params
  const invoice = invoiceById.get(invoiceId)
  if (!invoice) notFound()

  const customer = customerById.get(invoice.customer_id)

  /*
   * The two worlds the operator is choosing between, resolved from the same
   * version chain the engine would use.
   *
   * Both are read at the instant the correction will actually run — not at the
   * page's as-of coordinate. That matters here: the January factor was recorded
   * late, so a rebill executed today sees a January rate that the original run
   * could not have seen. That gap is the entire reason this bill is being
   * corrected, and the screen has to show it rather than hide it.
   */
  const rebillRecordedAt = correctionRun.recorded_at
  const historical = versionAsOf(pgaVersions, invoice.period_end, rebillRecordedAt)
  const current = versionAsOf(pgaVersions, asOf.validAt, rebillRecordedAt)
  /* What the voided bill actually charged, for contrast. */
  const asOriginallyBilled = versionAsOf(
    pgaVersions,
    invoice.period_end,
    invoice.first_issued_at ?? rebillRecordedAt,
  )

  return (
    <AppShell current="Bills">
      <PageHeader
        title="Void and rebill"
        meta={
          <>
            <span className="ident">{invoice.invoice_number}</span> ·{' '}
            {customer ? customerName(customer) : '—'} · {invoice.billing_period}
          </>
        }
        actions={
          <Link href={`/invoices/${invoice.id}`}>
            <Button variant="quiet">Cancel</Button>
          </Link>
        }
      />

      <div className="flex-1 overflow-auto">
        <div className="max-w-3xl mx-auto px-6 py-6 space-y-6">
          <StateBlock tone="warning">
            <p className="text-data text-ink-primary">
              The original bill is not edited. It is voided and stays on the account permanently,
              and a new correction bill replaces it. Both remain visible to the customer and to an
              auditor.
            </p>
          </StateBlock>

          {/* Step 1 — the bill being replaced. */}
          <Step n={1} title="Bill being corrected">
            <div className="border border-rule-solid bg-surface-raised px-4 py-3">
              <div className="flex items-center justify-between gap-4 mb-3">
                <span className="ident text-data text-ink-primary">{invoice.invoice_number}</span>
                <StateFlag tone={invoiceTone(invoice.status)}>
                  {humanize(invoice.status)}
                </StateFlag>
              </div>
              <FieldGrid cols={4}>
                <Field label="Period">
                  {date(invoice.period_start)} → {date(invoice.period_end)}
                </Field>
                <Field label="Issued">{stamp(invoice.first_issued_at)}</Field>
                <Field label="Amount">
                  <Money value={invoice.amount_due} />
                </Field>
                <Field label="Paid">
                  <Money value={invoice.amount_paid} />
                </Field>
              </FieldGrid>
            </div>
            <p className="text-micro text-ink-tertiary mt-2">
              Only a bill that was actually issued can be corrected — a held-then-voided draft was
              never a document, so there is nothing to replace.
            </p>
          </Step>

          {/* Step 2 — the void reason. */}
          <Step n={2} title="Why is it being voided?">
            <fieldset>
              <legend className="sr-only">Void reason code</legend>
              <div className="grid grid-cols-2 gap-x-6 gap-y-2">
                {VoidReasonCode.options.map((code, i) => (
                  <label key={code} className="flex items-center gap-2 text-data text-ink-primary">
                    <input
                      type="radio"
                      name="void_reason_code"
                      value={code}
                      defaultChecked={i === 1}
                      className="accent-accent"
                    />
                    {humanize(code)}
                  </label>
                ))}
              </div>
            </fieldset>
            <label className="block mt-3">
              <span className="text-micro text-ink-secondary">
                Notes <span className="text-exception-critical-text">required</span>
              </span>
              <textarea
                rows={3}
                defaultValue="January PGA adder applied at the December factor. Superseded factor was recorded late by Gas Supply."
                className="mt-1 w-full rounded-xs border border-rule-solid bg-surface-raised px-2 py-1.5 text-data text-ink-primary"
              />
            </label>
            <p className="text-micro text-ink-tertiary mt-1">
              Stored on the void permanently with your name and the time the database stamps it.
            </p>
          </Step>

          {/* Step 3 — the election. The consequential one. */}
          <Step n={3} title="Which rates should the rebill use?">
            <p className="text-data text-ink-secondary mb-3">
              This is a regulatory choice, not a technical one. It is recorded against the
              correction before the rebill runs.
            </p>
            {/*
              At the instant the original bill ran, NO version covered January —
              the January filing had not been recorded yet. The run priced it
              with December's factor anyway. That carry-forward is precisely the
              defect the schema now forbids: an as-of lookup that finds nothing
              must raise, never quietly reach for a neighbouring value.
            */}
            <div className="mb-3 border-l-[3px] border-exception-warning-rail bg-exception-warning-wash px-4 py-3">
              <p className="label-caps mb-1">What the voided bill charged</p>
              {asOriginallyBilled ? (
                <p className="text-data text-ink-primary">
                  PGA <span className="figures">{fmtRate(asOriginallyBilled.rate)}</span>/therm — the{' '}
                  {date(asOriginallyBilled.effective_from)} version.
                </p>
              ) : (
                <p className="text-data text-ink-primary">
                  PGA <span className="figures">$0.41200</span>/therm — December's factor, carried
                  forward. When this bill ran on {date(invoice.first_issued_at?.slice(0, 10) ?? '')},
                  no January version had been recorded at all, and the run used the neighbouring
                  month rather than stopping.
                </p>
              )}
              <p className="text-micro text-ink-secondary mt-1.5 leading-relaxed">
                The January factor was not recorded until{' '}
                {historical ? stamp(historical.recorded_from) : '—'}, six weeks into the period it
                applies to. A lookup that finds nothing at a coordinate now raises instead of
                falling back — which is why this is a correction rather than a silent edit.
              </p>
            </div>

            <div className="space-y-2">
              <Election
                mode="historical"
                title="Historical — the original period's world"
                defaultChecked
                detail={
                  historical
                    ? `PGA ${fmtRate(historical.rate)}/therm, in effect ${date(historical.effective_from)}`
                    : 'No version recorded at that coordinate'
                }
                explanation="Reproduces the bill as it should have been at the time. This is the default and what a PUC expects for a utility error."
              />
              <Election
                mode="current"
                title="Current — today's rates"
                detail={
                  current
                    ? `PGA ${fmtRate(current.rate)}/therm, in effect ${date(current.effective_from)}`
                    : 'No version recorded at that coordinate'
                }
                explanation="Prices the old period at today's tariff. Rarely correct; used when an order directs it."
              />
              <Election
                mode="custom"
                title="Custom — a specific date"
                detail="You supply the effective date the rebill prices at"
                explanation="For a corrected period that straddles a tariff change, or where an order names a date."
              />
            </div>

            {historical && current && historical.rate !== current.rate ? (
              <div className="mt-3 border-l-[3px] border-exception-info-rail bg-exception-info-wash px-4 py-3">
                <p className="text-data text-ink-primary">
                  These elections do not produce the same bill. The commodity rate differs by{' '}
                  <span className="figures font-medium">
                    {fmtRate(String(Math.abs(Number(current.rate) - Number(historical.rate))))}
                  </span>{' '}
                  per therm.
                </p>
              </div>
            ) : null}
          </Step>

          {/* Step 4 — where it runs. */}
          <Step n={4} title="Correction run">
            <div className="border border-rule-solid bg-surface-raised px-4 py-3">
              <FieldGrid cols={3}>
                <Field label="Run">
                  <span className="ident">BR-2026-02-COR-2</span>
                </Field>
                <Field label="Run type">Correction</Field>
                <Field label="Targets">1 bill</Field>
              </FieldGrid>
            </div>
            <p className="text-micro text-ink-tertiary mt-2">
              A correction cannot be produced outside a correction run. The run carries the default
              rate mode; your election above is recorded per target and overrides it.
            </p>
          </Step>

          <div className="flex items-center justify-between gap-4 border-t border-rule-heavy pt-4">
            <p className="text-micro text-ink-tertiary">
              Press <Key>⌘</Key>
              <Key>↵</Key> to commit, or <Key>Esc</Key> to cancel.
            </p>
            <div className="flex items-center gap-2">
              <Link href={`/invoices/${invoice.id}`}>
                <Button variant="quiet">Cancel</Button>
              </Link>
              <Button variant="danger">Void and queue rebill</Button>
            </div>
          </div>
        </div>
      </div>
    </AppShell>
  )
}

function Step({
  n,
  title,
  children,
}: {
  n: number
  title: string
  children: React.ReactNode
}) {
  return (
    <section>
      <div className="flex items-baseline gap-2.5 mb-2.5">
        <span className="ident flex h-5 w-5 items-center justify-center rounded-xs bg-surface-ink text-ink-inverse">
          {n}
        </span>
        <h2 className="text-h3 text-ink-primary">{title}</h2>
      </div>
      <div className="pl-[1.9rem]">{children}</div>
    </section>
  )
}

function Election({
  mode,
  title,
  detail,
  explanation,
  defaultChecked = false,
}: {
  mode: string
  title: string
  detail: string
  explanation: string
  defaultChecked?: boolean
}) {
  return (
    <label
      className={`flex gap-3 border px-4 py-3 cursor-pointer transition-colors duration-fast ${
        defaultChecked
          ? 'border-accent bg-accent-wash'
          : 'border-rule-solid bg-surface-raised hover:bg-surface-sunken'
      }`}
    >
      <input
        type="radio"
        name="rate_date_mode"
        value={mode}
        defaultChecked={defaultChecked}
        className="mt-0.5 accent-accent"
      />
      <div className="min-w-0">
        <p className="text-data text-ink-primary font-medium">{title}</p>
        <p className="text-data text-ink-secondary mt-0.5 figures-none">{detail}</p>
        <p className="text-micro text-ink-tertiary mt-1 leading-relaxed">{explanation}</p>
      </div>
    </label>
  )
}
