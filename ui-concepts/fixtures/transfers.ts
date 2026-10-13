/**
 * Transfers of service.
 *
 * A transfer moves a customer from one premise to another without closing
 * their account: service stops at the old premise on a final read and a final
 * bill, starts at the new one, and the balance, deposit and any payment
 * arrangement stay with the customer. For gas the start is a truck roll, not
 * a switch: a locked-off meter is turned on, the line pressure-tested and
 * every pilot relit with an adult present.
 *
 * Most transfers are routine. The ones that are not show on the Transfers tab
 * beside the exception queue, each with the rule that stopped it (see
 * `lib/transfers.ts`, which evaluates fixtures and new requests alike).
 */

export type MeterState = 'locked_off' | 'on'

/** Who holds service at a premise today. */
export type Occupant =
  | { kind: 'vacant' }
  | { kind: 'owner'; name: string }
  | { kind: 'customer'; name: string; accountNumber: string; stopOrderedFor: string | null }

/** A premise a customer can move to. Distinct from `locations`, which are premises with a modelled account. */
export type TransferPremise = {
  id: string
  number: string
  address: string
  city: string
  zip: string
  /** Null outside city limits: no franchise fee. */
  franchiseCity: string | null
  cycle: string
  meterNumber: string
  meterState: MeterState
  occupant: Occupant
  /** What a previous occupant left unpaid. Theirs, never the incoming customer's. */
  priorOccupantDebt: { name: string; amount: string } | null
}

export const transferPremises: TransferPremise[] = [
  {
    id: 'tp-01',
    number: 'P-090377',
    address: '1209 Welsh Ave',
    city: 'College Station',
    zip: '77840',
    franchiseCity: 'College Station',
    cycle: '04',
    meterNumber: '004311',
    meterState: 'on',
    occupant: { kind: 'customer', name: 'Vance, Theo', accountNumber: '100-266003', stopOrderedFor: null },
    priorOccupantDebt: null,
  },
  {
    id: 'tp-02',
    number: 'P-061582',
    address: '1310 Ehlinger Dr, Apt 4',
    city: 'Bryan',
    zip: '77801',
    franchiseCity: 'Bryan',
    cycle: '04',
    meterNumber: '005987',
    meterState: 'locked_off',
    occupant: { kind: 'vacant' },
    priorOccupantDebt: { name: 'Hale, Corey', amount: '186.40' },
  },
  {
    id: 'tp-03',
    number: 'P-077140',
    address: '2905 Cavitt Ave',
    city: 'Bryan',
    zip: '77801',
    franchiseCity: 'Bryan',
    cycle: '03',
    meterNumber: '006402',
    meterState: 'on',
    occupant: { kind: 'customer', name: 'Morales, Ana', accountNumber: '100-339120', stopOrderedFor: null },
    priorOccupantDebt: null,
  },
  {
    id: 'tp-04',
    number: 'P-084415',
    address: '3611 Old Oaks Dr',
    city: 'Bryan',
    zip: '77802',
    franchiseCity: 'Bryan',
    cycle: '02',
    meterNumber: '007105',
    meterState: 'locked_off',
    occupant: { kind: 'vacant' },
    priorOccupantDebt: null,
  },
  {
    id: 'tp-05',
    number: 'P-092260',
    address: '8810 Raintree Ln',
    city: 'College Station',
    zip: '77845',
    franchiseCity: 'College Station',
    cycle: '04',
    meterNumber: '008866',
    meterState: 'on',
    occupant: { kind: 'customer', name: 'Castillo, Maria', accountNumber: '100-248877', stopOrderedFor: null },
    priorOccupantDebt: null,
  },
  {
    id: 'tp-06',
    number: 'P-073318',
    address: '6020 FM 2154',
    city: 'College Station',
    zip: '77845',
    franchiseCity: null,
    cycle: '04',
    meterNumber: '007790',
    meterState: 'locked_off',
    occupant: { kind: 'vacant' },
    priorOccupantDebt: null,
  },
  {
    id: 'tp-07',
    number: 'P-091127',
    address: '415 Lincoln Ave',
    city: 'College Station',
    zip: '77840',
    franchiseCity: 'College Station',
    cycle: '04',
    meterNumber: '008214',
    meterState: 'on',
    occupant: { kind: 'owner', name: 'Aggieland Property Management' },
    priorOccupantDebt: null,
  },
]

export const transferPremiseById = new Map(transferPremises.map((p) => [p.id, p]))

/** Who is moving, and from where. Modelled accounts carry their id; the rest are the portfolio. */
export type Mover = {
  customerId?: string
  accountNumber: string
  name: string
  isResidential: boolean
  phone: string
  from: { premiseNumber: string; address: string; city: string; meterNumber: string; meterId?: string }
  balance: string
  pastDueDays: number
  deposit: string
  protection: { label: string; expires: string } | null
  arrangement: string | null
}

export type FinalReadMethod = 'meter_read' | 'field_read' | 'customer_read'
export type AfterStop = 'lock_off' | 'owner_takes_service' | 'next_customer'

export type Transfer = {
  id: string
  number: string
  requestedAt: string
  requestedBy: string
  channel: 'phone' | 'walk_in' | 'portal'
  mover: Mover
  stopDate: string
  finalRead: { method: FinalReadMethod; reading: string | null; takenAt: string | null }
  afterStop: AfterStop
  toPremiseId: string
  startDate: string
  turnOn: { window: 'AM' | 'PM'; adultPresent: boolean; appliances: number; completedAt: string | null; tech: string | null }
  /** Roll the old premise's final bill into the first bill at the new one, or bill it on its own. */
  finalBill: 'roll_forward' | 'separate'
  /** Set once the final bill is issued. Until then the screen shows an estimate. */
  finalInvoice: { number: string; amount: string } | null
  keepDeposit: boolean
  note: string | null
  completedAt: string | null
}

export const transfers: Transfer[] = [
  {
    id: 'tr-0214',
    number: 'TR-2026-0214',
    requestedAt: '2026-02-02T10:14:00-06:00',
    requestedBy: 'Renee Alvarado',
    channel: 'phone',
    mover: {
      customerId: 'cus-0008',
      accountNumber: '100-266003',
      name: 'Vance, Theo',
      isResidential: true,
      phone: '(979) 555-0619',
      from: { premiseNumber: 'P-090014', address: '4402 Hollow Oak Dr', city: 'College Station', meterNumber: '004188', meterId: 'mtr-0008' },
      balance: '0.00',
      pastDueDays: 0,
      deposit: '150.00',
      protection: null,
      arrangement: null,
    },
    stopDate: '2026-02-10',
    finalRead: { method: 'meter_read', reading: '1044', takenAt: '2026-02-10T06:00:00-06:00' },
    afterStop: 'lock_off',
    toPremiseId: 'tp-01',
    startDate: '2026-02-11',
    turnOn: { window: 'PM', adultPresent: true, appliances: 3, completedAt: '2026-02-11T14:40:00-06:00', tech: 'J. Ruiz' },
    finalBill: 'roll_forward',
    finalInvoice: null,
    keepDeposit: true,
    note: 'Customer says the register has not moved since December; field re-read ordered.',
    completedAt: null,
  },
  {
    id: 'tr-0216',
    number: 'TR-2026-0216',
    requestedAt: '2026-02-13T15:02:00-06:00',
    requestedBy: 'Renee Alvarado',
    channel: 'walk_in',
    mover: {
      accountNumber: '100-259840',
      name: 'Sandoval, Rita',
      isResidential: true,
      phone: '(979) 555-0730',
      from: { premiseNumber: 'P-048820', address: '706 Post Oak Ln', city: 'Bryan', meterNumber: '004566' },
      balance: '228.90',
      pastDueDays: 39,
      deposit: '0.00',
      protection: { label: 'Senior / disabled extended grace', expires: '2026-03-15' },
      arrangement: null,
    },
    stopDate: '2026-02-19',
    finalRead: { method: 'meter_read', reading: null, takenAt: null },
    afterStop: 'lock_off',
    toPremiseId: 'tp-02',
    startDate: '2026-02-19',
    turnOn: { window: 'AM', adultPresent: true, appliances: 2, completedAt: null, tech: null },
    finalBill: 'roll_forward',
    finalInvoice: null,
    keepDeposit: true,
    note: 'Moving to a smaller unit near her daughter.',
    completedAt: null,
  },
  {
    id: 'tr-0217',
    number: 'TR-2026-0217',
    requestedAt: '2026-02-16T11:20:00-06:00',
    requestedBy: 'Renee Alvarado',
    channel: 'portal',
    mover: {
      accountNumber: '100-266741',
      name: 'Nguyen, Elena',
      isResidential: true,
      phone: '(979) 555-0812',
      from: { premiseNumber: 'P-055013', address: '2416 Briarcrest Dr', city: 'Bryan', meterNumber: '005204' },
      balance: '440.80',
      pastDueDays: 0,
      deposit: '100.00',
      protection: null,
      arrangement: 'Payment arrangement, 1 of 6 instalments paid, next due Mar 12, 2026',
    },
    stopDate: '2026-02-20',
    finalRead: { method: 'meter_read', reading: null, takenAt: null },
    afterStop: 'lock_off',
    toPremiseId: 'tp-04',
    startDate: '2026-02-20',
    turnOn: { window: 'AM', adultPresent: true, appliances: 3, completedAt: null, tech: null },
    finalBill: 'roll_forward',
    finalInvoice: null,
    keepDeposit: true,
    note: null,
    completedAt: null,
  },
  {
    id: 'tr-0218',
    number: 'TR-2026-0218',
    requestedAt: '2026-02-16T16:45:00-06:00',
    requestedBy: 'Dana Pearce',
    channel: 'phone',
    mover: {
      accountNumber: '100-254410',
      name: 'Pruitt, Samuel',
      isResidential: true,
      phone: '(979) 555-0944',
      from: { premiseNumber: 'P-039906', address: '512 E 29th St', city: 'Bryan', meterNumber: '003877' },
      balance: '356.19',
      pastDueDays: 0,
      deposit: '75.00',
      protection: null,
      arrangement: 'Payment arrangement, 3 of 6 instalments paid, next due Mar 10, 2026',
    },
    stopDate: '2026-02-23',
    finalRead: { method: 'field_read', reading: null, takenAt: null },
    afterStop: 'owner_takes_service',
    toPremiseId: 'tp-03',
    startDate: '2026-02-23',
    turnOn: { window: 'AM', adultPresent: true, appliances: 0, completedAt: null, tech: null },
    finalBill: 'roll_forward',
    finalInvoice: null,
    keepDeposit: true,
    note: 'Landlord at 512 E 29th St takes the gas back between tenants.',
    completedAt: null,
  },
  {
    id: 'tr-0207',
    number: 'TR-2026-0207',
    requestedAt: '2026-02-03T09:31:00-06:00',
    requestedBy: 'Renee Alvarado',
    channel: 'phone',
    mover: {
      accountNumber: '100-248877',
      name: 'Castillo, Maria',
      isResidential: true,
      phone: '(979) 555-0458',
      from: { premiseNumber: 'P-044190', address: '1100 Esther Blvd', city: 'Bryan', meterNumber: '004702' },
      balance: '102.30',
      pastDueDays: 0,
      deposit: '100.00',
      protection: null,
      arrangement: 'Payment arrangement, 3 of 4 instalments paid, next due Mar 15, 2026',
    },
    stopDate: '2026-02-09',
    finalRead: { method: 'meter_read', reading: '6618', takenAt: '2026-02-09T06:00:00-06:00' },
    afterStop: 'owner_takes_service',
    toPremiseId: 'tp-05',
    startDate: '2026-02-09',
    turnOn: { window: 'AM', adultPresent: true, appliances: 0, completedAt: null, tech: null },
    finalBill: 'roll_forward',
    finalInvoice: { number: 'INV-2026-02-F04702', amount: '64.18' },
    keepDeposit: true,
    note: null,
    completedAt: '2026-02-09T17:05:00-06:00',
  },
]

export const transferById = new Map(transfers.map((t) => [t.id, t]))
