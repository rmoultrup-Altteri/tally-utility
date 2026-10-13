import { openExceptions } from '@/fixtures/exceptions'
import { asOf } from '@/fixtures/tenant'
import { currentCard } from '@/fixtures/tariff'
import { transferPremiseById, transfers, type Transfer, type TransferPremise } from '@/fixtures/transfers'
import { addCalendarDays, holidayOn, isWorkingDay, weekday } from '@/lib/working-days'
import { date, days, money } from '@/lib/format'

/**
 * The rules a transfer of service is held to.
 *
 * One function evaluates the recorded transfers and a request still being
 * keyed in, so the Transfers tab and the form can never disagree about what
 * stops a move. Each check names its level:
 *
 *   block  — the transfer cannot complete until someone does something
 *   review — it can proceed, but a person signs off on this first
 *   ok     — checked, and fine
 *   info   — worth knowing; nothing to do
 */

export type CheckLevel = 'block' | 'review' | 'ok' | 'info'
export type TransferCheck = { code: string; level: CheckLevel; title: string; detail: string }

export type TransferState = 'blocked' | 'needs_review' | 'scheduled' | 'completed'

export const STATE_LABEL: Record<TransferState, string> = {
  blocked: 'Blocked',
  needs_review: 'Needs review',
  scheduled: 'Scheduled',
  completed: 'Completed',
}

/** A transfer the form is building, before it has a number. */
export type TransferDraft = Omit<Transfer, 'id' | 'number' | 'requestedAt' | 'completedAt'> & {
  id?: string
}

const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? '' : 's'}`

function dayName(iso: string): string {
  return holidayOn(iso)?.name ?? (weekday(iso) === 'Sat' ? 'Saturday' : weekday(iso) === 'Sun' ? 'Sunday' : weekday(iso))
}

function nextWorkingDay(iso: string): string {
  let d = iso
  while (!isWorkingDay(d)) d = addCalendarDays(d, 1)
  return d
}

/**
 * Everything that has to be true before the move completes.
 *
 * `others` are the other open transfers, so two moves cannot claim the same
 * premise. `isNew` applies the rules that only make sense before anything has
 * happened — a stop date in the past is history on a recorded transfer and a
 * mistake on a new one.
 */
export function evaluateTransfer(t: TransferDraft, others: Transfer[], isNew: boolean): TransferCheck[] {
  const checks: TransferCheck[] = []
  const to = transferPremiseById.get(t.toPremiseId)
  const m = t.mover

  /* ---- Dates ---- */
  if (isNew && t.stopDate < asOf.validAt)
    checks.push({ code: 'stop_past', level: 'block', title: 'Stop date is in the past', detail: `Service cannot be stopped retroactively. The earliest stop is ${date(asOf.validAt)}.` })
  const gap = days(t.stopDate, t.startDate)
  if (gap < 0)
    checks.push({ code: 'overlap', level: 'review', title: `Both premises bill for ${plural(-gap, 'day')}`, detail: `Service starts at the new premise on ${date(t.startDate)}, before it stops at the old one on ${date(t.stopDate)}. Confirm the customer wants both.` })
  else if (gap > 1)
    checks.push({ code: 'gap', level: 'info', title: `No service for ${plural(gap - 1, 'day')}`, detail: `Off at the old premise after ${date(t.stopDate)}, on at the new one from ${date(t.startDate)}.` })
  else checks.push({ code: 'dates', level: 'ok', title: 'Dates line up', detail: `Stops ${date(t.stopDate)}, starts ${date(t.startDate)}.` })

  /* ---- The final read at the old premise ---- */
  const onOldMeter = m.from.meterId ? openExceptions.filter((e) => e.meter_id === m.from.meterId) : []
  for (const e of onOldMeter)
    checks.push({ code: `exception_${e.id}`, level: 'block', title: 'The final bill waits on an open exception', detail: `${e.description}. The final read cannot bill until it is resolved on the exception queue.` })
  if (!onOldMeter.length) {
    if (t.finalRead.method === 'customer_read')
      checks.push({ code: 'customer_read', level: 'review', title: 'Final read from the customer', detail: 'A customer read needs a dated photo of the dial before the final bill goes out.' })
    else if (t.finalRead.reading)
      checks.push({ code: 'final_read', level: 'ok', title: 'Final read taken', detail: `${t.finalRead.reading} on meter ${m.from.meterNumber}${t.finalRead.takenAt ? `, ${date(t.finalRead.takenAt)}` : ''}.` })
    else
      checks.push({ code: 'final_read', level: 'ok', title: t.finalRead.method === 'field_read' ? 'Field read ordered for the stop date' : 'Meter read on the stop date', detail: `Meter ${m.from.meterNumber} at ${m.from.address}, ${date(t.stopDate)}.` })
  }
  if (t.afterStop === 'lock_off')
    checks.push({ code: 'lock_off', level: 'info', title: 'Old meter locked off after the read', detail: 'A field order locks the meter so nobody uses gas on an account that has closed.' })

  /* ---- The new premise ---- */
  if (!to) {
    checks.push({ code: 'no_premise', level: 'block', title: 'Choose the new premise', detail: 'Pick the service address the customer is moving to.' })
    return checks
  }
  const occ = to.occupant
  if (occ.kind === 'customer' && occ.accountNumber !== m.accountNumber) {
    if (occ.stopOrderedFor)
      checks.push({ code: 'occupied', level: 'review', title: `${occ.name} stops there ${date(occ.stopOrderedFor)}`, detail: `Their stop is ordered. Start no earlier than ${date(occ.stopOrderedFor)} or both accounts bill the same meter.` })
    else
      checks.push({ code: 'occupied', level: 'block', title: `${occ.name} is still on service at ${to.address}`, detail: `Account ${occ.accountNumber} has no stop ordered. Their stop, or the landlord’s confirmation that they have left, comes first.` })
  } else if (occ.kind === 'owner') {
    checks.push({ code: 'owner', level: 'info', title: `${occ.name} holds service until the start`, detail: 'The meter stays on. A transfer read on the start date splits the usage; no truck roll.' })
  }
  const claimed = others.find((o) => o.id !== t.id && !o.completedAt && o.toPremiseId === to.id)
  if (claimed)
    checks.push({ code: 'claimed', level: 'block', title: `${to.address} is already in ${claimed.number}`, detail: `${claimed.mover.name} is moving in from ${date(claimed.startDate)}.` })
  if (to.priorOccupantDebt)
    checks.push({ code: 'prior_debt', level: 'info', title: `${money(to.priorOccupantDebt.amount)} left by a previous occupant`, detail: `${to.priorOccupantDebt.name} owes it on their closed account. It is not this customer’s, and it is not asked of them.` })

  /* ---- Turning the gas on ---- */
  checks.push(...turnOnChecks(t, to))

  /* ---- Money and protections ---- */
  if (Number(m.balance) > 0 && m.pastDueDays > 0)
    checks.push({ code: 'past_due', level: 'review', title: `${money(m.balance)} past due moves with the account`, detail: `${plural(m.pastDueDays, 'day')} past due. The collections clock carries on at the new premise; it does not restart.` })
  else if (Number(m.balance) > 0)
    checks.push({ code: 'balance', level: 'ok', title: `${money(m.balance)} balance stays on the account`, detail: 'Nothing is past due.' })
  if (m.arrangement) checks.push({ code: 'arrangement', level: 'info', title: 'Payment arrangement continues', detail: `${m.arrangement}. The instalments do not change with the address.` })
  if (m.protection)
    checks.push({ code: 'protection', level: 'review', title: `${m.protection.label} — re-verify at the new address`, detail: `On file to ${date(m.protection.expires)}. It belongs to the customer, but confirm it still applies at ${to.address} before it carries over.` })
  if (Number(m.deposit) > 0)
    checks.push({ code: 'deposit', level: 'ok', title: t.keepDeposit ? `${money(m.deposit)} deposit stays on the account` : `${money(m.deposit)} deposit refunded`, detail: t.keepDeposit ? 'No new deposit is asked for a move within the system.' : 'Applied to the final bill first; any remainder is refunded.' })
  checks.push({
    code: 'premise_terms',
    level: 'info',
    title: to.franchiseCity ? `${to.franchiseCity} franchise fee applies` : 'Outside city limits — no franchise fee',
    detail: `Cycle ${to.cycle}${to.cycle !== '04' ? ', so the first bill at the new premise comes on a different date' : ''}. Rate schedule ${m.isResidential ? 'R-1' : 'G-1'} carries over.`,
  })
  return checks
}

function turnOnChecks(t: TransferDraft, to: TransferPremise): TransferCheck[] {
  if (t.turnOn.completedAt)
    return [{ code: 'turn_on', level: 'ok', title: 'Gas on and relit', detail: `${date(t.turnOn.completedAt)} by ${t.turnOn.tech ?? 'field crew'}: pressure-tested, ${plural(t.turnOn.appliances, 'appliance')} relit.` }]
  if (to.meterState === 'on')
    return [{ code: 'turn_on', level: 'ok', title: 'No turn-on needed', detail: 'The meter is already on. A read on the start date opens the new service.' }]
  const out: TransferCheck[] = []
  if (!isWorkingDay(t.startDate))
    out.push({ code: 'turn_on_day', level: 'block', title: `No turn-ons on ${dayName(t.startDate)}`, detail: `Crews relight on working days only. The first one is ${date(nextWorkingDay(t.startDate))}.` })
  if (!t.turnOn.adultPresent)
    out.push({ code: 'adult', level: 'block', title: 'An adult must be home for the relight', detail: 'The tech pressure-tests the line and relights every pilot inside. Nobody home, no gas.' })
  if (!out.length)
    out.push({ code: 'turn_on', level: 'ok', title: `Turn-on ${date(t.startDate)}, ${t.turnOn.window === 'AM' ? '8 am – noon' : 'noon – 5 pm'}`, detail: `Meter ${to.meterNumber}: lock removed, pressure test, ${plural(t.turnOn.appliances, 'appliance')} to relight.` })
  return out
}

export function transferState(t: Transfer, checks: TransferCheck[]): TransferState {
  if (t.completedAt) return 'completed'
  if (checks.some((c) => c.level === 'block')) return 'blocked'
  if (checks.some((c) => c.level === 'review')) return 'needs_review'
  return 'scheduled'
}

/** Recorded transfers that are blocked or waiting on a person — the Transfers badge. */
export function transfersNeedingAttention(list: Transfer[] = transfers): number {
  return list.filter((t) => {
    const s = transferState(t, evaluateTransfer(t, list, false))
    return s === 'blocked' || s === 'needs_review'
  }).length
}

/**
 * The final bill at the old premise before the read is in: the days since the
 * last regular read at the customer's recent daily usage, with the monthly
 * charges prorated the way the R-1 tariff prorates a partial period.
 */
export function finalBillEstimate(daysOfService: number, thermsPerDay: number, insideCity: boolean) {
  const c = currentCard
  const share = daysOfService / 30
  const therms = Math.round(daysOfService * thermsPerDay * 100) / 100
  const limit = c.block1Limit * share
  const cents = (n: number) => Math.round(n * 100) / 100
  const charges = cents(
    cents(c.customerCharge * share) +
      cents(Math.min(therms, limit) * c.block1Rate) +
      cents(Math.max(0, therms - limit) * c.block2Rate) +
      cents(therms * c.pga) +
      cents(therms * c.wna) +
      cents(c.psf * share) +
      cents(therms * c.grip),
  )
  const tax = insideCity ? cents(cents(charges * c.franchisePct) + cents(charges * c.gutPct)) : cents(charges * c.gutPct)
  return { therms, total: cents(charges + tax) }
}
