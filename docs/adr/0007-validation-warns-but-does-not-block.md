# ADR-0007 — Validation warns; it blocks exactly one thing

**Status:** accepted
**Date:** 2026-08-25

## Context

Meter readings arrive from a user standing outside, often at night, sometimes in the rain,
holding a phone in one hand. Bad readings are common: a dropped leading digit, a misread
decimal, a meter that was replaced, a number typed while distracted.

The obvious handling is to validate and reject — refuse a reading lower than the last one on
a cumulative meter, refuse an implausible jump. It keeps the dataset clean.

It also loses the reading, and with it the user. A refusal at a meter at night means walking
back inside without having logged anything, and the thing that made Grid worth opening —
the forecast — decays. Worse, the values most likely to be rejected are the ones that matter
most: a genuine meter replacement, a genuine anomaly, a genuine spike worth disputing. A
validator confident enough to reject is confident enough to discard evidence.

## Decision

`ValidationEngine` returns structured warnings — never exceptions, never booleans. Each
carries a message, a severity, an ordered list of remedies, and the flag to record if the
user proceeds. The presentation layer renders them without embedding a single business rule.

**Every warning has a `confirmAnyway` path**, with exactly one exception: a reading dated
before the previous one is **rejected**, because readings are append-only in time order and
accepting one out of order corrupts every derived figure downstream. That is the only
`WarningRemedy.reject` in the engine, and a test asserts nothing else blocks.

Proceeding past a warning records a flag on the reading — `anomalousHigh`,
`rolloverOrReplacement`, `digitCountMismatch` and so on. Flagged readings:

- stay **fully visible** in history, with their flag shown;
- are **excluded from baselines and trends**, so one bad entry cannot poison a forecast;
- are either excluded from a dispute pack or included with the flag visible, never silently
  passed off as clean data.

## Consequences

**What it buys.** The reading is never lost. The user is never stuck. And the dataset stays
clean anyway, because exclusion happens at the analysis layer rather than at the door — which
also means a reading initially flagged as anomalous is still there if it later turns out to
have been the important one.

**What it costs.** Every consumer of readings must respect `isClean`, and forgetting to is a
silent bug — a forecast computed over flagged readings looks plausible and is wrong. The
engines all filter, and the entity exposes `isClean` rather than making callers assemble the
condition themselves.

**What it forbids.** A "reading rejected" state anywhere in the UI, and any validation rule
that hard-fails without a remedy. Adding one is a design error, not a strictness preference.

**The wording matters as much as the rule.** A warning that reads as an accusation gets
dismissed as fast as a block does. "This is lower than your last reading. Meters count up.
Did you read it correctly?" invites a second look; "Invalid reading" does not.
