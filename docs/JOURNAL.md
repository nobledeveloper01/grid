# Working journal

What we did, what we decided, and what surprised us — newest first.

The changelog says what shipped. This says what it was like to build, which is the part
nobody remembers a month later and everybody needs. The surprises section earns its place:
it is where the hours go.

New entry: `make journal T="what this session was about"`.

---

## 2026-08-26 — Supply inference, and fifteen features sourced

**Phase 3.**

### What we built

- `SupplyMonitor`, a platform facade over charging state, with a Kotlin `BroadcastReceiver`
  on Android and `UIDevice` battery notifications on iOS, plus a null implementation so the
  domain never has to ask whether a monitor exists.
- `SupplyInferenceEngine` — pure Dart, fifteen tests. A three-minute debounce, a forty-five
  minute staleness limit, and a rule that a period the user entered by hand is never
  overwritten by an inference.
- `SupplyInferenceController`, which samples on resume as well as on event, because neither
  platform will keep a process alive to watch a cable.
- `docs/FEATURE-BACKLOG.md`: fifteen features with the problem, the shape, the dependency and
  the cost, and five more that were considered and cut with the reason recorded. Phase 3.5
  and phases 8 through 10 in `docs/ROADMAP.md` are where they became commitments.

### What we decided

- **Both platforms report `periodic`, never `continuous`.** iOS has no background execution
  that fits this and Android will kill the process. Claiming continuous coverage would put a
  number in a dispute pack that the operating system never promised, and the capability in
  force is therefore recorded on every event so a log spanning a change reports honestly on
  both sides of it.
- **A transition closes at the moment the change was first seen, not when it was confirmed.**
  The debounce exists to reject noise, not to move the timestamp. Charging the outage three
  minutes late would have been a quiet, systematic, always-in-the-DisCo's-favour error.
- **Inference is switched off entirely for a household on an inverter**, where charging state
  no longer tracks the mains. Half a signal is worse here than none: a timeline built from it
  would be fiction that looks like measurement.
- **The phase 6 allocation invariant was pulled forward into phase 9.** The compound split
  needs the same guarantee — shares summing to the total, exactly — and can prove it offline.
  Phase 6 now inherits a tested engine rather than writing one against a server.

### What surprised us

- **Sourcing features surfaced how much phase 3 had already paid for.** Band adherence, the
  strongest evidence Grid can produce, is subtraction over data the supply timeline already
  holds. It was scoped at four days against features costing five and six. The measurement
  was the expensive part and it was already done — which is an argument for building the
  hard, unglamorous middle of a product before widening it, and one that is much easier to
  make after the fact than before.
- **Three of the five cuts were cut for the same reason**, and it was not cost. Neighbour
  cross-check, meter self-audit and roster adherence all fail because they would have Grid
  assert something it cannot actually stand behind — a fact it did not observe, a number the
  load model knows is soft, a document nobody honours. The filter that did the most work was
  not "is this valuable" but "can Grid defend this in front of somebody who disagrees".
- **In-app vending was the easiest cut and the most tempting feature.** It is the obvious
  revenue line, and it would quietly invalidate F5's effective-rate warnings, which only mean
  anything because Grid takes no margin. Writing that reason down was worth more than the
  decision itself.

### Where we stopped

- Phase 3's inference path is verified on the simulator and the tests are green at 209.
- Phase 2's accuracy gate remains carried against physical hardware; the roadmap now says so
  in the phase itself rather than only in this journal.
- Next: the supply timeline screen and band compliance alerting, which close the rest of
  phase 3's gate.

## 2026-08-26 — Splash screen, and a QA pass over every flow

**Phase 2.** 2 commits. 7 files changed, 122 insertions(+), 23 deletions(-).

### What we built

- A splash screen: gradient mark, warm bloom, wordmark, 1.2 s, with native launch screens
  painted to match so there is no white flash.
- A QA pass from a genuinely clean install over every flow, and the fixes it produced.

### What we decided

- **Dark is the default**, and the payoff screen is the one centred composition in the app —
  it is a moment rather than a working surface, and everything else stays left-aligned.
- **A splash is a standard for every app in this portfolio**, not a one-off for Grid.

### What surprised us

- **Flutter completes every `AnimationController` instantly when the platform reports
  animations disabled.** Hanging the splash's dismissal off `forward().whenComplete(...)`
  therefore tore it down before it drew a single frame — no flicker, no error, just an app
  that opened straight onto onboarding. It took three builds and a 30-second duration to
  believe it, because every instinct said "latency" rather than "the animation already
  finished". A fresh simulator has reduce-motion on, which is the only reason it was caught
  before a device. ADR-0009.
- The same class of bug as the `ColoredBox` one earlier today: correct data, no exception,
  nothing in the log, and a screen that simply is not there.

### Where we stopped

- Grid has a splash, a full design pass, a code review and a QA pass behind it. 179 tests.
- Next: phase 3, supply inference.

## 2026-08-26 — Design pass, code review, and two silent rendering bugs

**Phase 2.**

### What we built

- A visual redesign around energy amber, then a `/design-review` pass over it (4 findings,
  all fixed) and a `/review` pass over the phase 2 code (4 defects, all fixed).
- Tests for the platform recogniser façade against a mocked method channel — 14 cases
  including the time budget.

### What we decided

- **Dark is the default, not the system preference.** This app is opened at a meter,
  outdoors, after dark more often than not. Following the system setting meant most users
  would never see the version of Grid that looks like the thing it is about.
- **Amber is the brand, semantically.** Current, warmth, sunlight, the moment the light comes
  back on. A cool blue or a clinical grey says "utility bill".
- **The native side recognises text and nothing else.** Choosing which digit run is the meter
  register happens in Dart, so the judgement is testable without a device and identical on
  both platforms.

### What surprised us

- **Two rendering bugs that threw nothing and logged nothing.** The power log's day bars
  rendered at zero height for days, and looked exactly like missing data — a childless
  `ColoredBox` sizes to the smallest constraint it is given, and a `Row`'s default
  cross-axis alignment offers zero. The fix is one line; finding it took four builds,
  because every hypothesis about *data* was wrong and the data was fine the whole time.
  Adding a visible track was what finally separated "the row is not drawing" from "the row
  is drawing nothing".
- **`RichText` does not inherit `MediaQuery.textScaler`, but `Text` does.** The reading on
  the confirm screen is drawn with `RichText` so individual digits can be marked uncertain —
  which quietly made the single most important number in the app the one thing that ignored
  the user's text size.
- **Vision calls its completion handler on whatever queue performed the request.** We were
  replying to Flutter from a background thread, and `perform` can throw *after* that handler
  fires, which would reply twice and hit Flutter's fatal "reply already submitted". Neither
  shows up on a simulator with no camera.
- **A disposed `CameraController` still reports `value.isInitialized == true`.** The obvious
  lifecycle guard reads correctly and does nothing.

### Where we stopped

- Phase 2 is built and reviewed. Its accuracy gate still cannot be closed here — ≥95% on a
  well-lit analogue test set needs photographs of real meters, and the simulator has no
  camera.
- 179 tests green. Next: phase 3, supply inference via the platform channels.

## 2026-08-26 — Camera capture, on-device OCR, and the amber redesign

**Phase 2.** 1 commits. 28 files changed, 2092 insertions(+), 393 deletions(-).

### What we built

- Phase 2: the capture screen, the `TextRecogniser` façade with **Vision on iOS and ML Kit on
  Android**, `DigitExtractor` in pure Dart (19 tests), photo storage with SHA-256, and the
  confirm screen with per-character uncertainty marking.
- A full visual redesign around energy amber, with bundled variable fonts and a moderated
  type and control scale.

### What we decided

- **The native side recognises text and nothing else.** Choosing which digit run is the meter
  register happens in Dart, so the judgement — the part with the actual product thinking in
  it — is testable without a device and identical on both platforms. The native modules are
  each under 150 lines and have no opinions.
- **A reading the user retyped is a manual reading**, whatever the camera first suggested.
  Recording it as OCR would inflate the accuracy figure that phase 2's exit gate depends on.

### What surprised us

- **The naira sign reads as a strikethrough.** ₦ is an N with two full-width crossbars, and
  they run into the first digit: "₦209.60" renders as though struck out. It took four builds
  to pin down because it looked exactly like a stray `TextDecoration` — the actual cause was
  the glyph, reproducing at every size and in both Inter and the system font. A thin space
  after the symbol fixes it. For a Nigerian money app this is not cosmetic: an amount that
  looks struck out on a bill says the opposite of what it means.
- **The fonts were never shipped.** `fontFamily: 'Inter'` had been in the theme since phase 0
  and no font was ever bundled, so every screen quietly fell back to the system face. Nothing
  warns about this — the app just renders, and looks fine, and is not using your typeface.
- **`fontWeight` does nothing on a variable font.** Google Fonts publishes Inter and Roboto
  Mono only as variable files now, and Flutter renders those at their default instance unless
  `fontVariations` names the `wght` axis. Every weight came out identical and it read as a
  font-loading problem rather than an axis problem.
- **`printf '\-->\n'` fails** — `printf` reads the leading `--` as end-of-options. Second
  shell bug this week caused by prose rather than logic.

### Where we stopped

- Phase 2 is built but **its accuracy gate cannot be closed here**: ≥95% on a well-lit
  analogue test set needs photographs of real meters, and the iOS simulator has no camera.
  The graceful path is verified — no camera lands on manual entry as the primary action, with
  the photograph still retained on the paths that do capture.
- Next: run the review, design-review and QA passes over what is now on screen.

## 2026-08-26 — The documentation pipeline

**Phase 1.**

### What we built

- `CLAUDE.md`, `DESIGN.md`, `PHASE`, `docs/ROADMAP.md`, `docs/JOURNAL.md`, `CHANGELOG.md`
  and eight ADRs covering the decisions already load-bearing in the code.
- `scripts/doc-check.sh`, `scripts/new-adr.sh`, `scripts/journal.sh`,
  `scripts/coverage-report.py`, a `Makefile` whose targets are the ones CI runs, and a
  pre-commit hook.

### What we decided

- **The gate warns on a stale journal rather than blocking.** A hard block there trains
  people to reach for `--no-verify`, and a bypassed gate is worse than a noisy one. It blocks
  on a malformed document, where the fix is mechanical and obvious.
- **ADRs are written for decisions already made**, not only for new ones. Eight of them were
  reconstructed from this phase — the immutable-fact model, domain purity, the no-backend
  choice, the OCR façade. Writing them after the fact is worse than writing them before, and
  much better than not writing them.

### What surprised us

- **A shell quoting bug that a syntax check would not have caught.** `journal.sh` failed with
  `unexpected EOF while looking for matching '` — the cause was an apostrophe in the word
  "else's" inside a heredoc nested in `$( )`. Bash scans command substitution for balanced
  quotes before it understands the heredoc, so a perfectly ordinary apostrophe in prose broke
  the parser. Rewriting to build the entry in a temp file rather than in a substitution fixed
  it. Worth remembering the next time a script fails on a line that looks fine.
- **`printf '-->\n'` fails**, because `printf` reads `--` as end-of-options. It needs
  `printf '%s\n' '-->'`. Both bugs were in prose, not in logic.
- **The doc gate caught a missing `CHANGELOG.md` on its first real run** — which is the
  cheapest possible demonstration that it does something.

### Where we stopped

- The pipeline is live for Grid. The scripts are project-agnostic and should be copied into
  the other five repos as each one starts.
- Next: phase 2, the camera and OCR — ML Kit on Android and Vision on iOS, both behind the
  `TextRecogniser` façade from ADR-0004.
