# Tenant isolation and structural integrity

One utility never sees or changes another's records; shared platform data is read by every utility and changed by none; the identifiers a utility issues are unique within it; a file is imported once; a meter is billed once per run. Invariants: CI-116 (tenant isolation), CI-117 (identifiers unique per utility), CI-118 (imports not repeated), CI-119 (a meter once per billing run). Built across v5.4.0-01 (row-level security on every tenant table), v5.4.2-19 (imports; a refund names a payment of the same customer), v5.4.2-21 (only an active user passes; who may bind a login), v5.4.2-29 (the county list, mirrored 2026-11-05). The source outline: GBM `application/invariant-scenarios/tenant-isolation-and-structural-integrity.md` (16 axes; its connection-pool and privileged-role axes A4/A5 went to a deployment checklist, Kyle D15-1, 07-10, and are kept here as one smoke test, SCN-0061).

**Common to every scenario here.** Two utilities on the platform: Pecan Flat and Bluebonnet (`cast.md` §1–2), each its own tenant. Users (all **invented**): **PF-clerk**, a Pecan Flat billing clerk; **BB-clerk**, a Bluebonnet billing clerk; **BB-admin**, Bluebonnet's tenant administrator (a supervisor); **PL-admin**, a platform administrator (the platform's own staff). Each signs in through the platform's login (Cognito, Ryan 10-14), and every request acts as the user its verified login names (AC-43). No dollar figures: Kyle's check is light here; Ryan checks the rule.

---

### SCN-0060 — The same customer number in two utilities is fine; twice in one utility is refused

*Status:* draft (2026-11-05), not yet sent to Kyle. Built (CI-117, REP+PROT).
*Rule:* every identifier a utility issues (customer, premise, meter, bill, payment, charge, billing run and service order numbers, and an outside system's id when one is set) is unique within that utility, not across the platform; numbers are drawn from the utility's own counter, so two clerks working at once never get the same one. Sources: CI-117; the outline's axes A2, A6, A7, A8.

**Given** Pecan Flat's customer PF-01 has customer number **10001** (**invented**). Bluebonnet has no customer 10001.

**When**
- (a) BB-clerk creates a Bluebonnet customer numbered 10001;
- (b) BB-clerk then creates a second Bluebonnet customer numbered 10001;
- (c) (a) and (b) for each other kind of identifier: premise, meter, bill, payment, charge, billing run, service order, and an outside-system id on a meter and on a premise;
- (d) BB-clerk and a second Bluebonnet clerk each create a customer at the same moment, both taking the next number from Bluebonnet's counter;
- (e) two Bluebonnet customers carry no outside-system id; then a third is given the outside id **LEG-0042** (**invented**: the id in the city's old billing system), and a fourth is given LEG-0042 too.

**Then**
- (a) Accepted. PF-01 is untouched, and neither utility can see the other's 10001 (SCN-0061).
- (b) Refused: Bluebonnet already has customer 10001.
- (c) The same for each kind, each on its own. A test proves each, not customer numbers alone.
- (d) Both accepted, with two different numbers. The counter hands out one number at a time, so the second clerk's save waits for the first to finish. The application can also set the counter back; a number it then hands out again is refused at save by the uniqueness rule, so a rewound counter makes a save fail, never a duplicate (CI-117's residue).
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
- A request whose login names no user, or a user switched off (SCN-0062), sees no utility's rows. Shared platform data (places, the law rows, SCN-0063) stays readable to it.
- A refused attempt (a write that reached no row or was refused here, a duplicate import, SCN-0066, a double billing, SCN-0067) is not kept for the utility to see: it goes to the application's operational logs for Tally's engineers (Ryan 2026-11-07, DECISION-LOG; roadmap R-28). The database could not keep most of them anyway: a write the isolation check hides finds no row and raises nothing, and a refusal that raises undoes its own transaction. The outline's axis A16 (a rejection is only as good as its visibility) is met by operations monitoring, not by the utility's records. Tally's reading is recorded by the application (SCN-0065).

---

### SCN-0062 — A user switched off sees nothing, and only a supervisor binds a login or switches a user on or off

*Status:* draft (2026-11-05), not yet sent to Kyle. Built (v5.4.2-21 r1–r4) for (a)–(e). **(f) is written to Ryan's 2026-11-07 ruling (DECISION-LOG; roadmap R-27), not built:** today a platform administrator restores a supervisor acting as themselves; under the ruling, Tally does it in a session as the utility's Tally User (SCN-0080), and that user is not counted as the utility's supervisor. Each step names the session it runs in; where the acting session cannot see the row, the result is that nothing changes, not a refusal.
*Rule:* only an active user passes the isolation check; binding a login to a user, switching a user on or off, and demoting an administrator are a supervisor's acts (the utility's tenant administrator, or Tally acting through the utility's Tally User, SCN-0080), and a platform administrator's binding and switch are a platform administrator's; once bound, a login never changes. Sources: v5.4.2-21 (R1); AC-43 (binding); Ryan 11-07 (the Tally User).

**Given** Bluebonnet's users BB-clerk and BB-admin; **BB-clerk2 (invented)**, a second clerk, just provisioned, not yet bound to a login.

**When**
- (a) BB-admin switches BB-clerk off; BB-clerk's next request lists customers;
- (b) BB-clerk2 signs in for the first time, before any binding;
- (c) before (a), while active, BB-clerk tries to bind a second login of its own to BB-clerk2; after (a), switched off, it tries to switch itself back on;
- (d) BB-admin binds BB-clerk2's login at provisioning, then tries to change it later;
- (e) BB-admin tries to switch PL-admin off;
- (f) BB-admin switches itself off, the utility's last tenant administrator.

**Then**
- (a) Accepted; BB-clerk's request sees no utility's rows, not even its own utility's (shared platform data stays readable, SCN-0061).
- (b) The login names no user, so the session acts as nobody and sees no utility's rows; nothing can bind it from there (AC-43: the binding is written by a supervisor at provisioning).
- (c) The binding is refused with an error: not a supervisor (this is how a clerk would otherwise promote itself). Switching itself back on changes nothing: a switched-off user cannot reach any user row, its own included.
- (d) The binding is accepted; the later change is refused.
- (e) Nothing changes: PL-admin's user row belongs to Tally's own tenant, so BB-admin's session cannot reach it. (Were it reachable, the switch would be refused: only a platform administrator switches a platform administrator on or off.)
- (f) Accepted; Bluebonnet then has no supervisor of its own (its Tally User does not count, SCN-0080). On Bluebonnet's request, a Tally employee opens a session as Bluebonnet's Tally User, with a reason, and switches BB-admin back on; the change shows in Bluebonnet's history as Tally's, with the employee and the reason (SCN-0068, SCN-0080). A new utility's first supervisor is bound the same way.

---

### SCN-0063 — Shared platform data: every utility reads the Texas counties and the law rows, none can change them

*Status:* draft (2026-11-05), not yet sent to Kyle. Built: the law rows (-13, -18), places (-16) and the full county list with each county's dated time zone (v5.4.2-29, mirrored 2026-11-05); all read-only to the application.
*Rule:* some data is the platform's, not a utility's: places (counties, cities and their time zones) and the law rows (what a state's rules say). Every utility reads the same rows; no utility's user can add, change or remove one. A utility's own policy is its own tariff record, never an edit to shared data. Sources: Ryan 11-04 (every Texas county loaded once as shared place data); -18 (law rows are the platform's); memory rules "utility owns regulated values" and "a city's policy is its tariff row".

**Given** the county list and its time zones; Texas's backbilling law rows (`backbilling.md`).

**When**
- (a) PF-clerk and BB-clerk each read the time zone of their own utility's county, and of the other's;
- (b) BB-admin tries to change its county's time zone, and to add a county;
- (c) BB-admin tries to change Texas's six-month backbilling row;
- (d) PF-clerk, BB-clerk and a Gulf Plains clerk each read Texas's six-month backbilling row in force on Jun 15, 2026.

**Then**
- (a) Both read both, and get the same answers: shared data is not hidden by utility.
- (b), (c) Refused: an application user cannot write shared data. A change comes from the platform as a dated new row, never an edit (`backbilling.md`, the law rows).
- (d) The same row, the same terms, for all three. Reading it is not applying it: a Gulf Plains correction applies it (Texas law binds there); a Bluebonnet correction never does, since a city system's backbilling follows its own tariff record or the platform's default (SCN-0019; `backbilling.md`).
- Bluebonnet's wish for a different rule is recorded as its own tariff record (SCN-0019 b), which only Bluebonnet sees.

---

### SCN-0064 — A record of one utility cannot point at another utility's record

*Status:* draft (2026-11-05), not yet sent to Kyle. **Not fully built.** Where a link is checked today: a refund or a bounced-payment replacement names a payment of the same utility and customer (v5.4.2-19, CI-055); a reading or charge attached to a bill must be attached to one of the same utility (v5.4.2-20); and 86 links are already keys that include the utility. Across the schema, 273 links (counted 2026-11-05) between utility tables are single-column and not tied to the utility, and the database's own link check does not apply the isolation rule, so case (b) is accepted today (the board's rates → money note of 2026-11-04, from -28 r2). The fix (CI-116's cross-tenant link fix) runs last, alone, after both schema streams finish (the board). Ryan ruled 2026-11-05 that every link proves its utility (R-12, DECISION-LOG).
*Rule:* a link from one record to another is only ever to a record of the same utility (and, where the link means it, the same customer). A link to another utility's record is refused, whoever asks. Sources: CI-116; the board ("After both schema streams finish"); Ryan 11-05 (R-12: every link, option 1).

**Given** Pecan Flat's consolidated (summary) bill **PF-S1 (invented)**, a draft; Pecan Flat's payment **PF-P1 (invented)**; BB-clerk knows both internal ids (say, from a misdirected export).

**When** BB-clerk
- (a) records a refund on a Bluebonnet customer's account citing PF-P1;
- (b) attaches a Bluebonnet bill to PF-S1 as one of its member bills;
- (c) records a Bluebonnet meter reading against a Pecan Flat meter's id.

**Then**
- (a) Refused today: a refund must cite a payment of the same utility and customer.
- (b) and (c) Refused, under the rule. **Today both are accepted** (the gap above: a member bill's link to its summary bill and a reading's link to its meter are single-column). A test for (b) and (c) is written now and expected to fail until the fix mirrors.
- Each refusal names the link, not the other utility's record, so it reveals nothing of Pecan Flat's data (SCN-0061).

---

### SCN-0065 — A Tally employee reads across utilities, and changes a utility's records only in a recorded session

*Status:* draft (2026-11-05), not yet sent to Kyle. Reads built (the isolation check lets a platform administrator through, Q-11). **(b) is not built:** today the same check also lets an active platform administrator write any utility's rows as themselves (case b is accepted today). Ruled by Ryan 2026-11-05 and 2026-11-07 (DECISION-LOG; roadmap R-21, R-27). Not a limit on what Tally may do (Ryan 11-07: Tally's staff get as much freedom as possible): a change made as the Tally employee would stamp a utility's record with a user of another tenant, which the two-column keys refuse (SCN-0064, R-12); the same change made through a session is accepted (SCN-0068, SCN-0080).
*Rule:* Tally's own staff (platform administrators) may read every utility's records, for support, without a session. A change to a utility's records is made in an impersonation session, as the utility's Tally User (SCN-0080, Tally's permissions) or as a named user of the utility (that user's permissions) (SCN-0068), so the record names a user of the utility and the session names the employee. Sources: Ryan 11-05, 11-07; Q-11 (2026-05-29); v5.4.2-21 (only an active platform administrator).

**Given** PL-admin, active; a support request from Bluebonnet about BB-01's November bill.

**When** PL-admin, not impersonating, (a) opens BB-01 and the bill, and lists unpaid balances across utilities; (b) tries to void the bill, or to change BB-01's address; (c) is switched off by another platform administrator, then tries (a) again.

**Then**
- (a) Opened; the balances of every utility, each row showing its utility.
- (b) Refused outside a session: the change would name a Tally user on a Bluebonnet record. The refusal says to open a session as Bluebonnet's Tally User. Done in that session, with a reason, the void and the address change are accepted (SCN-0080).
- (c) Nothing: a switched-off administrator passes no check.
- (a) is recorded by the application, not the database (Ryan 2026-11-07, DECISION-LOG; roadmap R-28): an access log entry for each Bluebonnet record PL-admin opens (PL-admin, Bluebonnet, BB-01 and the bill, when), kept for a set period and shown to Bluebonnet on a screen or report; no reason is asked for a read. The cross-utility balance list is a platform report and is logged as Tally's own, not shown to each utility. **Not built** (an application requirement for the core and platform work; no schema change). A query run outside the application (an engineer at a database prompt) is not in this log; that is for production access controls (platform phase).

---

### SCN-0066 — A file is imported once: a re-sent or renamed copy is refused, and another utility may import the same file

*Status:* draft (2026-11-05), not yet sent to Kyle. Built (v5.4.2-19, CI-118, REP+PROT), except (d2): a failed import frees its file even when some of its rows were already posted, so a retry can post them twice (Opus r3); written to the rule, a test expected to fail. Two checks run side by side (Codex r3): the file's content fingerprint, freed when an import fails or is cancelled; and the import's job key, unique for every import the utility has ever run, failed ones included, and never freed. A key is the operator's own or, if none is given, made from the file name and content.
*Rule:* an import names its file, the file's content fingerprint and a job key; a utility can have only one live finished-or-running import of a given file's content, so the same content under another name, another job key or another import type is refused; and a job key is used once, ever. A preview doesn't count. An import that failed or was cancelled before finishing frees the file for a retry; a finished import's status is final. The rule is per utility. Sources: CI-118; v5.4.2-19; the outline's axes A9–A11.

**Given** Bluebonnet's bank sends a lockbox payment file, `lockbox-2026-11-16.csv` (**invented**), 42 payments.

**When**
- (a) BB-clerk previews the file, then imports it;
- (b) the bank re-sends the same file, and BB-clerk imports it again;
- (c) BB-clerk renames it `lockbox-1116-resend.csv` and imports it;
- (d) instead of (a): (d1) the import fails before posting anything (a processing error on Bluebonnet's side, **invented**; the file itself is fine), and BB-clerk imports the same file again under a new job key; (d3) BB-clerk instead retries under the failed import's job key; (d2) the import fails after 20 of the 42 payments posted, and BB-clerk imports the same file again;
- (e) the bank sends a corrected file with the same name and one payment changed, imported under a new job key (made from its content); (e2) the corrected file is imported under (a)'s job key;
- (f) Pecan Flat imports a file with exactly the same content (**invented**: say, a test file both utilities were sent).

**Then**
- (a) The preview posts nothing; the import posts 42 payments.
- (b) and (c) Refused: Bluebonnet already imported this content. Nothing posts twice.
- (d1) Accepted: a failed import frees the file. The failed job stays on record as failed, with its key.
- (d3) Refused: that job key is already used, by the failed import.
- (d2) The 20 payments already posted must not post again: that is what the rule is for. **Today the retry is accepted whole** and the 20 post twice, unless each carries the processor's transaction number (CI-055), which lockbox rows may not. How a retry posts only the remaining 22 is not ruled.
- (e2) Refused: the job key is used. (e) Accepted as a new file: its content differs. Whether the 41 unchanged payments are then duplicates is for the payment matching rules (CI-055, one receipt per processor transaction), not the file check.
- (f) Accepted: the check is per utility.

---

### SCN-0067 — A meter is billed at most once in a billing run; a re-run is a new run

*Status:* draft (2026-11-05), not yet sent to Kyle. **Built only in part** (CI-119): a meter appears once per run, and a billed outcome is refused for a meter with an open read exception or an incomplete record. **Not built:** an outcome, once written, can still be changed (b2), and a failed run can be moved back to running (c2); a second bill for the same period from an estimate or a replacement read is not caught (d2), since only the read lock stops the same read being billed twice. Those cases are written to the rule, as tests expected to fail.
*Rule:* each meter appears once in a billing run, with one outcome: billed, skipped with its reason, or errored. A run that failed partway is re-run as a new run, never by re-processing meters inside the old one. A meter's period is billed on one live bill only. Sources: CI-119; the outline's axes A12–A14; CI-112 and CI-023 (a meter with an open read exception or incomplete meter record cannot be billed).

**Given** Bluebonnet's November cycle run **BR-11 (invented)**: three meters: BB-01's (a good read), BB-02's (the read failed validation, an open exception), and a new meter whose record is incomplete (no pressure class on file, **invented**).

**When**
- (a) the run processes the three meters, and stops with an error partway through BB-01's bill;
- (b) (b1) the run tries to add BB-01's meter a second time within BR-11; (b2) BB-01's recorded outcome in BR-11 is changed from failed to billed;
- (c) (c1) BB-clerk re-runs the cycle as **BR-12**; (c2) BR-11 is moved back to running instead;
- (d) (d1) BR-12 and a stray second run both try to bill BB-01's November read; (d2) the stray run bills BB-01's November period from an estimate instead.

**Then**
- (a) One outcome per meter, in the run's own terms: BB-01's **failed in calculation** (with its error); BB-02's **skipped, pending review** (the open read exception); the new meter's **skipped as unbillable**, reason: meter record incomplete (no pressure class). Recording either skipped meter as billed is refused.
- (b1) Refused: the meter already has its outcome in BR-11. (b2) Refused under the rule: an outcome is final once written. **Accepted today.**
- (c1) BR-12 is a new run, with its own outcomes; BR-11 and its outcomes stay as they were. (c2) Refused under the rule: a failed run is re-run as a new run. **Accepted today.**
- (d1) One bill only: the read, once billed, is locked to that bill, so the other run can't bill it. (d2) Refused under the rule: the period is already on a live bill. **Accepted today.**
- While a run is in progress, a meter not yet reached shows as not yet processed, which reads differently from "skipped" (the run's status says which).

---

### SCN-0068 — A Tally employee impersonates a utility's user: the record says both who acted and as whom

*Status:* draft (2026-11-05), not yet sent to Kyle. Ruled by Ryan 2026-11-05, amended 2026-11-07 (DECISION-LOG; roadmap R-21, R-27); **not built** (no impersonation record exists; the schema owner is unassigned, board).
*Rule:* a Tally employee may impersonate a user of a utility and act on their behalf, on Tally's own decision, without the utility's permission. The database records each session (which Tally employee, which utility user, start, end, a required reason) and marks every change made in it, so the utility's history shows the change as the user's, made by the named Tally employee under that session; the utility can see every session and its changes. A session as a named user has exactly that user's permissions; a session as the utility's Tally User has the permissions Tally gives it, supervisor acts and user administration included (SCN-0080); a platform administrator cannot be impersonated. Sources: Ryan 11-05, 11-07; AC-43 (the acting user comes from the verified login); memory rule "an app-written log is not a guard".

**Given** PL-admin; Bluebonnet's BB-clerk (a clerk) and BB-admin (its supervisor); support ticket **T-5521 (invented)**: BB-clerk can't void BB-01's misread November bill (SCN-0002).

**When**
- (a) PL-admin starts a session as BB-clerk with no reason;
- (b) PL-admin starts a session as BB-clerk, reason "T-5521", voids the November bill and issues the correction, then ends the session;
- (c) within that session PL-admin tries to close Bluebonnet's October period, or to switch BB-clerk2 on;
- (d) PL-admin starts a session as Bluebonnet's Tally User, reason "T-5521: close October", and closes the period;
- (e) PL-admin tries to impersonate another platform administrator;
- (f) during (b), PL-admin opens a Pecan Flat customer;
- (g) BB-admin reviews the utility's history the next day.

**Then**
- (a) Refused: a session needs a reason.
- (b) Accepted. The void and the correction are BB-clerk's acts in every respect the rules check (Bluebonnet's tenant, a clerk's permissions, BB-clerk named as who did it), and each is marked by the database with the session: PL-admin, as BB-clerk, for T-5521, started and ended when.
- (c) Refused, as for BB-clerk: a session as BB-clerk has BB-clerk's permissions, and closing a period and switching a user on are a supervisor's acts (SCN-0020, SCN-0062). PL-admin opens a session as the Tally User instead, (d).
- (d) Accepted, recorded as the Tally User's close, by PL-admin under the session; BB-admin is not involved.
- (e) Refused.
- (f) Nothing found: the session sees only what BB-clerk sees (SCN-0061).
- (g) BB-admin sees both sessions, who opened them, their reasons, and every change made in them, beside BB-clerk's own changes and told apart from them; the close in (d) shows as Tally's (PL-admin, T-5521), not as an unnamed user's.
- Every link the session writes names a Bluebonnet user, so every link between tables can be tied to the utility (SCN-0064, R-12).

---

### SCN-0080 — Every utility has one hidden Tally User, reachable only through a recorded session

*Status:* draft (2026-11-07), not yet sent to Kyle. Ruled by Ryan 2026-11-07 (DECISION-LOG; roadmap R-27), his own proposal, with four conditions; **not built** (no Tally User, guards or session record; the schema owner is unassigned, board).
*Rule:* when a utility is set up, the database gives it exactly one Tally User: a user of that utility, so every change made through it names a user of the utility (SCN-0064). Its permissions are Tally's to set, supervisor acts and user administration included. (1) It has no login: it is reached only through an impersonation session (which Tally employee, start, end, a required reason), and every change is marked with the session (SCN-0068). (2) It is hidden from the utility's user list, never from its records. (3) The utility cannot change it, switch it off or bind a login to it; only Tally can. (4) It is not one of the utility's own staff: a rule about the utility's supervisors or a count of its users leaves it out. Sources: Ryan 11-07; R-12 (two-column keys); AC-43 (the acting user comes from the verified login).

**Given** Bluebonnet, BB-admin, PL-admin; **Gulf Plains** set up on the platform (Jan 2026, `cast.md`).

**When**
- (a) Gulf Plains is set up; then someone tries to add a second Tally User to it;
- (b) a Cognito login is bound to Bluebonnet's Tally User, and someone signs in as it without a session;
- (c) BB-admin lists Bluebonnet's users, then tries to switch the Tally User off and to change its permissions;
- (d) BB-admin, Bluebonnet's only active supervisor, switches itself off; a report counts Bluebonnet's users and its active supervisors;
- (e) PL-admin opens a session as Bluebonnet's Tally User, reason "T-5600 (invented): no supervisor", binds the login of Bluebonnet's new supervisor **BB-admin2 (invented)**, and ends the session; the report runs again;
- (f) after the session ends, a further change (switching BB-clerk2 on) is attempted under it: the same request context, and another request reusing the same database connection; then PL-admin opens a new session with a reason and makes the change;
- (g) BB-admin2 opens Bluebonnet's change history the next day.

**Then**
- (a) Gulf Plains has exactly one Tally User from the moment it exists; the second is refused.
- (b) The binding is refused: the Tally User has no login. No sign-in can act as it outside a session.
- (c) The Tally User is not in the list. The switch and the permission change are refused: only Tally changes it.
- (d) The switch is accepted, as in SCN-0062 (f): Bluebonnet has no active supervisor of its own, and the report says so (zero, not one); the user count leaves the Tally User out.
- (e) Accepted, though Bluebonnet has no supervisor: the Tally User's powers are Tally's. BB-admin2's binding names Bluebonnet's Tally User as who did it, and is marked with the session (PL-admin, T-5600). The report now counts one active supervisor.
- (f) The change under the ended session is refused, and nothing changes, from either request: an ended session authorizes nothing, and a reused connection carries no Tally User context. The change in the new session is accepted and cites the new session, not T-5600's.
- (g) The binding in (e) shows as Tally's: PL-admin, the reason, the session's start and end. Hidden from the user list, not from the history.

