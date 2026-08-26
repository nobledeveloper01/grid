# Grid

Electricity accountability and load management for Nigerian households and landlords.
Read `docs/00-PRODUCT-STATEMENT.md` for why this exists, `docs/ROADMAP.md` for what phase
the project is in and what its exit gate is, and `docs/adr/` for the decisions that are
already settled. `PHASE` holds the current phase number.

## Design system

Read `DESIGN.md` before making any visual or UI decision. Colour, type, spacing and target
sizes are defined there. Do not deviate without explicit approval.

Two rules from it are load-bearing and easy to break by accident:

- **Measured and modelled are never confused.** Measurements are solid; estimates are
  dashed, tinted with `estimate`, and labelled. A dispute pack built on a figure the user
  believed was measured is worse than no dispute pack.
- **The meter is outdoors, at night, in the rain.** The capture flow sets the floor for
  target size, contrast and one-handed reach across the whole app — 64 dp, not 48.

## The six things that are never traded

These outrank convenience, deadline and elegance. A change that weakens one is wrong
regardless of what it delivers.

1. **No update or delete path on a fact.** Readings, purchases and supply events are
   append-only. A correction writes a new row and marks the original superseded; the
   original always survives. A record that can be silently rewritten is not evidence.
2. **Unobserved time is `unknown`.** Never interpolated into whichever state is convenient,
   never hidden. Coverage is reported alongside every figure derived from it. See ADR-0006.
3. **The domain layer imports nothing from Flutter.** `make domain-purity` enforces it.
4. **Energy and money are integers.** Milli-kWh and kobo. A float in a figure that ends up
   in a dispute pack is a rounding error somebody has to defend. See ADR-0005.
5. **Validation warns; it does not block.** One exception, and only one: a reading dated
   before the previous one is rejected, because accepting it corrupts every derived figure.
   Everything else offers a way forward. See ADR-0007.
6. **No screen awaits the network.** Every read comes from Drift. There is no server yet and
   there must be no code that assumes one. See ADR-0003.

## Working on this repo

- `make ci` is the gate. `make gates` runs the blocking ones alone.
- `make setup` after cloning — generated sources (`*.g.dart`) are not committed, and the app
  will not compile without them.
- **`make gen` after touching a Drift table or a Riverpod provider.** The error you get
  otherwise names a missing generated symbol, not the table you changed.
- **Export `LANG=en_US.UTF-8` before any iOS build.** CocoaPods fails with
  `Encoding::CompatibilityError` otherwise, and the message does not mention the locale.
- **Swift Package Manager is disabled for this project.** Mixing it with CocoaPods-only
  plugins produces `Framework 'Pods_Runner' not found`, which reads as a signing problem
  and is not one.
- **`flutter run --dart-define=GRID_DEMO=true`** seeds a demo household. It is compiled out
  without the flag and refuses to run against a database that already holds a meter. Almost
  no screen can be judged against the two readings a fresh install has.
- The domain engines carry a **95% coverage gate**. They are the product; the UI renders
  what they decide.
- **`ConsumptionEngine.series` clips to the window it is given.** `total` is the window's
  total, not the history's. That is enforced there because two call sites had already made
  the opposite assumption and produced figures three times too large without anything
  looking wrong on screen.
- **A day in progress is never averaged in as a whole day**, and its unobserved remainder is
  not a gap in the record — it is a clock that has not got there yet.
- Prefer a sealed result over a nullable one wherever the UI could otherwise render a
  misleading figure. `BalanceUnavailable` exists so no screen can display "your units finish
  on null".
- ADRs live in `docs/adr/`. **Write one for any non-obvious decision, before the code that
  depends on it.** `make adr T="the decision"`.

## Documentation pipeline

Four documents move as the work moves. The gate in `scripts/doc-check.sh` runs in
pre-commit and in CI.

| Document | Answers | Updated |
|---|---|---|
| `docs/JOURNAL.md` | What did we do, and what surprised us? | Every working session — `make journal T="..."` |
| `CHANGELOG.md` | What changed for someone using this? | Every user-visible change, under `[Unreleased]` |
| `docs/adr/` | Why is it built this way? | When a non-obvious decision is made — `make adr T="..."` |
| `docs/ROADMAP.md` + `PHASE` | Where are we, and what finishes this phase? | When a phase's exit gate goes green |

The gate blocks on a malformed document and warns when code has changed since the last
journal entry. **The warning is the one that matters** — it is the difference between a
project that is documented and a project that has documentation.

## Definition of done

- [ ] Acceptance criteria met and demonstrated on a device
- [ ] Tests written; domain engines still above the 95% gate
- [ ] Works fully offline where the FRD requires it
- [ ] Verified on physical iOS **and** physical Android
- [ ] Verified on the reference low-end Android (2 GB RAM)
- [ ] Light and dark both authored
- [ ] 200% text scaling without truncation — check it, do not assume it. Seven rows across
      six screens overflowed the first time anybody actually looked
- [ ] Screen-reader labelled; colour never the sole carrier of meaning
- [ ] Every error path has a forward path — no dead ends
- [ ] No update or delete path introduced on a fact
- [ ] Copy reviewed against the voice guidelines in `DESIGN.md`
- [ ] ADR written for any non-obvious decision
- [ ] `CHANGELOG.md` updated under `[Unreleased]`
- [ ] `make ci` green
