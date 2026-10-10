/**
 * The meter record beyond what billing reads.
 *
 * `Meter` in the schemas carries only the columns the bill and the read queue
 * use. A meter shop, a field tech and a CSR answering "when was this meter
 * last tested" need the rest of the `meters` row — the physical asset, its
 * installation, its radio, its test history — plus the two history tables the
 * DDL hangs off it, `meter_deployments` and `meter_endpoint_history`.
 *
 * Keyed by meter id so the slim `Meter` rows stay the single list of meters.
 * Three meters here serve no premise: two sit in the warehouse, and one was
 * pulled from 1418 Ashburn St after it failed a test and was swapped out.
 */

export type MeterDetail = {
  meterId: string
  /** `meters.location_id`. Null for a meter in the warehouse. */
  locationId: string | null
  serviceType: 'gas'
  rateScheduleCode: string | null
  dialCount: number | null
  sealNumber: string | null
  installDate: string | null
  removalDate: string | null
  warrantyExpiration: string | null
  /** Pressure and temperature correction. 1.0000 at standard delivery pressure. */
  meterFactor: string | null
  amiSystem: string | null
  amiLastSyncAt: string | null
  amiSyncStatus: 'ok' | 'error' | 'not_configured'
  amiSyncError: string | null
  testIntervalMonths: number | null
  lastTestDate: string | null
  nextTestDueDate: string | null
  lastTestResult: 'pass' | 'fail' | null
  lastTestAccuracy: string | null
  startDate: string
  endDate: string | null
  lastReadValue: string | null
  lastReadDate: string | null
  locationNotes: string | null
  estimationBlocked: boolean
  estimationBlockedReason: string | null
  replacesMeterId: string | null
  swapReason: string | null
  warehouseLocation: string | null
  externalId: string | null
}

export type MeterDeployment = {
  meterId: string
  deploymentNumber: number
  locationId: string
  installDate: string
  installReadValue: string
  installedBy: string
  removalDate: string | null
  removalReadValue: string | null
  removalReason: string | null
  removedBy: string | null
}

export type EndpointHistory = {
  meterId: string
  endpointId: string
  endpointType: string
  installDate: string
  removalDate: string | null
  removalReason: string | null
  installedBy: string
}

const base = {
  serviceType: 'gas',
  amiLastSyncAt: null,
  amiSyncError: null,
  removalDate: null,
  endDate: null,
  locationNotes: null,
  estimationBlocked: false,
  estimationBlockedReason: null,
  replacesMeterId: null,
  swapReason: null,
  warehouseLocation: null,
} as const

export const meterDetails: MeterDetail[] = [
  {
    ...base,
    meterId: 'mtr-0001',
    locationId: 'loc-0001',
    rateScheduleCode: 'R-1',
    dialCount: 4,
    sealNumber: 'S-118204',
    installDate: '2024-06-18',
    warrantyExpiration: '2034-06-18',
    meterFactor: '1.0000',
    amiSystem: 'Itron ERT',
    amiLastSyncAt: '2026-02-12T06:14:00-06:00',
    amiSyncStatus: 'ok',
    testIntervalMonths: 120,
    lastTestDate: '2024-06-10',
    nextTestDueDate: '2034-06-10',
    lastTestResult: 'pass',
    lastTestAccuracy: '99.6',
    startDate: '2024-06-18',
    lastReadValue: '4821.00',
    lastReadDate: '2026-02-12',
    locationNotes: 'Left side of house behind the side gate. Dog on premise — knock first.',
    replacesMeterId: 'mtr-0011',
    swapReason: 'Previous meter failed periodic accuracy test (fast 2.8%)',
    externalId: 'CIS-M-004182',
  },
  {
    ...base,
    meterId: 'mtr-0002',
    locationId: 'loc-0002',
    rateScheduleCode: 'R-1',
    dialCount: 4,
    sealNumber: 'S-077310',
    installDate: '2015-03-02',
    warrantyExpiration: '2025-03-02',
    meterFactor: '1.0000',
    amiSystem: 'Itron ERT',
    amiLastSyncAt: '2026-02-12T06:15:00-06:00',
    amiSyncStatus: 'ok',
    testIntervalMonths: 120,
    lastTestDate: '2015-02-20',
    nextTestDueDate: '2025-02-20',
    lastTestResult: 'pass',
    lastTestAccuracy: '100.2',
    startDate: '2015-03-02',
    lastReadValue: '2210.00',
    lastReadDate: '2026-02-12',
    externalId: 'CIS-M-007733',
  },
  {
    ...base,
    meterId: 'mtr-0003',
    locationId: 'loc-0003',
    rateScheduleCode: 'G-2',
    dialCount: 8,
    sealNumber: 'S-200915',
    installDate: '2018-09-24',
    warrantyExpiration: '2028-09-24',
    /* Delivered at 2 psig, so the volume is corrected up from standard pressure. */
    meterFactor: '1.1360',
    amiSystem: 'Sensus FlexNet',
    amiLastSyncAt: '2026-02-14T05:00:00-06:00',
    amiSyncStatus: 'ok',
    testIntervalMonths: 36,
    lastTestDate: '2024-05-14',
    nextTestDueDate: '2027-05-14',
    lastTestResult: 'pass',
    lastTestAccuracy: '99.9',
    startDate: '2018-09-24',
    lastReadValue: '88140.00',
    lastReadDate: '2026-02-14',
    locationNotes: 'Regulator and meter set in the fenced yard at the loading dock. Check in at the front office.',
    externalId: 'CIS-M-119004',
  },
  {
    ...base,
    meterId: 'mtr-0004',
    locationId: 'loc-0004',
    rateScheduleCode: 'G-1',
    dialCount: 6,
    sealNumber: 'S-188072',
    installDate: '2020-01-13',
    warrantyExpiration: '2030-01-13',
    meterFactor: '1.0000',
    amiSystem: 'Sensus FlexNet',
    amiLastSyncAt: '2026-02-08T05:00:00-06:00',
    amiSyncStatus: 'error',
    amiSyncError: 'No interval data since Feb 8 — endpoint not reporting to the collector on RT-09',
    testIntervalMonths: 60,
    lastTestDate: '2025-01-09',
    nextTestDueDate: '2030-01-09',
    lastTestResult: 'pass',
    lastTestAccuracy: '99.8',
    startDate: '2020-01-13',
    lastReadValue: '12006.00',
    lastReadDate: '2026-02-14',
    locationNotes: 'North wall of the bus barn, beside the fuel island.',
    externalId: 'CIS-M-088210',
  },
  {
    ...base,
    meterId: 'mtr-0005',
    locationId: 'loc-0005',
    rateScheduleCode: 'R-1',
    dialCount: 4,
    sealNumber: 'S-049133',
    installDate: '2012-07-30',
    warrantyExpiration: '2022-07-30',
    meterFactor: '1.0000',
    amiSystem: null,
    amiSyncStatus: 'not_configured',
    testIntervalMonths: 120,
    lastTestDate: '2022-08-04',
    nextTestDueDate: '2032-08-04',
    lastTestResult: 'pass',
    lastTestAccuracy: '99.4',
    startDate: '2012-07-30',
    lastReadValue: '3391.00',
    lastReadDate: '2026-02-13',
    locationNotes: 'Back yard behind a locked gate. Customer has not answered three door hangers.',
    estimationBlocked: true,
    estimationBlockedReason: 'Third consecutive estimate — Texas cap reached; an actual read is required before the next bill',
    externalId: 'CIS-M-004913',
  },
  {
    ...base,
    meterId: 'mtr-0006',
    locationId: 'loc-0006',
    rateScheduleCode: 'R-1',
    dialCount: 4,
    sealNumber: 'S-055201',
    installDate: '2013-11-05',
    warrantyExpiration: '2023-11-05',
    meterFactor: '1.0000',
    amiSystem: 'Itron ERT',
    amiLastSyncAt: '2026-02-12T06:31:00-06:00',
    amiSyncStatus: 'ok',
    testIntervalMonths: 120,
    lastTestDate: '2023-10-30',
    nextTestDueDate: '2033-10-30',
    lastTestResult: 'pass',
    lastTestAccuracy: '100.1',
    startDate: '2013-11-05',
    lastReadValue: '112.00',
    lastReadDate: '2026-02-12',
    locationNotes: 'Rear of lot off the alley. Curb valve at the front sidewalk.',
    externalId: 'CIS-M-005520',
  },
  {
    ...base,
    meterId: 'mtr-0007',
    locationId: 'loc-0007',
    rateScheduleCode: 'G-1',
    dialCount: 6,
    sealNumber: 'S-160447',
    installDate: '2021-04-20',
    warrantyExpiration: '2031-04-20',
    meterFactor: '1.0000',
    amiSystem: 'Itron ERT',
    amiLastSyncAt: '2026-02-12T06:40:00-06:00',
    amiSyncStatus: 'ok',
    testIntervalMonths: 60,
    lastTestDate: '2021-04-14',
    nextTestDueDate: '2026-04-14',
    lastTestResult: 'pass',
    lastTestAccuracy: '99.7',
    startDate: '2021-04-20',
    lastReadValue: '8802.00',
    lastReadDate: '2026-02-11',
    locationNotes: 'Meter bank in the rear service corridor, second from the left.',
    externalId: 'CIS-M-062118',
  },
  {
    ...base,
    meterId: 'mtr-0008',
    locationId: 'loc-0008',
    rateScheduleCode: 'R-1',
    dialCount: 4,
    sealNumber: 'S-210338',
    installDate: '2016-08-09',
    warrantyExpiration: '2026-08-09',
    meterFactor: '1.0000',
    amiSystem: 'Itron ERT',
    amiLastSyncAt: '2026-02-12T07:02:00-06:00',
    amiSyncStatus: 'ok',
    testIntervalMonths: 120,
    lastTestDate: '2016-08-01',
    nextTestDueDate: '2026-08-01',
    lastTestResult: 'pass',
    lastTestAccuracy: '100.0',
    startDate: '2016-08-09',
    lastReadValue: '1044.00',
    lastReadDate: '2026-02-10',
    externalId: 'CIS-M-004188',
  },
  {
    ...base,
    meterId: 'mtr-0009',
    locationId: null,
    rateScheduleCode: null,
    dialCount: 4,
    sealNumber: null,
    installDate: null,
    warrantyExpiration: '2035-11-01',
    meterFactor: '1.0000',
    amiSystem: 'Itron ERT',
    amiSyncStatus: 'not_configured',
    testIntervalMonths: 120,
    lastTestDate: '2025-11-03',
    nextTestDueDate: '2035-11-03',
    lastTestResult: 'pass',
    lastTestAccuracy: '100.1',
    startDate: '2025-11-03',
    lastReadValue: '0000.00',
    lastReadDate: null,
    warehouseLocation: 'Meter shop · Rack B-4',
    externalId: 'CIS-M-004207',
  },
  {
    ...base,
    meterId: 'mtr-0010',
    locationId: null,
    rateScheduleCode: null,
    dialCount: 6,
    sealNumber: null,
    installDate: null,
    warrantyExpiration: '2035-09-15',
    meterFactor: '1.0000',
    amiSystem: null,
    amiSyncStatus: 'not_configured',
    testIntervalMonths: 60,
    lastTestDate: '2025-09-18',
    nextTestDueDate: '2030-09-18',
    lastTestResult: 'pass',
    lastTestAccuracy: '99.9',
    startDate: '2025-09-18',
    lastReadValue: '0000.00',
    lastReadDate: null,
    warehouseLocation: 'Meter shop · Rack D-1',
    externalId: 'CIS-M-062301',
  },
  {
    ...base,
    meterId: 'mtr-0011',
    locationId: null,
    rateScheduleCode: null,
    dialCount: 4,
    sealNumber: 'S-031877',
    installDate: '2009-05-12',
    removalDate: '2024-06-18',
    warrantyExpiration: '2019-05-12',
    meterFactor: '1.0000',
    amiSystem: null,
    amiSyncStatus: 'not_configured',
    testIntervalMonths: 120,
    lastTestDate: '2024-06-11',
    nextTestDueDate: null,
    lastTestResult: 'fail',
    lastTestAccuracy: '102.8',
    startDate: '2009-05-12',
    endDate: '2024-06-18',
    lastReadValue: '9915.00',
    lastReadDate: '2024-06-18',
    warehouseLocation: 'Scrap cage · awaiting vendor return',
    externalId: 'CIS-M-003015',
  },
]

export const meterDetailById = new Map(meterDetails.map((d) => [d.meterId, d]))

/** Every premise a meter has served, newest last. */
export const deployments: MeterDeployment[] = [
  { meterId: 'mtr-0011', deploymentNumber: 1, locationId: 'loc-0001', installDate: '2009-05-12', installReadValue: '0000.00', installedBy: 'J. Ortiz', removalDate: '2024-06-18', removalReadValue: '9915.00', removalReason: 'Failed periodic accuracy test', removedBy: 'M. Reyes' },
  { meterId: 'mtr-0001', deploymentNumber: 1, locationId: 'loc-0001', installDate: '2024-06-18', installReadValue: '0000.00', installedBy: 'M. Reyes', removalDate: null, removalReadValue: null, removalReason: null, removedBy: null },
  { meterId: 'mtr-0002', deploymentNumber: 1, locationId: 'loc-0002', installDate: '2015-03-02', installReadValue: '0000.00', installedBy: 'J. Ortiz', removalDate: null, removalReadValue: null, removalReason: null, removedBy: null },
  { meterId: 'mtr-0003', deploymentNumber: 1, locationId: 'loc-0003', installDate: '2018-09-24', installReadValue: '0000.00', installedBy: 'Contract — Brazos Mechanical', removalDate: null, removalReadValue: null, removalReason: null, removedBy: null },
  { meterId: 'mtr-0004', deploymentNumber: 1, locationId: 'loc-0004', installDate: '2020-01-13', installReadValue: '0000.00', installedBy: 'M. Reyes', removalDate: null, removalReadValue: null, removalReason: null, removedBy: null },
  { meterId: 'mtr-0005', deploymentNumber: 1, locationId: 'loc-0005', installDate: '2012-07-30', installReadValue: '0000.00', installedBy: 'J. Ortiz', removalDate: null, removalReadValue: null, removalReason: null, removedBy: null },
  { meterId: 'mtr-0006', deploymentNumber: 1, locationId: 'loc-0006', installDate: '2013-11-05', installReadValue: '0000.00', installedBy: 'J. Ortiz', removalDate: null, removalReadValue: null, removalReason: null, removedBy: null },
  { meterId: 'mtr-0007', deploymentNumber: 1, locationId: 'loc-0007', installDate: '2021-04-20', installReadValue: '0000.00', installedBy: 'M. Reyes', removalDate: null, removalReadValue: null, removalReason: null, removedBy: null },
  { meterId: 'mtr-0008', deploymentNumber: 1, locationId: 'loc-0008', installDate: '2016-08-09', installReadValue: '0000.00', installedBy: 'M. Reyes', removalDate: null, removalReadValue: null, removalReason: null, removedBy: null },
]

/** Radio modules fitted to each meter. A meter can outlive several. */
export const endpointHistory: EndpointHistory[] = [
  { meterId: 'mtr-0001', endpointId: '38104182', endpointType: 'Itron 100G ERT', installDate: '2024-06-18', removalDate: null, removalReason: null, installedBy: 'M. Reyes' },
  { meterId: 'mtr-0002', endpointId: '37201559', endpointType: 'Itron 40G ERT', installDate: '2015-03-02', removalDate: '2022-10-11', removalReason: 'Battery end of life', installedBy: 'J. Ortiz' },
  { meterId: 'mtr-0002', endpointId: '38107733', endpointType: 'Itron 100G ERT', installDate: '2022-10-11', removalDate: null, removalReason: null, installedBy: 'M. Reyes' },
  { meterId: 'mtr-0003', endpointId: 'FN-7719004', endpointType: 'Sensus FlexNet SmartPoint', installDate: '2018-09-24', removalDate: null, removalReason: null, installedBy: 'Contract — Brazos Mechanical' },
  { meterId: 'mtr-0004', endpointId: 'FN-7688210', endpointType: 'Sensus FlexNet SmartPoint', installDate: '2020-01-13', removalDate: null, removalReason: null, installedBy: 'M. Reyes' },
  { meterId: 'mtr-0006', endpointId: '38105520', endpointType: 'Itron 100G ERT', installDate: '2019-04-02', removalDate: null, removalReason: null, installedBy: 'J. Ortiz' },
  { meterId: 'mtr-0007', endpointId: '38162118', endpointType: 'Itron 100G ERT', installDate: '2021-04-20', removalDate: null, removalReason: null, installedBy: 'M. Reyes' },
  { meterId: 'mtr-0008', endpointId: '38104188', endpointType: 'Itron 100G ERT', installDate: '2016-08-09', removalDate: null, removalReason: null, installedBy: 'M. Reyes' },
  { meterId: 'mtr-0009', endpointId: '38104207', endpointType: 'Itron 100G ERT', installDate: '2025-11-03', removalDate: null, removalReason: null, installedBy: 'Meter shop' },
]
