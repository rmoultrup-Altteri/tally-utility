/**
 * Domain vocabulary.
 *
 * Persisted values are snake_case and lower-case; the industry writes them
 * differently. Ccf, Mcf, Dth, AMR, AMI, PGA and WNA are not arbitrary
 * capitalisation — getting them wrong on screen is the fastest way to tell a
 * utility director that the vendor does not know gas.
 */

const UNIT_LABELS: Record<string, string> = {
  ccf: 'Ccf',
  mcf: 'Mcf',
  cubic_feet: 'cu ft',
  cubic_meters: 'm³',
  therms: 'th',
  gallons: 'gal',
  kgal: 'kgal',
  kwh: 'kWh',
  kw: 'kW',
}

/** The unit as an operator writes it. Falls back to the stored value. */
export function unitLabel(unit: string | null | undefined): string {
  if (!unit) return ''
  return UNIT_LABELS[unit] ?? unit
}

const ACRONYMS: Record<string, string> = {
  amr: 'AMR',
  ami: 'AMI',
  pga: 'PGA',
  wna: 'WNA',
  gps: 'GPS',
  ai: 'AI',
  nsf: 'NSF',
  ach: 'ACH',
  ivr: 'IVR',
  grip: 'GRIP',
  liheap: 'LIHEAP',
  psf: 'PSF',
  isd: 'ISD',
  photo_ai: 'Photo AI',
}

/**
 * Turn a stored snake_case value into a label, respecting industry acronyms.
 * `amr` becomes AMR, not Amr.
 */
export function label(value: string | null | undefined): string {
  if (!value) return ''
  if (ACRONYMS[value]) return ACRONYMS[value]
  return value
    .split('_')
    .map((word) => ACRONYMS[word] ?? word)
    .join(' ')
    .replace(/^./, (c) => c.toUpperCase())
}

const RATE_UNIT_LABELS: Record<string, string> = {
  per_therm: '/therm',
  per_ccf: '/Ccf',
  per_mcf: '/Mcf',
  per_month: '/month',
  per_year: '/year',
  per_day: '/day',
  per_gallon: '/gal',
  per_kgal: '/kgal',
  per_kwh: '/kWh',
  per_cubic_meter: '/m³',
  percent: '',
  flat: '',
  decimal: '',
}

/** The suffix that follows a rate, e.g. `$0.43850` + `/therm`. */
export function rateUnitLabel(unit: string | null | undefined): string {
  if (!unit) return ''
  return RATE_UNIT_LABELS[unit] ?? ` ${label(unit)}`
}
