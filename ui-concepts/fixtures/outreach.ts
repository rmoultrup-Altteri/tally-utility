import type { Lang } from '@/fixtures/templates'
import { cycle, asOf } from '@/fixtures/tenant'
import { customerById, locationById, serviceLinks } from '@/fixtures/accounts'
import { customerName } from '@/schemas/models'
import { billFor, explain, explainDraft, weatherExpected, type Explanation } from '@/lib/bill-explain'

/**
 * High-bill outreach for Cycle 04.
 *
 * The pre-mail exception queue already knows, before a single bill is mailed,
 * which draft bills jumped. Every utility then waits for those customers to
 * call. This list is the alternative: tell them first, with the reason, while
 * there is still time to offer budget billing or an arrangement — and before
 * the first angry call lands in the queue.
 *
 * Each candidate's change is split by the bill-explanation engine — weather,
 * usage beyond the weather, gas cost, everything else — so the one-line reason
 * in the heads-up is the same reason the customer will read in the portal
 * after the bill arrives. Accounts the prototype does not model carry their
 * figures as given, split the same four ways and summing to the cent.
 *
 * A heads-up is a courtesy. It is not a notice under 16 TAC §7.460, it does
 * not start dunning, and nothing about it is required — which is why every
 * exclusion below is listed with its reason rather than silently dropped.
 */

export const OUTREACH_POLICY = {
  /** From Settings → Billing, “Warn on a bill amount swing over”. */
  swingPct: 30,
  minIncreaseCents: 2500,
  basisLabel: 'same period last year',
  sendBefore: cycle.billDate,
  quietStart: 8,
  quietEnd: 20,
} as const

export type Flag = 'medical' | 'collections' | 'payment_plan' | 'autopay' | 'paperless' | 'commercial'

export type Plan = 'text_email' | 'email' | 'text' | 'call' | 'bill_message'

export type Drivers = { weather: number; usage: number; gasCost: number; other: number }

export type Candidate = {
  id: string
  /** A fixture account, or null for one the prototype does not model (shown as plain text). */
  customerId: string | null
  invoiceId: string | null
  accountNumber: string
  name: string
  firstName: string
  lang: Lang
  address: string
  priorCents: number
  draftCents: number
  drivers: Drivers
  /** Usage beyond the weather is big enough to suggest a safety check or an appliance. */
  usageFlag: boolean
  reach: { email: string | null; mobile: string | null; smsConsent: boolean }
  flags: Flag[]
  plan: Plan
  planWhy: string
}

export type Excluded = { accountNumber: string; customerId: string | null; name: string; changePct: number; reason: string }

/* ---- Drivers from the engine ---------------------------------------- */

function driversOf(e: Explanation): Drivers {
  const get = (k: string) => e.drivers.filter((d) => d.key === k).reduce((a, d) => a + d.cents, 0)
  const weather = get('weather')
  const usage = get('usage')
  const gasCost = get('gas_cost')
  return { weather, usage, gasCost, other: e.delta - weather - usage - gasCost }
}

/** February's factors, laid over each account's latest bill to price its draft. */
const FEB_FACTORS = { 'R-1': { pga: 0.4385, wna: -0.0213 }, 'G-1': { pga: 0.4385, wna: -0.0184 } } as const

function fixtureCandidate(
  customerId: string,
  opts: { behaviour?: number; flags?: Flag[]; smsConsent?: boolean; lang?: Lang },
): { e: Explanation; c: Omit<Candidate, 'plan' | 'planWhy'> } | null {
  const customer = customerById.get(customerId)!
  const link = serviceLinks.find((l) => l.customerId === customerId)
  const loc = link ? locationById.get(link.locationId) : undefined
  const draft = billFor(customerId, cycle.periodLabel)
  let e: Explanation | null
  if (draft) e = explain(draft, 'year')
  else {
    const expected = weatherExpected(customerId, cycle.periodLabel)
    const schedule = customer.customer_type === 'residential' ? 'R-1' : 'G-1'
    e = expected === null ? null : explainDraft(customerId, cycle.periodLabel, expected * (opts.behaviour ?? 1), FEB_FACTORS[schedule])
  }
  if (!e) return null
  return {
    e,
    c: {
      id: `out-${customerId}`,
      customerId,
      invoiceId: draft?.id ?? null,
      accountNumber: customer.customer_number,
      name: customerName(customer),
      firstName: customer.first_name ?? customerName(customer),
      lang: opts.lang ?? 'en',
      address: loc ? `${loc.address}, ${loc.city}` : '',
      priorCents: e.priorCents,
      draftCents: e.currentCents,
      drivers: driversOf(e),
      usageFlag: e.usageFlag,
      reach: { email: customer.email, mobile: customer.phone, smsConsent: opts.smsConsent ?? false },
      flags: opts.flags ?? [],
    },
  }
}

/* ---- Accounts the prototype does not model --------------------------- */

function seeded(seed: number): () => number {
  let s = seed >>> 0
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0
    return s / 4294967296
  }
}

const FIRST = ['James', 'Linda', 'Roberto', 'Patricia', 'Darnell', 'Guadalupe', 'Karen', 'Hector', 'Shirley', 'Tyrone', 'Yolanda', 'Brian', 'Esperanza', 'Gary', 'Monique', 'Ruben', 'Deborah', 'Luis', 'Carol', 'Andre', 'Rosa', 'Kevin', 'Teresa', 'Jorge', 'Brenda', 'Marcus', 'Leticia', 'Dale', 'Imani', 'Victor']
const LAST = ['Whitaker', 'Salinas', 'Okonkwo', 'Garza', 'Pruitt', 'Villarreal', 'Hensley', 'Treviño', 'McBride', 'Castañeda', 'Dunn', 'Ochoa', 'Lockhart', 'Benavides', 'Rhodes', 'Ybarra', 'Sutton', 'Cortez', 'Haskins', 'Galván']
const STREETS = ['Ashburn St', 'Cavitt Ave', 'Tabor Rd', 'Villa Maria Rd', 'Briarcrest Dr', 'Kent St', 'Sulphur Springs Rd', 'Wayside Dr', 'Coulter Dr', 'Eastmark Dr', 'Holleman Dr', 'Navarro Dr']
const SPANISH_LEANING = new Set(['Roberto', 'Guadalupe', 'Hector', 'Yolanda', 'Esperanza', 'Ruben', 'Luis', 'Rosa', 'Teresa', 'Jorge', 'Leticia', 'Victor'])

function synthetic(): { kept: Omit<Candidate, 'plan' | 'planWhy'>[]; excluded: Excluded[] } {
  const rand = seeded(20260217)
  const kept: Omit<Candidate, 'plan' | 'planWhy'>[] = []
  const excluded: Excluded[] = []
  const used = new Set<string>()
  let i = 0
  while (kept.length < 40) {
    i += 1
    const first = FIRST[Math.floor(rand() * FIRST.length)]
    const last = LAST[Math.floor(rand() * LAST.length)]
    if (used.has(first + last)) continue
    used.add(first + last)
    const prior = Math.round((70 + rand() * 120) * 100)
    /* Last February was 28% warmer; the weather alone moves a heating bill a quarter to two-fifths. */
    const weather = Math.round(prior * (0.24 + rand() * 0.18))
    const big = rand() < 0.1
    const usage = Math.round(prior * (big ? 0.12 + rand() * 0.22 : -0.04 + rand() * 0.1))
    /* PGA fell from $0.4712 to $0.4385 a therm, so gas cost is a small credit on nearly every bill. */
    const gasCost = -Math.round(prior * (0.035 + rand() * 0.02))
    const other = Math.round(prior * (0.035 + rand() * 0.025))
    const delta = weather + usage + gasCost + other
    const acct = `100-${String(240000 + Math.floor(rand() * 70000)).padStart(6, '0')}`
    const name = `${first} ${last}`
    const pct = delta / prior
    if (pct * 100 < OUTREACH_POLICY.swingPct || delta < OUTREACH_POLICY.minIncreaseCents) continue
    const r = rand()
    if (r < 0.07) {
      excluded.push({ accountNumber: acct, customerId: null, name, changePct: pct, reason: 'On budget billing — the payment does not change, so there is nothing to warn about' })
      continue
    }
    if (r < 0.1) {
      excluded.push({ accountNumber: acct, customerId: null, name, changePct: pct, reason: 'Opted out of courtesy messages' })
      continue
    }
    const hasEmail = rand() < 0.84
    const hasMobile = rand() < 0.78
    const flags: Flag[] = []
    if (rand() < 0.24) flags.push('autopay')
    if (rand() < 0.38) flags.push('paperless')
    if (rand() < 0.05) flags.push('payment_plan')
    if (rand() < 0.03) flags.push('medical')
    kept.push({
      id: `out-s${String(i).padStart(3, '0')}`,
      customerId: null,
      invoiceId: null,
      accountNumber: acct,
      name,
      firstName: first,
      lang: SPANISH_LEANING.has(first) && rand() < 0.55 ? 'es' : 'en',
      address: `${1000 + Math.floor(rand() * 4800)} ${STREETS[Math.floor(rand() * STREETS.length)]}`,
      priorCents: prior,
      draftCents: prior + delta,
      drivers: { weather, usage, gasCost, other },
      usageFlag: big && usage >= 2000,
      reach: {
        email: hasEmail ? `${first[0].toLowerCase()}${last.toLowerCase().normalize('NFD').replace(/[^a-z]/g, '')}@example.com` : null,
        mobile: hasMobile ? `(979) 555-${String(1000 + Math.floor(rand() * 8999)).slice(0, 4)}` : null,
        smsConsent: hasMobile && rand() < 0.72,
      },
      flags,
    })
  }
  return { kept, excluded }
}

/* ---- The plan for each customer ------------------------------------- */

function planFor(c: Omit<Candidate, 'plan' | 'planWhy'>): { plan: Plan; planWhy: string } {
  if (c.flags.includes('medical'))
    return { plan: 'call', planWhy: 'Medical certificate on file — a person calls, and can offer an arrangement on the spot.' }
  if (c.flags.includes('collections'))
    return { plan: 'call', planWhy: 'Already in collections — a call can pair the warning with a payment arrangement.' }
  const text = c.reach.mobile && c.reach.smsConsent
  if (text && c.reach.email) return { plan: 'text_email', planWhy: 'Texts go only to customers who opted in; the email carries the detail.' }
  if (c.reach.email)
    return { plan: 'email', planWhy: c.reach.mobile ? 'No text consent on file, so email only.' : 'No mobile number on file.' }
  if (text) return { plan: 'text', planWhy: 'Text only — no email on file.' }
  return { plan: 'bill_message', planWhy: 'No email or text consent. A letter would arrive after the bill, so the explanation prints on the bill instead.' }
}

/* ---- Assemble -------------------------------------------------------- */

const herrera = fixtureCandidate('cus-0001', { flags: ['medical', 'paperless'], smsConsent: true })
const boyd = fixtureCandidate('cus-0002', { behaviour: 1.12, smsConsent: true })
const fry = fixtureCandidate('cus-0006', { behaviour: 1.12, flags: ['collections'] })
const linen = fixtureCandidate('cus-0003', { behaviour: 1.07, flags: ['commercial', 'collections'] })
const syn = synthetic()

const pick = [herrera, boyd, fry, linen].filter((x): x is NonNullable<typeof x> => x !== null).map((x) => x.c)

export const candidates: Candidate[] = [...pick, ...syn.kept]
  .filter((c) => {
    const delta = c.draftCents - c.priorCents
    return delta >= OUTREACH_POLICY.minIncreaseCents && (delta / c.priorCents) * 100 >= OUTREACH_POLICY.swingPct
  })
  .map((c) => ({ ...c, ...planFor(c) }))
  .sort((a, b) => b.draftCents - b.priorCents - (a.draftCents - a.priorCents))

/** Over the line, and deliberately not contacted. Each says why. */
export const excluded: Excluded[] = [
  {
    accountNumber: customerById.get('cus-0005')!.customer_number,
    customerId: 'cus-0005',
    name: customerName(customerById.get('cus-0005')!),
    changePct: 0.46,
    reason: 'Third estimated read in a row — the bill will change once an actual read posts. Warn on a real number, not a guess.',
  },
  ...syn.excluded,
]

const reachable = candidates.filter((c) => c.plan !== 'bill_message')

export const outreachSummary = {
  overThreshold: candidates.length + excluded.length,
  toContact: reachable.length,
  byPlan: {
    text_email: candidates.filter((c) => c.plan === 'text_email').length,
    email: candidates.filter((c) => c.plan === 'email').length,
    text: candidates.filter((c) => c.plan === 'text').length,
    call: candidates.filter((c) => c.plan === 'call').length,
    bill_message: candidates.filter((c) => c.plan === 'bill_message').length,
  },
  mostlyWeather: candidates.filter((c) => c.drivers.weather >= Math.max(c.drivers.usage, 0) && c.drivers.weather > 0).length,
  usageBeyondWeather: candidates.filter((c) => c.usageFlag).length,
  spanish: candidates.filter((c) => c.lang === 'es').length,
  extraCents: candidates.reduce((a, c) => a + c.draftCents - c.priorCents, 0),
  /** Texts and calls go out inside these hours, local time; anything later waits for morning. */
  sendsNow: (() => {
    /* The hour as the utility's clock reads it, not the server's. */
    const h = Number(asOf.recordedAt.slice(11, 13))
    return h >= OUTREACH_POLICY.quietStart && h < OUTREACH_POLICY.quietEnd
  })(),
}

export const candidateById = new Map(candidates.map((c) => [c.id, c]))
