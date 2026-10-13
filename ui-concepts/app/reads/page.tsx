import type { ReactNode } from 'react'
import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { ListStar } from '@/components/shell/Favorites'
import { Button, Key } from '@/components/ui/Panel'
import { Rail, StateFlag, StateBlock, humanize } from '@/components/ui/State'
import type { Tone } from '@/components/ui/State'
import { Flags, readFlags } from '@/components/ui/Flags'
import { Nil, Quantity, Variance } from '@/components/ui/Money'
import { AccountNumber, MeterNumber } from '@/components/ui/RecordLink'
import { TableFooter } from '@/components/table/Table'
import { ColumnTable, type ColumnDef } from '@/components/table/Columns'
import { readings } from '@/fixtures/reads'
import { customerById, meterById, serviceLinks } from '@/fixtures/accounts'
import { cycle } from '@/fixtures/tenant'
import { currentRun } from '@/fixtures/billing'
import { customerName } from '@/schemas/models'
import type { MeterReading } from '@/schemas/models'
import { dateShort, factor, reading as fmtReading } from '@/lib/format'

/**
 * Read validation — Stage 7.
 *
 * Nineteen columns, shipped in the order of five groups. The gas derivation
 * chain ships together because "gas-native" means the corrections are
 * legible, not merely correct: the analyst can see Ccf, the meter factor, the
 * BTU factor and the resulting therms side by side and judge whether the
 * arithmetic is sane.
 *
 * Note the units. The schema defaults `consumption_unit` to 'gallons'; a gas
 * surface must never inherit that silently, so the unit rides on every row.
 */

/**
 * The shipped columns run group by group — read, consumption, gas
 * correction, validation. Once columns can move, a group label row above them
 * can no longer be true, so the menu names carry the group instead ("Read date",
 * "Validation status"). The hidden four are further steps of the same chain.
 */
const COLUMNS: ColumnDef[] = [
  { key: 'rail', label: '', menuLabel: 'Status rail', width: '3px', rail: true, fixed: true },
  { key: 'account', label: 'Account' },
  { key: 'meter', label: 'Meter' },
  { key: 'flags', label: 'Flags', align: 'center' },

  { key: 'date', label: 'Date', menuLabel: 'Read date' },
  { key: 'index', label: 'Index', menuLabel: 'Read index', align: 'right' },
  { key: 'prior', label: 'Prior', menuLabel: 'Prior index', align: 'right' },
  { key: 'method', label: 'Method', menuLabel: 'Read method' },

  { key: 'volume', label: 'Volume', align: 'right' },
  { key: 'days', label: 'Days', menuLabel: 'Days in period', align: 'right' },
  { key: 'variance', label: 'vs typical', align: 'right' },
  { key: 'quality', label: 'Quality' },

  { key: 'multiplier', label: 'Mult.', menuLabel: 'Meter multiplier', align: 'right' },
  { key: 'btu', label: 'BTU factor', align: 'right' },
  { key: 'therms', label: 'Therms', align: 'right' },
  { key: 'purpose', label: 'Purpose', menuLabel: 'Read purpose' },

  { key: 'status', label: 'Status', menuLabel: 'Validation status' },
  { key: 'access', label: 'Access' },
  { key: 'note', label: 'Note', cellClassName: 'max-w-64' },

  { key: 'priorDate', label: 'Prior date', menuLabel: 'Prior read date', hidden: true },
  { key: 'estimateReason', label: 'Estimate reason', hidden: true },
  { key: 'corrected', label: 'Corrected vol.', menuLabel: 'Pressure-corrected volume', align: 'right', hidden: true },
  { key: 'lastYear', label: 'Last year', menuLabel: 'Same period last year', align: 'right', hidden: true },
]

function readTone(read: MeterReading): Tone {
  if (read.dispute_reason) return 'critical'
  if (read.quality_flag === 'negative' || read.quality_flag === 'zero') return 'critical'
  if (read.is_estimated) return 'warning'
  if (read.quality_flag === 'high' || read.quality_flag === 'low') return 'warning'
  if (read.validation_status === 'pending_review') return 'info'
  if (read.billing_period_locked) return 'posted'
  return 'cleared'
}

const customerForMeter = (meterId: string) => {
  const link = serviceLinks.find((l) => l.meterId === meterId)
  return link ? customerById.get(link.customerId) : undefined
}

/** One read's cells, rendered here on the server and arranged by `ColumnTable`. */
function readCells(r: MeterReading): Record<string, ReactNode> {
  const tone = readTone(r)
  const meter = meterById.get(r.meter_id)
  const customer = customerForMeter(r.meter_id)
  return {
    rail: <Rail tone={tone} />,
    account: customer ? (
      <>
        <p className="text-data text-ink-primary truncate max-w-40">{customerName(customer)}</p>
        <p>
          <AccountNumber number={customer.customer_number} id={customer.id} />
        </p>
      </>
    ) : (
      <Nil />
    ),
    meter: (
      <>
        {meter ? <MeterNumber number={meter.meter_number} id={meter.id} /> : null}
        <p className="text-micro text-ink-tertiary">{meter?.route_id}</p>
      </>
    ),
    flags: <Flags flags={readFlags(r)} />,

    date: <span className="text-micro">{dateShort(r.reading_date)}</span>,
    index: <span className="ident">{fmtReading(r.reading_value)}</span>,
    prior: (
      <span className="ident text-ink-tertiary">{r.previous_value ? fmtReading(r.previous_value) : '—'}</span>
    ),
    method: <span className="text-micro text-ink-secondary">{humanize(r.read_method)}</span>,

    volume: (
      <Quantity
        value={r.consumption}
        unit={r.consumption_unit}
        className={Number(r.consumption ?? 0) < 0 ? 'text-exception-critical-text' : ''}
      />
    ),
    days: <span className="figures text-ink-secondary">{r.days_in_period ?? '—'}</span>,
    variance: <Variance pct={r.consumption_pct_vs_typical} />,
    quality: (
      <span
        className={`text-micro ${r.quality_flag === 'normal' ? 'text-ink-tertiary' : 'text-exception-warning-text'}`}
      >
        {humanize(r.quality_flag)}
      </span>
    ),

    multiplier: <span className="figures text-ink-secondary">{meter ? factor(meter.multiplier) : '—'}</span>,
    btu: <span className="figures text-ink-secondary">{r.gas_btu_factor ? factor(r.gas_btu_factor) : '—'}</span>,
    therms: r.gas_therms ? <Quantity value={r.gas_therms} unit="th" /> : <Nil />,
    purpose: <span className="text-micro text-ink-tertiary">{humanize(r.reading_purpose)}</span>,

    status: <StateFlag tone={tone}>{humanize(r.validation_status)}</StateFlag>,
    access: (
      <span
        className={`text-micro ${r.access_status === 'accessed' ? 'text-ink-tertiary' : 'text-exception-warning-text'}`}
      >
        {humanize(r.access_status)}
      </span>
    ),
    note: <span className="text-micro text-ink-secondary line-clamp-2">{r.trouble_message ?? r.notes ?? ''}</span>,

    priorDate: r.previous_reading_date ? (
      <span className="text-micro">{dateShort(r.previous_reading_date)}</span>
    ) : (
      <Nil />
    ),
    estimateReason: r.estimation_reason ? (
      <span className="text-micro text-exception-warning-text">{humanize(r.estimation_reason)}</span>
    ) : (
      <span className="text-micro text-ink-tertiary">—</span>
    ),
    /* The same unit as the volume it corrects. */
    corrected: <Quantity value={r.gas_pressure_corrected_volume} unit={r.consumption_unit} />,
    lastYear: <Quantity value={r.consumption_same_period_last_year} unit={r.consumption_unit} />,
  }
}

export default function ReadValidationPage() {
  const pending = readings.filter(
    (r) => r.validation_status === 'pending_review' || r.validation_status === 'reviewed_with_exception',
  )

  return (
    <AppShell current="Read validation">
      <PageHeader
        title="Read validation"
        meta={
          <>
            {cycle.label} · read window {cycle.readWindow} · {currentRun.total_estimated_reads}{' '}
            estimated reads in this cycle
          </>
        }
        actions={
          <>
            <ListStar list="reads" />
            <Button>Export</Button>
            <Button variant="primary">Release clean reads to billing</Button>
          </>
        }
      />

      <div className="px-5 py-3 border-b border-rule-solid bg-surface">
        <StateBlock tone="warning">
          <p className="text-data text-ink-primary">
            <strong className="font-semibold">{pending.length} reads await validation.</strong> A
            read cannot move to a billable state while an exception is open against it, and one
            raised after approval stops the read at its next step.
          </p>
        </StateBlock>
      </div>

      {/* The table's own frame scrolls, so the strip holding the legend and the
          Columns button stays put and the header sticks above the rows. */}
      <ColumnTable
        fill
        listId="reads"
        caption="Cycle 04 meter reads with validation status and gas correction chain"
        columns={COLUMNS}
        rows={readings.map((r) => ({ key: r.id, muted: r.billing_period_locked, cells: readCells(r) }))}
        toolbar={
          <>
            <p className="flex-1 min-w-0 text-micro text-ink-secondary">
              Flags: <span className="ident font-semibold">E</span> estimated ·{' '}
              <span className="ident font-semibold">T</span> tamper ·{' '}
              <span className="ident font-semibold">D</span> disputed ·{' '}
              <span className="ident font-semibold">L</span> locked ·{' '}
              <span className="ident font-semibold">S</span> service transition ·{' '}
              <span className="ident font-semibold">A</span> access
            </p>
            <p className="text-micro text-ink-tertiary flex items-center gap-1.5">
              <Key>↑</Key>
              <Key>↓</Key> move · <Key>Enter</Key> open · <Key>v</Key> validate
            </p>
          </>
        }
      />

      <TableFooter shown={readings.length} total={3412} noun="reads in cycle 04" />
    </AppShell>
  )
}
