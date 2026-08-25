# Roadmap

Eight phases. Each has an **exit gate** that a machine checks — not a judgement call, not
"looks done". A phase is finished when its gate is green in CI. The gates accumulate: every
later phase must keep every earlier gate passing, which is what stops phase 6 from quietly
opening an update path on a fact that phase 0 made immutable.

`PHASE` holds the current number. `make phase` prints it and its gate.

## Three things settled before phase 1, because they change what gets built

**The domain engines are written before any widget exists.** Consumption, forecasting,
validation and compliance are pure Dart, unit-tested with no device in the loop. A forecast
bug found in phase 1 costs an afternoon; the same bug found after the home screen renders it
costs a user who stops trusting the number. This is also why the coverage gate sits on
`domain/services/` and nowhere else — the UI renders what the engines decide.

**Facts are immutable from the first migration.** Readings, purchases and supply events are
append-only before there is anything to sync and before a second device exists. Retrofitting
immutability onto a schema that already permits updates is a rewrite, not a refactor — and
the dispute pack, which is the product's destination, is only credible because the record
underneath it cannot be quietly rewritten.

**Phases 0–5 are a complete, shippable product with no backend at all.** Every feature is
arithmetic over locally-held facts. Phase 6 adds a server, and only because a landlord needs
to show a statement to a tenant. That ordering is deliberate: you cannot accidentally
introduce a network dependency into a product that has no network, and the backend
investment stays conditional on the offline product proving retention first.

---

## Phase 0 — Foundation

Nothing a user sees. Only the machinery every later gate depends on.

**Deliverables**
- Flutter scaffold, Riverpod composition root, GoRouter, design tokens and theme
- Drift schema with the fact/state split, hybrid logical clock, outbox table
- Test harness, coverage reporting, documentation gate, git hooks

**Exit gate**
- `make ci` green
- `make domain-purity` passes — the domain layer imports nothing from Flutter
- The documentation gate passes

---

## Phase 1 — Capture and forecast

The wedge. A user goes from install to a depletion date without an account.

**Deliverables**
- Onboarding: meter type, DisCo, tariff band, with a band estimator for users who do not know
- Manual reading entry on the large outdoor keypad, with live validation
- `ValidationEngine`, `ConsumptionEngine`, `ForecastEngine`, `ComplianceEngine`, `LoadModelEngine`
- Prepaid depletion forecast and postpaid cost projection, both as sealed results
- Prepaid purchase recording with effective-rate divergence detection
- Reading history with evidence flags visible
- Bundled tariff table and appliance catalogue — first launch needs no network

**Exit gate**
- Domain engines at **≥ 95% line coverage** (`make coverage-gate`)
- A user reaches a depletion date from a cold install in **under 90 seconds**
- Every P0 flow completes with the device in airplane mode
- Verified on physical iOS and physical Android

---

## Phase 2 — Camera and OCR

**Deliverables**
- Capture screen: live preview, guide rect, torch, 80 dp shutter
- `TextRecogniser` implementations — ML Kit on Android, Vision on iOS
- Digit-run extraction, confidence scoring, uncertain-character marking
- Evidence photographs retained per reading, with integrity hashes

**Exit gate**
- OCR accuracy **≥ 95%** on the well-lit analogue test set
- Extraction completes in **< 1500 ms** on the reference device, or abandons to manual entry
- OCR failure never blocks: manual entry is always one tap away
- The photograph is retained whether OCR succeeded or not

---

## Phase 3 — Supply and compliance

**Deliverables**
- Platform supply-monitor façade: Kotlin foreground service, Swift `BGAppRefreshTask`
- Charging-state inference with debounce, manual override, OEM whitelisting guide
- Supply timeline with per-day and per-window coverage
- Band compliance alerts with hysteresis

**Exit gate**
- Coverage is measured and reported honestly on both platforms; no gap is interpolated
- Compliance alerting verified against synthetic supply datasets
- Alert cooldown holds — no alert fires twice inside 14 days for one meter

---

## Phase 4 — Analytics and appliances

**Deliverables**
- Custom-painted chart library, scrubbable, with interpolation visibly distinguished
- Trend, cost projection, appliance inventory, modelled load attribution, reconciliation

**Exit gate**
- Charts sustain **60 fps** scrubbing on the reference low-end Android
- Interpolated regions are visually distinct from measured points on every chart
- The load model reconciles within 25% on internal test households

---

## Phase 5 — Dispute packs

The destination. Everything before this exists to make this credible.

**Deliverables**
- PDF engine, four templates, evidence selection with recorded exclusion reasons
- Escalation ladder with elapsed-day tracking; case status

**Exit gate**
- A 12-month pack generates in **< 3000 ms**, entirely offline
- Flagged readings are either excluded or shown flagged — never silently included as clean
- The pack states its own coverage honestly
- No pack generates from fewer than 14 days of data

**v1.0 ships here.**

---

## Phase 6 — Backend and landlord console

The first phase that needs a server, and only because a second person must read what the
first person wrote.

**Deliverables**
- Auth, delta sync, statement sharing, push
- Property and unit model, batch reading, allocation engine, tenant statements

**Exit gate**
- The allocation sum invariant holds under property-based testing: allocations always sum
  to the bill total, exactly, to the naira
- A 40-unit batch reading completes fully offline
- A tenant opens a statement without installing the app

---

## Phase 7 — Telemetry and community

**Deliverables**
- BLE façade, the two most common charge controllers, battery state-of-charge history
- Generator run-hours and cost-per-kWh comparison
- Community outage map with feeder inference

**Exit gate**
- BLE degrades to manual entry on any unsupported controller
- No individual location leaves the device at finer than LGA granularity
