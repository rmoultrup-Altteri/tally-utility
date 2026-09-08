# Author probes during round 1 (patch frozen at bb7cdbd9…; nothing edited)

## A-1 (MEDIUM, operational): the run-row FOR SHARE blocks every UPDATE of the run row
`validate_calculation_snapshot()` holds `billing_runs` FOR SHARE for the writer's transaction. FOR SHARE conflicts
with FOR NO KEY UPDATE, i.e. with EVERY plain UPDATE of that row — heartbeats (`last_heartbeat_at`), status, totals —
not just the election change the handshake is for. Live probe (`races/heartbeat-block-r1.out`): a heartbeat waited
~2.5 s behind a 4 s snapshot transaction. In a run that wraps many invoices in one transaction, liveness monitoring
would stall for the run's duration.

**Fix, prototyped on s10d (`races/proto-keyshare-locks.sql`, results in `races/heartbeat-and-race-proto.out`):**
writers take FOR KEY SHARE on the run row and the target row (conflicts only with FOR UPDATE / DELETE / key
changes); the two election guards escalate their own row to FOR UPDATE before the EXISTS check, so an election
change still waits behind in-flight snapshot writers and then sees them. Heartbeat: 2 ms while a writer held.
Election race: waited until the writer committed, then refused. Battery 39 green on the prototype.
Fold into revision 2.

## A-2 (held): no SECURITY DEFINER function writes invoices or billing_runs
`pg_proc` scan on s10c: none of the 13 definer functions inserts invoices / billing_runs or touches started_at,
so `tally_app` cannot reach the superuser exemption on the clock stamps through a callable. Holds.

## A-3 (candidate, not yet decided): should a correction's replaced invoice be required to be `void`?
The binding accepts any `replaces_invoice_id` with a target row. `void_invoice()` is the only route to `void`
(A-4), and a correction of a non-void bill is a double-bill. `get_correction_rate_date` does not check it either.
Cheap tooth; decide after the reviewers report whether they reach a repro through it.

## Round-1 fold → revision 2 (`9160f8af…`, 778 lines)
Every finding above and from both reviewers folded into one body; see `review-brief-10-r2.md` for the table.
A-3 (void requirement) was decided YES — both reviewers reached repros through it.
