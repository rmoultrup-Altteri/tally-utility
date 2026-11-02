# Scenarios

The cases the C# core must pass, one file per family. Kyle checks the dollar figures; Ryan checks the rule; tests are built from Given / When / Then. Decided 2026-11-02 (DECISION-LOG: where scenarios live, and their shape). The source inventory behind this folder: `application/scenarios-source-inventory-2026-11-02/`.

## The shape of one scenario

```
### SCN-NNNN — <what happens, in plain words>

*Status:* draft | sent to Kyle (date) | checked by Kyle (date, file) | changed by <ruling>
*Rule:* one sentence on the rule under test. Sources: <ruling, who, date>; …

**Given**
- the facts, each with its source (a ruling, a tariff row, or "invented for this example")

**When** the one event.

**Then**
| Line | Arithmetic | Amount |      ← a worked bill, when money is involved
- refusals or records expected, in plain words

**Open:** what is not yet ruled, and for whom (Kyle, Ryan, a citation check).
```

## Conventions

- **Rules and rulings, not tables.** No column or table names in a scenario. Where a family's schema is still being built (the board's mirror queue), write against the ruling and say what the patch may still change.
- **Arithmetic** follows Kyle's 10-15 rounding: four decimals in working figures, half-up to the cent on each line. A tax line's base is the sum of the rounded lines it names.
- **A worked bill shows the bill's components**, not the stored line rows: how many rows a component becomes (for example whether the commodity rate rides on the usage line) is the build's choice. A test asserts each component's arithmetic and amount, not the row count.
- **Dates.** Every tariff record in the cast is taken as in force from Jan 1, 2025 unless a scenario says otherwise (**invented**: the source tariffs are dated 2015–2026), so scenarios in 2026 can use them.
- **Places.** The cast (`cast.md`) is invented names on real small-city tariffs, so a scenario never makes a claim about a real city's current policy. A Texas state rule appears only where it binds the utility in the scenario; a city system's policy is its own tariff row, or nothing. Where a rule is a per-jurisdiction row, the scenario says which row.
- **IDs** are `SCN-NNNN`, assigned once and never reused. The next free number is kept below.
- **Kyle's answers** are recorded on the scenario (its Status line) and, for a ruling, in the decision log and in GBM as today.

## Files

| File | Family | Scenarios |
|---|---|---|
| `cast.md` | the utilities, places and customers every scenario uses | — |
| `billing-pipeline-and-charge-composition.md` | the billing pipeline and charge composition | SCN-0001 |
| `cancel-rebill.md` | voiding and rebilling a wrong bill | SCN-0002 – 0006, 0027, 0028, 0030 |
| `deposits.md` | taking, refunding and applying deposits | SCN-0007 – 0012, 0029, 0032 |
| `backbilling.md` | how far back a correction may reach | SCN-0013 – 0019, 0031 |
| `periods-and-aging.md` | periods, the close, GL mapping, aging, write-off recovery | SCN-0020 – 0026 |

**Next free ID: SCN-0033.**
