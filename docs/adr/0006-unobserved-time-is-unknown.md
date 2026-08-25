# ADR-0006 — Unobserved time is `unknown`, and coverage is always reported

**Status:** accepted
**Date:** 2026-08-25

## Context

Grid's band-compliance claim — "you are on Band A, which promises 20 hours a day, and you have
been getting 11.2" — is the product's sharpest output and the one most likely to be contested.

Supply availability is inferred from device charging state, and the inference is full of
holes. iOS grants no continuous background execution. Android OEMs that dominate this market
kill background work aggressively. The phone is sometimes off, sometimes elsewhere, sometimes
flat.

The obvious handling is to interpolate: assume the state persisted between samples and draw a
continuous timeline. It produces a clean chart and a confident average.

It also fabricates evidence. An interpolated hour is not an observed hour, and a 30-day
average built mostly from interpolation is a number nobody can defend. Presenting it as
measured — inside a document whose entire purpose is to be believed — is the single most
harmful thing this product could do.

## Decision

`SupplyState` has three values, and `unknown` is first-class alongside `available` and
`unavailable`. Time not covered by a recorded event is `unknown`. It is never inferred into
either of the other two.

Everything downstream carries that through:

- `DailySupply` reports `availableMinutes`, `unavailableMinutes` and `unknownMinutes`, and a
  derived `coverage`.
- Unknown time is excluded from **both numerator and denominator** of daily supply hours.
- A day below **60% coverage** is excluded from compliance scoring and from dispute packs.
- An alert requires **70% coverage across the window** before it can fire at all.
- Every supply event records the `platform_capability` in force when it was written —
  `continuous`, `periodic` or `foregroundOnly` — because it changes. An Android user who
  whitelists the app moves from `periodic` to `continuous`, and a pack spanning that boundary
  must report coverage honestly on both sides.
- The UI renders `unknown` in `supplyUnknown`, a deliberately flat, low-salience grey.
  Missing data is normal here and must not read as an error.

## Consequences

**What it buys.** Every compliance figure is defensible. The pack states its own coverage —
"this log covers 87% of the period; gaps are shown in grey" — which is what makes the other
87% believable.

**What it costs.** Weaker claims, and sometimes no claim at all. A user with a sparse log
gets "not enough data to build a case yet" rather than a number. On iOS, where coverage is
structurally lower, that will happen more often, and the honest response is to say so and
push manual logging rather than to quietly interpolate the difference.

**What it forbids.** Any chart that draws a continuous line through a gap without marking it.
Any average that silently treats absent data as one state or the other.

**The temptation to watch for.** A stakeholder will eventually ask why the chart has holes
and whether it could "just show the trend". The holes are the product.
