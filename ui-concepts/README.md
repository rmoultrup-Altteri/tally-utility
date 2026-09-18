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
| `/rates/sandbox` | Tariff sandbox — move a rate, rehearse it against a closed cycle's actual volumes |
| `/customers/cus-0001` | Customer 360 with usage-vs-weather |

## Design direction

"Pressroom" — editorial-utilitarian. A warm paper ground, hairline rules
instead of card shadows, and a deliberate pairing: **a grotesque for the tool,
a serif for the artifact.** Bills are set in the serif on white stock with
print geometry; the instrument around them is sans.

The reasoning, in short: the invoice is the most-scrutinised object this
product makes — customers dispute it, PUCs subpoena it, CSRs read it aloud. A
card-and-pill UI renders that as a web receipt. And since the core technical
differentiator is permanence (immutable bills, append-only ledger, bi-temporal
reproduction), a floaty dashboard aesthetic would contradict what is being
sold.

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
reading a bill against a printout wants it fixed. *System* is the absence of
`data-theme` and needs no JavaScript at all; *Day* and *Night* pin the
attribute, and a small inline script in the layout applies a stored pin before
first paint so the other palette never flashes.

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
record-level, no recents) is **not built yet**.

## Known gaps

- Interactions are presentational. Nothing writes; buttons do not submit.
- Favorites (T8-2) and the AR bucket drilldown lists are not built.
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
