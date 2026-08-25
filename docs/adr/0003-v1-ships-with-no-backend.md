# ADR-0003 — v1.0 ships with no backend at all

**Status:** accepted
**Date:** 2026-08-25

## Context

Grid's core loop is: read a meter, derive consumption, forecast, notify. Every step is
arithmetic over locally-held facts. There is no step that needs another computer.

The obvious architecture is a thin client against an API — it is what most teams reach for,
it makes multi-device sync free later, and it puts the data somewhere recoverable if a phone
is lost. All three are true.

But the users this product exists for are offline often and for long stretches, and the
moment a server exists, "just fetch it from the API" becomes the path of least resistance.
The offline promise then erodes one feature at a time, and nobody notices until a user in
Ojodu can't see their own reading history.

There is also a commercial argument. Retention for this product is unproven. A backend means
hosting, on-call, backups and a security surface, carried during the phase with zero revenue.

## Decision

v1.0 has **no backend**. Not a thin one — none.

Consumption, forecasting, cost projection, compliance scoring, load modelling, PDF
generation, notifications and the tariff table all run on the device. Six of the eight
notification types are local notifications that fire with the device permanently offline.

A backend arrives at v1.1, and only because a landlord must show a statement to a tenant —
a second person reading what the first person wrote. Even then it stores, relays and
aggregates; it computes nothing the device computes. There is deliberately no `/consumption`,
no `/forecast`, no `/allocate` endpoint, because each would make the device dependent on a
server for an answer it already has.

## Consequences

**What it buys.** The offline guarantee becomes structural rather than aspirational — you
cannot introduce a network dependency into a product with no network. Running cost is zero
during the unproven phase. And onboarding works partly *because* there is nothing to sign up
to: first value arrives in 90 seconds with no account, because there is no account.

It also makes the phase-6 investment gate real. Backend work is conditional on the
offline-only product proving D30 retention above 35%. That gate only has teeth if the
backend has not already been built.

**What it costs.** No multi-device sync, no cloud backup, no cross-device continuity in
v1.0. A lost phone is lost data. This is stated plainly in onboarding rather than glossed.

**What it demands of the client, from day one.** Three rules, so that adding the server
later is additive rather than invasive:

1. Every repository is an interface in the domain layer, implemented against Drift. The
   remote implementation arrives as a *second source behind the same interface*, so no
   presentation code changes.
2. **The outbox table exists now**, with nothing to drain to. Mutations are recorded as
   deltas with idempotency keys from the first commit.
3. **HLC stamps are written on every row now**, unused. Retrofitting causal ordering onto
   existing data is painful; writing an unused column is free.

The cost of that discipline today is close to zero. The cost of skipping it is a rewrite in
phase 6.
