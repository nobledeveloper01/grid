# Grid

**Electricity accountability and load management for Nigerian households and landlords.**

Nigerian electricity consumers have no evidence. A DisCo sends a bill, the consumer believes it
is wrong, and there is no reading history, no outage log, and no document a regulator will
accept. So the bill gets paid, or the consumer is disconnected.

Grid is a consumer-side evidence layer. It **records** meter readings and supply availability,
**explains** them as consumption, cost and band compliance, and **assembles** the result into a
dispute pack the DisCo and the regulator will actually read.

See [`docs/00-PRODUCT-STATEMENT.md`](docs/00-PRODUCT-STATEMENT.md) for the full problem
analysis and the reasoning behind the product.

---

## Status

Phase 1 of 8 — capture and forecast. Running on device.

| Working | Not yet built |
|---|---|
| Onboarding: meter type, DisCo, tariff band | Camera capture and OCR |
| Manual reading entry with live validation | Automatic supply inference |
| Prepaid depletion forecast, postpaid cost projection | Consumption charts |
| Supply logging, band compliance, coverage reporting | Appliance inventory and load attribution |
| Prepaid purchase recording with effective-rate detection | Dispute pack generation |
| Reading history with evidence flags | Landlord console and bill allocation |

**139 tests passing. Domain engines at 100% line coverage.**

---

## Why Flutter

The core surfaces are custom-painted — consumption charts with scrubbing, a meter-face capture
overlay, a supply timeline. Flutter renders through its own engine, so the frame budget is the
same on a ₦40,000 Tecno as on an iPhone. It also reaches phone, tablet and eventually web from
one widget tree, and its offline-first story (Drift over SQLite, with reactive queries) is
exactly what a product that must work for weeks without a network needs.

## Does it need a backend?

**Not for v1.0.** Every feature in the MVP is arithmetic over locally-held facts: consumption,
forecasting, compliance scoring, PDF generation and notifications all run on the device.

A backend arrives at v1.1, and only because a landlord needs to share a statement with a tenant —
that is, because a second person must read what the first person wrote. Even then it is a sync
and sharing peer, never on the correctness path.

Shipping v1.0 serverless is a structural decision, not a shortcut: you cannot accidentally
introduce a network dependency into a product that has no network.

---

## Architecture

```
presentation   Riverpod · GoRouter · responsive shells
      │
domain         PURE DART — no Flutter imports
      │        ConsumptionEngine · ForecastEngine · ComplianceEngine
      │        ValidationEngine · LoadModelEngine
      │
data           Drift (SQLite) · outbox · hybrid logical clock
      │
platform       façades for OCR, supply monitoring, notifications
```

The domain layer has zero Flutter imports. The engines are unit-testable without a device, run
identically on both platforms, and could be lifted to a server or a web target unchanged.

**Facts vs state.** Readings, purchases and supply events are append-only immutable facts that
merge by set union — they never conflict. Meter configuration and appliance inventory are
mutable state resolved last-writer-wins on a hybrid logical clock. That split is what makes
offline sync tractable, and it is why the dispute pack is credible: a record that can be
silently rewritten is not evidence.

---

## Running it

```bash
cd app
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter run
```

Generated sources (`*.g.dart`) are not committed — run the generator after cloning and after any
change to a Drift table or Riverpod provider.

**Two environment notes, learned the hard way:**

1. **CocoaPods needs a UTF-8 locale.** `pod install` fails with an
   `Encoding::CompatibilityError` otherwise. Export `LANG=en_US.UTF-8` before building for iOS.
2. **Swift Package Manager is disabled for this project.** Mixing SPM with CocoaPods-only
   plugins produced a `Framework 'Pods_Runner' not found` link failure.

## A note on OCR

Google's ML Kit iOS pods ship **no arm64 simulator slice**, so depending on it directly makes the
app un-installable on any Apple Silicon Mac — the whole team loses simulator development to gain
one feature.

OCR therefore sits behind a `TextRecogniser` façade. The engine is chosen per platform: ML Kit on
Android, Apple's Vision framework on iOS. Both are better than the cross-platform package, and
neither can hold simulator development hostage. The capture flow already has to handle
unavailable OCR gracefully, so the fallback path is one the product needs regardless.

---

## Platforms

iOS 15.5+ and Android 8.0+ from one codebase, with a tablet layout for the landlord console.
Feature parity is a hard requirement; where a platform capability differs, there is an explicit
fallback rather than a reduced feature set.

The honest one: **iOS grants no continuous background execution**, so supply-availability
coverage is lower there and the UI says so rather than interpolating a timeline. A fabricated
timeline in a dispute pack would be actively harmful.
