import { Customer, Meter, RateItemVersion, ServiceLocation } from '@/schemas/models'
import { CalculationType, CustomerStatus, CustomerType, DisplayGroup, RateUnit } from '@/schemas/enums'
import { rateSchedules } from '@/fixtures/rates'
import { currentUser, cycle, tenant } from '@/fixtures/tenant'
import { addDays, toStored } from '@/lib/rate-changes'
import { customerName } from '@/schemas/models'
import {
  ENTITY_NOUN,
  EMPTY_IMPORTED,
  type ImportEntity,
  type ImportIssue,
  type ImportProposal,
  type ImportedData,
  type ImportedLink,
  type ImportedRateItem,
} from './protocol'
import type { TenantView } from './tenant-data'

/**
 * Turning an uploaded file into records the schema would accept.
 *
 * The model decides which column means what; this module does everything
 * that must be exact — parsing the file, coercing each value, enforcing the
 * DDL's types and enums, and refusing duplicates. The model never writes a
 * record itself: it gets a validation report back, and the operator gets a
 * proposal to apply or discard.
 */

/* ---- Tables ---------------------------------------------------------- */

export type Table = { headers: string[]; rows: string[][] }

/** CSV, TSV, semicolon or pipe — whichever splits the header row the most — or a JSON array of objects. */
export function parseTable(text: string): Table {
  const body = text.replace(/^﻿/, '')
  const trimmed = body.trim()
  if (trimmed.startsWith('[')) {
    const data = JSON.parse(trimmed) as Record<string, unknown>[]
    if (!Array.isArray(data)) throw new Error('JSON must be an array of objects')
    const headers = [...new Set(data.flatMap((o) => Object.keys(o ?? {})))]
    return {
      headers,
      rows: data.map((o) => headers.map((h) => (o?.[h] == null ? '' : String(o[h])))),
    }
  }
  const firstLine = body.split(/\r?\n/, 1)[0] ?? ''
  const delimiter = [',', '\t', ';', '|'].reduce((best, d) =>
    firstLine.split(d).length > firstLine.split(best).length ? d : best,
  )
  const records = splitDelimited(body, delimiter).filter((r) => r.some((c) => c.trim() !== ''))
  const [headers = [], ...rows] = records
  return { headers: headers.map((h) => h.trim()), rows }
}

/** RFC 4180: quoted fields may hold the delimiter, newlines and doubled quotes. */
function splitDelimited(text: string, d: string): string[][] {
  const out: string[][] = []
  let row: string[] = []
  let field = ''
  let quoted = false
  for (let i = 0; i < text.length; i++) {
    const ch = text[i]
    if (quoted) {
      if (ch === '"' && text[i + 1] === '"') {
        field += '"'
        i++
      } else if (ch === '"') quoted = false
      else field += ch
    } else if (ch === '"' && field === '') quoted = true
    else if (ch === d) {
      row.push(field)
      field = ''
    } else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && text[i + 1] === '\n') i++
      row.push(field)
      out.push(row)
      row = []
      field = ''
    } else field += ch
  }
  if (field !== '' || row.length) {
    row.push(field)
    out.push(row)
  }
  return out
}

/** What the model sees of an attachment: enough to map the columns, not the whole file. */
export function describeTable(name: string, t: Table, sample = 12): string {
  const lines = [
    `Attached table "${name}": ${t.rows.length} data rows, ${t.headers.length} columns.`,
    `Columns: ${t.headers.map((h) => JSON.stringify(h)).join(', ')}`,
    `First ${Math.min(sample, t.rows.length)} rows (row 1 is the header, so the first data row is row 2):`,
    ...t.rows.slice(0, sample).map((r, i) => `row ${i + 2}: ${JSON.stringify(Object.fromEntries(t.headers.map((h, j) => [h, r[j] ?? ''])))}`),
  ]
  return lines.join('\n')
}

/* ---- Field specs ----------------------------------------------------- */

type Kind = 'text' | 'enum' | 'bool' | 'date' | 'decimal' | 'int'
type FieldSpec = {
  key: string
  kind: Kind
  required?: boolean
  values?: readonly string[]
  /** Places for a decimal. */
  places?: number
  note?: string
}

const CUSTOMER_FIELDS: FieldSpec[] = [
  { key: 'customer_number', kind: 'text', required: true, note: 'account number, unique' },
  { key: 'customer_type', kind: 'enum', values: CustomerType.options, note: 'default residential' },
  { key: 'first_name', kind: 'text' },
  { key: 'last_name', kind: 'text' },
  { key: 'company_name', kind: 'text', note: 'a person or a company name is required' },
  { key: 'email', kind: 'text' },
  { key: 'phone', kind: 'text' },
  { key: 'status', kind: 'enum', values: CustomerStatus.options, note: 'default active' },
  { key: 'is_tax_exempt', kind: 'bool', note: 'default false' },
  { key: 'move_in_date', kind: 'date' },
  { key: 'deposit_amount', kind: 'decimal', places: 2, note: 'default 0.00' },
]

const LOCATION_FIELDS: FieldSpec[] = [
  { key: 'location_number', kind: 'text', required: true, note: 'premise number, unique' },
  { key: 'address', kind: 'text', required: true, note: 'street line' },
  { key: 'city', kind: 'text', required: true },
  { key: 'state', kind: 'text', note: 'default TX' },
  { key: 'zip', kind: 'text', required: true },
  { key: 'inside_city_limits', kind: 'bool', note: 'drives franchise fees; assumed from franchise_city when absent' },
  { key: 'franchise_city', kind: 'enum', values: tenant.franchiseCities, note: 'only for in-city premises' },
  { key: 'billing_cycle', kind: 'text', note: `default ${cycle.code}` },
]

const METER_FIELDS: FieldSpec[] = [
  { key: 'meter_number', kind: 'text', required: true, note: 'unique' },
  { key: 'serial_number', kind: 'text' },
  { key: 'manufacturer', kind: 'text' },
  { key: 'model', kind: 'text' },
  { key: 'size', kind: 'text' },
  { key: 'read_type', kind: 'enum', values: ['manual', 'amr', 'ami'], note: 'default amr when ami_endpoint_id is set, else manual' },
  { key: 'ami_endpoint_id', kind: 'text', note: 'ERT / AMR radio ID' },
  { key: 'multiplier', kind: 'decimal', places: 4, note: 'default 1.0000' },
  { key: 'gas_btu_factor', kind: 'decimal', places: 4 },
  { key: 'rollover_point', kind: 'decimal', places: 0 },
  { key: 'route_id', kind: 'text' },
  { key: 'route_sequence', kind: 'int' },
  { key: 'meter_status', kind: 'enum', values: ['active', 'inactive', 'removed', 'in_stock'], note: 'default active' },
]

const RATE_FIELDS: FieldSpec[] = [
  { key: 'rate_schedule_code', kind: 'enum', required: true, values: rateSchedules.map((s) => s.code) },
  { key: 'item_code', kind: 'text', required: true },
  { key: 'item_name', kind: 'text', note: 'required for a new item; inherited for an existing one' },
  { key: 'display_group', kind: 'enum', values: DisplayGroup.options, note: 'inherited for an existing item' },
  { key: 'calculation_type', kind: 'enum', values: CalculationType.options, note: 'inherited for an existing item' },
  { key: 'rate', kind: 'text', required: true, note: 'as printed on the tariff: percent as percent (5 for 5%)' },
  { key: 'rate_unit', kind: 'enum', values: RateUnit.options, note: 'inherited for an existing item' },
  { key: 'effective_from', kind: 'date', required: true },
  { key: 'effective_to', kind: 'date' },
  { key: 'change_reason', kind: 'text', required: true, note: 'required on every version (AC-14)' },
  { key: 'regulatory_reference', kind: 'text', note: 'tariff sheet or docket' },
]

export const FIELDS: Record<ImportEntity, FieldSpec[]> = {
  accounts: [
    ...CUSTOMER_FIELDS,
    ...LOCATION_FIELDS,
    ...METER_FIELDS.map((f) => (f.key === 'meter_number' ? { ...f, required: false, note: 'optional; links the meter to the premise' } : f)),
  ],
  customers: CUSTOMER_FIELDS,
  locations: LOCATION_FIELDS,
  meters: [...METER_FIELDS, { key: 'location_number', kind: 'text', note: 'optional; premise to set the meter at' }],
  rate_items: RATE_FIELDS,
}

/** The field list as the model reads it in the tool description. Stable text, so it caches. */
export function fieldGuide(): string {
  return (Object.keys(FIELDS) as ImportEntity[])
    .map((e) => {
      const fields = FIELDS[e]
        .map((f) => {
          const bits = [f.kind === 'enum' ? `one of ${f.values!.join('|')}` : f.kind]
          if (f.required) bits.unshift('required')
          if (f.note) bits.push(f.note)
          return `${f.key} (${bits.join('; ')})`
        })
        .join(', ')
      return `- ${e}: ${fields}`
    })
    .join('\n')
}

/* ---- Coercion -------------------------------------------------------- */

type Coerced = { ok: true; value: string | boolean | number | null } | { ok: false; message: string }

const SYNONYMS: Record<string, Record<string, string>> = {
  customer_type: {
    res: 'residential', resi: 'residential', residence: 'residential',
    comm: 'commercial', com: 'commercial', business: 'commercial',
    small_comm: 'small_commercial', sm_commercial: 'small_commercial',
    large_comm: 'large_commercial', lg_commercial: 'large_commercial',
    ind: 'industrial', gov: 'government', govt: 'government', municipal: 'government',
  },
  status: { open: 'active', closed_account: 'closed', final: 'final_billed' },
  read_type: { ert: 'amr', radio: 'amr', drive_by: 'amr', manual_read: 'manual', walk: 'manual', smart: 'ami' },
  rate_unit: {
    month: 'per_month', monthly: 'per_month', '$/month': 'per_month', ccf: 'per_ccf', '$/ccf': 'per_ccf',
    mcf: 'per_mcf', '$/mcf': 'per_mcf', therm: 'per_therm', '$/therm': 'per_therm', '%': 'percent', pct: 'percent',
  },
}

const STATES: Record<string, string> = { texas: 'TX', louisiana: 'LA', oklahoma: 'OK', 'new mexico': 'NM', arkansas: 'AR' }

function coerce(f: FieldSpec, raw: string): Coerced {
  const v = raw.trim()
  if (v === '') return { ok: true, value: null }
  switch (f.kind) {
    case 'text':
      return { ok: true, value: v.replace(/\s+/g, ' ') }
    case 'enum': {
      const values = f.values ?? []
      const exact = values.find((x) => x.toLowerCase() === v.toLowerCase())
      if (exact) return { ok: true, value: exact }
      const slug = v.toLowerCase().replace(/[\s-]+/g, '_')
      const hit = values.find((x) => x === slug) ?? SYNONYMS[f.key]?.[slug] ?? SYNONYMS[f.key]?.[v.toLowerCase()]
      return hit && values.includes(hit)
        ? { ok: true, value: hit }
        : { ok: false, message: `"${v}" is not one of ${values.join(', ')}` }
    }
    case 'bool': {
      const s = v.toLowerCase()
      if (['y', 'yes', 'true', 't', '1', 'x'].includes(s)) return { ok: true, value: true }
      if (['n', 'no', 'false', 'f', '0'].includes(s)) return { ok: true, value: false }
      return { ok: false, message: `"${v}" is not yes or no` }
    }
    case 'date': {
      let m = v.match(/^(\d{4})[-/](\d{1,2})[-/](\d{1,2})$/)
      let y: number, mo: number, d: number
      if (m) [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])]
      else if ((m = v.match(/^(\d{1,2})[-/](\d{1,2})[-/](\d{2}|\d{4})$/))) {
        ;[mo, d, y] = [Number(m[1]), Number(m[2]), Number(m[3])]
        if (y < 100) y += y < 50 ? 2000 : 1900
      } else return { ok: false, message: `"${v}" is not a date (YYYY-MM-DD or MM/DD/YYYY)` }
      const iso = `${y}-${String(mo).padStart(2, '0')}-${String(d).padStart(2, '0')}`
      const check = new Date(`${iso}T00:00:00Z`)
      return check.getUTCMonth() + 1 === mo && check.getUTCDate() === d
        ? { ok: true, value: iso }
        : { ok: false, message: `"${v}" is not a real calendar date` }
    }
    case 'decimal': {
      let s = v.replace(/[$,\s]/g, '')
      const negative = /^\(.*\)$/.test(s)
      if (negative) s = `-${s.slice(1, -1)}`
      if (!/^-?(\d+\.?\d*|\.\d+)$/.test(s)) return { ok: false, message: `"${v}" is not a number` }
      const places = f.places ?? 2
      const [whole, frac = ''] = s.replace(/^(-?)\./, '$10.').split('.')
      if (frac.replace(/0+$/, '').length > places)
        return { ok: false, message: `"${v}" has more than ${places} decimal places — not rounded silently` }
      return { ok: true, value: places ? `${whole}.${frac.padEnd(places, '0').slice(0, places)}` : whole }
    }
    case 'int':
      return /^-?\d+$/.test(v) ? { ok: true, value: Number(v) } : { ok: false, message: `"${v}" is not a whole number` }
  }
}

function phone(v: string | null): string | null {
  if (!v) return null
  const digits = v.replace(/\D/g, '').replace(/^1(?=\d{10}$)/, '')
  return digits.length === 10 ? `(${digits.slice(0, 3)}) ${digits.slice(3, 6)}-${digits.slice(6)}` : v
}

/* ---- Building -------------------------------------------------------- */

export type StageInput = {
  entity: ImportEntity
  attachment?: string
  column_map?: Record<string, string>
  constants?: Record<string, string>
  rows?: Record<string, string>[]
  assign_numbers?: boolean
}

type Row = { line: number; get: (field: string) => string }

const rid = (prefix: string) => `imp-${prefix}-${crypto.randomUUID().slice(0, 8)}`

export function stage(input: StageInput, tables: Map<string, Table>, view: TenantView): ImportProposal {
  const specs = FIELDS[input.entity]
  const known = new Set(specs.map((s) => s.key))
  const errors: ImportIssue[] = []
  const warnings: ImportIssue[] = []
  const constants = input.constants ?? {}

  for (const key of [...Object.keys(input.column_map ?? {}), ...Object.keys(constants)]) {
    if (!known.has(key)) throw new Error(`"${key}" is not a field of ${input.entity}. Fields: ${[...known].join(', ')}`)
  }

  let rows: Row[]
  if (input.attachment) {
    const t = tables.get(input.attachment)
    if (!t) throw new Error(`No table attachment named "${input.attachment}". Attached: ${[...tables.keys()].join(', ') || 'none'}`)
    const map = input.column_map ?? {}
    const index = new Map<string, number>()
    for (const [field, column] of Object.entries(map)) {
      const i = t.headers.indexOf(column)
      const j = i >= 0 ? i : t.headers.findIndex((h) => h.toLowerCase() === column.toLowerCase())
      if (j < 0) throw new Error(`Column "${column}" (mapped to ${field}) is not in ${input.attachment}. Columns: ${t.headers.join(', ')}`)
      index.set(field, j)
    }
    rows = t.rows.map((r, n) => ({
      line: n + 2,
      get: (field) => {
        const j = index.get(field)
        const v = j === undefined ? '' : (r[j] ?? '')
        return v.trim() === '' ? (constants[field] ?? '') : v
      },
    }))
  } else {
    rows = (input.rows ?? []).map((r, n) => {
      for (const key of Object.keys(r)) {
        if (!known.has(key)) throw new Error(`"${key}" is not a field of ${input.entity}. Fields: ${[...known].join(', ')}`)
      }
      return {
        line: n + 1,
        get: (field) => {
          const v = r[field] == null ? '' : String(r[field])
          return v.trim() === '' ? (constants[field] ?? '') : v
        },
      }
    })
  }
  if (rows.length === 0) throw new Error('Nothing to import: no rows.')

  const out: ImportedData = structuredClone(EMPTY_IMPORTED)
  const preview: string[][] = []

  /* Natural keys already on file, and those claimed earlier in this file. */
  const taken = {
    customer: new Set(view.customers.map((c) => c.customer_number)),
    location: new Map(view.locations.map((l) => [l.location_number, l])),
    meter: new Map(view.meters.map((m) => [m.meter_number, m])),
  }
  const seen = {
    customer: new Map<string, number>(),
    location: new Map<string, number>(),
    meter: new Map<string, number>(),
    rate: new Map<string, number>(),
  }
  let serial = 0
  const assign = (prefix: string) => `${prefix}-${String(Date.now() % 1_000_000).padStart(6, '0')}${String(++serial).padStart(3, '0')}`

  for (const row of rows) {
    const rowErrors: ImportIssue[] = []
    /* A rejected row's warnings are noise; they are dropped with it. */
    const warnStart = warnings.length
    const values: Record<string, string | boolean | number | null> = {}
    for (const f of specs) {
      const c = coerce(f, row.get(f.key))
      if (!c.ok) rowErrors.push({ row: row.line, field: f.key, message: c.message })
      else values[f.key] = c.value
    }
    const s = (k: string) => (values[k] as string | null) ?? null

    const need = (k: string, label = k) => {
      if (values[k] == null && !rowErrors.some((e) => e.field === k))
        rowErrors.push({ row: row.line, field: k, message: `${label} is required` })
    }
    const claim = (kind: keyof typeof seen, key: string, field: string) => {
      const prior = seen[kind].get(key)
      if (prior !== undefined) {
        rowErrors.push({ row: row.line, field, message: `${key} also appears on row ${prior}` })
        return false
      }
      seen[kind].set(key, row.line)
      return true
    }

    let customer: Customer | null = null
    let location: ServiceLocation | null = null
    let meter: Meter | null = null
    let reusedLocation = false
    let reusedMeter = false

    /* Customer half. */
    if (input.entity === 'accounts' || input.entity === 'customers') {
      if (values.customer_number == null && input.assign_numbers) values.customer_number = assign('900')
      need('customer_number', 'Account number (map a column, or set assign_numbers)')
      const number = s('customer_number')
      if (number && taken.customer.has(number))
        rowErrors.push({ row: row.line, field: 'customer_number', message: `account ${number} already exists` })
      else if (number) claim('customer', number, 'customer_number')
      if (!s('company_name') && !s('first_name') && !s('last_name'))
        rowErrors.push({ row: row.line, field: 'company_name', message: 'needs a person name or a company name' })
      const email = s('email')
      if (email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email))
        warnings.push({ row: row.line, field: 'email', message: `"${email}" does not look like an email address` })
      if (number && !rowErrors.length) {
        const parsed = Customer.safeParse({
          id: rid('cus'),
          customer_number: number,
          customer_type: s('customer_type') ?? 'residential',
          first_name: s('first_name'),
          last_name: s('last_name'),
          company_name: s('company_name'),
          email,
          phone: phone(s('phone')),
          status: s('status') ?? 'active',
          /* Protections and holds are set through customer_state_events with a reason, never by import. */
          do_not_disconnect: false,
          disconnect_protection_type: null,
          disconnect_protection_expiry: null,
          billing_hold: false,
          billing_hold_reason: null,
          is_tax_exempt: values.is_tax_exempt ?? false,
          move_in_date: s('move_in_date'),
          deposit_amount: s('deposit_amount') ?? '0.00',
          /* An opening balance is a ledger entry, not a column. Imports start at zero. */
          balance: '0.00',
          created_at: new Date().toISOString(),
        })
        if (parsed.success) customer = parsed.data
        else rowErrors.push(...parsed.error.issues.map((i) => ({ row: row.line, field: String(i.path[0] ?? ''), message: i.message })))
      }
    }

    /* Premise half. */
    if (input.entity === 'accounts' || input.entity === 'locations') {
      if (values.location_number == null && input.assign_numbers) values.location_number = assign('P')
      need('location_number', 'Premise number (map a column, or set assign_numbers)')
      const number = s('location_number')
      const existing = number ? taken.location.get(number) : undefined
      if (existing && input.entity === 'locations') {
        rowErrors.push({ row: row.line, field: 'location_number', message: `premise ${number} already exists` })
      } else if (existing) {
        /* A new customer moving into a premise already on file: link to it, never re-create it. */
        location = existing
        reusedLocation = true
        const occupied = view.links.find((l) => l.locationId === existing.id && l.customerId)
        if (occupied) {
          const who = view.customers.find((c) => c.id === occupied.customerId)
          warnings.push({
            row: row.line,
            field: 'location_number',
            message: `premise ${number} is already served to ${who ? customerName(who) : occupied.customerId}; this links a second account to it`,
          })
        }
      } else if (number && claim('location', number, 'location_number')) {
        need('address', 'Street address')
        need('city', 'City')
        need('zip', 'ZIP')
        let state = s('state') ?? 'TX'
        state = STATES[state.toLowerCase()] ?? state.toUpperCase()
        if (!/^[A-Z]{2}$/.test(state)) rowErrors.push({ row: row.line, field: 'state', message: `"${state}" is not a two-letter state` })
        let zip = s('zip')
        if (zip && /^\d{4}$/.test(zip)) {
          warnings.push({ row: row.line, field: 'zip', message: `ZIP ${zip} padded to 0${zip} (a spreadsheet dropped its leading zero)` })
          zip = `0${zip}`
        }
        if (zip && !/^\d{5}(-\d{4})?$/.test(zip)) rowErrors.push({ row: row.line, field: 'zip', message: `"${zip}" is not a ZIP code` })
        const franchise = s('franchise_city')
        let inside = values.inside_city_limits as boolean | null
        if (inside == null) {
          inside = franchise !== null
          warnings.push({
            row: row.line,
            field: 'inside_city_limits',
            message: `inside city limits not given — taken as ${inside ? 'inside' : 'outside'}${franchise ? ` (${franchise})` : ''}; franchise fees follow it`,
          })
        }
        if (inside && !franchise)
          warnings.push({ row: row.line, field: 'franchise_city', message: 'inside city limits but no franchise city, so no franchise fee will bill' })
        if (!rowErrors.length) {
          const parsed = ServiceLocation.safeParse({
            id: rid('loc'),
            location_number: number,
            address: s('address'),
            city: s('city'),
            state,
            zip,
            inside_city_limits: inside,
            franchise_city: inside ? franchise : null,
            billing_cycle: s('billing_cycle') ?? cycle.code,
          })
          if (parsed.success) location = parsed.data
          else rowErrors.push(...parsed.error.issues.map((i) => ({ row: row.line, field: String(i.path[0] ?? ''), message: i.message })))
        }
      }
    }

    /* Meter half. */
    if (input.entity === 'meters' || (input.entity === 'accounts' && values.meter_number != null)) {
      if (values.meter_number == null && input.assign_numbers && input.entity === 'meters') values.meter_number = assign('M')
      need('meter_number', input.entity === 'meters' ? 'Meter number (map a column, or set assign_numbers)' : 'Meter number')
      const number = s('meter_number')
      const existing = number ? taken.meter.get(number) : undefined
      if (existing && input.entity === 'accounts' && reusedLocation) {
        const set = view.links.find((l) => l.meterId === existing.id)
        if (set && set.locationId === location?.id) {
          meter = existing
          reusedMeter = true
        } else rowErrors.push({ row: row.line, field: 'meter_number', message: `meter ${number} is already set at another premise` })
      } else if (existing) {
        rowErrors.push({ row: row.line, field: 'meter_number', message: `meter ${number} already exists` })
      } else if (number && claim('meter', number, 'meter_number')) {
        const endpoint = s('ami_endpoint_id')
        const readType = s('read_type') ?? (endpoint ? 'amr' : 'manual')
        if (readType !== 'manual' && !endpoint)
          warnings.push({ row: row.line, field: 'ami_endpoint_id', message: `read type ${readType} but no radio endpoint ID` })
        if (!rowErrors.length) {
          const parsed = Meter.safeParse({
            id: rid('mtr'),
            meter_number: number,
            serial_number: s('serial_number'),
            manufacturer: s('manufacturer'),
            model: s('model'),
            size: s('size'),
            read_type: readType,
            ami_endpoint_id: endpoint,
            multiplier: s('multiplier') ?? '1.0000',
            gas_btu_factor: s('gas_btu_factor'),
            rollover_point: s('rollover_point'),
            route_id: s('route_id'),
            route_sequence: (values.route_sequence as number | null) ?? null,
            status: s('meter_status') ?? 'active',
            /* Database-maintained. Never written by the UI. */
            consecutive_estimate_count: 0,
          })
          if (parsed.success) meter = parsed.data
          else rowErrors.push(...parsed.error.issues.map((i) => ({ row: row.line, field: String(i.path[0] ?? ''), message: i.message })))
        }
      }
      if (input.entity === 'meters' && s('location_number')) {
        const at = view.locations.find((l) => l.location_number === s('location_number'))
        if (!at) rowErrors.push({ row: row.line, field: 'location_number', message: `premise ${s('location_number')} is not on file` })
        else {
          location = at
          reusedLocation = true
          if (view.links.some((l) => l.locationId === at.id && l.meterId))
            warnings.push({ row: row.line, field: 'location_number', message: `premise ${at.location_number} already has a meter set` })
        }
      }
    }

    /* Rate items. */
    let rateItem: ImportedRateItem | null = null
    if (input.entity === 'rate_items') {
      need('rate_schedule_code', 'Rate schedule')
      need('item_code', 'Item code')
      need('rate', 'Rate')
      need('effective_from', 'Effective from')
      need('change_reason', 'Change reason')
      const code = s('item_code')
      const chain = code ? view.rateVersions.filter((v) => v.item_code === code) : []
      /* The newest version still on record — the one a succession closes. */
      const prior =
        chain
          .filter((v) => v.recorded_until === null)
          .sort((a, b) => a.effective_from.localeCompare(b.effective_from))
          .at(-1) ?? null
      const unit = (s('rate_unit') ?? prior?.rate_unit ?? null) as RateUnit | null
      if (!prior) {
        need('item_name', 'Item name (new item)')
        need('display_group', 'Display group (new item)')
        need('calculation_type', 'Calculation type (new item)')
        need('rate_unit', 'Rate unit (new item)')
      } else if (s('rate_unit') && s('rate_unit') !== prior.rate_unit) {
        rowErrors.push({ row: row.line, field: 'rate_unit', message: `${code} is billed ${prior.rate_unit}; a unit change is a new item, not a version` })
      }
      const stored = unit && s('rate') ? toStored(s('rate')!.replace(/[$,%\s]/g, ''), unit) : null
      if (unit && s('rate') && stored === null)
        rowErrors.push({ row: row.line, field: 'rate', message: `"${s('rate')}" is not a rate in ${unit}` })
      const from = s('effective_from')
      const to = s('effective_to')
      if (from && to && to < from) rowErrors.push({ row: row.line, field: 'effective_to', message: 'ends before it starts' })
      if (prior && from && from <= prior.effective_from)
        rowErrors.push({
          row: row.line,
          field: 'effective_from',
          message: `${code} already has a version from ${prior.effective_from}; a change on or before it is a correction, which needs the rate editor, not an import`,
        })
      const key = `${s('rate_schedule_code')}|${code}|${from}`
      if (!rowErrors.length && claim('rate', key, 'item_code') && stored && from && code) {
        const parsed = RateItemVersion.safeParse({
          id: rid('rate'),
          item_code: code,
          item_name: s('item_name') ?? prior!.item_name,
          display_group: s('display_group') ?? prior!.display_group,
          calculation_type: s('calculation_type') ?? prior!.calculation_type,
          rate: stored,
          rate_unit: unit,
          effective_from: from,
          effective_to: to,
          recorded_from: new Date().toISOString(),
          recorded_until: null,
          supersedes_id: prior?.id ?? null,
          change_type: prior ? 'succession' : 'initial',
          change_reason: s('change_reason'),
          regulatory_reference: s('regulatory_reference'),
          changed_by: currentUser.name,
        })
        if (parsed.success) {
          rateItem = { ...parsed.data, rate_schedule_code: s('rate_schedule_code')! }
          if (prior && prior.effective_to === null)
            warnings.push({
              row: row.line,
              field: 'effective_from',
              message: `closes ${code} at ${prior.rate} on ${addDays(from, -1)} and starts the new rate ${from}`,
            })
        } else rowErrors.push(...parsed.error.issues.map((i) => ({ row: row.line, field: String(i.path[0] ?? ''), message: i.message })))
      }
    }

    if (rowErrors.length) {
      errors.push(...rowErrors)
      warnings.length = warnStart
      continue
    }

    if (customer) out.customers.push(customer)
    if (location && !reusedLocation) out.locations.push(location)
    if (meter && !reusedMeter) out.meters.push(meter)
    if (rateItem) out.rateItems.push(rateItem)
    if (location && (customer || meter)) {
      const link: ImportedLink = { customerId: customer?.id ?? null, locationId: location.id, meterId: meter?.id ?? null }
      out.links.push(link)
    } else if (location && input.entity === 'locations') {
      out.links.push({ customerId: null, locationId: location.id, meterId: null })
    }

    preview.push(previewRow(input.entity, row.line, { customer, location, meter, rateItem }))
  }

  const valid = preview.length
  const [one, many] = ENTITY_NOUN[input.entity]
  const failed = new Set(errors.map((e) => e.row)).size
  const summary =
    `${valid} of ${rows.length} ${rows.length === 1 ? one : many} ready` +
    (failed ? ` · ${failed} ${failed === 1 ? 'row' : 'rows'} with errors` : '') +
    (warnings.length ? ` · ${warnings.length} ${warnings.length === 1 ? 'warning' : 'warnings'}` : '')

  return {
    id: rid('batch'),
    entity: input.entity,
    source: input.attachment ?? null,
    summary,
    rowCount: rows.length,
    records: out,
    preview: { columns: PREVIEW_COLUMNS[input.entity], rows: preview.slice(0, 200) },
    errors: errors.slice(0, 500),
    warnings: warnings.slice(0, 500),
  }
}

const PREVIEW_COLUMNS: Record<ImportEntity, string[]> = {
  accounts: ['Row', 'Account', 'Name', 'Service address', 'Meter'],
  customers: ['Row', 'Account', 'Name', 'Type', 'Phone'],
  locations: ['Row', 'Premise', 'Address', 'City', 'Inside city'],
  meters: ['Row', 'Meter', 'Serial', 'Read type', 'Multiplier'],
  rate_items: ['Row', 'Schedule', 'Item', 'Rate', 'Effective', 'Change'],
}

function previewRow(
  entity: ImportEntity,
  line: number,
  r: { customer: Customer | null; location: ServiceLocation | null; meter: Meter | null; rateItem: ImportedRateItem | null },
): string[] {
  const where = r.location ? `${r.location.address}, ${r.location.city} ${r.location.zip}` : '—'
  switch (entity) {
    case 'accounts':
      return [String(line), r.customer!.customer_number, customerName(r.customer!), where, r.meter?.meter_number ?? '—']
    case 'customers':
      return [String(line), r.customer!.customer_number, customerName(r.customer!), r.customer!.customer_type, r.customer!.phone ?? '—']
    case 'locations':
      return [String(line), r.location!.location_number, r.location!.address, `${r.location!.city}, ${r.location!.state} ${r.location!.zip}`, r.location!.inside_city_limits ? (r.location!.franchise_city ?? 'yes') : 'no']
    case 'meters':
      return [String(line), r.meter!.meter_number, r.meter!.serial_number ?? '—', r.meter!.read_type, r.meter!.multiplier]
    case 'rate_items':
      return [String(line), r.rateItem!.rate_schedule_code, r.rateItem!.item_code, `${r.rateItem!.rate} ${r.rateItem!.rate_unit}`, r.rateItem!.effective_from, r.rateItem!.change_type]
  }
}

/** What goes back to the model: counts, a grouped error list, and a reminder of who applies it. */
export function reportForModel(p: ImportProposal): string {
  const grouped = new Map<string, number[]>()
  for (const e of p.errors) {
    const k = `${e.field ?? 'row'}: ${e.message.replace(/"[^"]*"/, '"…"')}`
    grouped.set(k, [...(grouped.get(k) ?? []), e.row])
  }
  const lines = [
    `Staged import ${p.id}: ${p.summary}.`,
    p.errors.length
      ? `Errors (rows excluded):\n${[...grouped].slice(0, 20).map(([k, rows]) => `- ${k} — rows ${rows.slice(0, 12).join(', ')}${rows.length > 12 ? ` and ${rows.length - 12} more` : ''}`).join('\n')}`
      : 'No errors.',
    p.warnings.length ? `Warnings:\n${p.warnings.slice(0, 12).map((w) => `- row ${w.row}${w.field ? ` ${w.field}` : ''}: ${w.message}`).join('\n')}` : '',
    `Sample: ${JSON.stringify(p.preview.rows.slice(0, 3))}`,
    'The operator now sees this as a proposal card with Import and Discard buttons. Nothing is written until they click Import. Do not say it has been imported.',
  ]
  return lines.filter(Boolean).join('\n\n')
}
