**Ready on source review. No blocking findings.** All round-1 blockers are structurally closed; all four hashes match.

Top should-fix: `battery-19-frozen-r2.sql:546` can pass via the old idempotency constraint without testing cross-type file uniqueness. Also add a direct assertion for `void_invoice().credit_balance`.

Docker/database tests were **read, not run**.

[Full review](tests/v5.4.2-19/review/codex-r2.md)