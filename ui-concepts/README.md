# TallyUtility — UI concepts

First-iteration UI concepts for the TallyUtility portal. **Not the final UI** —
the point is to get something real on screen so we can react to it.

Fixture-driven: there is no API and no database behind this. Every screen reads
from typed fixtures in `fixtures/`, validated by Zod schemas in `schemas/` that
were transcribed from the DDL in `../application/database/schema.sql` and the
CHECK constraints in `../sql/tu.sql`.

```bash
pnpm install
pnpm dev          # http://localhost:4182
pnpm build        # typecheck + production build
pnpm screenshots  # capture all screens to /tmp/tu-shots (needs pnpm dev running)
                  # override the target with BASE_URL=http://localhost:PORT
```

Dev and start are pinned to **port 4182** — the meter number that runs through
the fixtures, and clear of the usual 3000 / 4200 / 5173 / 8080 collisions.

## Screens

| Route | What it is |
|---|---|
| `/dashboard` | Billing operations dashboard, built to the locked T8 rulings |
| `/` | Pre-mail exception queue — the home surface |
| `/reads` | Read validation grid, 20 columns in 6 groups |
| `/runs/run-2026-02-04` | Billing run cockpit with the post gate |
| `/runs/run-2026-02-sbx` | The same, as a dry run |
| `/invoices/inv-0001` | The bill, with its derivation rail |
| `/invoices/inv-0002` | A held commercial bill on G-1 — declining block, no sales-tax exemption |
| `/invoices/inv-0003` | A voided bill showing lineage |
| `/invoices/inv-0003/rebill` | Void → rebill, with the rate-date election |
| `/invoices/inv-0004/diff` | Correction diff — both input sets, balanced delta |
| `/collections` | Collections & disconnect worklist — bypass evaluation, stay exclusion, relight queue |
| `/rates` | Rate versions and the bi-temporal timeline |
| `/rates/pga` | PGA console — the bi-temporal lattice, late-filing exposure, filing discipline |
| `/rates/rate-case` | Rate case toolkit — revenue requirement, class allocation, solved rate design, bill impacts, filing schedules, implement. `/rates/sandbox` redirects here |
| `/outreach` | High-bill outreach — tell customers before a jumped bill lands, with the reason in one line |
| `/invoices/inv-0001/explain` | Why this bill changed — the CSR's explanation, English and Spanish, priced to the cent |
| `/portal/bills/inv-0001` | The same explanation as the customer sees it in the portal, at phone width |
| `/communications` | Every letter, email and text the utility sends, as versioned templates |
| `/communications/high-bill-heads-up` | The template editor — words, live preview from a real account, required text, versions |
| `/customers/cus-0001` | Customer 360 with usage-vs-weather |
| `/meters` | Every meter, set or in stock — filter by status, read type, route, size and what needs attention |
| `/meters/mtr-0001` | The meter record — equipment, premise, factors, endpoint, testing, swap lineage and history |
| `/settings` | Tenant settings — reached from the operator's name, top right |
| `/settings/dunning` | Automatic dunning setup, with a working-day preview on a real bill |

## Design direction

A warm paper ground with rounded, softly lifted panels, and a deliberate
pairing: **a grotesque for the tool, a serif for the artifact.** The
instrument is rounded; the bill is not. Bills are set in the serif on square
white stock with print geometry; the instrument around them is sans.

The frame is three rounded cards — the as-of band, the sidebar and the page —
on an inset ground. Corners step with the size of the thing: 4px for keys,
8px for buttons and inputs, 12px for panels, 16px for the assistant and
dialogs. Chips, status badges, search fields and the theme switch are pills.
Panels carry a hairline and a soft `--shadow-panel`; labels and column headers
are quiet sentence case rather than tracked capitals.

The reasoning for keeping the bill square: the invoice is the most-scrutinised
object this product makes — customers dispute it, PUCs subpoena it, CSRs read
it aloud. It should look like the page that gets printed and mailed, not a web
receipt. The `stock` utility sets every radius and the panel shadow back to
zero inside the sheet, so nothing in the document has to opt out on its own.

All tokens live in `app/theme.css` as a Tailwind v4 `@theme` block, named for
their **role in gas billing** rather than by hue — `--color-read-estimated-rail`,
`--color-state-held-rail`, `--color-money-credit`. Screens compose primitives
(`<Money>`, `<StateFlag>`, `<Rail>`) rather than scattering utility classes;
the long class strings live inside the primitives.

### Two lights

Every colour is declared **once**, as `light-dark(day, night)`. There is no
second palette to keep in sync — the dark theme is the second half of each
token, resolved by the browser against the nearest `color-scheme`. Day is ink
on warm paper; night is warm near-black with panels rising out of it, not an
inversion.

The switch has three states, because "follow the OS" and "pin it" are different
needs: an analyst working a night close wants the machine to decide, one
reading a bill against a printout wants it fixed. *Day* is the default — the
palette the design was drawn in, and the right first impression for daylight
office users. *Auto* is the absence of `data-theme` and follows the OS with no
JavaScript; *Night* pins the press palette. A small inline script in the layout
applies the choice before first paint so the other palette never flashes.

### Density

Beside the theme, under **Display** at the foot of the sidebar (and in Your
preferences), a second switch: *Comfortable* or *Compact*. Compact tightens the
4px spacing base and steps the data and body type down half a point, and
because every padding and gap utility is a multiple of `--spacing`, every screen
closes up together without knowing density exists (`globals.css`). Analysts
working a queue pick Compact; CSRs on a call usually do not.

### Navigation and detail on demand

The sidebar is five groups named for the job — Today, Customers, Billing,
Rates, Library — rather than fifteen flat links. Today is always open; the other
four are an accordion, so opening one folds whichever was open. Each page opens
on the group that holds it, and a folded group still shows its badges
(`components/shell/SidebarNav.tsx`).

Screens lead with the decision and keep the supporting detail one click away:
the bill explanation opens on the headline, the bridge chart and the talk track,
with each cause in words and **Show the math** folded beneath; the outreach
board shows its rules and five figures on a first visit and a single summary
line after; its side panel folds the breakdown and reach details to one-line
gists; rate design hides billing determinants until asked; and the template
editor puts its 37 merge fields behind a searchable **Insert field** menu.

**The bill is exempt.** A statement is a printed object, so the `stock` utility
pins `color-scheme: light` inside the sheet: every token in that subtree
resolves to its day value, and the document stays white paper with dark ink in
both themes without any of its markup knowing themes exist.

Contrast is audited rather than asserted — all rendered text meets WCAG AA in
both themes. Getting there moved three things: accent split into a fill role
and a text role (a blue dark enough to carry white button text is unreadable
as a link on a dark panel), voided records now carry their meaning in the
strikethrough rather than in being faint, and `--color-ink-muted` is reserved
for placeholders and `aria-hidden` separators — anything an operator must read,
including the em-dash that means "no value recorded", sits at `ink-tertiary` or
above.

## What the concepts are arguing

Three schema invariants drove most of these decisions:

1. **Issued bills are immutable.** There is no edit affordance anywhere on a
   bill. The only correction is void → rebill, and it is a guided election
   rather than a button, because the database refuses anything less.
2. **Every rate lookup needs an explicit `valid_at` + `recorded_at` pair** with
   no fallback to current values. So the as-of coordinate is persistent chrome,
   run screens state the coordinate they resolved, and the rates timeline shows
   both time axes — including a factor recorded six weeks late.
3. **Nothing is deleted and nothing is edited in place.** Void bills and
   superseded rate versions stay visible and struck, never hidden.

## Locked decisions this implements

Several surfaces here are **not open design questions** — they were ruled by the
domain expert and live in `gas-billing-memory/application/`:

| Ruling | Where it shows up |
|---|---|
| **T8-1** quick-find on every page, five match fields, no advanced search | Header on all screens |
| **T8-4** portlet placement by *item type*, never by row severity | `/dashboard` portlets |
| **T8-5** revenue pair, voids net at void date, **no ratio** between the figures | `/dashboard` revenue |
| **T8-6/7** AR aged **by invoice**, dollars primary, drilldowns must sum to the tile | `/dashboard` AR strip |
| **T8-8** rate card reads **as-billed** from `invoice_line_items.rate`, drift marker only where it differs | `/dashboard` rate card |

`T8-2` (favorites: reports, record lists and saved searches only — nothing
record-level, no recents) is built — see the next section.

## Favorites and saved views (T8-2)

Favorites cover reports, record lists and saved searches only. Nothing
record-level, and no recents list — the reasoning is lifespan, since a report
stays useful for years and a customer record for the length of one call.

That exclusion is enforced by **shape**, not by convention: `lib/views.ts`
defines a three-variant target union with no `entity_type` / `entity_id` pair
anywhere. A polymorphic favorite would reopen record-level the first time
somebody wrote a row with `entity_type = 'customer'`, and no review catches
that reliably; a union with nowhere to put a customer id catches it at compile
time.

A saved search and a saved filtered view are one object, because given T8-1
they are one thing. Filter state on the exception queue lives in the URL, so a
filtered queue is already a shareable link and a saved view is that link with a
name on it — `?severity=critical&blocking=1&assignee=unassigned`.

## Fixture invariants

`pnpm check:fixtures` asserts every identity the screens display but nothing
enforces — referential integrity, the gas derivation chain, invoice arithmetic,
rate version chains, lifecycle rules, and the cross-fixture numbers one screen
states in prose about another's rows.

It exists because of a bug that hid in plain sight: the bill's derivation rail
applied the meter multiplier twice, and looked correct on every account for as
long as every multiplier was 1.0000. That is the shape of the whole class — an
identity that holds for free until the one record arrives where it doesn't —
and eyeballing screenshots will not find it.

The checks are mutation-tested rather than assumed: breaking a cent, a
multiplier, a day count, a version chain or a narrative total each produce a
finding. A check that has never failed is not evidence of anything.

## Back and edit

Detail screens — an account, a bill, its correction diff and rebill, Add
payment — have a small back arrow left of the title. It goes back to the screen
the operator came from (a bill opened from an account returns to the account),
and falls back to the parent screen when there is nothing behind it in the app.

**Edit**, top right, opens a form dialog:

- **Accounts:** name, phone, email, customer type, tax exemption, billing hold,
  and disconnect protection. Changing a protection, a hold or the tax status
  needs a reason, because the schema records those through
  `customer_state_events`. Account number, status, balance and deposit are not
  editable; money moves only through bills, payments and the ledger.
- **Bills:** only draft and held bills — none has been issued — and only the
  bill date, due date and hold reason. Issued bills show no Edit; their only
  correction is still void then rebill. Amounts and lines come from the run.

**Inactivate** / **Reactivate**, beside Edit on an account and on a meter,
changes status as a state event: a reason, an effective date, and a tick
against each consequence (a balance or deposit still on the account, a meter
serving an account, a read still in review). Inactivating an account can take
its premise's meter with it. Only an active meter can be inactivated — setting
or pulling one is a service order. Roles without Edit accounts see the button
disabled.

The Accounts and Meters lists open on **Active**, with a chip per status and
**All**. An account counts as active while it is in service or in collections,
or while any balance remains on it, so an inactivated account still owing money
stays on the default list. A search on the default list looks across every
status. Every account and meter number on every screen opens its record, unless
the prototype doesn't model that record; those show as plain text.

Edits overlay the fixtures in this browser (`lib/edits-store.ts`) with a log
of who changed what and why; the header shows when the record was last edited.
The assistant sees them too.

## Settings

The operator's name at top right opens a menu with **Settings** and **Log out**.
Settings holds every tenant-configurable value from the configurable-rules
review (`tally-utility-memory/application/configurable-rules/`), catalogued as
data in `fixtures/settings.ts` and grouped by area: organization, billing,
money in, collections, operations, and the operator's own preferences.

Each setting says how far the tenant's hand reaches. *Fixed* values are statute
or platform invariants, shown read-only so nobody hunts for the switch.
*Tariff-bound* values are editable but must match the filing, and saving one
asks for the reference. *Not in schema yet* marks values ruled configurable
that have no column yet, and *Open question* marks values the domain expert
has not ruled on.

Tenant configuration is history (`tenant_configuration_history`, v5.4.1-02),
so a save never overwrites. It asks when the change takes effect (the next
billing period by default, never backdated) and why, and appends to the change
history on the overview. Changes are kept in this browser (`lib/settings-store.ts`).

**Access.** Tenant settings are open only to roles holding the **Change
settings** capability (`settings.edit`), built to the RBAC ruling D-1
(2026-08-18). Each tenant role is composed from a platform-seeded capability
catalog and inherits a fixed system tier (`fixtures/roles.ts`). Without the
capability, the user menu offers **Preferences** instead of Settings, and a
settings URL explains who has access and who to ask. An operator's own
preferences stay open to everyone.

**Roles & access** is where an administrator assigns roles and decides what
each role may do. Holding Change settings lets you see that page. Changing it
takes an Administrator-tier role, and nobody may change their own role. Two
tier rules are enforced in the editor:

- Administrator roles always keep Change settings, so the utility can never
  lock itself out.
- Read-only roles hold nothing that writes.

Access changes apply at once rather than from a date.

The user menu has a concept-only **View as** list, so gated screens can be
seen as an administrator, a CSR or an auditor without editing fixtures. The
gate in the concepts hides screens. Real enforcement belongs on the server.

**Dunning** has its own setup screen, built to be done in a minute:

- Choose Off, Preview (evaluate daily, send nothing) or On.
- Pick a schedule: Standard, Gentle or Fastest lawful.
- Adjust any step if needed.

The steps follow the platform's fixed sequence: reminder, late fee,
termination notice, disconnect. The form enforces the statutory floors of five
working days past due before the notice, and five working days after confirmed
delivery before a disconnect. Beside the steps, a preview runs the schedule on
Cycle 04's real due date in working days around the Texas holiday calendar
(`lib/working-days.ts`). A disconnect landing on a Friday moves to Monday,
because a disconnect may not fall on the day before a weekend. The protection
checks that run before every step are listed beneath, read-only.

## Bill explanation

**Why it changed** on a bill (and on the account's usage panel) opens the
explanation: the bill against the same month last year or last month, split
into weather, usage beyond the weather, gas cost, the weather adjustment, each
base-rate change, and taxes. `lib/bill-explain.ts` does it by re-pricing the
comparison bill one change at a time, line by line, rounded the way the biller
writes lines, so the steps add to the real difference to the cent. It reads
each bill's prices back off its own lines and reproduces all 87 issued bills in
the fixtures exactly; if one ever did not, the gap would show as its own
"rounding" step rather than vanish into another.

The CSR view adds a talk track, the arithmetic and what to offer. The portal
view (`/portal/bills/…`) is the customer's phone screen, in the utility's
brand and the day palette, with an English/Spanish switch. The sentences are
written in both languages side by side, not translated after the fact.

## High-bill outreach

The pre-mail queue already knows which draft bills jumped. The outreach board
turns that into a heads-up before the bill is dated: each candidate's change is
split by the same engine, the reason goes in one line, and the message comes
from the **High-bill heads-up** template. A text goes only to a number with
consent on file, inside quiet hours; protected and in-collections customers get
a call with talking points instead; anyone with neither email nor consent gets
the explanation printed on the bill. Everything over the threshold but not
contacted is listed with its reason: an estimated read, a budget-billing
account, an opt-out. Sends need the **Send outreach** capability and are kept
in this browser (`lib/outreach-store.ts`). The high-usage exception in the
queue links straight to the customer on the board.

## Rate case toolkit

Replaces the tariff sandbox. It carries a case end to end against RRC
GUD-11042: the revenue requirement (Schedule A), billing determinants from the
system's own volumes (the locked January cycle carried across the test year
and scaled to every account), a class allocation slider, rate design with
**Solve volumetric rates** / **Solve customer charge**, a proof of revenue
within the residue of four-decimal rates, typical bills and the January
distribution, the filing schedules A–E with a redlined tariff, the customer
notice from the communications library (with the typical change filled in
from the design), and the rate versions to stage for a second person's
approval. Bills are priced with the same `priceAt` the explanation uses.

## Communications

Every message a customer receives lives in one catalog
(`fixtures/templates.ts`), grouped Billing, Payments, Collections, Service,
Safety and Regulatory, and linked from the bottom of the sidebar. Dunning,
outreach, the bill explanation and the rate case all send from it, so a wording
change is made once.

The editor shows the words beside the customer's view, filled from a real
account (pick any fixture customer) through the same engine. Merge fields
insert at the cursor; anything not on the list is refused. Rule-prescribed
text (`{{required.termination_rights}}`, the rate-case notice, the gas-leak
steps) is shown with its citation and placed by a token that cannot be removed.
Text messages show their real length, including the automatic opt-out line, and
name the character that forces Unicode. Saving needs **Edit communications**
and a reason, and appends a version (`lib/templates-store.ts`) — nothing is
overwritten, and the history shows a word-level diff.

The assistant can edit templates too. Its tools read the library and stage an
edit, which the server validates with the same checks as the editor before it
reaches the chat as a card with **Apply edit** and **Discard**. An applied edit
becomes a version marked *with the assistant*, and the open editor picks it up
(or, if you have an unsaved draft, says a newer version arrived). Buttons in the
editor — Shorter, Warmer, Plainer, Check it, Write the Spanish — hand the
request to the chat for you (`lib/assistant/bus.ts`).

## Assistant

The bubble in the bottom-right corner of every screen opens a chat backed by
Claude (`claude-opus-5-5`) through `app/api/assistant/route.ts`. It needs
credentials on the server:

```bash
echo ANTHROPIC_API_KEY=sk-ant-... > .env.local   # then restart pnpm dev
```

It can do four things:

- **Read the tenant's account** — search, an account in full, a bill with its
  lines, rates in force at a date, the billing overview, and a generic
  filter/sort/sum over every fixture (`lib/assistant/tenant-data.ts`). Totals
  are summed in exact integer micro-units, never floats.
- **Read the web** — Anthropic's server-side web search and fetch, with sources
  listed under the answer.
- **Stage imports** of accounts, customers, service addresses, meters and rate
  items from an attached CSV, TSV, JSON or PDF, or from rows typed in the chat.
  The model only maps columns; `lib/assistant/imports.ts` parses the file,
  coerces every value, validates it against the Zod schemas and rejects
  duplicates. Rate items are close-then-insert successions with a required
  change reason; a back-dated change is refused as a correction.
- **Edit communication templates** — read the library and stage a new version
  of one channel and language, refused with the reason if it drops required
  text, uses an unknown merge field or runs a text past three messages.

The model can propose an import, but it cannot apply one. Each staged import
appears as a card with **Import** and **Discard**, the same trust boundary as
an exception's `suggested_action`. Applied records live in this browser
(`lib/imports-store.ts`) until the API exists. The Accounts list shows them
marked *imported*; they have no account page yet.

The conversation is kept in sessionStorage and survives navigation. The route
is stateless: the panel sends the API transcript with each turn and gets the
extended one back.

## Known gaps

- Interactions are presentational. Nothing writes; buttons do not submit.
  Payments taken, assistant imports, account and draft-bill edits, template
  versions and outreach sends are the exceptions, and all are kept only in
  this browser.
- Outreach candidates beyond the fixture accounts, and the general-service
  population in the rate case, are seeded rather than drawn from records; their
  figures are given, split the same way and summing to the cent.
- The rate case's cost-of-service components are a settlement's black box: O&M
  is the residual that makes them equal the settled requirement.
- The assistant route has no authentication and trusts the transcript the
  browser sends. That is fine on localhost and not fine anywhere else.
- Assistant imports of meters, premises and rate items are stored but not yet
  shown on the Rates or account screens; the assistant itself can see them.
- Excel files must be saved as CSV before attaching.
- The AR bucket drilldown lists are not built.
- Collections rules are Texas-specific (16 TAC §7.460 forecast rule, no
  calendar moratorium). A real deployment parameterises these per jurisdiction;
  the fixture hard-codes one state.
- The whole shell overflows horizontally below ~600px — the 208px sidebar and
  the fixed-width quick-find never collapse. Pre-existing on every screen; the
  target user is at a desk, but it should be a deliberate decision rather than
  an accident.
- Keyboard affordances are shown (`j`/`k`, `⌘K`) but not yet wired.
- A large share of the features these screens imply are marked `✗ gap` in
  `gas-billing-memory/application/feature-list.md`. These are built to the spec,
  not to the current schema — deliberately, since concepts are a cheap way to
  pressure-test the spec before the DDL hardens.
