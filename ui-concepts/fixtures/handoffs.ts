/**
 * Move-outs and move-ins at the same address.
 *
 * A termination (one customer stopping service at a premise) and an
 * application (a new customer starting service there) are two requests that
 * arrive separately — often days apart, often through different channels —
 * but they meet at one meter. Reconciling them is what keeps that meter from
 * billing two accounts at once, billing nobody, or being locked off the
 * morning a new tenant moves in.
 *
 * Stop orders and applications are recorded here. Transfers of service add
 * their own move-out (the old premise) and, when someone is still on service
 * at the new premise, a move-in; `lib/handoffs.ts` gathers both and pairs
 * them by premise.
 */

/** What happens to the meter once the outgoing customer's final read is taken. */
export type AfterStop = 'lock_off' | 'owner_takes_service' | 'leave_on'

export type ReadMethod = 'meter_read' | 'field_read' | 'customer_read'

export type HandoffPremise = { number: string; address: string; city: string; meterNumber: string; meterState: 'on' | 'locked_off' }

/** A customer stopping service at a premise. */
export type MoveOut = {
  id: string
  number: string
  requestedAt: string
  channel: 'phone' | 'walk_in' | 'portal'
  /** Set when the move-out is the old end of a transfer of service. */
  transferId?: string
  customer: { name: string; accountNumber: string; customerId?: string; phone: string }
  /** Adults named on the account at this premise, the customer included. */
  occupants: string[]
  premise: HandoffPremise
  stopDate: string
  finalRead: { method: ReadMethod; reading: string | null; takenAt: string | null }
  afterStop: AfterStop
  balance: string
  pastDueDays: number
  deposit: string
  /** Where the final bill goes. A transfer's is the new premise. */
  forwarding: string | null
}

/** A new customer applying for service at a premise. */
export type MoveIn = {
  id: string
  number: string
  requestedAt: string
  channel: 'phone' | 'walk_in' | 'portal'
  /** Set when the move-in is the new end of a transfer of service. */
  transferId?: string
  applicant: { name: string; phone: string; accountNumber?: string; customerId?: string }
  premise: HandoffPremise
  startDate: string
  openingRead: { method: ReadMethod; reading: string | null; takenAt: string | null }
  idVerified: boolean
  /** The applicant says they lived at this premise before applying in their own name. */
  livedHere: boolean
  deposit: { amount: string; basis: string }
  /** Who is on service at the premise today, when it is someone other than the outgoing customer on file. */
  currentCustomer: { name: string; accountNumber: string } | null
}

const premise = (number: string, address: string, city: string, meterNumber: string, meterState: 'on' | 'locked_off' = 'on'): HandoffPremise => ({
  number,
  address,
  city,
  meterNumber,
  meterState,
})

const P = {
  holleman: premise('P-052231', '1820 Holleman Dr W, Apt 12', 'College Station', '005512'),
  carterCreek: premise('P-063307', '2207 Carter Creek Pkwy', 'Bryan', '006170'),
  turkeyCreek: premise('P-070918', '903 Turkey Creek Rd', 'Bryan', '006933'),
  springLoop: premise('P-058842', '4005 Spring Loop', 'College Station', '005846'),
  dominik: premise('P-049975', '611 Dominik Dr', 'College Station', '004981'),
  parkPl: premise('P-081104', '1508 Park Pl', 'Bryan', '008032'),
  longmire: premise('P-076650', '3300 Longmire Dr', 'College Station', '007611'),
  austinAve: premise('P-045512', '1416 Austin Ave', 'College Station', '004430'),
  postOak: premise('P-048820', '706 Post Oak Ln', 'Bryan', '004566'),
}

export const moveOuts: MoveOut[] = [
  {
    id: 'so-0331',
    number: 'SO-2026-0331',
    requestedAt: '2026-02-12T09:40:00-06:00',
    channel: 'portal',
    customer: { name: 'Patel, Rohan', accountNumber: '100-271145', phone: '(979) 555-0177' },
    occupants: ['Patel, Rohan'],
    premise: P.holleman,
    stopDate: '2026-02-20',
    finalRead: { method: 'meter_read', reading: null, takenAt: null },
    afterStop: 'leave_on',
    balance: '84.12',
    pastDueDays: 0,
    deposit: '100.00',
    forwarding: '77 Rue Lafayette, Houston TX 77002',
  },
  {
    id: 'so-0334',
    number: 'SO-2026-0334',
    requestedAt: '2026-02-13T14:05:00-06:00',
    channel: 'phone',
    customer: { name: 'Whitfield, Grace', accountNumber: '100-262290', phone: '(979) 555-0261' },
    occupants: ['Whitfield, Grace'],
    premise: P.carterCreek,
    stopDate: '2026-02-24',
    finalRead: { method: 'meter_read', reading: null, takenAt: null },
    afterStop: 'leave_on',
    balance: '61.40',
    pastDueDays: 0,
    deposit: '0.00',
    forwarding: '1401 Kyle South Dr, Austin TX 78744',
  },
  {
    id: 'so-0329',
    number: 'SO-2026-0329',
    requestedAt: '2026-02-10T11:12:00-06:00',
    channel: 'phone',
    customer: { name: 'Lindqvist, Erik', accountNumber: '100-258803', phone: '(979) 555-0390' },
    occupants: ['Lindqvist, Erik', 'Lindqvist, Mara'],
    premise: P.turkeyCreek,
    stopDate: '2026-02-18',
    finalRead: { method: 'meter_read', reading: null, takenAt: null },
    afterStop: 'lock_off',
    balance: '0.00',
    pastDueDays: 0,
    deposit: '75.00',
    forwarding: '22 Prairie View Ln, Navasota TX 77868',
  },
  {
    id: 'so-0327',
    number: 'SO-2026-0327',
    requestedAt: '2026-02-09T08:55:00-06:00',
    channel: 'portal',
    customer: { name: 'Chen, Wei', accountNumber: '100-269917', phone: '(979) 555-0418' },
    occupants: ['Chen, Wei'],
    premise: P.springLoop,
    stopDate: '2026-02-16',
    finalRead: { method: 'customer_read', reading: '3318', takenAt: '2026-02-16T07:30:00-06:00' },
    afterStop: 'leave_on',
    balance: '47.85',
    pastDueDays: 0,
    deposit: '100.00',
    forwarding: '905 W 5th St, Austin TX 78703',
  },
  {
    id: 'so-0332',
    number: 'SO-2026-0332',
    requestedAt: '2026-02-12T16:20:00-06:00',
    channel: 'walk_in',
    customer: { name: 'Jordan, Kim', accountNumber: '100-247760', phone: '(979) 555-0522' },
    occupants: ['Jordan, Kim', 'Jordan, Alex'],
    premise: P.dominik,
    stopDate: '2026-02-19',
    finalRead: { method: 'meter_read', reading: null, takenAt: null },
    afterStop: 'leave_on',
    balance: '412.67',
    pastDueDays: 74,
    deposit: '0.00',
    forwarding: null,
  },
  {
    id: 'so-0335',
    number: 'SO-2026-0335',
    requestedAt: '2026-02-14T10:02:00-06:00',
    channel: 'phone',
    customer: { name: 'Gutierrez, Luis', accountNumber: '100-260514', phone: '(979) 555-0603' },
    occupants: ['Gutierrez, Luis'],
    premise: P.parkPl,
    stopDate: '2026-02-20',
    finalRead: { method: 'meter_read', reading: null, takenAt: null },
    afterStop: 'leave_on',
    balance: '0.00',
    pastDueDays: 0,
    deposit: '100.00',
    forwarding: '3104 Wildflower Dr, Bryan TX 77802',
  },
  {
    id: 'so-0330',
    number: 'SO-2026-0330',
    requestedAt: '2026-02-11T13:48:00-06:00',
    channel: 'phone',
    customer: { name: 'Abbott, Hugh', accountNumber: '100-251093', phone: '(979) 555-0687' },
    occupants: ['Abbott, Hugh'],
    premise: P.austinAve,
    stopDate: '2026-02-18',
    finalRead: { method: 'meter_read', reading: null, takenAt: null },
    afterStop: 'leave_on',
    balance: '38.20',
    pastDueDays: 0,
    deposit: '75.00',
    forwarding: '1209 Nueces St, Austin TX 78701',
  },
]

export const moveIns: MoveIn[] = [
  {
    id: 'ap-0418',
    number: 'AP-2026-0418',
    requestedAt: '2026-02-15T12:30:00-06:00',
    channel: 'portal',
    applicant: { name: 'Brooks, Jordan', phone: '(979) 555-0711' },
    premise: P.holleman,
    startDate: '2026-02-20',
    openingRead: { method: 'meter_read', reading: null, takenAt: null },
    idVerified: true,
    livedHere: false,
    deposit: { amount: '150.00', basis: 'No credit history on file' },
    currentCustomer: null,
  },
  {
    id: 'ap-0420',
    number: 'AP-2026-0420',
    requestedAt: '2026-02-16T09:15:00-06:00',
    channel: 'walk_in',
    applicant: { name: 'Okafor, Daniel', phone: '(979) 555-0745' },
    premise: P.postOak,
    startDate: '2026-02-19',
    openingRead: { method: 'meter_read', reading: null, takenAt: null },
    idVerified: true,
    livedHere: false,
    deposit: { amount: '0.00', basis: 'Waived — letter of good credit from his previous gas utility' },
    currentCustomer: null,
  },
  {
    id: 'ap-0416',
    number: 'AP-2026-0416',
    requestedAt: '2026-02-14T15:40:00-06:00',
    channel: 'phone',
    applicant: { name: 'Haddad, Omar', phone: '(979) 555-0782' },
    premise: P.carterCreek,
    startDate: '2026-02-18',
    openingRead: { method: 'meter_read', reading: null, takenAt: null },
    idVerified: true,
    livedHere: false,
    deposit: { amount: '100.00', basis: 'Credit score below the waiver threshold' },
    currentCustomer: null,
  },
  {
    id: 'ap-0421',
    number: 'AP-2026-0421',
    requestedAt: '2026-02-16T10:50:00-06:00',
    channel: 'portal',
    applicant: { name: 'Reyes, Paloma', phone: '(979) 555-0809' },
    premise: P.turkeyCreek,
    startDate: '2026-02-25',
    openingRead: { method: 'meter_read', reading: null, takenAt: null },
    idVerified: true,
    livedHere: false,
    deposit: { amount: '0.00', basis: 'Waived — 12 months on time at her previous address' },
    currentCustomer: null,
  },
  {
    id: 'ap-0414',
    number: 'AP-2026-0414',
    requestedAt: '2026-02-13T17:05:00-06:00',
    channel: 'phone',
    applicant: { name: 'Morris, Kayla', phone: '(979) 555-0836' },
    premise: P.springLoop,
    startDate: '2026-02-16',
    openingRead: { method: 'field_read', reading: '3342', takenAt: '2026-02-17T09:10:00-06:00' },
    idVerified: true,
    livedHere: false,
    deposit: { amount: '100.00', basis: 'Credit score below the waiver threshold' },
    currentCustomer: null,
  },
  {
    id: 'ap-0419',
    number: 'AP-2026-0419',
    requestedAt: '2026-02-15T16:25:00-06:00',
    channel: 'walk_in',
    applicant: { name: 'Jordan, Alex', phone: '(979) 555-0858' },
    premise: P.dominik,
    startDate: '2026-02-19',
    openingRead: { method: 'meter_read', reading: null, takenAt: null },
    idVerified: true,
    livedHere: true,
    deposit: { amount: '150.00', basis: 'No credit history in their own name' },
    currentCustomer: null,
  },
  {
    id: 'ap-0422',
    number: 'AP-2026-0422',
    requestedAt: '2026-02-17T08:20:00-06:00',
    channel: 'portal',
    applicant: { name: 'Bell, Tamara', phone: '(979) 555-0880' },
    premise: P.parkPl,
    startDate: '2026-02-20',
    openingRead: { method: 'meter_read', reading: null, takenAt: null },
    idVerified: false,
    livedHere: false,
    deposit: { amount: '100.00', basis: 'Pending the identity check' },
    currentCustomer: null,
  },
  {
    id: 'ap-0417',
    number: 'AP-2026-0417',
    requestedAt: '2026-02-15T11:00:00-06:00',
    channel: 'phone',
    applicant: { name: 'Fields, Nora', phone: '(979) 555-0903' },
    premise: P.longmire,
    startDate: '2026-02-23',
    openingRead: { method: 'meter_read', reading: null, takenAt: null },
    idVerified: true,
    livedHere: false,
    deposit: { amount: '0.00', basis: 'Waived — letter of good credit from her previous gas utility' },
    currentCustomer: { name: 'Ortiz, Benjamin', accountNumber: '100-263318' },
  },
]
