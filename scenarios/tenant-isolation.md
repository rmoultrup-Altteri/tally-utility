# Tenant isolation and structural integrity

One utility never sees or changes another's records; shared platform data is read by every utility and changed by none; the identifiers a utility issues are unique within it; a file is imported once; a meter is billed once per run. Invariants: CI-116 (tenant isolation), CI-117 (identifiers unique per utility), CI-118 (imports not repeated), CI-119 (a meter once per billing run). Built across v5.4.0-01 (row-level security on every tenant table), v5.4.2-19 (imports; a refund names a payment of the same customer), v5.4.2-21 (only an active user passes; who may bind a login), v5.4.2-29 (the county list, in review). The source outline: GBM `application/invariant-scenarios/tenant-isolation-and-structural-integrity.md` (16 axes; its connection-pool and privileged-role axes A4/A5 went to a deployment checklist, Kyle D15-1, 07-10, and are kept here as one smoke test, SCN-0061).

**Common to every scenario here.** Two utilities on the platform: Pecan Flat and Bluebonnet (`cast.md` §1–2), each its own tenant. Users (all **invented**): **PF-clerk**, a Pecan Flat billing clerk; **BB-clerk**, a Bluebonnet billing clerk; **BB-admin**, Bluebonnet's tenant administrator (a supervisor); **PL-admin**, a platform administrator (the platform's own staff). Each signs in through the platform's login (Cognito, Ryan 10-14), and every request acts as the user its verified login names (AC-43). No dollar figures: Kyle's check is light here; Ryan checks the rule.

---

### SCN-0060 — The same customer number in two utilities is fine; twice in one utility is refused

*Status:* draft (2026-11-05), not yet sent to Kyle. Built (CI-117, REP+PROT).
*Rule:* every identifier a utility issues (customer, premise, meter, bill, payment, charge, billing run and service order numbers, and an outside system's id when one is set) is unique within that utility, not across the platform; numbers are drawn from the utility's own counter, so two clerks working at once never get the same one. Sources: CI-117; the outline's axes A2, A6, A7, A8.

**Given** Pecan Flat's customer PF-01 has customer number **10001** (**invented**). Bluebonnet has no customer 10001.

**When**
- (a) BB-clerk creates a Bluebonnet customer numbered 10001;
- (b) BB-clerk then creates a second Bluebonnet customer numbered 10001;
- (c) (a) and (b) for each other kind of identifier: premise, meter, bill, payment, charge, billing run, service order;
- (d) BB-clerk and a second Bluebonnet clerk each create a customer at the same moment, both taking the next number from Bluebonnet's counter;
- (e) two Bluebonnet customers carry no outside-system id; then a third is given the outside id **LEG-0042** (**invented**: the id in the city's old billing system), and a fourth is given LEG-0042 too.

**Then**
- (a) Accepted. PF-01 is untouched, and neither utility can see the other's 10001 (SCN-0061).
- (b) Refused: Bluebonnet already has customer 10001.
- (c) The same for each kind, each on its own. A test proves each, not customer numbers alone.
- (d) Both accepted, with two different numbers. The counter hands out one number at a time, so the second clerk's save waits for the first to finish; it never reuses a number.
- (e) The two with no outside id are both accepted (an unset id collides with nothing); the third is accepted; the fourth is refused.

---

### SCN-0061 — A clerk sees, finds and changes only their own utility's records, whatever the request asks for

*Status:* draft (2026-11-05), not yet sent to Kyle. Built for reads and for writes inside a utility (CI-116's read side; v5.4.0-01; -21's active-user rule). This is the one smoke test the outline keeps for its pooled-connection and privileged-role axes (D15-1); the rest of those axes is a deployment checklist, not a scenario.
*Rule:* every request sees only rows of its user's utility, even when it names no utility, names another utility's record directly, or would match another utility's rows; a write may only create or change rows of the user's own utility. Sources: CI-116; Q-11 (row-level security, not filters in each query, 2026-05-29); AC-43 (the user is set from the verified login, per transaction, in one place).

**Given** Bluebonnet's customer BB-01 and its November bill (`cancel-rebill.md`, the reference bill). PF-clerk is signed in.

**When** PF-clerk's session
- (a) lists every customer, with no filter at all;
- (b) searches for "BB-01" by number and by name;
- (c) opens BB-01's record and its November bill by their internal ids (say, copied from a support ticket);
- (d) tries to change BB-01's mailing address, and to void the November bill;
- (e) creates a customer and stamps it as Bluebonnet's;
- (f) runs a report of all unpaid balances;
- (g) then, on the same pooled connection, BB-clerk's next request runs.

**Then**
- (a) Only Pecan Flat's customers. (b) and (c): nothing found, exactly as for a record that does not exist, so the reply reveals nothing about Bluebonnet's data. (That the screen says "not found", not "not yours", is this stream's reading of what the app should show.)
- (d) Nothing changes: no row of Bluebonnet's is reachable to change.
- (e) Refused: a row can be created only for the user's own utility.
- (f) Only Pecan Flat's balances.
- (g) BB-clerk's request acts as BB-clerk and sees only Bluebonnet's rows, nothing left over from PF-clerk's.
- A request whose login names no user, or a user switched off (SCN-0062), sees no rows at all.

---

### SCN-0062 — A user switched off sees nothing, and only a supervisor binds a login or switches a user on or off

*Status:* draft (2026-11-05), not yet sent to Kyle. Built (v5.4.2-21 r1–r4).
*Rule:* only an active user passes the isolation check; binding a login to a user, switching a user on or off, and demoting an administrator are a supervisor's acts (the utility's tenant administrator, or a platform administrator), and a platform administrator's binding and switch are a platform administrator's; once bound, a login never changes. Sources: v5.4.2-21 (R1); AC-43 (binding).

**Given** Bluebonnet's users BB-clerk and BB-admin; **BB-clerk2 (invented)**, a second clerk, just provisioned, not yet bound to a login.

**When**
- (a) BB-admin switches BB-clerk off; BB-clerk's next request lists customers;
- (b) BB-clerk2 tries to bind its own login on first sign-in;
- (c) BB-clerk tries to switch itself back on, or to bind a second login of its own to BB-clerk2;
- (d) BB-admin binds BB-clerk2's login at provisioning, then tries to change it later;
- (e) BB-admin tries to switch PL-admin off;
- (f) BB-admin switches itself off, the utility's last tenant administrator.

**Then**
- (a) Accepted; BB-clerk's request sees nothing, not even its own utility's rows.
- (b) Refused: a new user's own sign-in cannot bind its login.
- (c) Both refused: not a supervisor. (This is how a clerk would otherwise promote itself.)
- (d) The binding is accepted; the later change is refused.
- (e) Refused: only a platform administrator switches a platform administrator on or off.
- (f) Accepted; Bluebonnet then has no supervisor until a platform administrator restores one (AC-43).

---

### SCN-0063 — Shared platform data: every utility reads the Texas counties and the law rows, none can change them

*Status:* draft (2026-11-05), not yet sent to Kyle. Built for the law rows (-13, -18) and places (-16); the full county list is v5.4.2-29 (in review, the rates stream's).
*Rule:* some data is the platform's, not a utility's: places (counties, cities and their time zones) and the law rows (what a state's rules say). Every utility reads the same rows; no utility's user can add, change or remove one. A utility's own policy is its own tariff record, never an edit to shared data. Sources: Ryan 11-04 (every Texas county loaded once as shared place data); -18 (law rows are the platform's); memory rules "utility owns regulated values" and "a city's policy is its tariff row".

**Given** the county list and its time zones; Texas's backbilling law rows (`backbilling.md`).

**When**
- (a) PF-clerk and BB-clerk each read the time zone of their own utility's county, and of the other's;
- (b) BB-admin tries to change its county's time zone, and to add a county;
- (c) BB-admin tries to change Texas's six-month backbilling row;
- (d) a correction at Gulf Plains and one at Bluebonnet both read the Texas row in force on the same date.

**Then**
- (a) Both read both, and get the same answers: shared data is not hidden by utility.
- (b), (c) Refused: an application user cannot write shared data. A change comes from the platform as a dated new row, never an edit (`backbilling.md`, the law rows).
- (d) The same row, the same terms. Whether it binds each utility is a separate question (it binds Gulf Plains; Bluebonnet is a city system, `cast.md`).
- Bluebonnet's wish for a different rule is recorded as its own tariff record (SCN-0019 b), which only Bluebonnet sees.

---

### SCN-0064 — A record of one utility cannot point at another utility's record

*Status:* draft (2026-11-05), not yet sent to Kyle. **Not fully built.** Where a link is checked today: a refund or a bounced-payment replacement names a payment of the same utility and customer (v5.4.2-19, CI-055). Across the schema, 267 links between utility tables are single-column and not tied to the utility, and the database's own link check does not apply the isolation rule, so case (b) is accepted today (the board's rates → money note of 2026-11-04, from -28 r2). The fix (CI-116's cross-tenant link fix) runs last, alone, after both schema streams finish (the board). Whether every link proves its utility, or only the ones that carry weight, is Ryan's open question R-12.
*Rule:* a link from one record to another is only ever to a record of the same utility (and, where the link means it, the same customer). A link to another utility's record is refused, whoever asks. Sources: CI-116; the board ("After both schema streams finish"); R-12 (open).

**Given** Pecan Flat's consolidated (summary) bill **PF-S1 (invented)**, a draft; Pecan Flat's payment **PF-P1 (invented)**; BB-clerk knows both internal ids (say, from a misdirected export).

**When** BB-clerk
- (a) records a refund on a Bluebonnet customer's account citing PF-P1;
- (b) attaches a Bluebonnet bill to PF-S1 as one of its member bills;
- (c) records a Bluebonnet meter reading against a Pecan Flat meter's id.

**Then**
- (a) Refused today: a refund must cite a payment of the same utility and customer.
- (b) and (c) Refused, under the rule. **Today (b) is accepted** (the gap above); (c) is the same kind of link (the decision log flagged it for readings). A test for (b) and (c) is written now and expected to fail until the fix mirrors.
- Each refusal names the link, not the other utility's record, so it reveals nothing of Pecan Flat's data (SCN-0061).
- **Open (Ryan):** R-12, whether every link between tables must prove both ends are the same utility (267 links), or only the ones that carry weight. This scenario is written to "every link".

---

### SCN-0065 — A Tally employee reads across utilities, and changes nothing without impersonating

*Status:* draft (2026-11-05), not yet sent to Kyle. Reads built (the isolation check lets a platform administrator through, Q-11). **The read-only rule is not built:** today the same check also lets an active platform administrator write any utility's rows (case b is accepted today). Ruled by Ryan 2026-11-05 (DECISION-LOG; roadmap R-21).
*Rule:* Tally's own staff (platform administrators) may read every utility's records, for support; acting as themselves, they change no utility's records. A change goes through the utility's own users, or through impersonation (SCN-0068). Sources: Ryan 11-05; Q-11 (2026-05-29); v5.4.2-21 (only an active platform administrator).

**Given** PL-admin, active; a support request from Bluebonnet about BB-01's November bill.

**When** PL-admin, not impersonating, (a) opens BB-01 and the bill, and lists unpaid balances across utilities; (b) tries to void the bill, or to change BB-01's address; (c) is switched off by another platform administrator, then tries (a) again.

**Then**
- (a) Opened; the balances of every utility, each row showing its utility.
- (b) Refused: a Tally employee acting as themselves changes nothing in a utility's records. The refusal says to impersonate a user of the utility.
- (c) Nothing: a switched-off administrator passes no check.
- **Open (Ryan):** whether a Tally employee's reading of a utility's records (not impersonating) is itself recorded for the utility to see (the outline's axis A16). Ruled for impersonation (SCN-0068), not for plain reading.

---

### SCN-0066 — A file is imported once: a re-sent or renamed copy is refused, and another utility may import the same file

*Status:* draft (2026-11-05), not yet sent to Kyle. Built (v5.4.2-19, CI-118, REP+PROT).
*Rule:* an import names its file and the file's content fingerprint; a utility can have only one live finished-or-running import of a given file's content, so the same content under another name, another job key or another import type is refused. A preview doesn't count. An import that failed or was cancelled before finishing frees the file for a retry; a finished import's status is final. The rule is per utility. Sources: CI-118; v5.4.2-19; the outline's axes A9–A11.

**Given** Bluebonnet's bank sends a lockbox payment file, `lockbox-2026-11-16.csv` (**invented**), 42 payments.

**When**
- (a) BB-clerk previews the file, then imports it;
- (b) the bank re-sends the same file, and BB-clerk imports it again;
- (c) BB-clerk renames it `lockbox-1116-resend.csv` and imports it;
- (d) the first import had failed partway (a file the bank must fix), and BB-clerk imports it again;
- (e) the bank sends a corrected file with the same name and one payment changed;
- (f) Pecan Flat imports a file with exactly the same content (**invented**: say, a test file both utilities were sent).

**Then**
- (a) The preview posts nothing; the import posts 42 payments.
- (b) and (c) Refused: Bluebonnet already imported this content. Nothing posts twice.
- (d) Accepted: a failed import frees the file. The failed job stays on record as failed.
- (e) Accepted as a new file: its content differs. Whether the 41 unchanged payments are then duplicates is for the payment matching rules (CI-055, one receipt per processor transaction), not the file check.
- (f) Accepted: the check is per utility.

---

### SCN-0067 — A meter is billed at most once in a billing run; a re-run is a new run

*Status:* draft (2026-11-05), not yet sent to Kyle. Built within a run (CI-119, REP+PROT). Across runs, a meter billed twice for one period is held off by the read lock (a read billed on one bill is locked to it), not by a rule on bills; the parity measurement did not trace that to the end, so (d) is written to the rule and may need a patch.
*Rule:* each meter appears once in a billing run, with one outcome: billed, skipped with its reason, or errored. A run that failed partway is re-run as a new run, never by re-processing meters inside the old one. A meter's period is billed on one live bill only. Sources: CI-119; the outline's axes A12–A14; CI-112 and CI-023 (a meter with an open read exception or incomplete meter record cannot be billed).

**Given** Bluebonnet's November cycle run **BR-11 (invented)**: three meters: BB-01's (a good read), BB-02's (the read failed validation, an open exception), and a new meter whose record is incomplete (no size on file, **invented**).

**When**
- (a) the run processes the three meters, and stops with an error partway through BB-01's bill;
- (b) the run tries to process BB-01's meter a second time within BR-11;
- (c) BB-clerk re-runs the cycle as **BR-12**;
- (d) BR-12 and a stray second run both try to bill BB-01's November read.

**Then**
- (a) One outcome per meter: BB-01's failed in calculation (with its error), BB-02's skipped (open read exception), the new meter's skipped (meter record incomplete). Neither skip may be recorded as billed.
- (b) Refused: the meter already has its outcome in BR-11.
- (c) BR-12 is a new run, with its own outcomes; BR-11 and its outcomes stay as they were.
- (d) One bill only: the read, once billed, is locked to that bill, so the other run can't bill it.
- While a run is in progress, a meter not yet reached shows as not yet processed, which reads differently from "skipped" (the run's status says which).

---

### SCN-0068 — A Tally employee impersonates a utility's user: the record says both who acted and as whom

*Status:* draft (2026-11-05), not yet sent to Kyle. Ruled by Ryan 2026-11-05 (DECISION-LOG; roadmap R-21); **not built** (no impersonation record exists; the schema owner is unassigned, board).
*Rule:* a Tally employee may impersonate a user of a utility and act on their behalf, on Tally's own decision, without the utility's permission. The database records each session (which Tally employee, which utility user, start, end, a required reason) and marks every change made in it, so the utility's history shows the change as the user's, made by the named Tally employee under that session; the utility can see every session and its changes. The session has exactly the impersonated user's permissions; a platform administrator cannot be impersonated; a supervisor's act needs the utility's supervisor to be the one impersonated. Sources: Ryan 11-05; AC-43 (the acting user comes from the verified login); memory rule "an app-written log is not a guard".

**Given** PL-admin; Bluebonnet's BB-clerk (a clerk) and BB-admin (its supervisor); support ticket **T-5521 (invented)**: BB-clerk can't void BB-01's misread November bill (SCN-0002).

**When**
- (a) PL-admin starts a session as BB-clerk with no reason;
- (b) PL-admin starts a session as BB-clerk, reason "T-5521", voids the November bill and issues the correction, then ends the session;
- (c) within that session PL-admin tries to close Bluebonnet's October period, or to switch BB-clerk2 on;
- (d) PL-admin starts a session as BB-admin, reason "T-5521: close October", and closes the period;
- (e) PL-admin tries to impersonate another platform administrator;
- (f) during (b), PL-admin opens a Pecan Flat customer;
- (g) BB-admin reviews the utility's history the next day.

**Then**
- (a) Refused: a session needs a reason.
- (b) Accepted. The void and the correction are BB-clerk's acts in every respect the rules check (Bluebonnet's tenant, a clerk's permissions, BB-clerk named as who did it), and each is marked by the database with the session: PL-admin, as BB-clerk, for T-5521, started and ended when.
- (c) Refused, as for BB-clerk: closing a period and switching a user on are a supervisor's acts (SCN-0020, SCN-0062).
- (d) Accepted, recorded as BB-admin's close, by PL-admin under the session.
- (e) Refused.
- (f) Nothing found: the session sees only what BB-clerk sees (SCN-0061).
- (g) BB-admin sees both sessions, who opened them, their reasons, and every change made in them, beside BB-clerk's own changes and told apart from them.
- Every link the session writes names a Bluebonnet user, so every link between tables can be tied to the utility (SCN-0064, R-12).

