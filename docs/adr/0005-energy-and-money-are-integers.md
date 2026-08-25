# ADR-0005 — Energy and money are integers, never floats

**Status:** accepted
**Date:** 2026-08-25

## Context

Grid's output is arithmetic that a user will put in front of a distribution company, and
later in front of a regulator. Every figure in a dispute pack has to survive being checked
by hand.

The obvious representation is `double` — kWh as 42.05, naira as 2500.00. It reads naturally
and every API returns it.

It is also wrong in a way that only shows up in aggregate. `0.1 + 0.2 != 0.3` in binary
floating point, and a month of interval sums drifts. Worse, the drift is invisible until
someone adds the column by hand and gets a different answer to the app — which, in a dispute,
is the moment the app stops being credible.

## Decision

Two extension types over `int`:

- `Kwh` holds **milli-kWh**. `Kwh.fromDouble(42.05).milli == 42050`.
- `Naira` holds **kobo**. `Rate` holds **kobo per kWh**.

All arithmetic happens in integer space. `double` appears only at the presentation boundary,
and only for display.

Formatting rounds in integer space too. The first version of `Kwh.format()` used
`value.toStringAsFixed(1)`, and a test caught it rendering 42.05 kWh as "42.0" — because
42.05 is stored as 42.0499…, and `toStringAsFixed` rounds the binary value, not the decimal
one. That is exactly the class of error the type exists to prevent, reintroduced at the last
step. It now divides and rounds on the integer.

## Consequences

**What it buys.** Sums are exact. A month of readings adds up the same way in the app, in the
PDF and on paper. `₦0.1 × 3` is `₦0.30`, not `₦0.30000000000000004`.

**What it costs.** Every construction and read crosses a conversion, and the unit is easy to
get wrong at the boundary — `Kwh.fromMilli(42)` and `Kwh.fromDouble(42)` differ by a factor
of a thousand and both compile. The named constructors exist to make the mistake visible at
the call site; there is deliberately no unnamed constructor.

**What it forbids.** Storing a derived figure as a float anywhere, including in JSON payloads
and in the outbox. A `REAL` column for money or energy is a bug regardless of what it is for.

**Where a float is still correct.** Ratios, coverage percentages, shares and daily rates —
figures that are inherently fractional and never summed into a total anyone will check.
`ocr_confidence` and `hours_per_day` are `REAL` for that reason.
