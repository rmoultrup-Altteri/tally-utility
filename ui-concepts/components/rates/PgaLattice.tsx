'use client'

import { useState } from 'react'
import {
  carryForwardDefect,
  factorAt,
  recordedInstants,
  serviceMonths,
  type RecordedInstant,
  type ServiceMonth,
} from '@/fixtures/pga'
import { rate as fmtRate, stamp } from '@/lib/format'
import { StateBlock, StateFlag } from '@/components/ui/State'

/**
 * The bi-temporal lattice.
 *
 * Columns are valid time — the service month a bill is priced for. Rows are
 * transaction time — the instants at which the database's knowledge changed.
 * A cell holds the factor a run would have used had it priced that month at
 * that instant, which is the only question a rebill or an audit ever asks.
 *
 * Read down a column and you see what the utility believed over time. Read
 * across a row and you see everything it knew at one moment. The staircase
 * that results is the normal shape: knowledge arrives shortly before the month
 * it governs. January breaks the staircase — its factor lands two rows below
 * where the pattern puts it, and the cells above it are empty even though 412
 * bills were issued out of them.
 *
 * Empty is the point. An empty cell is not zero and not "use the last known
 * value"; it is a coordinate at which the factor is unknowable, and the
 * schema's own lookups raise there rather than reach for a current value.
 */

type Selection = { month: ServiceMonth; instant: RecordedInstant }

export function PgaLattice() {
  const [selected, setSelected] = useState<Selection | null>(null)

  return (
    <div>
      <div className="overflow-x-auto">
        <table className="w-full text-data border-separate border-spacing-0">
          <caption className="sr-only">
            Purchased gas adjustment by service month and recorded instant
          </caption>
          <thead>
            <tr>
              <th
                scope="col"
                className="label-caps sticky left-0 z-10 bg-surface-raised border-b border-rule-heavy px-cell-x py-1.5 text-left align-bottom"
                style={{ width: '17rem' }}
              >
                Recorded ↓ / Service month →
              </th>
              {serviceMonths.map((m) => (
                <th
                  key={m.key}
                  scope="col"
                  className="label-caps bg-surface-raised border-b border-l border-rule-heavy px-cell-x py-1.5 text-center font-semibold"
                >
                  {m.label}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {recordedInstants.map((instant, rowIndex) => {
              const prior = recordedInstants[rowIndex - 1]
              return (
                <tr key={instant.id}>
                  <th
                    scope="row"
                    className={`sticky left-0 z-10 border-b border-rule-hair px-cell-x py-cell-y text-left font-normal ${rowGround(instant)}`}
                  >
                    <InstantLabel instant={instant} />
                  </th>
                  {serviceMonths.map((month) => (
                    <Cell
                      key={month.key}
                      month={month}
                      instant={instant}
                      prior={prior}
                      selected={
                        selected?.month.key === month.key && selected?.instant.id === instant.id
                      }
                      onSelect={() => setSelected({ month, instant })}
                    />
                  ))}
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>

      <Legend />
      <Probe selection={selected} />
    </div>
  )
}

/** Row grounds separate the moments that changed the record from the rest. */
function rowGround(instant: RecordedInstant): string {
  switch (instant.kind) {
    case 'viewpoint':
      return 'bg-accent-wash'
    case 'billing':
      return 'bg-exception-critical-wash'
    case 'correction':
      return 'bg-exception-cleared-wash'
    default:
      return 'bg-surface-raised'
  }
}

function InstantLabel({ instant }: { instant: RecordedInstant }) {
  const late = instant.id === 'ri-v4'
  return (
    <span className="flex items-baseline justify-between gap-3">
      <span className="min-w-0">
        <span
          className={`block text-data truncate ${
            instant.kind === 'viewpoint' ? 'text-ink-primary font-medium' : 'text-ink-primary'
          }`}
        >
          {instant.label}
        </span>
        <span
          className={`block text-micro ${late ? 'text-exception-warning-text' : 'text-ink-tertiary'}`}
        >
          {stamp(instant.at)}
        </span>
      </span>
      {instant.kind === 'billing' ? <StateFlag tone="critical">Priced</StateFlag> : null}
      {instant.kind === 'correction' ? <StateFlag tone="approved">Rebilled</StateFlag> : null}
    </span>
  )
}

/**
 * A cell is a button because the coordinate it names is the thing an operator
 * actually wants to interrogate — and because these people work by keyboard,
 * so the whole lattice has to be tabbable.
 */
function Cell({
  month,
  instant,
  prior,
  selected,
  onSelect,
}: {
  month: ServiceMonth
  instant: RecordedInstant
  prior?: RecordedInstant
  selected: boolean
  onSelect: () => void
}) {
  const version = factorAt(month, instant)
  const priorVersion = prior ? factorAt(month, prior) : null
  const learned = version !== null && version.id !== priorVersion?.id
  const defect =
    month.key === carryForwardDefect.monthKey && instant.id === carryForwardDefect.instantId

  const ground = version
    ? learned
      ? 'bg-exception-cleared-wash'
      : 'bg-surface-raised'
    : defect
      ? 'bg-exception-critical-wash'
      : 'bg-surface-sunken'

  return (
    <td
      className={`border-b border-l border-rule-hair p-0 ${
        learned ? 'border-t border-t-rule-heavy' : ''
      }`}
    >
      <button
        type="button"
        onClick={onSelect}
        aria-pressed={selected}
        aria-label={`${month.label} priced at ${stamp(instant.at)}: ${
          version ? fmtRate(version.rate) : 'no version recorded'
        }`}
        className={`block w-full h-11 px-2 text-center transition-colors duration-fast ${ground} ${
          selected ? 'outline-2 -outline-offset-2 outline-accent' : 'hover:bg-accent-wash'
        }`}
      >
        {version ? (
          <span
            className={`ident text-data ${
              learned ? 'text-ink-primary font-medium' : 'text-ink-secondary'
            }`}
          >
            {fmtRate(version.rate)}
          </span>
        ) : defect ? (
          <span className="block leading-tight">
            <span className="ident text-data line-through decoration-1 text-exception-critical-text">
              {fmtRate(carryForwardDefect.billedFactor)}
            </span>
            <span className="block text-label uppercase tracking-[0.06em] font-semibold text-exception-critical-text">
              billed anyway
            </span>
          </span>
        ) : (
          <span aria-hidden className="text-ink-muted">
            ·
          </span>
        )}
      </button>
    </td>
  )
}

function Legend() {
  return (
    <div className="flex flex-wrap items-center gap-x-6 gap-y-2 border-t border-rule-hair px-4 py-2.5">
      <LegendItem swatch="bg-exception-cleared-wash border-t-2 border-t-rule-heavy">
        Factor recorded at this instant
      </LegendItem>
      <LegendItem swatch="bg-surface-raised">Standing, carried from above</LegendItem>
      <LegendItem swatch="bg-surface-sunken">
        No version recorded — unknowable, not zero
      </LegendItem>
      <LegendItem swatch="bg-exception-critical-wash">
        No version recorded, and billed regardless
      </LegendItem>
    </div>
  )
}

function LegendItem({ swatch, children }: { swatch: string; children: React.ReactNode }) {
  return (
    <span className="flex items-center gap-2">
      <span aria-hidden className={`inline-block h-3.5 w-6 border border-rule-solid ${swatch}`} />
      <span className="text-micro text-ink-secondary">{children}</span>
    </span>
  )
}

/**
 * The coordinate probe.
 *
 * Deliberately refuses to answer without both axes, and says so in the null
 * case rather than showing the current factor with a caveat. A caveat is not
 * a guard; the empty answer is the correct one.
 */
function Probe({ selection }: { selection: Selection | null }) {
  if (!selection) {
    return (
      <div className="border-t border-rule-solid bg-surface-sunken px-4 py-3">
        <p className="text-micro text-ink-tertiary">
          Select a cell to resolve the factor at that coordinate. Both axes are required — the
          schema&rsquo;s as-of functions raise on a missing one rather than defaulting to now.
        </p>
      </div>
    )
  }

  const { month, instant } = selection
  const version = factorAt(month, instant)
  const defect =
    month.key === carryForwardDefect.monthKey && instant.id === carryForwardDefect.instantId

  return (
    <div className="border-t border-rule-solid px-4 py-4">
      <dl className="grid grid-cols-2 md:grid-cols-4 gap-x-6 gap-y-3">
        <div>
          <dt className="label-caps mb-0.5">valid_at</dt>
          <dd className="ident text-data text-ink-primary">{month.probeAt}</dd>
        </div>
        <div>
          <dt className="label-caps mb-0.5">recorded_at</dt>
          <dd className="ident text-data text-ink-primary">{instant.at}</dd>
        </div>
        <div>
          <dt className="label-caps mb-0.5">Resolves to</dt>
          <dd className="text-data text-ink-primary">
            {version ? (
              <span className="ident font-medium">{version.id}</span>
            ) : (
              <span className="text-exception-critical-text font-medium">no row</span>
            )}
          </dd>
        </div>
        <div>
          <dt className="label-caps mb-0.5">Factor</dt>
          <dd className="text-data">
            {version ? (
              <span className="ident text-ink-primary font-medium">{fmtRate(version.rate)}</span>
            ) : (
              <span className="text-ink-tertiary">—</span>
            )}
          </dd>
        </div>
      </dl>

      <div className="mt-3">
        {version ? (
          <StateBlock tone="cleared">
            <p className="text-data text-ink-primary">
              {version.change_reason}
            </p>
            <p className="text-micro text-ink-tertiary mt-1">
              {version.regulatory_reference} · recorded by {version.changed_by} at{' '}
              {stamp(version.recorded_from)}
            </p>
          </StateBlock>
        ) : defect ? (
          <StateBlock tone="critical">
            <p className="text-data text-ink-primary">
              <strong className="font-semibold">
                The January run priced 412 bills out of this empty cell.
              </strong>{' '}
              No PGA version stood at this coordinate — December&rsquo;s valid time had already
              closed and January&rsquo;s had not yet been recorded. The run carried December forward
              at {fmtRate(carryForwardDefect.billedFactor)} instead of refusing to price. That is
              the defect; the void-and-rebill lineage is the repair, not the cause.
            </p>
          </StateBlock>
        ) : (
          <StateBlock tone="info">
            <p className="text-data text-ink-primary">
              Nothing was known about {month.label} at this instant. A bill cannot be priced here,
              and the correct behaviour is to stop — not to reach for the nearest factor in either
              direction.
            </p>
          </StateBlock>
        )}
      </div>
    </div>
  )
}
