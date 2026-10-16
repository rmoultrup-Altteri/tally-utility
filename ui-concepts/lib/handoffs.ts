import { moveIns as applications, moveOuts as stopOrders, type AfterStop, type MoveIn, type MoveOut } from '@/fixtures/handoffs'
import { transferPremiseById, transfers, type Transfer } from '@/fixtures/transfers'
import type { CheckLevel, TransferCheck } from '@/lib/transfers'
import { date, days, money } from '@/lib/format'

/**
 * Reconciling a move-out with the move-in at the same address.
 *
 * Each premise with a stop or a start pending gets one row: the outgoing
 * customer's termination, the incoming customer's application, or both. The
 * pair is held to the rules that keep one meter honest — the stop and the
 * start meet on one read, the gas is not locked off the morning someone moves
 * in, the outgoing customer's debt stays theirs — and checked with the same
 * levels the transfer rules use (`lib/transfers.ts`).
 */

export type HandoffState = 'conflict' | 'needs_review' | 'matched' | 'move_out_only'

export const HANDOFF_LABEL: Record<HandoffState, string> = {
  conflict: 'Conflict',
  needs_review: 'Needs review',
  matched: 'Matched',
  move_out_only: 'No move-in',
}

export type Handoff = {
  premiseNumber: string
  address: string
  city: string
  meterNumber: string
  out: MoveOut | null
  in: MoveIn | null
  checks: TransferCheck[]
  state: HandoffState
}

const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? '' : 's'}`
/** `Patel, Rohan` -> `Rohan Patel`, for sentences. */
export const spoken = (name: string) => name.split(', ').reverse().join(' ')

const AFTER_STOP: Record<Transfer['afterStop'], AfterStop> = {
  lock_off: 'lock_off',
  owner_takes_service: 'owner_takes_service',
  next_customer: 'leave_on',
}

/** The old end of each open transfer, as a move-out at that premise. */
function transferMoveOuts(list: Transfer[]): MoveOut[] {
  return list
    .filter((t) => !t.completedAt)
    .map((t) => {
      const to = transferPremiseById.get(t.toPremiseId)
      return {
        id: `${t.id}-out`,
        number: t.number,
        requestedAt: t.requestedAt,
        channel: t.channel,
        transferId: t.id,
        customer: { name: t.mover.name, accountNumber: t.mover.accountNumber, customerId: t.mover.customerId, phone: t.mover.phone },
        occupants: [t.mover.name],
        premise: { number: t.mover.from.premiseNumber, address: t.mover.from.address, city: t.mover.from.city, meterNumber: t.mover.from.meterNumber, meterState: 'on' },
        stopDate: t.stopDate,
        finalRead: t.finalRead,
        afterStop: AFTER_STOP[t.afterStop],
        balance: t.mover.balance,
        pastDueDays: t.mover.pastDueDays,
        deposit: t.mover.deposit,
        forwarding: to ? `${to.address}, ${to.city}` : null,
      }
    })
}

/** The new end of each open transfer whose premise someone else is still on service at. */
function transferMoveIns(list: Transfer[]): MoveIn[] {
  return list.flatMap((t) => {
    const to = transferPremiseById.get(t.toPremiseId)
    const occ = to?.occupant
    if (!to || t.completedAt || occ?.kind !== 'customer' || occ.accountNumber === t.mover.accountNumber || occ.stopOrderedFor) return []
    return [
      {
        id: `${t.id}-in`,
        number: t.number,
        requestedAt: t.requestedAt,
        channel: t.channel,
        transferId: t.id,
        applicant: { name: t.mover.name, phone: t.mover.phone, accountNumber: t.mover.accountNumber, customerId: t.mover.customerId },
        premise: { number: to.number, address: to.address, city: to.city, meterNumber: to.meterNumber, meterState: to.meterState },
        startDate: t.startDate,
        openingRead: { method: 'meter_read' as const, reading: null, takenAt: null },
        idVerified: true,
        livedHere: false,
        deposit: { amount: '0.00', basis: 'An existing customer moving within the system' },
        currentCustomer: { name: occ.name, accountNumber: occ.accountNumber },
      },
    ]
  })
}

export function buildHandoffs(list: Transfer[] = transfers): Handoff[] {
  const outs = [...stopOrders, ...transferMoveOuts(list)]
  const ins = [...applications, ...transferMoveIns(list)]
  const premises = new Map<string, { out: MoveOut | null; in: MoveIn | null }>()
  for (const o of outs) premises.set(o.premise.number, { out: o, in: null })
  for (const i of ins) premises.set(i.premise.number, { out: premises.get(i.premise.number)?.out ?? null, in: i })

  return [...premises.entries()].map(([number, { out, in: inn }]) => {
    const p = (out ?? inn)!.premise
    const checks = reconcile(out, inn)
    return { premiseNumber: number, address: p.address, city: p.city, meterNumber: p.meterNumber, out, in: inn, checks, state: handoffState(out, inn, checks) }
  })
}

function handoffState(out: MoveOut | null, inn: MoveIn | null, checks: TransferCheck[]): HandoffState {
  if (checks.some((c) => c.level === 'block')) return 'conflict'
  if (checks.some((c) => c.level === 'review')) return 'needs_review'
  return out && inn ? 'matched' : 'move_out_only'
}

/** Everything that has to be true for one meter to pass from one customer to the next. */
export function reconcile(out: MoveOut | null, inn: MoveIn | null): TransferCheck[] {
  const checks: TransferCheck[] = []
  const add = (code: string, level: CheckLevel, title: string, detail: string) => checks.push({ code, level, title, detail })

  /* ---- A move-in with nobody moving out ---- */
  if (inn && !out && inn.currentCustomer) {
    const cc = inn.currentCustomer
    add(
      'no_stop',
      'block',
      `${spoken(cc.name)} is still on service here`,
      `Account ${cc.accountNumber} has no stop ordered at ${inn.premise.address}. ${spoken(inn.applicant.name)}’s start on ${date(inn.startDate)} would bill the same meter — order their stop, or take the landlord’s word that they have left, first.`,
    )
  }

  /* ---- A move-out with nobody moving in ---- */
  if (out && !inn) {
    if (out.afterStop === 'lock_off')
      add('lock_off', 'info', 'Nobody moving in — locked off after the read', `A field order locks meter ${out.premise.meterNumber} on ${date(out.stopDate)}. A move-in that arrives later is a turn-on and relight.`)
    else if (out.afterStop === 'owner_takes_service')
      add('owner', 'info', 'The owner takes service after the read', `Meter ${out.premise.meterNumber} stays on in the owner’s name from ${date(out.stopDate)}.`)
    else
      add('left_on', 'review', 'The gas stays on with nobody to bill', `${spoken(out.customer.name)}’s stop leaves meter ${out.premise.meterNumber} on, and no one has applied at ${out.premise.address}. Lock it off after the final read, or confirm the owner takes service.`)
  }

  /* ---- Both: the stop and the start meet on one meter ---- */
  if (out && inn) {
    const who = spoken(out.customer.name)
    const next = spoken(inn.applicant.name)
    const gap = days(out.stopDate, inn.startDate)
    const by = out.transferId ? out.number : 'The stop order'

    if (gap < 0)
      add('overlap', 'block', `One meter, two accounts for ${plural(-gap, 'day')}`, `${next} starts ${date(inn.startDate)}, before ${who} stops ${date(out.stopDate)}. Move the start to ${date(out.stopDate)}, or ask ${who} for an earlier stop.`)
    else if (gap > 1)
      add(
        'gap',
        'review',
        `Nobody billed for ${plural(gap - 1, 'day')}`,
        out.afterStop === 'lock_off'
          ? `Locked off ${date(out.stopDate)} and turned on again ${date(inn.startDate)}: two truck rolls and a relight. Ask the owner to hold service between them, or move one of the dates.`
          : `The meter stays on from ${date(out.stopDate)} to ${date(inn.startDate)} with nobody on the account. Lock it off, or ask the owner to hold service.`,
      )
    else add('dates', 'ok', 'Stop and start line up', `${who} stops ${date(out.stopDate)}; ${next} starts ${date(inn.startDate)}.`)

    const closing = out.finalRead.reading
    const opening = inn.openingRead.reading
    if (closing && opening && closing !== opening) {
      const diff = Math.abs(Number(opening) - Number(closing))
      add(
        'read_mismatch',
        'review',
        `Closing and opening reads differ by ${diff}`,
        `${who} closes at ${closing} (${out.finalRead.method === 'customer_read' ? 'their own read' : 'meter read'}, ${date(out.finalRead.takenAt)}); ${next} opens at ${opening} (${inn.openingRead.method === 'field_read' ? 'field read' : 'meter read'}, ${date(inn.openingRead.takenAt)}). One read serves both accounts — choose one, or the ${diff} between them bills to nobody.`,
      )
    } else if (out.finalRead.method === 'customer_read') {
      add('customer_read', 'review', 'Final read from the customer', 'It opens the next account too, so it needs a dated photo of the dial before either bill goes out.')
    } else if (gap <= 1) {
      add('shared_read', 'ok', 'One read closes one account and opens the next', `Meter ${out.premise.meterNumber} on ${date(out.stopDate)}: ${who}’s final read is ${next}’s opening read.`)
    }

    if (gap >= 0 && gap <= 1) {
      if (out.afterStop === 'lock_off')
        add('cancel_lock_off', 'review', 'Cancel the lock-off — someone moves in', `${by} locks meter ${out.premise.meterNumber} off after the final read. With ${next} starting ${date(inn.startDate)} it would only be turned on again: cancel the lock-off and leave the gas on.`)
      else add('no_truck', 'ok', 'No truck roll — the gas stays on', 'No lock-off, no relight, and nobody needs to be home for the start.')
    }

    /* The outgoing customer's debt is theirs, unless the applicant shared it. */
    if (Number(out.balance) > 0) {
      if (out.transferId)
        add('balance_moves', 'info', `${who}’s ${money(out.balance)} moves with them`, `Carried to ${out.forwarding ?? 'their new service address'} on the transfer. It is not asked of ${next}.`)
      else if (inn.livedHere && out.occupants.includes(inn.applicant.name))
        add(
          'co_occupant',
          'review',
          `${next} is named on the account that owes ${money(out.balance)}`,
          `They lived here on ${who}’s account while it accrued (${plural(out.pastDueDays, 'day')} past due). Asking an occupant who shared the service to pay it is a supervisor’s decision — confirm it against the service rules before it is raised with ${next}.`,
        )
      else add('out_balance', 'info', `${money(out.balance)} goes on ${who}’s final bill`, `${out.forwarding ? `Mailed to ${out.forwarding}.` : 'No forwarding address on file.'} It is never ${next}’s.`)
    }
    if (Number(out.deposit) > 0 && !out.transferId)
      add('out_deposit', 'info', `${money(out.deposit)} deposit applied to ${who}’s final bill`, 'Any remainder is refunded to the forwarding address.')
  }

  /* ---- The incoming customer ---- */
  if (inn) {
    const next = spoken(inn.applicant.name)
    if (!inn.idVerified)
      add('identity', 'block', 'Identity not verified', `Service in a new name starts only after the ID check. Ask ${next} for a government ID, or verify through the portal.`)
    if (Number(inn.deposit.amount) > 0) add('in_deposit', 'info', `${money(inn.deposit.amount)} deposit asked of ${next}`, inn.deposit.basis + '.')
    else if (!inn.transferId) add('in_deposit', 'ok', 'No deposit asked', inn.deposit.basis + '.')
  }

  return checks
}

/** Premises where the move-out and move-in conflict or wait on a person. */
export function handoffsNeedingAttention(list: Handoff[] = buildHandoffs()): number {
  return list.filter((h) => h.state === 'conflict' || h.state === 'needs_review').length
}
