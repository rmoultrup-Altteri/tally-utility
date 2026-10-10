/**
 * The rate case behind RRC GUD-11042.
 *
 * Brazos Valley Gas filed a statement of intent in January asking for
 * $486,000 more a year in base-rate revenue, to fund bare-steel main
 * replacement and the cost of running the system. A unanimous settlement was
 * reached on 11 February; the final order is expected in March and new rates
 * take effect on 1 April.
 *
 * Everything a small utility normally pays a rate consultant to produce —
 * billing determinants, proof of revenue, typical-bill tables, redlined tariff
 * sheets, the customer notice — is computed here from the system's own bills,
 * not typed into a spreadsheet. The figures below are the case's inputs; the
 * toolkit derives the rest.
 */

export type ClassKey = 'R-1' | 'G-1'

export type Milestone = { key: string; label: string; date: string; done: boolean; detail: string }

export const rateCase = {
  docket: 'RRC GUD-11042',
  title: 'Statement of intent to change gas utility rates',
  testYear: 'Twelve billing months, Feb 2025 – Jan 2026',
  testYearShort: 'TY Jan 2026',
  requestedIncrease: 486_000,
  effectiveDate: '2026-04-01',
  /** Base-rate revenue only: gas cost (PGA), WNA and riders are outside the case. */
  scope: 'Customer and distribution charges on R-1 and G-1. Gas cost, weather adjustment and riders are outside the case.',
  milestones: [
    { key: 'test_year', label: 'Test year closed', date: '2026-01-16', done: true, detail: 'January bills issued; twelve months of actual volumes locked.' },
    { key: 'filed', label: 'Statement of intent filed', date: '2026-01-23', done: true, detail: 'Schedules A–E and the proposed tariff filed with the Commission.' },
    { key: 'notice', label: 'Customer notice mailed', date: '2026-01-30', done: true, detail: 'Sent with January bills, English and Spanish, from the communications library.' },
    { key: 'settled', label: 'Unanimous settlement', date: '2026-02-11', done: true, detail: 'Staff and intervenors agreed the full $486,000 with the class allocation below.' },
    { key: 'order', label: 'Final order', date: '2026-03-12', done: false, detail: 'Expected at the Commission’s March open meeting.' },
    { key: 'effective', label: 'New rates in effect', date: '2026-04-01', done: false, detail: 'First day of a billing month, so no bill straddles the change.' },
  ] as Milestone[],
  /**
   * Cost of service, test year. Return is rate base × rate of return; O&M is
   * the residual that makes the total equal the settled requirement, which is
   * how a settlement “black-boxes” the components it did not litigate.
   */
  costOfService: {
    rateBase: 9_840_000,
    rateOfReturn: 0.0762,
    depreciation: 1_104_600,
    taxesOther: 388_200,
    otherRevenue: 64_500,
  },
  /** The settlement's split of the increase between classes. */
  settledAllocation: { 'R-1': 0.82, 'G-1': 0.18 } as Record<ClassKey, number>,
  /** Where the settlement set the customer charges; the volumetric rates are solved to the target. */
  settledCustomerCharge: { 'R-1': 24.0, 'G-1': 52.0 } as Record<ClassKey, number>,
} as const

export const CLASSES: { key: ClassKey; name: string; codes: [string, string, string]; blockLimit: number; systemAccounts: number }[] = [
  { key: 'R-1', name: 'Residential Firm Gas Service', codes: ['CUST-CHG-RES', 'DIST-RES-T1', 'DIST-RES-T2'], blockLimit: 50, systemAccounts: 13_240 },
  { key: 'G-1', name: 'General Service', codes: ['CUST-CHG-GS', 'DIST-GS-T1', 'DIST-GS-T2'], blockLimit: 500, systemAccounts: 978 },
]

/** Rates in force today, as published in `rates.ts`. */
export const presentRates: Record<ClassKey, { cc: number; r1: number; r2: number }> = {
  'R-1': { cc: 22.5, r1: 0.1824, r2: 0.1419 },
  'G-1': { cc: 48.0, r1: 0.1085, r2: 0.0842 },
}
