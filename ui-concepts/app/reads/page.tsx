import { AppShell, PageHeader } from '@/components/shell/AppShell'
import { ListStar } from '@/components/shell/Favorites'
import { Button, Key } from '@/components/ui/Panel'
import { Rail, StateFlag, StateBlock, humanize } from '@/components/ui/State'
import type { Tone } from '@/components/ui/State'
import { Flags, readFlags } from '@/components/ui/Flags'
import { Nil, Quantity, Variance } from '@/components/ui/Money'
import {
  Table,
  GroupRow,
  HeadRow,
  Th,
  Row,
  Td,
  RailCell,
  TableFooter,
} from '@/components/table/Table'
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
 * Twenty columns in six labelled groups. The gas derivation chain gets its own
 * group because "gas-native" means the corrections are legible, not merely
 * correct: the analyst can see Ccf, the meter factor, the BTU factor and the
 * resulting therms side by side and judge whether the arithmetic is sane.
 *
 * Note the units. The schema defaults `consumption_unit` to 'gallons'; a gas
 * surface must never inherit that silently, so the unit rides on every row.
 */

const GROUPS = [
  { label: '', span: 4 },
  { label: 'Read', span: 4 },
  { label: 'Consumption', span: 4 },
  { label: 'Gas correction', span: 4 },
  { label: 'Validation', span: 3 },
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

      <div className="flex items-center justify-between gap-4 px-cell-x py-2 border-b border-rule-hair bg-surface">
        <p className="text-micro text-ink-secondary">
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
      </div>

      <div className="flex-1 min-h-0 overflow-auto">
        <Table caption="Cycle 04 meter reads with validation status and gas correction chain">
          <thead className="sticky top-0 z-10">
            <GroupRow groups={GROUPS} />
            <HeadRow>
              <Th width="3px"> </Th>
              <Th>Account</Th>
              <Th>Meter</Th>
              <Th align="center">Flags</Th>

              <Th groupStart>Date</Th>
              <Th align="right">Index</Th>
              <Th align="right">Prior</Th>
              <Th>Method</Th>

              <Th groupStart align="right">Volume</Th>
              <Th align="right">Days</Th>
              <Th align="right">vs typical</Th>
              <Th>Quality</Th>

              <Th groupStart align="right">Mult.</Th>
              <Th align="right">BTU factor</Th>
              <Th align="right">Therms</Th>
              <Th>Purpose</Th>

              <Th groupStart>Status</Th>
              <Th>Access</Th>
              <Th>Note</Th>
            </HeadRow>
          </thead>
          <tbody>
            {readings.map((r) => {
              const tone = readTone(r)
              const meter = meterById.get(r.meter_id)
              const customer = customerForMeter(r.meter_id)
              return (
                <Row key={r.id} muted={r.billing_period_locked}>
                  <RailCell>
                    <Rail tone={tone} />
                  </RailCell>
                  <Td>
                    {customer ? (
                      <>
                        <p className="text-data text-ink-primary truncate max-w-40">
                          {customerName(customer)}
                        </p>
                        <p className="ident text-ink-tertiary">{customer.customer_number}</p>
                      </>
                    ) : (
                      <Nil />
                    )}
                  </Td>
                  <Td>
                    <span className="ident text-ink-secondary">{meter?.meter_number}</span>
                    <p className="text-micro text-ink-tertiary">{meter?.route_id}</p>
                  </Td>
                  <Td align="center">
                    <Flags flags={readFlags(r)} />
                  </Td>

                  <Td groupStart>
                    <span className="text-micro">{dateShort(r.reading_date)}</span>
                  </Td>
                  <Td align="right">
                    <span className="ident">{fmtReading(r.reading_value)}</span>
                  </Td>
                  <Td align="right">
                    <span className="ident text-ink-tertiary">
                      {r.previous_value ? fmtReading(r.previous_value) : '—'}
                    </span>
                  </Td>
                  <Td>
                    <span className="text-micro text-ink-secondary">{humanize(r.read_method)}</span>
                  </Td>

                  <Td groupStart align="right">
                    <Quantity
                      value={r.consumption}
                      unit={r.consumption_unit}
                      className={
                        Number(r.consumption ?? 0) < 0 ? 'text-exception-critical-text' : ''
                      }
                    />
                  </Td>
                  <Td align="right">
                    <span className="figures text-ink-secondary">{r.days_in_period ?? '—'}</span>
                  </Td>
                  <Td align="right">
                    <Variance pct={r.consumption_pct_vs_typical} />
                  </Td>
                  <Td>
                    <span
                      className={`text-micro ${
                        r.quality_flag === 'normal' ? 'text-ink-tertiary' : 'text-exception-warning-text'
                      }`}
                    >
                      {humanize(r.quality_flag)}
                    </span>
                  </Td>

                  <Td groupStart align="right">
                    <span className="figures text-ink-secondary">
                      {meter ? factor(meter.multiplier) : '—'}
                    </span>
                  </Td>
                  <Td align="right">
                    <span className="figures text-ink-secondary">
                      {r.gas_btu_factor ? factor(r.gas_btu_factor) : '—'}
                    </span>
                  </Td>
                  <Td align="right">
                    {r.gas_therms ? (
                      <Quantity value={r.gas_therms} unit="th" />
                    ) : (
                      <Nil />
                    )}
                  </Td>
                  <Td>
                    <span className="text-micro text-ink-tertiary">
                      {humanize(r.reading_purpose)}
                    </span>
                  </Td>

                  <Td groupStart>
                    <StateFlag tone={tone}>{humanize(r.validation_status)}</StateFlag>
                  </Td>
                  <Td>
                    <span
                      className={`text-micro ${
                        r.access_status === 'accessed'
                          ? 'text-ink-tertiary'
                          : 'text-exception-warning-text'
                      }`}
                    >
                      {humanize(r.access_status)}
                    </span>
                  </Td>
                  <Td className="max-w-64">
                    <span className="text-micro text-ink-secondary line-clamp-2">
                      {r.trouble_message ?? r.notes ?? ''}
                    </span>
                  </Td>
                </Row>
              )
            })}
          </tbody>
        </Table>
      </div>

      <TableFooter shown={readings.length} total={3412} noun="reads in cycle 04" />
    </AppShell>
  )
}
