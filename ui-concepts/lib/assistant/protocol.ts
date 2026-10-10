import type { Customer, Invoice, Meter, RateItemVersion, ServiceLocation } from '@/schemas/models'
import type { Channel, ChannelContent, Lang, TemplateContent } from '@/fixtures/templates'

/**
 * The wire contract between the chat panel and `/api/assistant`.
 *
 * The server is stateless: the panel holds the API transcript and hands it
 * back on every turn, append-only, so thinking blocks and server-tool results
 * reach the model exactly as it produced them.
 */

/* ---- Imports --------------------------------------------------------- */

export const IMPORT_ENTITIES = ['accounts', 'customers', 'locations', 'meters', 'rate_items'] as const
export type ImportEntity = (typeof IMPORT_ENTITIES)[number]

export const ENTITY_NOUN: Record<ImportEntity, [string, string]> = {
  accounts: ['account', 'accounts'],
  customers: ['customer', 'customers'],
  locations: ['service address', 'service addresses'],
  meters: ['meter', 'meters'],
  rate_items: ['rate item', 'rate items'],
}

/** A rate item version carries no schedule column in the DDL; an import has to say which tariff it belongs to. */
export type ImportedRateItem = RateItemVersion & { rate_schedule_code: string }

/** Which customer sits at which premise on which meter. A meter or premise may be imported before it has an occupant. */
export type ImportedLink = { customerId: string | null; locationId: string; meterId: string | null }

export type ImportBatch = {
  id: string
  entity: ImportEntity
  label: string
  count: number
  appliedAt: string
}

/** Everything applied from the chat, kept in this browser until the API exists. */
export type ImportedData = {
  customers: Customer[]
  locations: ServiceLocation[]
  meters: Meter[]
  rateItems: ImportedRateItem[]
  links: ImportedLink[]
  batches: ImportBatch[]
}

export const EMPTY_IMPORTED: ImportedData = {
  customers: [],
  locations: [],
  meters: [],
  rateItems: [],
  links: [],
  batches: [],
}

export type ImportIssue = { row: number; field: string | null; message: string }

/**
 * A validated, not-yet-applied import. The model can stage one; only the
 * operator can apply it. That is the same trust boundary as an exception's
 * `suggested_action` — presented, never applied.
 */
export type ImportProposal = {
  id: string
  entity: ImportEntity
  /** The attachment it came from, or null when the model typed the rows. */
  source: string | null
  summary: string
  rowCount: number
  /** One entry per row that passed, ready to write. */
  records: ImportedData
  /** Display rows for the preview table, one per valid source row. */
  preview: { columns: string[]; rows: string[][] }
  errors: ImportIssue[]
  warnings: ImportIssue[]
}

/* ---- Template edits -------------------------------------------------- */

/**
 * A staged change to one channel and language of a customer communication
 * template. Like an import, the model proposes and the operator applies; an
 * applied edit becomes a new template version marked as made with the
 * assistant. Proposals that fail the template checks are refused at the
 * server, so a card only ever offers something that could be saved.
 */
export type TemplateProposal = {
  id: string
  templateId: string
  templateName: string
  channel: Channel
  lang: Lang
  before: ChannelContent | null
  after: ChannelContent
  reason: string
  warnings: string[]
}

/* ---- Attachments ----------------------------------------------------- */

/** A file the operator dropped into the chat. Tables stay as text; PDFs go to the model whole. */
export type Attachment =
  | { name: string; kind: 'table'; text: string }
  | { name: string; kind: 'pdf'; base64: string }

/* ---- Request and stream --------------------------------------------- */

export type AssistantRequest = {
  /** The API transcript so far, exactly as the server last returned it. */
  transcript: unknown[]
  message: {
    text: string
    /** Names of attachments added with this message. */
    attachments: string[]
    /** Where the operator is standing, so "this account" resolves. */
    pathname: string
    /** Imports applied since the last turn, for the model's benefit. */
    notes: string[]
  }
  /** Every table attachment in the conversation, so a later turn can still import from it. */
  files: Attachment[]
  imported: ImportedData
  /** Account and draft-bill edits made in this browser, overlaid on the records. */
  edits?: RecordEdits
  /** Current content of every template edited in this browser, overlaid on the catalog. */
  templates?: Record<string, TemplateContent>
}

export type RecordEdits = {
  customers: Record<string, Partial<Customer>>
  invoices: Record<string, Partial<Invoice>>
}

export type ActivityKind = 'web' | 'tenant' | 'import' | 'template'

export type StreamEvent =
  | { type: 'text'; text: string }
  | { type: 'activity'; kind: ActivityKind; label: string }
  | { type: 'sources'; sources: { title: string; url: string }[] }
  | { type: 'proposal'; proposal: ImportProposal }
  | { type: 'template_proposal'; proposal: TemplateProposal }
  | { type: 'transcript'; messages: unknown[] }
  | { type: 'error'; message: string }
  | { type: 'done' }
