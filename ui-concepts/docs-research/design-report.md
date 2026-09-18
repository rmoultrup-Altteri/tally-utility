# DESIGN DIRECTION — TallyUtility operational UI

**Scope:** first-iteration UI prototype of a natural-gas CIS / meter-to-cash platform for LDCs in the 500–150,000 meter band. Users are billing analysts, CSRs, and utility directors who live in this software eight hours a day and are coming off Oracle CC&B, NISC, Harris/Cayenta, or SEDC.

**Grounding:** read `/Users/ryanscomputer/code/tally-utility/CONTEXT.md` and the actual DDL in `/Users/ryanscomputer/code/tally-utility/application/database/schema.sql` — `invoices`, `invoice_line_items`, `meter_readings`, `anomalies`, `rate_item_history`, `rate_item_history_archive`, `billing_runs`, `billing_run_meters`, `correction_run_targets`. Every pattern below binds to real columns rather than generic design advice.

**Build constraint:** Tailwind v4. Section 2 is expressed as a paste-ready `@theme` block.

---

## 1. Three candidate directions

### A. "Ledger" — Swiss / International, instrument-grade

Strict 4px grid, rules instead of shadows, near-zero chroma, one accent, a Helvetica-lineage grotesque with true tabular figures. No cards anywhere. Hierarchy comes from weight and rule-weight, never from boxes. Everything aligns to a visible column structure that persists across screens.

**What it feels like to a billing analyst:** the software reads as a measuring device. Nothing decorative competes with the numbers; a 40-row read-validation screen scans in a single pass, and the eye learns the grid in a day.

**Risk:** in a 30-minute demo to a Utility Director it can read as austere or unfinished. Swiss rigor rewards the daily user and undersells to the buyer — a real problem in a competitive procurement.

### B. "Pressroom" — editorial-utilitarian  *(RECOMMENDED)*

Warm paper ground rather than cool SaaS gray. Hairline rules and a genuinely editorial typographic hierarchy — a real display/body/caption/label ladder — deployed inside tight spatial density. The pairing strategy carries the whole product: **a grotesque for the tool, a serif for the artifact.** Bills, notices, and anything a PUC might read are set in serif on white paper stock with print geometry; everything else is the sans-serif instrument around it. Status is carried by left-edge rails and letterform flags, not by pill badges.

**What it feels like to a billing analyst:** working inside a well-made ledger book that happens to run at screen speed. The bill looks like a document, not a `div`. Numbers sit in ruled columns the way they do on the paper reports these people have filed for twenty years, but the software answers in 80ms instead of overnight.

### C. "Console" — professional-tool rigor, denser than Linear

Cool neutral layering, 2px radii, subtle surface elevation, command-palette-centric navigation, motion used strictly to explain state changes. The Stripe/Linear school taken two density notches further than either actually ships.

**What it feels like to a billing analyst:** fast, modern, software-y. Strongest with CSRs and IT Directors; the easiest direction to hire frontend talent against. Its weakness is precisely the highest-stakes screen — it cannot make an invoice look like a legal record. A bill rendered in Console chrome looks like a web receipt, which is exactly wrong when a customer is disputing it.

### Recommendation: **Pressroom**

Three product-specific reasons, not aesthetic preference:

1. **The invoice is the most-scrutinized artifact this product produces.** Customers dispute it, PUCs subpoena it, CSRs read it aloud over the phone. It must look authoritative in print and on screen. Pressroom is the only direction that treats the document as the design center rather than as an export target.
2. **The bi-temporal / audit story is the core technical differentiator.** A visual language of permanence — rules, paper, serif records, provenance shown inline — sells the invariants in `CONTEXT.md` (immutable bills, append-only ledger, subpoena-ready audit). A floaty card UI actively contradicts them.
3. **Competitive positioning.** Against NISC/SEDC/Cayenta the bar is "not Windows 98." Against any modern startup entrant the bar is "not another Tailwind dashboard." Pressroom clears both. Console clears only the first, and in a bake-off against a well-funded competitor that is the difference between differentiated and interchangeable.

Light-first. A dark theme should exist but must not be the default — these are daylight office users who compare screen to printed bill all day.

---

## 2. Token set — Tailwind v4 `@theme`

Paste-ready. Tokens are named for their **role in gas billing**, not for hue, so a palette change never requires renaming a class.

Two Tailwind v4 namespace notes to avoid collisions:
- `--text-*` in v4 is the **font-size** namespace. Text *colors* therefore live under `--color-text-*` (→ `text-text-primary`). If that reads awkwardly in markup, rename the color tier prefix to `--color-ink-*` (→ `text-ink-primary`); the values below are unchanged either way.
- `--spacing` in v4 is a single multiplier. The named steps below are additive extras for the few places where a semantic name beats a number (cell padding, rail width, document measure).

```css
@import "tailwindcss";

@theme {
  /* ==========================================================================
     SURFACE LAYERS — warm neutral paper (hue 95, very low chroma).
     White reads as RAISED against warm paper: elevation without shadows.
     ========================================================================== */
  --color-surface-sunken:    oklch(95.2% 0.004 95);  /* app chrome, table gutters, behind panels */
  --color-surface:           oklch(98.4% 0.003 95);  /* the working paper — default page ground */
  --color-surface-raised:    oklch(100%  0     0  ); /* rows/panels above paper; popovers */
  --color-surface-inset:     oklch(92.8% 0.005 95);  /* input wells, read-only derivations, code */
  --color-surface-document:  oklch(100%  0     0  ); /* bill & notice stock — always pure white */
  --color-surface-ink:       oklch(21%   0.010 95);  /* inverse blocks, print headers */
  --color-surface-scrim:     oklch(21%   0.010 95 / 0.38);

  /* ==========================================================================
     TEXT TIERS  (→ text-text-primary, or rename prefix to `ink` if preferred)
     --color-text-primary on --color-surface is ~14:1. AAA, not AA:
     these people read numbers for eight hours.
     ========================================================================== */
  --color-text-primary:      oklch(20% 0.008 95);  /* numbers, names, decision-bearing text */
  --color-text-secondary:    oklch(43% 0.008 95);  /* supporting copy, secondary columns */
  --color-text-tertiary:     oklch(57% 0.006 95);  /* unit suffixes, timestamps, column labels */
  --color-text-muted:        oklch(70% 0.004 95);  /* disabled, placeholder, the null em-dash */
  --color-text-inverse:      oklch(98% 0.003 95);

  /* ==========================================================================
     ACCENT — interaction ONLY. Never carries status.
     ========================================================================== */
  --color-accent:            oklch(46% 0.150 262); /* links, primary action, focus ring */
  --color-accent-hover:      oklch(40% 0.155 262);
  --color-accent-active:     oklch(35% 0.150 262);
  --color-accent-wash:       oklch(94% 0.030 262); /* selected row, range selection */
  --color-accent-wash-hover: oklch(91% 0.038 262); /* selected AND hovered */

  /* ==========================================================================
     EXCEPTION SEVERITY — maps to anomalies.severity and blocking state.
     Each has: -rail (3px left edge / fill, >=3:1 non-text),
               -text (>=4.5:1 on paper),
               -wash (row tint).
     ========================================================================== */
  --color-exception-critical-rail: oklch(52% 0.190  27);
  --color-exception-critical-text: oklch(44% 0.170  27);
  --color-exception-critical-wash: oklch(96%   0.028  27);

  --color-exception-warning-rail:  oklch(72% 0.150  75);
  --color-exception-warning-text:  oklch(46% 0.105  70);
  --color-exception-warning-wash:  oklch(96.5% 0.032  80);

  --color-exception-info-rail:     oklch(58% 0.100 250);
  --color-exception-info-text:     oklch(45% 0.100 250);
  --color-exception-info-wash:     oklch(96%   0.020 250);

  --color-exception-cleared-rail:  oklch(55% 0.130 150);
  --color-exception-cleared-text:  oklch(43% 0.110 150);
  --color-exception-cleared-wash:  oklch(96%   0.025 150);

  --color-exception-snoozed-rail:  oklch(72% 0.006  95); /* anomalies.snoozed_until set */
  --color-exception-snoozed-text:  oklch(57% 0.006  95);
  --color-exception-snoozed-wash:  oklch(96.8% 0.003 95);

  /* ==========================================================================
     LIFECYCLE STATE — billing_runs.status / invoices.status
     ========================================================================== */
  --color-state-draft-rail:      oklch(72% 0.006  95);
  --color-state-draft-text:      oklch(57% 0.006  95);
  --color-state-pending-rail:    oklch(58% 0.100 250);  /* running, dry run, held */
  --color-state-pending-text:    oklch(45% 0.100 250);
  --color-state-approved-rail:   oklch(55% 0.130 150);
  --color-state-approved-text:   oklch(43% 0.110 150);
  --color-state-posted-rail:     oklch(45% 0.120 150);  /* terminal + irreversible */
  --color-state-posted-text:     oklch(38% 0.105 150);
  --color-state-failed-rail:     oklch(52% 0.190  27);
  --color-state-failed-text:     oklch(44% 0.170  27);
  --color-state-void-rail:       oklch(80% 0.005  95);  /* + strikethrough + 70% opacity */
  --color-state-void-text:       oklch(62% 0.005  95);
  --color-state-superseded-rail: oklch(80% 0.005  95);  /* replaces_invoice_id lineage */
  --color-state-superseded-text: oklch(62% 0.005  95);

  /* HELD / BLOCKED — invoices.held_at, hold_reason. Deliberately distinct from
     both "failed" (something broke) and "pending" (something is working):
     held means a human stopped it and a human must release it. */
  --color-state-held-rail:       oklch(62% 0.140  40);  /* burnt orange — not red, not amber */
  --color-state-held-text:       oklch(44% 0.125  40);
  --color-state-held-wash:       oklch(96.5% 0.026 40);

  /* DRY RUN — billing_runs.is_dry_run. Nothing here is real. Carried by color
     AND a repeating diagonal hatch on the run header, because the single most
     expensive mistake in this product is treating a dry run as posted. */
  --color-state-dryrun-rail:     oklch(60% 0.075 300);  /* muted violet — used nowhere else */
  --color-state-dryrun-text:     oklch(45% 0.085 300);
  --color-state-dryrun-wash:     oklch(96.5% 0.018 300);
  --color-state-dryrun-hatch:    oklch(88%   0.030 300); /* repeating-linear-gradient stripe */

  /* ==========================================================================
     READ PROVENANCE — actual vs estimated vs disputed.
     The single most consequential distinction on a read-validation grid.
     ========================================================================== */
  --color-read-actual-rail:     oklch(55% 0.130 150);
  --color-read-actual-text:     oklch(43% 0.110 150);
  --color-read-estimated-rail:  oklch(72% 0.150  75);  /* meter_readings.is_estimated */
  --color-read-estimated-text:  oklch(46% 0.105  70);
  --color-read-estimated-wash:  oklch(96.5% 0.032 80);
  --color-read-unvalidated-rail:oklch(58% 0.100 250);  /* validation_status='pending_review' */
  --color-read-unvalidated-text:oklch(45% 0.100 250);
  --color-read-disputed-rail:   oklch(52% 0.190  27);  /* dispute_reason IS NOT NULL */
  --color-read-disputed-text:   oklch(44% 0.170  27);
  --color-read-locked-text:     oklch(57% 0.006  95);  /* billing_period_locked */
  --color-read-tamper-rail:     oklch(52% 0.190  27);  /* tamper_count_*_changed_flag */

  /* ==========================================================================
     MONEY — deliberate: sign is NOT carried by red/green.
     Red is already exception, and sign-by-color fails ~8% of male analysts.
     Money is --color-text-primary; sign is typographic (minus or parentheses)
     plus a subtle tint. Red appears in money ONLY for aged arrears.
     ========================================================================== */
  --color-money:             oklch(20% 0.008  95);  /* default amount — same as primary text */
  --color-money-positive:    oklch(20% 0.008  95);  /* charge / debit — intentionally identical
                                                       to --color-money: a normal charge is not
                                                       an event and must not be colored like one */
  --color-money-credit:      oklch(42% 0.085 160);  /* negative / credit to customer */
  --color-money-arrears:     oklch(44% 0.170  27);  /* past-due in AGING contexts only */
  --color-money-adjustment:  oklch(45% 0.100 262);  /* total_adjustments, ad-hoc charges */
  --color-money-zero:        oklch(57% 0.006  95);  /* real 0.00 — distinct from the null dash */

  /* ==========================================================================
     RULES & BORDERS — borders do the work, not shadows.
     ========================================================================== */
  --color-rule-hair:   oklch(89% 0.004 95);  /* between rows, inside column groups */
  --color-rule-solid:  oklch(82% 0.005 95);  /* between column groups, panel edges */
  --color-rule-heavy:  oklch(30% 0.008 95);  /* under table headers, above totals */
  --color-rule-doc:    oklch(35% 0.006 95);  /* accounting rules on the bill document */

  /* ==========================================================================
     TYPOGRAPHY — two families, one deliberate pairing:
     grotesque for the tool, serif for the artifact.
     Mono is SEMANTIC: "this is a key you will read aloud or paste."
     ========================================================================== */
  --font-sans:  "Inter", "Inter Tight", system-ui, sans-serif;
  --font-mono:  "IBM Plex Mono", ui-monospace, monospace;
  --font-doc:   "Source Serif 4", "IBM Plex Serif", Georgia, serif;

  /* Fixed scale. This is an application at controlled density — no clamp(). */
  --text-label:   11px;   --text-label--line-height:  14px;
                          --text-label--letter-spacing: 0.06em;
                          --text-label--font-weight: 600;
  --text-micro:   11px;   --text-micro--line-height:  15px;
  --text-data:    13px;   --text-data--line-height:   18px;   /* table body — the workhorse */
  --text-body:    14px;   --text-body--line-height:   21px;
  --text-h3:      15px;   --text-h3--line-height:     20px;   --text-h3--font-weight: 600;
  --text-h2:      18px;   --text-h2--line-height:     24px;   --text-h2--font-weight: 600;
  --text-h1:      22px;   --text-h1--line-height:     28px;   --text-h1--font-weight: 600;
  --text-figure:  28px;   --text-figure--line-height: 32px;   --text-figure--font-weight: 600;
  --text-doc:     10.5pt; --text-doc--line-height:    15pt;   /* bill body, print units */
  --text-doc-h:   13pt;   --text-doc-h--line-height:  17pt;

  /* ==========================================================================
     SPACING — 4px base with a 2px sub-unit for optical alignment in cells.
     Named extras where a semantic name beats a number.
     ========================================================================== */
  --spacing: 4px;
  --spacing-cell-x-compact: 10px;
  --spacing-cell-y-compact: 6px;
  --spacing-cell-x:         12px;
  --spacing-cell-y:         8px;
  --spacing-rail:           3px;    /* status rail width */
  --spacing-row-compact:    26px;
  --spacing-row:            30px;
  --spacing-row-comfy:      36px;
  --spacing-doc-measure:    8.5in;  /* bill paper width */

  /* ==========================================================================
     RADIUS — near-zero. Table cells and document edges are square.
     ========================================================================== */
  --radius-none: 0px;
  --radius-xs:   2px;   /* inputs, buttons, chips */
  --radius-sm:   4px;   /* popovers, panels, modals */

  /* ==========================================================================
     ELEVATION — exactly three levels.
     1 inline: no shadow at all (border + surface change only)
     2 overlay: popovers, dropdowns, the provenance card
     3 modal: scrim + this
     Plus the sticky-header shadow, applied ONLY while scrolled.
     ========================================================================== */
  --shadow-overlay: 0 8px 24px -12px oklch(20% 0.010 95 / 0.28);
  --shadow-modal:   0 24px 48px -20px oklch(20% 0.010 95 / 0.34);
  --shadow-sticky:  0 1px 0 0 oklch(20% 0.010 95 / 0.12);

  /* ==========================================================================
     MOTION — transform/opacity only. Zero row-enter animation in tables.
     ========================================================================== */
  --ease-standard: cubic-bezier(0.2, 0, 0, 1);
  --duration-fast: 90ms;
  --duration-base: 140ms;
}

/* Tabular figures and a slashed zero are not optional in this product.
   Meter serials get read aloud on the phone. */
@layer base {
  body, table, input, .tabular {
    font-variant-numeric: tabular-nums;
    font-feature-settings: "ss01", "zero";
  }
  @media (prefers-reduced-motion: reduce) {
    *, ::before, ::after { animation-duration: 0s !important; transition-duration: 0s !important; }
  }
}
```

### Dark theme overrides

Recommended, but **not** as the default — see section 1. Two rules make it work: the surface
ladder inverts, and **the bill document stays white paper in both themes.** A dark invoice is
not the artifact the customer received, and CSRs compare screen to mailed bill constantly.

Tailwind v4 has no `dark:` token indirection built in, so override the same custom properties
under a `data-theme` attribute (an explicit user choice — do not switch on `prefers-color-scheme`
alone for an all-day operational tool; let the user decide and persist it).

```css
@layer base {
  [data-theme="dark"] {
    /* Surfaces: the ladder inverts, but keeps the warm hue so it is recognizably
       the same product. Raised is LIGHTER than the ground, as in light mode. */
    --color-surface-sunken:   oklch(17% 0.008 95);
    --color-surface:          oklch(21% 0.008 95);
    --color-surface-raised:   oklch(25% 0.009 95);
    --color-surface-inset:    oklch(15% 0.008 95);
    --color-surface-ink:      oklch(12% 0.006 95);
    --color-surface-scrim:    oklch(8%  0.004 95 / 0.58);
    /* --color-surface-document stays oklch(100% 0 0). The bill is paper. */

    /* Text tiers: never pure white — it vibrates against a dark ground over an
       eight-hour shift. Top tier lands ~13:1, still AAA. */
    --color-text-primary:     oklch(94% 0.004 95);
    --color-text-secondary:   oklch(76% 0.005 95);
    --color-text-tertiary:    oklch(62% 0.005 95);
    --color-text-muted:       oklch(48% 0.005 95);
    --color-text-inverse:     oklch(18% 0.008 95);

    /* Accent: raise lightness, drop chroma slightly — saturated blue on dark
       fringes badly at 13px. */
    --color-accent:           oklch(70% 0.120 262);
    --color-accent-hover:     oklch(76% 0.120 262);
    --color-accent-active:    oklch(64% 0.125 262);
    --color-accent-wash:      oklch(30% 0.055 262);
    --color-accent-wash-hover:oklch(34% 0.065 262);

    /* Status: rails brighten (they are now figure against a dark ground),
       text variants rise to ~72-80% L, washes become dark tints not light ones. */
    --color-exception-critical-rail: oklch(62% 0.180  27);
    --color-exception-critical-text: oklch(78% 0.140  27);
    --color-exception-critical-wash: oklch(27% 0.055  27);
    --color-exception-warning-rail:  oklch(76% 0.145  75);
    --color-exception-warning-text:  oklch(82% 0.115  78);
    --color-exception-warning-wash:  oklch(27% 0.045  75);
    --color-exception-info-rail:     oklch(68% 0.105 250);
    --color-exception-info-text:     oklch(78% 0.090 250);
    --color-exception-info-wash:     oklch(27% 0.040 250);
    --color-exception-cleared-rail:  oklch(66% 0.125 150);
    --color-exception-cleared-text:  oklch(78% 0.100 150);
    --color-exception-cleared-wash:  oklch(26% 0.045 150);
    --color-exception-snoozed-rail:  oklch(45% 0.006  95);
    --color-exception-snoozed-text:  oklch(62% 0.005  95);
    --color-exception-snoozed-wash:  oklch(24% 0.006  95);

    --color-state-draft-rail:      oklch(45% 0.006  95);
    --color-state-draft-text:      oklch(62% 0.005  95);
    --color-state-pending-rail:    oklch(68% 0.105 250);
    --color-state-pending-text:    oklch(78% 0.090 250);
    --color-state-approved-rail:   oklch(66% 0.125 150);
    --color-state-approved-text:   oklch(78% 0.100 150);
    --color-state-posted-rail:     oklch(58% 0.120 150);
    --color-state-posted-text:     oklch(72% 0.100 150);
    --color-state-failed-rail:     oklch(62% 0.180  27);
    --color-state-failed-text:     oklch(78% 0.140  27);
    --color-state-void-rail:       oklch(40% 0.005  95);
    --color-state-void-text:       oklch(56% 0.005  95);
    --color-state-superseded-rail: oklch(40% 0.005  95);
    --color-state-superseded-text: oklch(56% 0.005  95);
    --color-state-held-rail:       oklch(70% 0.135  40);
    --color-state-held-text:       oklch(80% 0.110  40);
    --color-state-held-wash:       oklch(27% 0.048  40);
    --color-state-dryrun-rail:     oklch(70% 0.080 300);
    --color-state-dryrun-text:     oklch(80% 0.070 300);
    --color-state-dryrun-wash:     oklch(27% 0.030 300);
    --color-state-dryrun-hatch:    oklch(36% 0.045 300);

    --color-read-actual-rail:      oklch(66% 0.125 150);
    --color-read-actual-text:      oklch(78% 0.100 150);
    --color-read-estimated-rail:   oklch(76% 0.145  75);
    --color-read-estimated-text:   oklch(82% 0.115  78);
    --color-read-estimated-wash:   oklch(27% 0.045  75);
    --color-read-unvalidated-rail: oklch(68% 0.105 250);
    --color-read-unvalidated-text: oklch(78% 0.090 250);
    --color-read-disputed-rail:    oklch(62% 0.180  27);
    --color-read-disputed-text:    oklch(78% 0.140  27);
    --color-read-locked-text:      oklch(62% 0.005  95);
    --color-read-tamper-rail:      oklch(62% 0.180  27);

    /* Money: same discipline — sign is typographic, not chromatic. */
    --color-money:             oklch(94% 0.004  95);
    --color-money-positive:    oklch(94% 0.004  95);
    --color-money-credit:      oklch(74% 0.085 160);
    --color-money-arrears:     oklch(78% 0.140  27);
    --color-money-adjustment:  oklch(76% 0.085 262);
    --color-money-zero:        oklch(62% 0.005  95);

    /* Rules: on dark, hairlines must LIGHTEN rather than darken, and the heavy
       rule loses its power — it becomes the lightest, not the darkest. */
    --color-rule-hair:   oklch(30% 0.006 95);
    --color-rule-solid:  oklch(38% 0.006 95);
    --color-rule-heavy:  oklch(62% 0.006 95);
    --color-rule-doc:    oklch(35% 0.006 95);  /* unchanged — draws on white paper */

    /* Elevation: shadows stop reading on dark. Raise the surface step instead
       and keep only a faint shadow for overlay separation. */
    --shadow-overlay: 0 8px 24px -12px oklch(0% 0 0 / 0.55);
    --shadow-modal:   0 24px 48px -20px oklch(0% 0 0 / 0.65);
    --shadow-sticky:  0 1px 0 0 oklch(0% 0 0 / 0.40);
  }

  /* The document is paper in every theme. */
  [data-theme="dark"] .bill-document {
    --color-text-primary:   oklch(20% 0.008 95);
    --color-text-secondary: oklch(43% 0.008 95);
    --color-text-tertiary:  oklch(57% 0.006 95);
    color-scheme: light;
  }
}
```

### Notes on the token set

- **Density modes** (`row-compact` / `row` / `row-comfy`) are a user preference, persisted per user. Default **compact for queues**, default for browse tables.
- **Rhythm is deliberately not uniform.** Table regions are tight (`cell-y-compact`); consequential decision surfaces — approve a run, void a bill — get 24–32px of breathing room so they feel different under the hand before the user has read a word.
- **The accounting rule set** (`--color-rule-heavy` above a subtotal, a double rule under a grand total) is borrowed literally from accounting typography and should be used literally on the bill document and on run totals.
- **Dry run is the one place color is not enough.** `--color-state-dryrun-hatch` drives a repeating diagonal stripe across the run header and a persistent top-rail band, the same way the as-of band works. `is_dry_run` mistaken for posted is the most expensive error the product can make.
- **Held is not failed and not pending.** `--color-state-held-*` gets its own hue precisely because `held_at` / `hold_reason` means a human stopped it and a human must release it — an operational state, not an error and not progress.
- **Validate every status color against four grounds**, not just paper: `surface`, hover (`surface-sunken`), selected (`accent-wash`), and `exception-critical-wash`. A rail that passes 3:1 on paper and fails on a tinted row is a real defect.

---

## 3. Patterns for the hard problems

### (a) Dense data tables — 15+ columns with row-level status

- **Status rail, not a status column.** A 3px left edge (`--spacing-rail`) carries lifecycle state and reclaims a full column of horizontal budget. The row background stays paper; the wash tints are reserved for selection and for genuinely critical rows, so a tint always means "act on this" rather than "this exists."
- **A narrow flags column of single monospace letters.** `E` estimated, `T` tamper, `D` disputed, `L` billing-period-locked, `S` service transition, `X` anomaly. These map directly onto `meter_readings.is_estimated`, `tamper_count_1_changed_flag` / `tamper_count_2_changed_flag`, `dispute_reason`, `billing_period_locked`, `is_service_transition`, and `billing_run_meters.has_anomaly`. Legacy users already read coded flags fluently; this is both familiar *and* roughly four times denser than badge chips. Every glyph carries a tooltip and a screen-reader label.
- **Column groups with a `rule-solid` divider** and a group label row above the header row: `Identity | Read | Consumption | Gas | Validation | Audit`. A 20-column table with six labelled groups is navigable. Twenty undifferentiated columns are not.
- **Frozen identity columns** — account number, customer name, meter number — with a hairline plus `--shadow-sticky` on horizontal scroll. The frozen set is fixed by the product, not user-draggable; draggable frozen columns generate support tickets forever.
- **No zebra striping.** Hairlines plus the status rail do the row-tracking work, and zebra fights every tint you need for state.
- **Column visibility, order, width, sort, filters, and density live in the URL** and the last-used configuration persists per user per table. Analysts build a personal view of the read-validation grid and fully expect it to be there on Monday morning; losing it once destroys trust in the tool.
- **Virtualized body, real `<table>` semantics.** Stable pagination with exact counts — never infinite scroll in a financial list. Reconciliation requires "1–100 of 3,412."
- **Interaction states:** hover fills `surface-sunken`; focus is a 2px inset `accent` ring that remains visible over both hover and selection washes; selection uses a checkbox column with shift-range, and `Ctrl/Cmd-A` selects **within the current filter only**, with a persistent bar reading "312 selected across 4 pages."

### (b) Exception / work queues

The home surface of this product is a **queue, not a dashboard.**

- **Two-pane triage** — list on the left in compact rows, detail on the right. Never a modal: the analyst needs the surrounding rows visible to judge whether this is one bad read or a whole route gone wrong.
- **Ranked by consequence, not recency.** `anomalies.estimated_impact` weighted by `severity`. `confidence` renders as a five-segment bar rather than "0.82" — a printed percentage invites arguing with the model; a bar invites judgment.
- **Grouping on `dedup_key` / `anomaly_type`** with collapse. `recurrence_count` and `first_detected_at` render as "7th occurrence since Jan 3" — a repeat is a categorically different problem from a first, and the schema already knows the difference.
- **Single-key verbs in queue context:** `j`/`k` move, `r` resolve, `s` snooze (writes `snoozed_until` + `snooze_reason`), `a` assign (`assigned_to`), `o` open the underlying record, `u` undo. Verbs disable whenever a text field holds focus. Resolution reason (`resolution_notes`) is an inline required field, never a modal.
- **`suggested_action` is presented, never applied.** Render it as a primary button with an explicit plain-language line beneath it: "This will re-estimate the Feb read for meter 004182 using the prior-year same-period value." Then a Preview showing the resulting numbers before commit. This is the trust boundary for the AI features and the place where a wrong default becomes a wrong bill.
- **A decrementing remaining count and a session tally:** "142 remaining · 38 cleared today." Eight-hour work needs visible progress. Legacy systems gave none, and analysts kept tallies on paper — that is a requirement hiding in plain sight.
- **Bulk actions on a group** confirm with an itemized list of what will change, not a count.
- `linked_anomaly_id` gets a visible "related" affordance in the detail pane — cascading anomalies from one root cause should be resolvable together.

### (c) Invoice / bill document view

- **Render the artifact, not a representation of it.** Fixed measure at 8.5×11 proportion on `surface-document`, `font-doc` at point sizes, square corners, no card shadow beyond a single hairline defining the paper edge. The same CSS produces the screen view, the PDF (`pdf_url`), and the print output — one source of truth for what the customer actually receives, which is also what makes CSR phone support work.
- **The inspector rail sits beside the document, never over it.** Clicking a line item shows the full derivation from `invoice_line_items`: `gas_ccf_used` → `gas_meter_factor` → pressure correction → `gas_btu_factor` → `gas_therms_billed` → `gas_commodity_rate` → `amount`, naming `rate_schedule_id` / `rate_item_id` / `tier_label`, the `coverage_start`–`coverage_end` span, `days_covered` of `days_in_period`, and `partial_period_policy_applied`. **This is the product's signature screen** — the bill explains itself. No legacy CIS does this, and it is exactly what a CSR needs mid-call with an angry customer.
- **Lineage is chrome, not a badge.** A voided invoice gets a genuine diagonal VOID overprint in `state-void` at low opacity, plus a lineage strip across the top: `← replaces INV-2025-004182` / `superseded by INV-2025-004900 →`, driven by `replaces_invoice_id`. `void_reason_code`, `void_reason_notes`, `voided_by`, and `voided_at` are shown on the face, not hidden behind an info icon. `void_rebill_expected = true` with no rebill present is itself an exception worth surfacing here in `exception-warning`.
- **State the pricing world in words.** For anything produced by a correction run, a line under the header: "Priced with rates in effect 2025-11-30 (original period)" versus "Priced with rates in effect today" — reading `billing_runs.correction_rate_mode` and `correction_run_targets.rate_date_mode` / `rate_date_override`. Reproducibility is only worth something if the analyst can see which world they are standing in.
- `has_estimated_reads` / `estimated_read_count` appears as a printed note **on the document itself**, because it does on the real bill.
- `tax_breakdown` renders as a proper ruled sub-table, not a JSON blob; `previous_balance` / `total_charges` / `total_credits` / `total_taxes` / `total_adjustments` → `amount_due` uses accounting rules (single rule above each subtotal, double rule under the total).

### (d) Date-effective records and version timelines

- **"As of" is persistent chrome, not a filter.** A control in the top rail, always visible, always displaying the active coordinate. When it is anything other than today, **the entire application changes appearance** — an `exception-info` band across the top rail reading "Viewing as of 2025-11-30 · Return to today." There must be no way to mistake a historical view for a live one; that mistake is a billing error, and the codebase's own memory notes that as-of functions deliberately refuse to fall back to live values. The UI should carry the same discipline.
- **Timeline band** for `rate_item_history` and every other date-effective set: contiguous horizontal segments from `effective_date` to `end_date`, proportional but with a minimum segment width so a one-day PGA correction stays clickable. The current segment is filled; **future segments are outlined or hatched, never filled** — a scheduled rate is not an active rate, and conflating them is how someone bills next month's PGA today. The open-ended segment (`end_date IS NULL`) fades to the right rather than terminating in an arrow. Clicking a segment sets the as-of coordinate for the whole screen.
- **Adjacent-version diff inline:** `0.412000 → 0.438500 /therm`, with `change_reason`, `regulatory_reference`, `changed_by`, and `created_at`. The regulatory reference must be first-class and copyable — it is what goes into a PUC filing, and making an analyst dig for it is a daily tax.
- **Provenance on hover for any date-effective value anywhere in the app**, in an overlay-level card: the value, its effective range, who changed it, why, and a link into the timeline. If a number on screen came from a dated record, the user can learn why in one gesture without losing their place.
- **Archived history (`rate_item_history_archive`) appears in the same timeline, visually identical**, marked "archived" only inside the provenance card. The user should never have to know which physical table a value came from.
- `rate_item_dependencies` deserves a small derived-from indicator on any rate item that is computed from a base item (franchise fees, percentage riders) — changing the base silently changes the dependent, and the analyst needs to see that before committing.

### (e) Money and unit formatting

- **Tabular figures and decimal alignment everywhere.** Numeric columns right-align. No proportional digits in a numeric column, ever.
- **Full precision on rates.** `NUMERIC(12,6)` means six decimals displayed: `0.438500`, trailing zeros preserved. Rounding a rate for visual tidiness is how billing disputes start. Amounts are always 2dp with grouping separators.
- **Currency symbol in the column header and on totals only**, not repeated per row — it costs horizontal budget and adds no information.
- **Sign:** leading minus (or accounting parentheses, per-user preference — staff trained on Cayenta and SEDC expect `(1,204.55)`; younger CSRs expect `−1,204.55`) plus the `money-credit` tint. Never red-for-negative.
- **Units are `text-tertiary` suffixes at ~0.85em** — `1,204.55 therms` — and move up into the column header when the column is uniform. Mixed-unit columns (`consumption_unit` varies by meter) must keep the per-row suffix; that is precisely when a wrong assumption becomes a wrong bill. Note the schema still defaults `consumption_unit` to `'gallons'` — gas surfaces must never inherit that silently.
- **Show the factor chain, don't hide it.** Where both exist, Ccf and therms get separate columns; `gas_meter_factor` and `gas_btu_factor` surface on hover with the arithmetic spelled out. Gas-native means the corrections are *legible*, not merely correct.
- **Deltas** against `consumption_prior_period` and `consumption_same_period_last_year` render as a compact signed percent with a direction glyph, and are **thresholded** — suppress anything under ±5% so the column speaks only when it has something to say. `consumption_pct_vs_typical` drives the same treatment.
- **Zero is not null.** `0.00` in `money-zero` means a real zero read; `—` in `text-muted` means no value. Conflating these is a classic read-validation failure and an easy one to build in by accident.
- **Dates** are unambiguous in all data contexts — `2025-11-30` or `30 Nov 2025`. Never `11/30/25` in a table an auditor may read.

---

## 4. Anti-patterns — specific to this audience

- **SaaS whitespace luxury.** 40px rows and 16px body text halve the rows on screen. These users are implicitly benchmarking against a green-screen that showed 50 records at once; losing that is a real productivity regression they will name in week one, and it will be the first thing in the reference call.
- **Modal-driven workflows.** Modals hide the reference data needed to make the decision and destroy keyboard flow. Two-pane layouts and inline editing instead; modals only for irreversible financial commits.
- **Toast-only confirmation of financial actions.** Posting a run or voiding a bill must leave a durable, findable record on screen. A toast that fades in four seconds is not an audit trail and, more importantly, does not *feel* like one.
- **Infinite scroll in any financial list.** Reconciliation needs stable pages and exact counts.
- **Autosave on rate, factor, or money fields.** Explicit commit, with the effective date stated in the confirmation copy: "Effective 2026-01-01. This will not change bills already issued."
- **Color as the sole carrier of state.** Every status needs a glyph or a word beside the hue.
- **A KPI dashboard as the landing page.** Donuts and sparkline tiles are for the director's monthly review, not for the person who logs in at 7:40 to clear exceptions. Ship the queue as home and put the KPIs on their own surface.
- **Hiding decision-relevant data behind hover or expand.** If it is needed to judge a row, it must be present, copyable, and printable.
- **Rounding for looks, dropping trailing zeros, localized ambiguous dates.** All three manufacture disputes.
- **Cheerful empty states.** "You're all caught up 🎉" is wrong for software that gets read in a deposition. "No open exceptions for cycle 04." is correct.
- **Dark mode by default.** Daylight offices, and the bill document is white paper in every theme. Light-first; dark as an option.
- **Sanding off the domain vocabulary.** Say therms, Mcf, Ccf, PGA, WNA, dunning stage, relight, cancel-rebill, escheatment. Generic microcopy — "items," "records," "issues" — signals to a Utility Director that the vendor does not know gas, which undercuts the entire positioning in `CONTEXT.md`.
- **Drag-and-drop as the only path** to anything (column order, route sequencing, queue priority). These are keyboard users; every drag needs a keyboard equivalent.
- **Soft-delete presented as deletion.** The product has no hard deletes. A row that was "deleted" must remain visible in an explicit state with its reason, or the UI is lying about the data model.

---

## 5. Accessibility

**Contrast.** Body and numeric text target **7:1 (AAA)**, not 4.5:1 — this is eight-hour-a-day reading, and the AAA target is also a hedge for an experienced workforce with aging eyes. Non-text carriers — status rails, borders, focus rings, chart marks — hold ≥3:1 against **both** the row background and the hover/selection washes. Validate every status color against all four possible row grounds (paper, hover, selected, critical-wash), not just paper.

**Keyboard-first operation.** The highest-leverage accessibility decision here, because it is also how these users genuinely work.

- Every list and table is arrow-navigable via a roving tabindex. `Tab` moves between regions, not between cells.
- Type-ahead jump in tables: start typing an account number, land on the row.
- A command palette (`Ctrl`/`Cmd`-`K`) whose verbs are **domain verbs** — "void invoice," "start correction run," "set as-of date," "open route 14" — not generic navigation.
- Single-key verbs inside queue context, automatically disabled when a text field has focus.
- `Esc` returns to the list and **never discards filters or selection.**
- Date fields accept typed `113025` / `11302025` alongside a picker. Decades of numeric-keypad muscle memory live there, and forcing a mouse trip to a calendar widget is the most reliably hated thing in modern CIS replacements.
- **Ship a printable keyboard reference card** plus a `?` overlay. Legacy users taped one to the monitor; meeting them there buys disproportionate goodwill in the first week.

**Focus.** A 2px inset `accent` ring, never removed, visible over every row state. Focus is restored to the originating row after a modal or inline action closes. After resolving a queue item, focus lands on the next item — the queue must be clearable end-to-end without touching the mouse once.

**Density and sizing.** Three persisted density levels, plus a numeric-zoom that scales table text independently of chrome, so a director can read over a shoulder without reflowing the analyst's layout. Respect OS text scaling to 200% without horizontal loss in detail panes; tables may scroll horizontally, nothing else may.

**Motion.** ≤140ms, transform and opacity only, nothing animated inside table bodies. `prefers-reduced-motion` drops all durations to zero — and since motion is never load-bearing here, nothing breaks when it does.

**Assistive tech.** Real `<table>` with `<caption>`, `scope`, and `aria-sort`. Queues are lists with a polite live region announcing the remaining count after each resolution. Every flag glyph carries a text label; every status rail is accompanied by a word in the row or an `aria-label`. Forms use real labels — never placeholder-as-label — and errors bind via `aria-describedby` stating the specific fix, not "invalid input."

---

## Source note

Read: `/Users/ryanscomputer/code/tally-utility/CONTEXT.md`, `/Users/ryanscomputer/code/tally-utility/application/database/schema.sql`, `/Users/ryanscomputer/code/tally-utility/application/FEATURE-LIST.md` (a pointer file only).

The authoritative feature list at `/Users/ryanscomputer/code/LLM-wiki/projects/TallyUtility/knowledge/FEATURE-LIST.md` is **not present on this machine**, so section 3 is grounded in the DDL rather than the ~350-feature inventory. Worth a second pass against the feature list once available — particularly for the 18 pipeline stages, which likely imply navigation structure this report does not address.
