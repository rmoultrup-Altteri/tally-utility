# TallyUtility — Project Context

## What This Is

TallyUtility is a modern utility billing platform (CIS / meter-to-cash) targeting natural gas Local Distribution Companies (LDCs) in the 500–150,000 meter band. This includes small municipal gas systems, public gas districts, co-ops, and small-to-mid investor-owned utilities — customers who are underserved by enterprise platforms (Oracle CC&B, SAP IS-U) and poorly served by legacy mid-market vendors (NISC, Harris/Cayenta, SEDC, Milsoft, CUSI).

**Parent company:** Altteri (incorporated)
**Deployment model:** SaaS multi-tenant only — no on-premise
**Commodity scope:** Schema supports gas, water, electric, and sewer. Gas is the only commodity available at launch.

---

## The Problem This Solves

Legacy CIS vendors treat rate changes as professional services engagements — a billing analyst who needs to update a PGA factor waits weeks and pays for it. Their tariff engines are hardcoded, their APIs are legacy, their UX is Windows-desktop-era, and their implementation timelines run 12–24 months. The core positioning: **gas-native domain modeling** (BTU correction, PGA, WNA, cold-weather rules, relight workflows as first-class features) combined with **rate changes that billing staff can do themselves**, no vendor consultant required.

The target buyers are Utility Directors, CFOs, IT Directors, Billing Analysts, and CSR Managers at LDCs in the 500–150K meter band. The primary trade community is APGA (American Public Gas Association).

---

## Current State

Domain research is complete. Feature extraction is done. The project is now in **application planning** — hardening the data model before any application code is written.

**What exists in this repo so far:**
- `sql/tu.sql` — the schema (auto-generated from Supabase; 60 tables in the `public` schema)
- `postgres/` — Docker setup for local schema iteration (Postgres 16, schema loads on container start)
- `application/database/schema.sql` — human-readable DDL dump of all 60 tables, reconstructed for reference
- `application/APPLICATION-CONTRACTS.md` — running list of obligations the schema places on future application code (things the DB will reject or silently get wrong if the app doesn't do its part)
- `application/DECISION-LOG.md` — permanent ledger of schema decisions with rationale and failed approaches (HANDOFF.md is rewritten each session; this is not)

**What does not exist yet:** any application code.

---

## Tech Stack (Planned)

- **Database:** PostgreSQL (standalone — no Supabase)
- **Schema version:** v5.2.1 (`sql/tu.sql` header) — note: the current schema file contains Supabase artifacts (`auth.uid()`, `auth.users`) that need to be removed before the schema is production-ready

---

## Knowledge Base

All domain research, product strategy, buyer personas, feature lists, and billing domain knowledge live in the LLM wiki:

```
/Users/ryanscomputer/code/LLM-wiki/projects/TallyUtility/
```

**Start here when beginning a session on this project:**

| File | Purpose |
|---|---|
| `CONTEXT.md` | Project orientation — current phase, key decisions, changelog summary |
| `knowledge/INDEX.md` | Router for all domain knowledge — load this before loading any KB file |

**Key files for application development:**

| File | Purpose |
|---|---|
| `application/feature-list.md` | ~350+ features across 18 pipeline stages, each with priority (required/nice-to-have) and schema status (supported/partial/gap). The primary artifact for data model hardening. |
| `application/CONTEXT.md` | Session log for the 2026-05-14 planning session — scope decisions, feature extraction findings, notable schema gaps, plan going forward |
| `knowledge/06-data-model.md` | Core entity model and invariants (immutable bills, append-only ledger, bi-temporality, cancel-rebill reproducibility) |
| `knowledge/16-bi-temporality.md` | Deep architectural reference — the most consequential technical decision in the platform |
| `knowledge/07-billing-calculation.md` | Canonical billing batch flow end-to-end |
| `knowledge/13-gotchas-and-lessons.md` | Hard-won operational traps — read before any major architectural decision |

---

## Guiding Principles

These invariants apply to every design and implementation decision:

- **No hard deletes** on any financial or operational record — soft delete with marker and reason only
- **Bills are immutable** — corrections happen through cancel-rebill, never in-place edits
- **The ledger is append-only** — reversals are new transactions that offset prior ones
- **Every rate, rider, factor, and rule is date-effective** — "current value only" anywhere in the system is a bug
- **Audit trail must be subpoena-ready** — complete, reproducible, permanent; PUC investigations happen
- **Cancel-rebill uses the original period's world** — historical rates, BTU factors, WNA inputs, tax rates; not today's values
- **Gas-native first** — BTU correction, PGA, WNA, cold-weather rules, and relight workflows are first-class features
- 