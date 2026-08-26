# Roadmap

Twelve phases. Each has an **exit gate** that a machine checks — not a judgement call, not
"looks done". A phase is finished when its gate is green in CI. The gates accumulate: every
later phase must keep every earlier gate passing, which is what stops phase 6 from quietly
opening an update path on a fact that phase 0 made immutable.

`PHASE` holds the current number. `make phase` prints it and its gate.

Phases 0–7 were planned before any code existed. Phase 3.5 and phases 8–10 come from
`docs/FEATURE-BACKLOG.md`, sourced once phase 3 was measuring supply and it became clear how
much was reachable from measurement already in hand. The backlog holds the reasoning; this
file holds the commitment.

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

**Carried.** The accuracy and latency gates cannot be measured on a simulator — there is no
camera — so they are open against physical hardware while later phases proceed. The two
gates that *can* be checked without a device are green: capture never blocks on OCR, and the
photograph is retained on every path. Work moved to phase 3 rather than idling, and this
line exists so that decision is visible rather than forgotten.

---

## Phase 3 — Supply and compliance

**Deliverables**
- Platform supply-monitor façade: Kotlin foreground service, Swift `BGAppRefreshTask`
- Charging-state inference with debounce, manual override, OEM whitelisting guide
- Supply timeline with per-day and per-window coverage
- Band compliance alerts with hysteresis

**Exit gate**
- Coverage is measured and reported honestly on both platforms; no gap is interpolated ✅
- Compliance alerting verified against synthetic supply datasets ✅
- Alert cooldown holds — no alert fires twice inside 14 days for one meter ✅

**Green, with the alerting scope stated.** "Alert" here means the in-app banner, which is a
status and carries no cooldown, plus a best-effort local notification which does. Nothing in
this product can reach a user who is not opening it: there is no server and neither platform
grants the background execution that would be needed. ADR-0010 sets out why, what was
rejected, and what phase 6 makes possible. The gap is real and it is left open rather than
papered over with a notification fired from an assumption.

---

## Phase 3.5 — Evidence at hand

Four features that were not in the original plan and became nearly free the moment phase 3
started measuring supply. Inserted rather than appended because each one strengthens the
record *before* the analytics in phase 4 start drawing conclusions from it, and because
F8's reading cadence is what phase 4's bill reconciliation depends on existing.

**Deliverables**
- **F1** Token vault: the STS token stored against its purchase, with load confirmation
  inferred from the next reading
- **F4** Band adherence: promised hours against measured hours, valued in naira, with
  coverage on every figure ✅
- **F5** Vendor effective-rate watch, baselined on the user's own median rather than on the
  gazetted tariff
- **F8** Cycle-anchored reading reminders ✅ — the streak that counts cycles covered is not
  built yet

**Exit gate**
- No band-adherence figure is reported for a period below the coverage floor —
  `InsufficientCoverage` is returned instead, and a test asserts it
- Token load confirmation never asserts `confirmed` without a subsequent reading that
  supports it
- Tokens are absent from every log sink and from any dispute pack the user did not opt into
- The reminder is offered once, is declinable permanently, and never fires more than once
  per cycle

---

## Phase 4 — Analytics, bills and budget

**Deliverables**
- Custom-painted chart library, scrubbable, with interpolation visibly distinguished ✅
- Trend, cost projection, appliance inventory, modelled load attribution, reconciliation ✅
- **F2** Bill capture and reconciliation: the DisCo's claimed reading against the user's own
- **F3** Estimated-bill cap check for unmetered customers
- **F7** Budget mode — the forecast reframed against the date money next arrives ✅

**Exit gate**
- Charts sustain **60 fps** scrubbing on the reference low-end Android
- Interpolated regions are visually distinct from measured points on every chart
- The load model reconciles within 25% on internal test households
- Bill reconciliation returns `Unreconcilable` rather than a divergence whenever the nearest
  reading falls outside the tolerance window — asserted by test, because manufacturing a
  divergence is the one failure this feature cannot survive
- The cap basis and every regulatory citation in user-facing copy are verified against the
  NERC order **currently in force**, with the verification date recorded in the tariff table

---

## Phase 5 — Dispute packs

The destination. Everything before this exists to make this credible.

**Deliverables**
- PDF engine, four templates, evidence selection with recorded exclusion reasons
- Escalation ladder with elapsed-day tracking; case status

**Exit gate**
- A 12-month pack generates in **< 3000 ms**, entirely offline ✅ — about 200 ms, asserted by
  `test/dispute_pack_performance_test.dart`, which prints the figure on every run so a pack
  creeping towards the limit is visible rather than silently inside it
- Flagged readings are either excluded or shown flagged — never silently included as clean ✅
- The pack states its own coverage honestly ✅
- No pack generates from fewer than 14 days of data ✅
- The escalation ladder's steps and waiting periods are verified against the customer-
  complaints procedure currently in force — **still open**, and it gates release rather than
  the phase: Grid citing a superseded procedure in a letter to a DisCo would damage the
  user's case, which is the one thing this product exists not to do

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

---

## Phase 8 — Household economics

The grid is not the whole bill. This phase makes Grid answer the question households actually
argue about — grid, generator or solar — using that household's own measured data rather than
a vendor's assumption.

**Deliverables**
- **F9** Fuel purchases and generator run-log, with a naira-per-kWh for generated power set
  beside the grid rate
- **F10** Solar and battery sizing derived from measured consumption and the *longest*
  measured outage, with payback computed against logged generator spend
- **F12** Appliance coach: ranked attribution in naira, with a what-if on run-time

**Exit gate**
- Every figure derived from the load model renders in the `estimate` treatment — dashed,
  tinted, labelled — with a widget test asserting it, since this is the phase where a
  modelled number is most likely to be mistaken for a measured one
- The sizing output states what it does not know, in the same view as the recommendation
- Generator run-time is never inferred from charging state on a household with mains supply
- Payback refuses to compute from fewer than 60 days of logged fuel spend

---

## Phase 9 — Many meters, many people

**Deliverables**
- **F6** Meter as a selectable entity, with a combined spend view across meters
- **F11** Compound split: an explicit, versioned split rule and a shareable per-occupant
  receipt carrying the meter photograph, the period, the rule and the share
- **F13** Encrypted backup and restore to any platform file destination, with a versioned
  archive format

**Exit gate**
- The allocation sum invariant holds under property-based testing — shares always sum to the
  period total, exactly, to the naira. This is phase 6's gate, brought forward and proven
  offline; phase 6 inherits the engine rather than reimplementing it
- A receipt regenerated from a past period reproduces the rule in force at the time, not the
  current one
- Restore verifies every integrity hash and reports what failed rather than importing it
- An archive written by the earliest released format version still restores

---

## Phase 10 — Reach

**Deliverables**
- **F14** Home-screen widget on both platforms; Live Activity on iOS during an outage
- **F15** Nigerian Pidgin, Hausa, Yoruba and Igbo, translated by a person, plus a mode where
  the figures carry the meaning and the words are support

**Exit gate**
- The capture flow completes end to end without reading a sentence — verified by a run with
  all string resources replaced by a single glyph
- Every screen renders in all five languages at 200% text scaling without truncation
- The widget reads from shared storage and never blocks on the app process being alive
- Regulatory and tariff terminology is reviewed by a native speaker per language, not
  machine-translated
