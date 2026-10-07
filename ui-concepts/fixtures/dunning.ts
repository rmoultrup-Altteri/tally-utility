/**
 * Automatic dunning — the tenant's configuration and the rules around it.
 *
 * The step sequence is fixed by the platform (`dunning-step-routing`): a
 * reminder, a late fee, the Termination Notice, then scheduling the
 * disconnect. What a tenant sets is whether each optional step runs, how
 * many working days after the due date it fires, and how it is sent. The
 * statutory floors are enforced by the form, and everything the engine checks
 * before taking a step is listed beside it, read-only.
 *
 * In the schema this is `tenants.settings.dunning`, reserved and empty today;
 * the target is a versioned `collections_pipeline_config` (A-14). Every
 * threshold here is built to that spec.
 */

export type DunningMode = 'off' | 'preview' | 'on'
export type ReminderChannel = 'email' | 'mail' | 'sms'
export type PresetKey = 'fastest' | 'standard' | 'gentle'

export type DunningConfig = {
  mode: DunningMode
  preset: PresetKey | 'custom'
  runTime: string
  /** Balances below this are never dunned. */
  minBalance: string
  partialPayment: 'hold' | 'continue' | 'reset'
  reminder: { enabled: boolean; days: number; channels: ReminderChannel[] }
  lateFee: { enabled: boolean; days: number; basis: 'percent' | 'flat'; amount: string; recurring: boolean; exemptPrograms: boolean }
  /** Days are working days after the due date. */
  notice: { days: number; handDelivery: boolean; emailCopy: boolean }
  /** Lead days are working days after the notice is confirmed delivered. */
  disconnect: { leadDays: number; scheduling: 'worklist' | 'automatic' }
}

/** Statutory floors, in working days. */
export const NOTICE_MIN_DAYS = 5
export const DISCONNECT_MIN_LEAD = 5

/** The preview assumes mail is confirmed delivered this many working days after it is sent. */
export const ASSUMED_TRANSIT_DAYS = 2

export const PRESETS: {
  key: PresetKey
  title: string
  summary: string
  recommended?: boolean
  timing: { reminder: number; lateFee: number; notice: number; lead: number }
}[] = [
  {
    key: 'standard',
    title: 'Standard',
    summary: 'A reminder three working days after the due date, a late fee two days later, and the termination notice two weeks out.',
    recommended: true,
    timing: { reminder: 3, lateFee: 5, notice: 10, lead: 7 },
  },
  {
    key: 'gentle',
    title: 'Gentle',
    summary: 'More time at every step. Suits a municipal system that would rather call than cut.',
    timing: { reminder: 3, lateFee: 10, notice: 15, lead: 10 },
  },
  {
    key: 'fastest',
    title: 'Fastest lawful',
    summary: 'Each step at the earliest the rules allow. Expect more calls and more truck rolls.',
    timing: { reminder: 1, lateFee: 3, notice: NOTICE_MIN_DAYS, lead: DISCONNECT_MIN_LEAD },
  },
]

export const DEFAULT_DUNNING: DunningConfig = {
  mode: 'off',
  preset: 'standard',
  runTime: '06:00',
  minBalance: '25.00',
  partialPayment: 'hold',
  reminder: { enabled: true, days: 3, channels: ['email', 'mail'] },
  lateFee: { enabled: true, days: 5, basis: 'percent', amount: '5.00', recurring: false, exemptPrograms: true },
  notice: { days: 10, handDelivery: false, emailCopy: true },
  disconnect: { leadDays: 7, scheduling: 'worklist' },
}

export function applyPreset(c: DunningConfig, key: PresetKey): DunningConfig {
  const p = PRESETS.find((x) => x.key === key)!.timing
  return {
    ...c,
    preset: key,
    reminder: { ...c.reminder, days: p.reminder },
    lateFee: { ...c.lateFee, days: p.lateFee },
    notice: { ...c.notice, days: p.notice },
    disconnect: { ...c.disconnect, leadDays: p.lead },
  }
}

/** Which preset the timing matches, if any — editing a day turns the choice to Custom. */
export function matchPreset(c: DunningConfig): PresetKey | 'custom' {
  const hit = PRESETS.find(
    (p) =>
      p.timing.reminder === c.reminder.days &&
      p.timing.lateFee === c.lateFee.days &&
      p.timing.notice === c.notice.days &&
      p.timing.lead === c.disconnect.leadDays,
  )
  return hit?.key ?? 'custom'
}

/** Problems that stop the configuration being saved, keyed by step. */
export function validateDunning(c: DunningConfig): Record<string, string> {
  const e: Record<string, string> = {}
  const whole = (n: number) => Number.isInteger(n) && n >= 1
  if (c.reminder.enabled) {
    if (!whole(c.reminder.days)) e.reminder = 'At least one working day after the due date.'
    else if (!c.reminder.channels.length) e.reminder = 'Choose at least one way to send it.'
  }
  if (c.lateFee.enabled) {
    if (!whole(c.lateFee.days)) e.lateFee = 'At least one working day after the due date.'
    else if (c.reminder.enabled && c.lateFee.days <= c.reminder.days)
      e.lateFee = 'Must come after the reminder. The engine takes one step per day.'
    else if (!/^\d+(\.\d{1,2})?$/.test(c.lateFee.amount) || Number(c.lateFee.amount) <= 0) e.lateFee = 'Enter the fee.'
  }
  const before = Math.max(c.reminder.enabled ? c.reminder.days : 0, c.lateFee.enabled ? c.lateFee.days : 0)
  if (!Number.isInteger(c.notice.days) || c.notice.days < NOTICE_MIN_DAYS)
    e.notice = `No sooner than ${NOTICE_MIN_DAYS} working days past the due date.`
  else if (c.notice.days <= before) e.notice = 'Must come after the steps before it.'
  if (!Number.isInteger(c.disconnect.leadDays) || c.disconnect.leadDays < DISCONNECT_MIN_LEAD)
    e.disconnect = `At least ${DISCONNECT_MIN_LEAD} working days after the notice is delivered.`
  if (!/^\d+(\.\d{1,2})?$/.test(c.minBalance)) e.minBalance = 'Enter an amount, or 0.00 to dun every balance.'
  return e
}

/**
 * What the engine checks every morning before it takes any step, in rank
 * order. All conditions in force are recorded, not just the first. These are
 * not settings; they are listed so an administrator knows what dunning will
 * never do.
 */
export const ALWAYS_CHECKED: { title: string; detail: string; citation?: string }[] = [
  { title: 'Bankruptcy stay', detail: 'Removes the account from collections entirely. In-flight work is recalled.' },
  {
    title: 'Extreme-weather hold',
    detail: 'Prior-day high and 24-hour forecast at or below 32°F at the county’s NWS station. Residential service.',
    citation: '16 TAC §7.460',
  },
  {
    title: 'Seriously-ill hold',
    detail: 'Physician’s statement within five working days of delinquency, with an installment agreement.',
    citation: '16 TAC §7.45',
  },
  { title: 'Agency pledge', detail: 'Inside the agency’s commitment window.', citation: '16 TAC §7.460' },
  { title: 'Payment agreement', detail: 'Active, or a missed installment still inside its grace period.' },
  { title: 'Open dispute', detail: 'Where the undisputed balance alone would not support the step.' },
  { title: 'Unapplied money', detail: 'A payment or pledge on hand that would cure the balance.' },
  { title: 'Anything unknown', detail: 'If any condition cannot be evaluated, the step does not happen. Fails closed.' },
]

export const DISCONNECT_NEVER: string[] = [
  'On a weekend or holiday, or the day before either.',
  'Unless the notice was confirmed delivered — sent is not enough.',
  'On the strength of yesterday’s check. Eligibility is evaluated again on the day of the field order.',
  'Before the customer has been offered a payment agreement where the rule requires one.',
]

export const NOTICE_RULES: string[] = [
  'Headed “Termination Notice”, in English and Spanish.',
  'By U.S. mail or hand delivery, even to a paperless customer.',
  'Copied to any third party the customer enrolled.',
  'A returned notice is re-sent another way and the step waits.',
]
