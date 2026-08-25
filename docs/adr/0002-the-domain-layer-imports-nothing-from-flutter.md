# ADR-0002 — The domain layer imports nothing from Flutter

**Status:** accepted
**Date:** 2026-08-25

## Context

Grid's actual product is arithmetic: what did you use, what will it cost, when do your units
run out, is your supply below what your band promises. The screens render those answers.
If the arithmetic is wrong, no amount of UI saves it — and a user who catches Grid being
wrong once will not trust the dispute pack.

The obvious structure is the one most Flutter projects use: business logic lives in the
provider or the widget that needs it, reaching for `BuildContext`, `Theme`, `DateTime.now()`
and a repository as convenient. It works, and it makes the logic untestable without a widget
harness, unrunnable outside Flutter, and subtly different between platforms whenever a
platform-specific value leaks into a calculation.

## Decision

`lib/domain/` contains pure Dart. No `package:flutter/` import, no plugin, no I/O, no
`DateTime.now()` — the clock is injected. Entities, value objects, repository *contracts*
and the engines live there:

```
ConsumptionEngine · ForecastEngine · ComplianceEngine · ValidationEngine · LoadModelEngine
```

`make domain-purity` greps for `package:flutter/` under `lib/domain` and fails the build.
It runs in `make analyze`, in `make ci`, and in the pre-commit hook.

The engines carry a **95% line coverage gate**, and nothing else in the codebase does.

## Consequences

**What it buys.** The engines are unit-testable with no device and no widget harness — the
current suite runs in under a second. They behave identically on iOS and Android because
they are the same bytes. They could be lifted to a Dart server, a web target or a CLI
unchanged, which matters for the dispute-pack generator and for any future landlord web
console.

It also made three real bugs findable that a widget test would not have caught: daily
interpolation double-counting energy across calendar days, `dailyMean` dividing by bucket
count instead of elapsed days, and prepaid consumption going negative when a purchase fell
mid-interval. All three were caught by tests that never built a widget.

**What it costs.** Ceremony. A value the UI has — the current time, the selected meter, the
tariff rate — must be passed in rather than read where it is needed. Repository interfaces
are declared in one layer and implemented in another. For a small feature this is more files
than the alternative.

**What it forbids.** Convenience imports. `intl` for date formatting, `flutter/foundation`
for `@immutable`, a plugin for device locale — all of them are banned inside the domain
layer even though each is individually harmless. The rule is only enforceable because it has
no exceptions; the first exception makes the grep meaningless.
