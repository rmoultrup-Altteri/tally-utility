/**
 * Heating degree days by bill period, for weather zone BV-N.
 *
 * Weather belongs to the zone, not to the account, so one table serves every
 * customer on cycle 04. The actuals match the read windows the Customer 360
 * usage chart plots; the normals are the ten-year figures the WNA rider prices
 * against, which is why WNA is a credit in every winter month below — each of
 * them ran colder than normal.
 *
 * Keyed by the bill's `billing_period` label, because that is the one string a
 * bill, its comparison bill and this table all agree on.
 */

export type PeriodWeather = { hdd: number; normal: number }

export const weatherByPeriod: Record<string, PeriodWeather> = {
  'Feb 2025': { hdd: 441, normal: 498 },
  'Mar 2025': { hdd: 291, normal: 318 },
  'Apr 2025': { hdd: 132, normal: 151 },
  'May 2025': { hdd: 38, normal: 44 },
  'Jun 2025': { hdd: 2, normal: 4 },
  'Jul 2025': { hdd: 0, normal: 0 },
  'Aug 2025': { hdd: 0, normal: 0 },
  'Sep 2025': { hdd: 9, normal: 6 },
  'Oct 2025': { hdd: 96, normal: 88 },
  'Nov 2025': { hdd: 322, normal: 290 },
  'Dec 2025': { hdd: 486, normal: 455 },
  'Jan 2026': { hdd: 529, normal: 505 },
  'Feb 2026': { hdd: 612, normal: 498 },
}

/** Bill periods in order, oldest first — the x-axis of every usage chart. */
export const PERIODS = Object.keys(weatherByPeriod)

export const WEATHER_ZONE = 'BV-N'
