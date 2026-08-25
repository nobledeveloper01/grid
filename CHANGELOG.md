# Changelog

All notable changes to Grid are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Entries say *why*, not only *what*. A line that records a change without its reasoning is a
line somebody will undo in six months.

## [Unreleased]

### Added

- **The documentation pipeline.** `CLAUDE.md`, `DESIGN.md`, `PHASE`, `docs/ROADMAP.md`,
  `docs/JOURNAL.md` and eight ADRs, with `scripts/doc-check.sh` enforcing them in pre-commit
  and CI. The gate blocks on a malformed document and warns when code has changed since the
  last journal entry — the second check is the one the script exists for. Documentation that
  is only a convention decays; a convention with a gate in front of it does not.
- `make` targets that CI runs, so local and CI cannot disagree: `ci`, `gates`, `analyze`,
  `domain-purity`, `coverage-gate`, `doc-check`, `adr`, `journal`, `phase`.

## [0.1.0] — the arithmetic, and a way to feed it — 2026-08-26

Phase 1. A user goes from a cold install to a depletion date without an account, without a
network and without a server existing anywhere.

The engines came first and the screens came second, which is why the three real bugs in this
release were found by tests rather than by looking at a chart.

### Added

- **Onboarding without an account.** Meter type, DisCo, tariff band, then a payoff screen —
  no splash, no carousel, no login wall, and no permission request until the step that needs
  it. The band step offers an estimator for users who do not know theirs, and labels the
  result an estimate rather than presenting it as fact.
- **The five domain engines**, in pure Dart with no Flutter import:
  `ConsumptionEngine`, `ForecastEngine`, `ComplianceEngine`, `ValidationEngine`,
  `LoadModelEngine`. 100% line coverage; the gate is 95%.
- **Forecasts are sealed results, not nullable values.** `BalanceUnavailable` carries the
  reason and how many more readings would fix it, so a screen cannot render "your units
  finish on null" and the empty state can say something useful instead: *"Log 2 more readings
  and Grid can tell you when your units finish."*
- **Manual reading entry on a custom 64 dp keypad**, not the system keyboard. This flow runs
  outdoors, one-handed, sometimes in the dark.
- **Validation that warns rather than blocks.** Wrong-direction readings, implausible jumps,
  zero usage with power available, digit-count changes — each explains itself, offers
  remedies, and keeps the primary action enabled. Exactly one rule rejects: a reading dated
  before the previous one, because accepting it corrupts every derived figure. ADR-0007.
- **Prepaid purchase recording that computes the rate you actually paid**, and says so when
  it diverges more than 10% from the band rate. A sustained divergence is direct evidence of
  band misclassification, which is one of the four dispute templates.
- Supply logging, band-compliance scoring with 14-day alert hysteresis, and a seven-day
  supply strip.
- **Bundled tariff table and appliance catalogue.** First launch needs no network; the app
  always displays the effective date of the rates in use, and the user can override the rate.
- Drift schema with the fact/state split, hybrid logical clock stamps on every row, and an
  outbox table — all three unused today and all three cheap now, expensive to retrofit.
  ADR-0001, ADR-0003.

### Fixed

Three bugs the tests caught before any of them reached a screen.

- **Daily interpolation double-counted energy.** Each interval allocated a full day's
  consumption to *every* calendar day it touched, so a reading taken at noon each day
  inflated totals by roughly 2×. It now apportions by actual overlap, and a test asserts the
  daily figures sum back to the interval total.
- **`dailyMean` divided by bucket count rather than elapsed days**, so two half-days at the
  ends of a run counted as two full days and understated the mean by a fifth.
- **Prepaid consumption went negative when units were loaded mid-interval.** A balance rising
  from 20 to 90 kWh reads as negative usage unless the 100 kWh purchase in between is
  accounted for. It now is, and where a purchase went unrecorded the interval is clamped and
  marked estimated rather than propagating a nonsensical figure.

### Changed

- **`supplyOn` and `supplyOff` were repalletted.** They had a 1.02:1 luminance ratio — the
  classic green/red pair that disappears in greyscale and for a red-green colour-blind
  viewer, which is the commonest form and the exact pair this product would naively reach
  for. They now separate in lightness as well as hue, and a test asserts both that separation
  and 3:1 against the surface.
- **`Kwh.format()` rounds in integer space.** It used `toStringAsFixed(1)`, which rendered
  42.05 kWh as "42.0" because 42.05 is stored as 42.0499… — the exact float error the type
  exists to prevent, reintroduced at the final step. ADR-0005.

### Removed

- **The ML Kit dependency.** Its iOS pods ship no arm64 simulator slice, so depending on it
  made the app un-installable on any Apple Silicon Mac — the whole team loses iOS simulator
  development to gain one feature. OCR now sits behind a `TextRecogniser` façade, to be
  implemented per platform in phase 2: ML Kit on Android, Vision on iOS. Both are better than
  the shared package. ADR-0004.

### Infrastructure

- **iOS deployment target raised to 15.5** and **Swift Package Manager disabled** for this
  project. Mixing SPM with CocoaPods-only plugins produces `Framework 'Pods_Runner' not
  found`, which reads as a signing problem and is not one.
- CocoaPods requires `LANG=en_US.UTF-8`; without it `pod install` fails with
  `Encoding::CompatibilityError` and no mention of the locale.

[Unreleased]: https://github.com/nobledeveloper01/grid/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/nobledeveloper01/grid/releases/tag/v0.1.0
