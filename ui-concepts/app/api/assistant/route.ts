import Anthropic from '@anthropic-ai/sdk'
import { z } from 'zod'
import { asOf, currentUser, cycle, tenant } from '@/fixtures/tenant'
import { rateSchedules } from '@/fixtures/rates'
import {
  EMPTY_IMPORTED,
  IMPORT_ENTITIES,
  type AssistantRequest,
  type ImportedData,
  type StreamEvent,
} from '@/lib/assistant/protocol'
import { describeTable, fieldGuide, parseTable, reportForModel, stage, type Table } from '@/lib/assistant/imports'
import {
  QUERY_ENTITIES,
  billingOverview,
  getAccount,
  getInvoice,
  listRates,
  queryRecords,
  searchTenant,
  tenantView,
  type TenantView,
} from '@/lib/assistant/tenant-data'

/**
 * The assistant behind the chat bubble.
 *
 * One POST per operator message. The server runs the tool loop — web search
 * and fetch on Anthropic's side, tenant lookups and import staging here — and
 * streams newline-delimited JSON events back to the panel. It holds no state:
 * the panel sends the transcript in and gets the extended transcript out.
 *
 * Credentials come from the environment (ANTHROPIC_API_KEY in .env.local, or
 * an `ant auth login` profile). Nothing reaches the browser but the answer.
 */

const MODEL = 'claude-opus-5-5'
const MAX_ITERATIONS = 16
const MAX_RESULT_CHARS = 60_000

type Msg = Anthropic.Beta.BetaMessageParam
type Block = Anthropic.Beta.BetaContentBlockParam

const SYSTEM = `You are the assistant inside Tally Utility, the meter-to-cash portal for natural gas distribution. You work for ${tenant.name}, a Texas municipal gas system regulated by the ${tenant.jurisdiction}, serving ${tenant.meters.toLocaleString('en-US')} meters across ${tenant.franchiseCities.join(', ')}. The person you are talking to is ${currentUser.name}, ${currentUser.role}.

The portal reads through an as-of coordinate: valid ${asOf.validAt}, recorded ${asOf.recordedAt}. Everyone is working ${cycle.label} (${cycle.periodLabel}, ${cycle.periodStart} to ${cycle.periodEnd}, bills dated ${cycle.billDate}). Rate schedules: ${rateSchedules.map((s) => `${s.code} ${s.name}`).join('; ')}.

What you can do:
- Answer from the tenant's own records with the tenant tools. Never state a balance, rate, count or date about this tenant that a tool did not give you. If the data is not there, say so. Money and rates are exact decimal strings: quote them as given, and do arithmetic only through query_records' sum.
- Search and read the web for anything outside the tenant: tariffs and filings at the Railroad Commission, gas price indices, weather, regulations, vendor documentation. Say where a fact came from and link the source.
- Stage imports of accounts, customers, service addresses, meters and rate items from files the operator attaches or from rows they dictate. You map columns and call stage_import; the server validates every value against the schema. You cannot write records: the operator applies or discards each staged import from a card in the chat. Never say records were imported until a note tells you an import was applied.

Rules the portal enforces and you should explain rather than work around: issued bills are immutable and are corrected only by void then rebill; reference data is close-then-insert, so a rate change is a new version with a change reason and an earlier version is never edited; nothing is deleted. Disconnect protections, billing holds and opening balances are not set by import.

For an import: look at the columns and sample rows, choose the entity, map every column you can to a field, put file-wide values (a state, a cycle, a change reason the operator gave you) in constants, and stage it. If a mapping is genuinely ambiguous, ask one short question first. After staging, summarise what is ready and what failed, grouped by cause, and suggest how to fix the file.

This is a chat panel about 400px wide. Lead with the answer, keep it short, use small tables only when comparing rows, and link records with their portal path (for example [Marisol Herrera](/customers/cus-0001)).

Import fields by entity:
${fieldGuide()}`

/* ---- Tools ----------------------------------------------------------- */

const scalar = z.union([z.string(), z.number(), z.boolean()])

const INPUTS = {
  search_tenant: z.object({
    query: z.string().describe('Name, account number, meter number or serial, street address, or invoice number'),
    limit: z.number().int().optional(),
  }),
  get_account: z.object({
    account: z.string().describe('Customer id (cus-…) or account number (100-248193)'),
  }),
  get_invoice: z.object({
    invoice: z.string().describe('Invoice id (inv-…) or invoice number'),
    include_lines: z.boolean().optional(),
  }),
  query_records: z.object({
    entity: z.enum(QUERY_ENTITIES),
    where: z
      .record(z.string(), scalar)
      .optional()
      .describe('Field filters. Plain values match exactly (case-insensitive); prefix a string with >, >=, <, <=, != or ~ (contains). "null" matches empty.'),
    fields: z.array(z.string()).optional().describe('Only these fields per row'),
    sort_by: z.string().optional(),
    descending: z.boolean().optional(),
    limit: z.number().int().optional().describe('Default 25, max 200'),
    sum: z.string().optional().describe('A decimal field to total exactly across every matching row'),
  }),
  list_rates: z.object({
    schedule_code: z.string().optional(),
    valid_at: z.string().optional().describe('YYYY-MM-DD; defaults to the as-of date'),
  }),
  billing_overview: z.object({}),
  stage_import: z.object({
    entity: z.enum(IMPORT_ENTITIES),
    attachment: z.string().optional().describe('Name of an attached table. Omit when passing rows.'),
    column_map: z.record(z.string(), z.string()).optional().describe('field → source column header, for an attachment'),
    constants: z.record(z.string(), z.string()).optional().describe('field → value used wherever the row has none'),
    rows: z.array(z.record(z.string(), z.string())).optional().describe('Rows keyed by field name, when there is no attachment (e.g. read from a PDF or dictated)'),
    assign_numbers: z.boolean().optional().describe('Assign account, premise or meter numbers where the source has none'),
  }),
} as const

type ToolName = keyof typeof INPUTS

const DESCRIPTIONS: Record<ToolName, string> = {
  search_tenant: "Find records in the tenant's account the way the quick-find does: customer name, account number, meter number or serial, service address, invoice number. Returns ids to pass to get_account or get_invoice.",
  get_account: 'One account in full: customer, premises with meter and latest read, bills newest first, payments, open exceptions, and any collections worklist row.',
  get_invoice: 'One bill with its line items and the gas derivation on each line.',
  query_records: 'List, filter, sort, count and total any record type in the tenant. Returns total_matching, the rows, and the field names. Use for questions like "how many commercial accounts", "unpaid bills over $500", "estimated reads this cycle".',
  list_rates: 'The rates in force on each schedule at a date, with any scheduled future versions. Every lookup resolves valid_at and recorded_at explicitly.',
  billing_overview: 'Portfolio figures: the current billing run, month-to-date revenue and collections, AR aged by invoice, open exception counts, the collections pipeline, and what has been imported.',
  stage_import: 'Validate an import and present it to the operator to apply. Pass an attachment with column_map, or rows keyed by field. Returns counts, grouped errors and warnings. Does not write anything; the operator applies it.',
}

function inputSchema(schema: z.ZodType): Anthropic.Beta.BetaTool.InputSchema {
  const { $schema: _drop, ...json } = z.toJSONSchema(schema) as Record<string, unknown>
  return { ...json, type: 'object' } as Anthropic.Beta.BetaTool.InputSchema
}

const TOOLS: Anthropic.Beta.BetaToolUnion[] = [
  {
    type: 'web_search_20260209',
    name: 'web_search',
    max_uses: 6,
    user_location: { type: 'approximate', city: 'Bryan', region: 'Texas', country: 'US', timezone: 'America/Chicago' },
  },
  { type: 'web_fetch_20260209', name: 'web_fetch', max_uses: 6 },
  ...(Object.keys(INPUTS) as ToolName[]).map(
    (name): Anthropic.Beta.BetaTool => ({
      name,
      description: DESCRIPTIONS[name],
      input_schema: inputSchema(INPUTS[name]),
      /* Import rows can be long; let them stream as they are written. */
      eager_input_streaming: true,
    }),
  ),
]

function activityFor(name: string, input: Record<string, unknown>): StreamEvent {
  switch (name) {
    case 'search_tenant':
      return { type: 'activity', kind: 'tenant', label: `Searching the account for “${input.query}”` }
    case 'get_account':
      return { type: 'activity', kind: 'tenant', label: `Reading account ${input.account}` }
    case 'get_invoice':
      return { type: 'activity', kind: 'tenant', label: `Reading bill ${input.invoice}` }
    case 'query_records':
      return { type: 'activity', kind: 'tenant', label: `Querying ${String(input.entity).replace(/_/g, ' ')}` }
    case 'list_rates':
      return { type: 'activity', kind: 'tenant', label: `Reading rates${input.schedule_code ? ` on ${input.schedule_code}` : ''}` }
    case 'billing_overview':
      return { type: 'activity', kind: 'tenant', label: 'Reading the billing overview' }
    case 'stage_import':
      return { type: 'activity', kind: 'import', label: `Validating ${String(input.entity).replace(/_/g, ' ')}${input.attachment ? ` from ${input.attachment}` : ''}` }
    case 'web_search':
      return { type: 'activity', kind: 'web', label: `Searching the web for “${input.query}”` }
    case 'web_fetch':
      return { type: 'activity', kind: 'web', label: `Reading ${input.url}` }
    default:
      return { type: 'activity', kind: 'tenant', label: name }
  }
}

function runTool(
  name: ToolName,
  input: unknown,
  view: TenantView,
  tables: Map<string, Table>,
  send: (e: StreamEvent) => void,
): string {
  switch (name) {
    case 'search_tenant': {
      const i = INPUTS.search_tenant.parse(input)
      return JSON.stringify(searchTenant(view, i.query, i.limit))
    }
    case 'get_account':
      return JSON.stringify(getAccount(view, INPUTS.get_account.parse(input).account))
    case 'get_invoice': {
      const i = INPUTS.get_invoice.parse(input)
      return JSON.stringify(getInvoice(view, i.invoice, i.include_lines ?? true))
    }
    case 'query_records':
      return JSON.stringify(queryRecords(view, INPUTS.query_records.parse(input)))
    case 'list_rates': {
      const i = INPUTS.list_rates.parse(input)
      return JSON.stringify(listRates(view, i.schedule_code, i.valid_at))
    }
    case 'billing_overview':
      return JSON.stringify(billingOverview(view))
    case 'stage_import': {
      const proposal = stage(INPUTS.stage_import.parse(input), tables, view)
      send({ type: 'proposal', proposal })
      return reportForModel(proposal)
    }
  }
}

/* ---- The turn -------------------------------------------------------- */

function userTurn(req: AssistantRequest, tables: Map<string, Table>, tableErrors: Map<string, string>): Msg {
  const content: Block[] = []
  const context = [
    `Operator is viewing ${req.message.pathname || '/'}. Wall clock ${new Date().toISOString()}.`,
    ...req.message.notes,
  ]
  content.push({ type: 'text', text: `<context>\n${context.join('\n')}\n</context>` })
  for (const name of req.message.attachments) {
    const file = req.files.find((f) => f.name === name)
    if (!file) continue
    if (file.kind === 'pdf') {
      content.push({
        type: 'document',
        title: file.name,
        source: { type: 'base64', media_type: 'application/pdf', data: file.base64 },
      })
    } else {
      const t = tables.get(name)
      content.push({
        type: 'text',
        text: t ? describeTable(name, t) : `Attached "${name}" could not be read as a table: ${tableErrors.get(name)}`,
      })
    }
  }
  content.push({ type: 'text', text: req.message.text || '(no message — see the attachment)' })
  return { role: 'user', content }
}

function clip(s: string) {
  return s.length > MAX_RESULT_CHARS
    ? `${s.slice(0, MAX_RESULT_CHARS)}\n…truncated (${s.length} chars). Narrow the query with where, fields or limit.`
    : s
}

function friendly(err: unknown): string {
  if (err instanceof Anthropic.AuthenticationError || err instanceof Anthropic.PermissionDeniedError)
    return 'The assistant could not authenticate with Anthropic. Set ANTHROPIC_API_KEY in ui-concepts/.env.local and restart pnpm dev.'
  if (err instanceof Anthropic.RateLimitError) return 'Anthropic is rate-limiting requests. Try again in a moment.'
  if (err instanceof Anthropic.APIError) return `Anthropic API error ${err.status ?? ''}: ${err.message}`
  if (err instanceof Anthropic.AnthropicError && /api ?key|auth/i.test(err.message))
    return 'No Anthropic credentials found. Set ANTHROPIC_API_KEY in ui-concepts/.env.local and restart pnpm dev.'
  return err instanceof Error ? err.message : String(err)
}

export async function POST(request: Request) {
  const req = (await request.json()) as AssistantRequest
  const imported: ImportedData = { ...EMPTY_IMPORTED, ...(req.imported ?? {}) }
  const view = tenantView(imported, req.edits)

  const tables = new Map<string, Table>()
  const tableErrors = new Map<string, string>()
  for (const f of req.files ?? []) {
    if (f.kind !== 'table') continue
    try {
      tables.set(f.name, parseTable(f.text))
    } catch (e) {
      tableErrors.set(f.name, e instanceof Error ? e.message : String(e))
    }
  }

  const messages: Msg[] = [...((req.transcript ?? []) as Msg[]), userTurn(req, tables, tableErrors)]
  const encoder = new TextEncoder()

  const body = new ReadableStream<Uint8Array>({
    async start(controller) {
      const send = (e: StreamEvent) => {
        try {
          controller.enqueue(encoder.encode(`${JSON.stringify(e)}\n`))
        } catch {
          /* The panel hung up (Stop, or the tab closed). The loop ends on the abort signal. */
        }
      }
      try {
        const client = new Anthropic()
        let jsonRetries = 0

        for (let i = 0; i < MAX_ITERATIONS; i++) {
          const stream = client.beta.messages.stream(
            {
              model: MODEL,
              max_tokens: 32000,
              system: SYSTEM,
              tools: TOOLS,
              messages,
              thinking: { type: 'adaptive' },
              output_config: { effort: 'medium' },
              cache_control: { type: 'ephemeral' },
              /* A false-positive safety decline re-runs on Anthropic's recommended model instead of ending the turn. */
              betas: ['server-side-fallback-2026-07-01'],
              fallbacks: 'default',
            },
            { signal: request.signal },
          )
          stream.on('text', (text) => send({ type: 'text', text }))
          stream.on('contentBlock', (block) => {
            if (block.type === 'server_tool_use') send(activityFor(block.name, block.input as Record<string, unknown>))
            if (block.type === 'web_search_tool_result' && Array.isArray(block.content)) {
              send({
                type: 'sources',
                sources: block.content
                  .filter((r) => r.type === 'web_search_result')
                  .slice(0, 6)
                  .map((r) => ({ title: r.title, url: r.url })),
              })
            }
          })

          let message: Anthropic.Beta.BetaMessage
          try {
            message = await stream.finalMessage()
            jsonRetries = 0
          } catch (err) {
            /* Only an unparseable streamed tool input is retried; API errors go to the operator. */
            if (err instanceof Anthropic.APIError || request.signal.aborted || jsonRetries++ >= 2) throw err
            continue
          }

          if (message.stop_reason === 'refusal') {
            messages.push({ role: 'assistant', content: message.content })
            send({ type: 'text', text: '\n\nI can’t help with that one.' })
            break
          }

          messages.push({ role: 'assistant', content: message.content })
          if (message.stop_reason === 'pause_turn') continue

          const calls = message.content.filter((b): b is Anthropic.Beta.BetaToolUseBlock => b.type === 'tool_use')
          if (calls.length === 0) break
          if (message.stop_reason === 'max_tokens') {
            messages.pop()
            throw new Error('The reply ran out of room mid-tool-call. Try a smaller import or a narrower question.')
          }

          const results: Anthropic.Beta.BetaToolResultBlockParam[] = []
          for (const call of calls) {
            const name = call.name as ToolName
            if (!(name in INPUTS)) {
              results.push({ type: 'tool_result', tool_use_id: call.id, is_error: true, content: `Unknown tool ${call.name}` })
              continue
            }
            const parsed = INPUTS[name].safeParse(call.input)
            if (!parsed.success) {
              results.push({
                type: 'tool_result',
                tool_use_id: call.id,
                is_error: true,
                content: `Invalid input: ${parsed.error.issues.map((x) => `${x.path.join('.')}: ${x.message}`).join('; ')}`,
              })
              continue
            }
            send(activityFor(name, parsed.data as Record<string, unknown>))
            try {
              results.push({ type: 'tool_result', tool_use_id: call.id, content: clip(runTool(name, parsed.data, view, tables, send)) })
            } catch (e) {
              results.push({ type: 'tool_result', tool_use_id: call.id, is_error: true, content: e instanceof Error ? e.message : String(e) })
            }
          }
          messages.push({ role: 'user', content: results })
        }

        send({ type: 'transcript', messages })
      } catch (err) {
        if (!request.signal.aborted) send({ type: 'error', message: friendly(err) })
      } finally {
        send({ type: 'done' })
        try {
          controller.close()
        } catch {
          /* Already closed by the client. */
        }
      }
    },
  })

  return new Response(body, {
    headers: { 'Content-Type': 'application/x-ndjson; charset=utf-8', 'Cache-Control': 'no-store' },
  })
}
