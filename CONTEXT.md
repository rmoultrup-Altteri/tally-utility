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

## Current State (updated 2026-09-23)

Domain research, feature extraction and application planning are done. The project is **hardening the database schema before any application code is written.** The schema is the only enforcement artifact; there is no billing engine, API or production UI yet.

**The schema.** `sql/tu.sql` is the single canonical schema: the v5.2.1 baseline plus **21 landed patches** (v5.4.0-00 → v5.4.2-11), 21,916 lines, 82 tables, plain PostgreSQL 16 (Supabase removed 2026-08-18). It is **append-only**: every change is a `sql/v5.4.x-NN-*.sql` patch, reviewed, then its body mirrored onto the end of tu.sql. What the patches delivered, in outline:
- a restricted app role (`tally_app`) with forced row-level security per tenant;
- bills that cannot be edited once issued, an append-only ledger, no hard deletes;
- two dates on every rate and rule (when it applies, when it was recorded) and a per-invoice record of the exact inputs it was calculated from, so a rebill reproduces the original;
- read and bill exception queues, account lifecycle and deposits, the Texas Pipeline Safety Fee, tax-exemption certificates;
- `public.assert_tenant_isolation_invariants()`, which every patch must now call at its end (contract AC-32).

**In flight:** `sql/v5.4.2-12-backbilling-caps.sql` (A-2, the 16 TAC §7.45 limits on backbilling) is drafted and through one review round but **not landed** — two questions with Kyle block it. The meter test history (CI-091) is specced and may land ahead of it. See `HANDOFF.md` for the live queue.

**What exists in this repo:**
- `sql/tu.sql` + the patch files — the schema; `sql/DEPLOY-VERIFICATION.md` — per-patch verification record and object counts
- `postgres/` — Docker build of tu.sql (container `tally-pg`, no host port; connect with `docker exec tally-pg psql -U tally -d tally`)
- `tests/` — per-patch test batteries and review artefacts (from -09 on; earlier batteries were lost), and the verification loop
- `application/APPLICATION-CONTRACTS.md` — 32 obligations the schema places on future application code (AC-1 … AC-32)
- `application/DECISION-LOG.md` — permanent ledger of schema decisions with rationale and failed approaches
- `application/database/schema.sql` — a **Claude-authored** reconstruction of the May 2026 tables (60 of them), not a real dump; column reference only, and stale
- `ui-concepts/` — a Next.js UI prototype, 15 screens on invented fixture data, nothing writes; parked pending Ryan's direction call
- `HANDOFF.md` (rewritten each session) and `CHANGELOG.md` (appended each session)
- `INVESTIGATION-BRIEF.md` — historical (2026-08-13), superseded

**What does not exist yet:** application code, test scenarios, a permission/role model, an identity provider, a hosting design.

---

## Tech Stack (decided 2026-06-07 — see `TECH-STACK-DISCUSSION.md`)

- **Database:** PostgreSQL 16, standalone, AWS-hosted. Shared tables with `tenant_id`; RLS reads the `app.user_id` session setting.
- **Backend:** C#/.NET modular monolith; the billing calculation core is a pure library with no I/O; data access is raw SQL via Dapper/Npgsql.
- **Frontend:** TypeScript/React against an OpenAPI-generated client.
- **Open:** the testing approach (deferred until scenarios exist), identity/auth, hosting and deployment.

---

## Knowledge Base

Domain research, planning, Kyle's rulings and the invariant register live in the sibling repo **`/Users/ryanscomputer/code/gas-billing-memory/`** (branch `main`). A wiki copy exists at `/Users/ryanscomputer/code/wiki-vault/wiki/projects/tally-utility/` but it is frozen at 2026-06-07; everything since is queued in `gas-billing-memory/application/wiki-ingestion-pending.md`.

| File (in gas-billing-memory) | Purpose |
|---|---|
| `knowledge/INDEX.md` | Router for all domain knowledge — load before any KB file |
| `application/schema-parity-plan.md` | The schema roadmap: every item and its status |
| `application/canonical-invariants.md` | The 135 rules the system must always obey (CI-001 … CI-135) |
| `application/kyle-decisions-*.md` / `kyle-questions-*.md` | Kyle's rulings, and what is still open with him |
| `application/feature-list.md` | ~500 features with priority and schema status (status is a May 2026 baseline) |
| `knowledge/06-data-model.md`, `16-bi-temporality.md`, `07-billing-calculation.md`, `13-gotchas-and-lessons.md` | Core architecture references |

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
