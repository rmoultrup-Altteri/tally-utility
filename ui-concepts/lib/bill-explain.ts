import type { Invoice, InvoiceLine } from '@/schemas/models'
import { invoices, linesByInvoiceId } from '@/fixtures/billing'
import { PERIODS, weatherByPeriod, type PeriodWeather } from '@/fixtures/weather'
import { tenant } from '@/fixtures/tenant'

/**
 * Why a bill changed, in exact cents.
 *
 * "Why is my bill so high" is the call that spikes every January, and the
 * honest answer is almost always a mix: it was colder, gas cost moved, a rider
 * started, and sometimes the house really did burn more. This module splits the
 * difference between two bills into those causes so a CSR — or the customer, in
 * the portal — can read it in plain words.
 *
 * The method is re-pricing, one change at a time. Start from the comparison
 * bill; re-price it at the volume the weather alone would predict; then at the
 * volume actually used; then swap in the new gas cost, the new weather
 * adjustment, and each base-rate change in turn. Every step is priced line by
 * line and rounded to the cent the way the biller writes lines, so the steps
 * telescope: they add up to the real difference to the cent. Taxes are the
 * actual difference in taxes, because they ride on everything above them.
 *
 * Money is integer cents from here to the screen. Nothing is summed in floats.
 */

export type Basis = 'year' | 'month'
export type Lang = 'en' | 'es'

/** The prices a bill was priced at, read back off its own lines. */
export type PriceSheet = {
  schedule: string
  customerCharge: number
  /** Upper bound of the first block, in therms. */
  blockLimit: number
  block1: number
  block2: number
  pga: number
  wna: number
  grip: number
  psf: number
  taxes: { label: string; rate: number }[]
}

const BLOCK_LIMIT: Record<string, number> = { 'R-1': 50, 'G-1': 500 }

const num = (v: string | null | undefined) => (v == null ? 0 : Number(v))
/** quantity × rate, rounded half-up to the cent — the biller's own rule. */
const extend = (qty: number, rate: number) => Math.round(qty * rate * 100)
const q2 = (v: number) => Math.round(v * 100) / 100
const cents = (v: string) => Math.round(Number(v) * 100)

/** Billed therms on a bill: the gas line carries the derivation. */
export function thermsOn(lines: InvoiceLine[]): number {
  const gas = lines.find((l) => l.charge_type === 'pga')
  return num(gas?.gas_therms_billed ?? gas?.usage_quantity)
}

export function sheetFrom(lines: InvoiceLine[]): PriceSheet {
  const schedule = lines.find((l) => l.rate_schedule_code)?.rate_schedule_code ?? 'R-1'
  const blocks = lines.filter((l) => l.charge_type === 'volumetric')
  const therms = thermsOn(lines)
  const first = blocks[0]
  /* A first block shorter than the whole volume tells us where the break is. */
  const limit =
    first && blocks.length > 1 ? num(first.usage_quantity) : (BLOCK_LIMIT[schedule] ?? Math.max(therms, 1))
  const rider = (code: string) => num(lines.find((l) => l.rate_item_code === code)?.rate)
  return {
    schedule,
    customerCharge: num(lines.find((l) => l.charge_type === 'customer_charge')?.rate),
    blockLimit: limit,
    block1: num(first?.rate),
    block2: num(blocks[1]?.rate ?? first?.rate),
    pga: num(lines.find((l) => l.charge_type === 'pga')?.rate),
    wna: num(lines.find((l) => l.charge_type === 'wna')?.rate),
    grip: rider('GRIP-2025'),
    psf: rider('PSF-TX'),
    taxes: lines
      .filter((l) => l.display_group === 'taxes_fees')
      .map((l) => ({ label: l.description, rate: num(l.rate) })),
  }
}

export type Priced = {
  base: number
  distribution: number
  gas: number
  wna: number
  riders: number
  charges: number
  taxes: number
  total: number
}

/** One bill's charges at a volume and a price sheet, in cents. */
export function priceAt(therms: number, s: PriceSheet): Priced {
  const t = q2(Math.max(0, therms))
  const b1 = q2(Math.min(t, s.blockLimit))
  const b2 = q2(t - b1)
  const base = Math.round(s.customerCharge * 100)
  const distribution = extend(b1, s.block1) + (b2 > 0 ? extend(b2, s.block2) : 0)
  const gas = extend(t, s.pga)
  const wna = s.wna ? extend(t, s.wna) : 0
  const riders = Math.round(s.psf * 100) + (s.grip ? extend(t, s.grip) : 0)
  const charges = base + distribution + gas + wna + riders
  const taxes = s.taxes.reduce((a, x) => a + Math.round(charges * x.rate), 0)
  return { base, distribution, gas, wna, riders, charges, taxes, total: charges + taxes }
}

/* ---- Finding the comparison bill ------------------------------------- */

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
const MONTHS_ES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre']

function shiftPeriod(label: string, months: number): string {
  const [m, y] = label.split(' ')
  const idx = MONTHS.indexOf(m) + Number(y) * 12 - months
  return `${MONTHS[idx % 12]} ${Math.floor(idx / 12)}`
}

/** "Feb 2026" → "February" / "febrero", for the sentences a customer reads. */
export function monthName(label: string, lang: Lang): string {
  const i = MONTHS.indexOf(label.split(' ')[0])
  if (i < 0) return label
  return lang === 'es' ? MONTHS_ES[i] : new Date(Date.UTC(2026, i, 1)).toLocaleString('en-US', { month: 'long', timeZone: 'UTC' })
}

/** The live bill a customer had for a period: never a void one. */
export function billFor(customerId: string, period: string): Invoice | null {
  return (
    invoices.find(
      (i) => i.customer_id === customerId && i.billing_period === period && i.status !== 'void',
    ) ?? null
  )
}

export function comparisonFor(invoice: Invoice, basis: Basis): Invoice | null {
  return billFor(invoice.customer_id, shiftPeriod(invoice.billing_period, basis === 'year' ? 12 : 1))
}

/**
 * How much gas the home burns when it is not heating: the average of its
 * summer bills. Weather explains everything above this line and nothing below.
 */
export function baseLoadFor(customerId: string): number {
  const summer = ['Jun 2025', 'Jul 2025', 'Aug 2025', 'Sep 2025']
    .map((p) => billFor(customerId, p))
    .filter((i): i is Invoice => i !== null)
    .map((i) => thermsOn(linesByInvoiceId(i.id)))
  return summer.length ? summer.reduce((a, b) => a + b, 0) / summer.length : 0
}

/* ---- The explanation -------------------------------------------------- */

export type DriverKey = 'weather' | 'usage' | 'gas_cost' | 'wna' | 'rates' | 'taxes' | 'rounding'

export type Driver = {
  key: DriverKey
  cents: number
  /** For base-rate changes, which items moved and by how much. */
  parts?: { label: string; cents: number }[]
}

export type Explanation = {
  /** The bill being explained — null for a draft the run has not written yet. */
  current: Invoice | null
  prior: Invoice
  period: string
  basis: Basis
  /** Current charges plus taxes — the previous balance is not part of the change. */
  currentCents: number
  priorCents: number
  delta: number
  drivers: Driver[]
  therms: { current: number; prior: number; expected: number; beyondWeather: number }
  weather: { current: PeriodWeather | null; prior: PeriodWeather | null }
  baseLoad: number
  sheets: { current: PriceSheet; prior: PriceSheet }
  /** True when usage beyond the weather is big enough to be worth a conversation. */
  usageFlag: boolean
  verdict: 'weather' | 'usage' | 'gas_cost' | 'rates' | 'lower' | 'flat'
}

type Side = { sheet: PriceSheet; therms: number; weather: PeriodWeather | null }

/**
 * The split itself, between any two pricings of the same premise. Shared by
 * issued bills and by drafts still sitting in a run, so the heads-up a
 * customer gets before the bill and the explanation they read after it can
 * never disagree.
 */
export function decompose(a: Side, b: Side, base: number) {
  const { sheet: A, therms: tA, weather: wA } = a
  const { sheet: B, therms: tB, weather: wB } = b

  /*
   * What the weather alone predicts: the comparison period's heating load per
   * degree day, carried to this period's degree days. A summer comparison has
   * too few degree days to measure a heating load from, so it attributes
   * nothing to weather rather than inventing a slope.
   */
  let expected = tA
  if (wA && wB && wA.hdd >= 20) {
    const heating = Math.max(tA - base, 0) / wA.hdd
    expected = Math.min(tA, base) + heating * wB.hdd
  }
  expected = q2(Math.max(expected, 0))

  const at = (t: number, s: PriceSheet) => priceAt(t, s).charges
  const steps: Driver[] = []
  const p0 = at(tA, A)
  const p1 = at(expected, A)
  const p2 = at(tB, A)
  steps.push({ key: 'weather', cents: p1 - p0 })
  steps.push({ key: 'usage', cents: p2 - p1 })

  const withGas = { ...A, pga: B.pga }
  const p3 = at(tB, withGas)
  steps.push({ key: 'gas_cost', cents: p3 - p2 })

  const withWna = { ...withGas, wna: B.wna }
  const p4 = at(tB, withWna)
  steps.push({ key: 'wna', cents: p4 - p3 })

  /* Base rates and riders, one item at a time so each gets its own line. */
  const parts: { label: string; cents: number }[] = []
  let sheet = withWna
  let prev = p4
  const swap = (label: string, patch: Partial<PriceSheet>) => {
    sheet = { ...sheet, ...patch }
    const next = at(tB, sheet)
    if (next !== prev) parts.push({ label, cents: next - prev })
    prev = next
  }
  swap('customer', { customerCharge: B.customerCharge })
  swap('distribution', { block1: B.block1, block2: B.block2, blockLimit: B.blockLimit })
  swap('psf', { psf: B.psf })
  swap(A.grip === 0 && B.grip > 0 ? 'grip_new' : 'grip', { grip: B.grip })
  steps.push({ key: 'rates', cents: prev - p4, parts })

  /* Taxes are a percentage of everything above, so they are the actual difference in taxes, last. */
  const before = priceAt(tA, A)
  const after = priceAt(tB, B)
  steps.push({ key: 'taxes', cents: after.taxes - before.taxes })

  const delta = after.total - before.total
  const usage = p2 - p1
  const beyondWeather = q2(tB - expected)
  const usageFlag = usage >= 500 && beyondWeather >= Math.max(5, expected * 0.1)

  let verdict: Explanation['verdict'] = 'flat'
  if (Math.abs(delta) < 100) verdict = 'flat'
  else if (delta < 0) verdict = 'lower'
  else {
    const ranked = steps
      .filter((s) => ['weather', 'usage', 'gas_cost', 'rates'].includes(s.key))
      .sort((x, y) => y.cents - x.cents)
    verdict = ranked[0].key as Explanation['verdict']
  }

  return {
    priorCents: before.total,
    currentCents: after.total,
    delta,
    drivers: steps,
    therms: { current: tB, prior: tA, expected, beyondWeather },
    weather: { current: wB, prior: wA },
    baseLoad: base,
    sheets: { current: B, prior: A },
    usageFlag,
    verdict,
  }
}

/** Why an issued (or draft) bill differs from the comparison bill. */
export function explain(invoice: Invoice, basis: Basis): Explanation | null {
  const prior = comparisonFor(invoice, basis)
  if (!prior) return null
  const curLines = linesByInvoiceId(invoice.id)
  const priLines = linesByInvoiceId(prior.id)
  const d = decompose(
    { sheet: sheetFrom(priLines), therms: thermsOn(priLines), weather: weatherByPeriod[prior.billing_period] ?? null },
    { sheet: sheetFrom(curLines), therms: thermsOn(curLines), weather: weatherByPeriod[invoice.billing_period] ?? null },
    baseLoadFor(invoice.customer_id),
  )

  /* The model reproduces every issued bill to the cent. If one ever did not, the gap is said out loud, not hidden in a step. */
  const actualCurrent = cents(invoice.total_charges) + cents(invoice.total_taxes)
  const actualPrior = cents(prior.total_charges) + cents(prior.total_taxes)
  const residual = actualCurrent - actualPrior - d.delta
  if (residual !== 0) d.drivers.push({ key: 'rounding', cents: residual })

  return {
    ...d,
    current: invoice,
    prior,
    period: invoice.billing_period,
    basis,
    currentCents: actualCurrent,
    priorCents: actualPrior,
    delta: actualCurrent - actualPrior,
  }
}

/**
 * A draft bill the run has priced but not written as an invoice — what the
 * outreach board needs before bills post. The draft is priced on the
 * comparison bill's own sheet with this period's gas cost and weather
 * adjustment laid over it.
 */
export function explainDraft(
  customerId: string,
  period: string,
  therms: number,
  overlay: Partial<PriceSheet>,
  basis: Basis = 'year',
): Explanation | null {
  const prior = billFor(customerId, shiftPeriod(period, basis === 'year' ? 12 : 1))
  if (!prior) return null
  /* The latest issued bill carries today's base rates and riders; the overlay adds this period's factors. */
  const latest = billFor(customerId, shiftPeriod(period, 1)) ?? prior
  const priLines = linesByInvoiceId(prior.id)
  const sheet = { ...sheetFrom(linesByInvoiceId(latest.id)), ...overlay }
  const d = decompose(
    { sheet: sheetFrom(priLines), therms: thermsOn(priLines), weather: weatherByPeriod[prior.billing_period] ?? null },
    { sheet, therms: q2(therms), weather: weatherByPeriod[period] ?? null },
    baseLoadFor(customerId),
  )
  return { ...d, current: null, prior, period, basis }
}

/** The therms the weather alone predicts for a period, from the comparison bill — the anchor drafts are built on. */
export function weatherExpected(customerId: string, period: string, basis: Basis = 'year'): number | null {
  const prior = billFor(customerId, shiftPeriod(period, basis === 'year' ? 12 : 1))
  if (!prior) return null
  const tA = thermsOn(linesByInvoiceId(prior.id))
  const wA = weatherByPeriod[prior.billing_period]
  const wB = weatherByPeriod[period]
  const base = baseLoadFor(customerId)
  if (!wA || !wB || wA.hdd < 20) return tA
  return Math.min(tA, base) + (Math.max(tA - base, 0) / wA.hdd) * wB.hdd
}

/* ---- Plain words ------------------------------------------------------ */

const usd = (c: number) =>
  `$${(Math.abs(c) / 100).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
const signed = (c: number) => `${c < 0 ? '−' : '+'}${usd(c)}`
const per = (r: number) => `$${r.toFixed(4)}`
const pctOf = (a: number, b: number) => Math.round((Math.abs(a - b) / Math.max(b, 1)) * 100)
const th = (n: number) => Math.round(n).toLocaleString('en-US')

export type Verdict = Explanation['verdict']

/** The one-sentence reason, shared by the explanation, the heads-up and the portal. */
export const REASON: Record<Lang, Record<Verdict, string>> = {
  en: {
    weather: 'Most of the difference is colder weather — your heating ran more.',
    usage: 'Most of the difference is gas used beyond what the weather explains.',
    gas_cost: 'Most of the difference is the cost of natural gas, which we pass through at no markup.',
    rates: 'Most of the difference is a change in rates or charges.',
    lower: 'You used less gas, or gas cost less.',
    flat: 'Nothing changed much.',
  },
  es: {
    weather: 'La razón principal es el clima más frío: su calefacción trabajó más.',
    usage: 'La razón principal es que usó más gas de lo que el clima explica.',
    gas_cost: 'La razón principal es el costo del gas natural, que se traslada sin ganancia.',
    rates: 'La razón principal es un cambio en las tarifas o cargos.',
    lower: 'Usó menos gas o el gas costó menos.',
    flat: 'Ningún cambio importante.',
  },
}

/** The same reason in a few words, for a text message. */
export const REASON_SHORT: Record<Lang, Record<Verdict, string>> = {
  en: { weather: 'colder weather', usage: 'higher usage', gas_cost: 'the cost of gas', rates: 'a rate change', lower: 'lower usage', flat: 'small changes' },
  es: { weather: 'el clima más frío', usage: 'mayor consumo', gas_cost: 'el costo del gas', rates: 'un cambio de tarifa', lower: 'menor consumo', flat: 'cambios pequeños' },
}

export type DriverCopy = { key: DriverKey; title: string; body: string; cents: number }

export type ExplanationCopy = {
  headline: string
  summary: string
  drivers: DriverCopy[]
  comparisonLabel: string
}

/**
 * The words. English and Spanish are written side by side rather than
 * translated after the fact, so neither is a machine's afterthought — a Texas
 * gas system's customers are both.
 */
export function explanationCopy(e: Explanation, lang: Lang): ExplanationCopy {
  const es = lang === 'es'
  const curM = monthName(e.period, lang)
  const priM = monthName(e.prior.billing_period, lang)
  const compare = e.basis === 'year'
    ? es ? `${priM} del año pasado` : `last ${priM}`
    : es ? `su factura de ${priM}` : `your ${priM} bill`
  const up = e.delta > 0
  const { current: wB, prior: wA } = e.weather

  const headline =
    e.verdict === 'flat'
      ? es ? `Su factura de ${curM} es casi igual a ${compare}.` : `Your ${curM} bill is about the same as ${compare}.`
      : es
        ? `Su factura de ${curM} es ${usd(e.delta)} ${up ? 'más alta' : 'más baja'} que ${compare}.`
        : `Your ${curM} bill is ${usd(e.delta)} ${up ? 'higher' : 'lower'} than ${compare}.`

  const reason = REASON[lang]

  const summary = es
    ? `${reason[e.verdict]} Comparamos ${th(e.therms.current)} termias este periodo con ${th(e.therms.prior)} en ${compare}.`
    : `${reason[e.verdict]} You used ${th(e.therms.current)} therms this period against ${th(e.therms.prior)} ${e.basis === 'year' ? `last ${priM}` : `in ${priM}`}.`

  const colder = wA && wB ? pctOf(wB.hdd, wA.hdd) : 0
  const warmer = wA && wB && wB.hdd < wA.hdd

  const body = (d: Driver): { title: string; body: string } | null => {
    switch (d.key) {
      case 'weather':
        if (!wA || !wB || d.cents === 0)
          return es
            ? { title: 'Clima', body: 'Los dos periodos tuvieron muy poca necesidad de calefacción, así que el clima no explica la diferencia.' }
            : { title: 'Weather', body: 'Neither period needed much heating, so weather does not explain the difference.' }
        return es
          ? {
              title: warmer ? 'Clima más templado' : 'Clima más frío',
              body: `Este periodo tuvo ${wB.hdd} grados-día de calefacción contra ${wA.hdd} — ${colder}% ${warmer ? 'menos frío' : 'más frío'}. Con el mismo uso por grado de frío, eso equivale a unas ${th(Math.abs(e.therms.expected - e.therms.prior))} termias ${warmer ? 'menos' : 'más'}.`,
            }
          : {
              title: warmer ? 'Milder weather' : 'Colder weather',
              body: `This period had ${wB.hdd} heating degree days against ${wA.hdd} — ${colder}% ${warmer ? 'milder' : 'colder'}. At the same gas per degree of cold, that alone is about ${th(Math.abs(e.therms.expected - e.therms.prior))} therms ${warmer ? 'less' : 'more'}.`,
            }
      case 'usage': {
        if (Math.abs(d.cents) < 100) return null
        const more = d.cents > 0
        const t = th(Math.abs(e.therms.beyondWeather))
        return es
          ? {
              title: more ? 'Uso más allá del clima' : 'Uso menor al esperado',
              body: more
                ? `Aun tomando en cuenta el frío, usó unas ${t} termias más de lo usual en su hogar. Causas comunes: termostato más alto, un aparato de gas nuevo, visitas, o una fuga. Si huele a gas, salga y llame al ${tenant.emergencyPhone} desde afuera.`
                : `Usó unas ${t} termias menos de lo que el clima predice. Buen trabajo — eso le ahorró dinero.`,
            }
          : {
              title: more ? 'Usage beyond the weather' : 'Less usage than expected',
              body: more
                ? `Even allowing for the cold, you used about ${t} therms more than your home usually does. Common causes: a higher thermostat, a new gas appliance, guests, or a leak. If you ever smell gas, leave and call ${tenant.emergencyPhone} from outside.`
                : `You used about ${t} therms less than the weather predicts — that saved you money.`,
            }
      }
      case 'gas_cost': {
        if (d.cents === 0) return null
        const { prior: A, current: B } = e.sheets
        return es
          ? {
              title: 'Costo del gas natural',
              body: `El ajuste por gas comprado (PGA) — lo que pagamos por el gas, trasladado sin ganancia — ${B.pga > A.pga ? 'subió' : 'bajó'} de ${per(A.pga)} a ${per(B.pga)} por termia.`,
            }
          : {
              title: 'Natural gas cost',
              body: `The purchased gas adjustment — what we pay for the gas itself, passed through at no markup — ${B.pga > A.pga ? 'rose' : 'fell'} from ${per(A.pga)} to ${per(B.pga)} a therm.`,
            }
      }
      case 'wna': {
        if (d.cents === 0) return null
        const { prior: A, current: B } = e.sheets
        const normal = wB ? wB.normal : null
        const kind = (r: number) => (r < 0 ? (es ? 'crédito' : 'credit') : es ? 'cargo' : 'charge')
        const lead = A.wna
          ? es
            ? `El ${kind(B.wna)} por clima pasó de ${per(Math.abs(A.wna))} a ${per(Math.abs(B.wna))} por termia.`
            : `The weather adjustment ${kind(B.wna)} went from ${per(Math.abs(A.wna))} to ${per(Math.abs(B.wna))} a therm.`
          : es
            ? `Se aplicó un ${kind(B.wna)} de ${per(Math.abs(B.wna))} por termia.`
            : `A ${kind(B.wna)} of ${per(Math.abs(B.wna))} a therm applied this period.`
        return es
          ? {
              title: 'Ajuste por clima',
              body: `${lead} Equilibra la parte de distribución cuando el clima se aleja de lo normal${normal ? ` (${normal} grados-día es lo normal)` : ''}, para suavizar las facturas en inviernos extremos.`,
            }
          : {
              title: 'Weather adjustment',
              body: `${lead} It evens out the delivery part of your bill when weather strays from normal${normal ? ` (${normal} degree days is normal for this period)` : ''}, softening bills in extreme winters.`,
            }
      }
      case 'rates': {
        if (!d.parts?.length) return null
        const words: Record<string, [string, string]> = {
          customer: ['the monthly customer charge changed', 'cambió el cargo mensual por cliente'],
          distribution: ['delivery (distribution) rates changed', 'cambiaron las tarifas de distribución'],
          psf: ['the state pipeline safety fee changed', 'cambió el cargo estatal de seguridad de ductos'],
          grip: ['the cost-of-service adjustment (GRIP) changed', 'cambió el ajuste de costo de servicio (GRIP)'],
          grip_new: ['the cost-of-service adjustment (GRIP) was added', 'se agregó el ajuste de costo de servicio (GRIP)'],
        }
        const list = d.parts.map((p) => `${words[p.label]?.[es ? 1 : 0] ?? p.label} (${signed(p.cents)})`).join('; ')
        return es
          ? { title: 'Tarifas y cargos', body: `Desde ${compare}, ${list}.` }
          : { title: 'Rates and charges', body: `Since ${compare}, ${list}.` }
      }
      case 'taxes':
        if (d.cents === 0) return null
        return es
          ? { title: 'Impuestos y cuotas', body: 'La cuota de franquicia de la ciudad y los impuestos son un porcentaje de los cargos anteriores, así que se mueven con ellos.' }
          : { title: 'Taxes and fees', body: 'The city franchise fee and taxes are a percentage of the charges above, so they move with them.' }
      case 'rounding':
        return es
          ? { title: 'Redondeo', body: 'Centavos de redondeo entre las líneas de la factura.' }
          : { title: 'Rounding', body: 'Cents of rounding between bill lines.' }
    }
  }

  const drivers: DriverCopy[] = []
  for (const d of e.drivers) {
    const c = body(d)
    if (c) drivers.push({ key: d.key, cents: d.cents, ...c })
  }
  drivers.sort((a, b) => Math.abs(b.cents) - Math.abs(a.cents))

  return {
    headline,
    summary,
    drivers,
    comparisonLabel: e.basis === 'year' ? (es ? 'Mismo mes, año pasado' : 'Same month last year') : es ? 'Mes anterior' : 'Last month',
  }
}

export const formatCents = usd
export const formatSigned = signed

/* ---- Context for the screens ----------------------------------------- */

/** Every live bill the account has across the year, with the weather it was billed in. */
export function usageHistory(customerId: string): { label: string; therms: number; hdd: number; estimated: boolean }[] {
  return PERIODS.map((p) => {
    const bill = billFor(customerId, p)
    if (!bill) return null
    return {
      label: p,
      therms: thermsOn(linesByInvoiceId(bill.id)),
      hdd: weatherByPeriod[p].hdd,
      estimated: bill.has_estimated_reads,
    }
  }).filter((x): x is NonNullable<typeof x> => x !== null)
}

/** About what budget billing would charge: the last twelve bills' current charges, averaged and rounded up to the dollar. */
export function budgetEstimate(customerId: string): number {
  const bills = PERIODS.slice(-12)
    .map((p) => billFor(customerId, p))
    .filter((b): b is Invoice => b !== null)
  if (!bills.length) return 0
  const total = bills.reduce((a, b) => a + cents(b.total_charges) + cents(b.total_taxes), 0)
  return Math.ceil(total / bills.length / 100) * 100
}
