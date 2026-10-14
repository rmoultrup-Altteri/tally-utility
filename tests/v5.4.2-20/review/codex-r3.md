**ready — predicted from read-only static review.**

**Blocking items:** None predicted. The PUBLIC restriction matches the current grants; the pinned search path supports the CHECK comparison; grant-option strings distinguish elevated grants; temporary invoker helpers remain excluded.

**Should-fix — predicted:** `mutations-20.py:252` still filters selected failure patterns rather than every failure: an earlier `FATAL`, `PANIC`, or generic `FAIL` could be skipped before the expected failure. Broaden detection to fully support the “first failure of any kind” claim.

Runtime results were not reproduced.