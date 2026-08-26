# Working journal

What we did, what we decided, and what surprised us — newest first.

The changelog says what shipped. This says what it was like to build, which is the part
nobody remembers a month later and everybody needs. The surprises section earns its place:
it is where the hours go.

New entry: `make journal T="what this session was about"`.

---

## 2026-08-26 — Finishing the phases, and what could not be finished

**Phases 6, 7, 9 closed; 8 already was; 10 deliberately not.**

### What we built

- **F6** — a meter switcher and a four-field add sheet. Every fact was already keyed by
  meter, so the schema did not move.
- **F13** — encrypted backup and restore. JSON rather than the database file, versioned from
  the first release, PBKDF2-HMAC-SHA256 with encrypt-then-MAC built only from the crypto
  package already in the tree.
- **Phase 7** — the inverter façade and the outage-map payload, both designed around refusal
  rather than capability.
- **Phase 6's other half** — Postgres behind the existing port, one conformance suite across
  both implementations, schema embedded and self-applying.
- **F14's glance layer** — the snapshot a widget would read, and the rules about staleness.

### What we decided

- **A backup is JSON, not the SQLite file.** A database file is tied to the schema that
  wrote it; JSON costs size and buys the ability to restore an archive written two years and
  four migrations ago.
- **A wrong passphrase and a tampered archive are not distinguished.** Telling them apart
  tells an attacker which one they got right.
- **Restoring adds rather than replaces.** Running the same archive twice changes nothing,
  which is what somebody unsure whether the first attempt worked will rely on.
- **The outage payload generates its own consent copy.** A consent screen written separately
  from the payload drifts from it, and the drift is invisible until somebody audits both.
- **Phase 10 is not built, and not for lack of time.** The widget needs native extension
  targets on a machine where the Android half has never compiled. The languages need a
  translator: machine-translating "tariff band" or "estimated billing" into a document
  somebody hands a regulator would be worse than shipping English.

### What surprised us

- **`go:embed` cannot reach a parent directory**, which is obvious once you read the error
  and not before. The fix was to make `migrations/` a package of its own rather than scatter
  the SQL under whichever package happens to read it — the schema stays where somebody
  looking for the schema would look.
- **A conformance suite found nothing, and that is the result.** Nine behaviours ran
  identically against the fake and against Postgres on the first attempt. Worth noting
  precisely because the value of that suite is not the bugs it finds today; it is that every
  other test in the repository is now known to be asserting against something faithful.
- **The Postgres test almost ran against somebody else's database.** Port 55432 was already
  bound — by ComplyLayer's container, on this same machine. A `TRUNCATE statements` against
  a stranger's database is the kind of mistake that has no undo, and the only thing between
  that and here was checking what held the port before reaching for `docker rm -f`.
- **Rounding a widget's day count is a safety decision, not a formatting one.** `round()`
  would show "4 days" with 3.1 remaining. Flooring shows "3" with 3.9 — and the direction
  that understates is the one that does not send somebody to bed on units that run out
  overnight.

### Where we stopped

- 389 Dart tests, 97.8% coverage on the domain engines. Go: allocation, API and store suites
  green, the last of them twice.
- Phases 6, 7, 8 and 9 have their gates marked with what is green and what is not. Phase 10
  is documented as blocked on a translator and on native targets.
- Still open and gating release: the regulatory verification of the escalation ladder and the
  tariff table. Unchanged, and still the thing that matters most.

## 2026-08-26 — Phases 8, 9 and 6, a backend, and a README that shows the app

**Phase 3, with 8 done, 9 part-done and 6 part-done alongside it.**

### What we built

- **Phase 8 — household economics.** `GeneratorEngine` (what a generated unit costs, and the
  blend against grid), `SolarSizingEngine` (sized from measured consumption and the longest
  measured outage), and the appliance coach on top of the load model. Three Drift tables, a
  screen, and 33 tests.
- **Phase 9 (part) — F11, the compound split.** `AllocationEngine` in Dart, four rules, a
  per-occupant PDF receipt, and the exact-sum invariant under 300 randomised trials.
- **Phase 6 (core) — a Go server in `server/`.** The allocation engine mirrored, statement
  issue/list/revoke, capability links, and a tenant page that needs no account, no app and no
  JavaScript. Plus the landlord side in the phone: server settings, a send button, and a
  screen of links.
- **A README in the house style**, sixteen screenshots, and `scripts/screenshot.sh`.
- **Docker.** `--target verify` runs analyze and the full suite on a pinned Flutter. The APK
  target does not work and the reason is written into the Dockerfile.

### What we decided

- **The server splits again rather than trusting the client.** Not because the landlord is
  suspected of anything — because the server is what the tenant is shown, and arithmetic done
  somewhere else cannot be checked by the person being asked to pay it. If the shares fail to
  balance, nothing is issued at all.
- **The whole split travels with each statement**, not only the reader's own figure. A tenant
  who can see one number is being asked to trust the split; being able to check it against
  everyone else's is the point.
- **Allocation happens in whole naira.** See below — this was a decision forced by looking at
  output rather than one taken in advance.
- **Run-time is recorded by hand, not inferred.** A household with both mains and a generator
  charges its phone from whichever is on, so charging state cannot tell them apart. Guesswork
  dressed as measurement is the thing this product does not do.
- **Solar payback is absent without logged fuel spend.** Inventing a fuel bill to produce a
  payback figure is exactly the vendor behaviour the feature exists to replace.

### What surprised us

- **Exact shares that visibly did not add up.** The allocation was correct to the kobo — and
  a ₦65,098 bill split three ways by rooms rendered as ₦39,058, ₦13,019 and ₦13,019, which
  add to ₦65,096, directly beneath a line claiming they balanced. For a document whose only
  purpose is to end an argument about arithmetic, it is hard to do worse. The kobo-level
  invariant had been green in both languages the whole time; the defect lived entirely in the
  gap between *correct* and *settleable*. Nobody pays eighty kobo. **Found by looking at a
  rendered page, not by a test.**
- **The two allocation engines formatted the same amount differently.** Go truncated where
  Dart rounded. The cross-check test compared kobo, not strings, so it passed. A tenant would
  have disputed a statement against their landlord's phone over a discrepancy we created.
- **Auto-capitalisation broke a URL.** `TextCapitalization.sentences` on a generic prompt
  sheet turned `http://` into `HTTP://`, which the normaliser did not recognise as a scheme —
  producing `https://HTTP://host`. The same sheet would have capitalised an API key.
- **The same content failed to render two different ways.** Appending the issued links to the
  split screen grew a list the user was already scrolled inside, leaving them staring at
  blank space; moving them to a bottom sheet produced a sheet with zero height, so a request
  that had returned in seven milliseconds looked like a hang. Both are layout problems a full
  route does not have, which is where they ended up.
- **A Docker base image can set an ENV that silently beats your ARG.** `ARG FLUTTER_VERSION`
  resolved to the image's own 3.44.0 rather than the 3.47.1 default, so the build downloaded,
  installed and then "verified" the wrong SDK without a word. Renaming the argument fixed it.
  The version assertion caught the drift on its first run, which is the only reason it was
  noticed at all.

### Where we stopped

- 327 Dart tests, 98% coverage on the domain engines. Go: allocation and API suites green,
  including phase 6's exit gate as a test.
- Not built: phase 7 entirely (BLE and the outage map need hardware), phase 10 entirely (the
  widget needs native targets, the languages need a translator), F6 multi-meter, F13 backup,
  F1/F2/F3/F5, delta sync, and the Postgres adapter behind the store port.
- Still open and gating release: the regulatory verification of the escalation ladder and the
  tariff table.

## 2026-08-26 — Insights, dispute packs, cases, budget: the app end to end

**Phase 3, and most of 3.5, 4 and 5.**

### What we built

- **Band adherence (F4)** — measured hours against the band's promise, valued in naira over
  the energy used in the same window. Three results, all rendered, including the one that
  says there is not enough measurement to make a claim.
- **A demo dataset** behind `--dart-define=GRID_DEMO=true`: ninety days of readings, forty of
  supply, an appliance inventory and one deliberately anomalous reading. It refuses to run
  against a database that already holds a meter and is compiled out of release builds.
- **Insights** — a hand-painted, scrubbable trend chart, the appliance inventory, and
  modelled load attribution with its reconciliation against the meter shown either way.
- **Dispute packs** — four templates, a pure-Dart assembly engine, and a PDF renderer that
  adds no figures of its own. Plus the escalation ladder, case tracking with the clock
  running, and a settings screen.
- **Budget mode (F7)** and **cycle reminders (F8)**.

### What we decided

- **The trend plots reading intervals, not days.** A per-day series looked like a richer
  chart and was a worse one: readings come four to six days apart, so every daily figure is
  apportioned, the whole line rendered as estimated, and a signal that is always on stopped
  being a signal. One point per interval is what was actually measured.
- **The supply log rolls up by period length**, and a rolled-up pack names its ten worst
  observed days separately — because a monthly average hides the days a complaint is actually
  about.
- **An unobserved day is excluded from a rolled-up mean, never counted as zero hours.**
  Counting it as zero would manufacture an outage. It would also flatter the user's own case,
  which is precisely why the rule needs writing down rather than leaving to judgement.
- **A case opens when a pack is shared, not when it is previewed.** A preview is somebody
  checking their own work, and a case list full of drafts is a case list nobody trusts.
- **The in-app banner is the alert** (ADR-0010). There is no server and no background
  execution, so nothing here can reach a user who is not opening the app. Saying so was
  better than scheduling a notification that fires from an assumption.

### What surprised us

- **The same windowing bug shipped twice in one morning.** `ConsumptionEngine.series` took a
  `windowStart` and applied it only to the coverage figure, so `total` silently described the
  whole history. It produced a band-shortfall valuation three times too large, and then a
  "used in 30 days" figure that reported ninety. Neither looked wrong. They were just large,
  and a large number on a screen about overcharging is exactly the number nobody
  double-takes at. The fix had to go in the engine — clipping intervals to the window with
  straddling ones apportioned — because two call sites had already made the same mistake and
  a third would have.
- **The home screen's biggest number meant nothing at all.** `ForecastEngine.cost` projected
  only the days still to come; the card labelled it "Bill so far this month". So the largest
  figure in the app was neither what had been spent nor what the bill would be. It had been
  there since phase 1, through a design review and a QA pass, because it was plausible.
  Plausible is the property that gets a wrong number past review.
- **A twelve-month dispute pack could not be generated at all**, and twelve months is exactly
  the period a serious dispute uses. Three hundred and sixty-five daily rows sat inside a
  `pw.Column`, which cannot be split across pages, so the PDF engine added pages until it
  gave up. Raising the page limit to 200 did not help — it is not a limit problem, it is a
  layout one. Sections had to become top-level children the layout can break.
- **Today was being scored against twenty-four hours it had not had yet.** At 03:00 a
  perfectly observed morning reported 12% coverage and rendered as "No data". That is a
  cosmetic bug on the surface and a serious one underneath: it dragged the window average
  down far enough to threaten the coverage floor that decides whether a case may be stated
  at all.
- **A flagged reading could still be included as clean.** Not every flag disqualifies a
  reading, and the ones that do not were being presented as unremarkable — which is precisely
  what the phase 5 gate forbids. The test that caught it was a loop over every `ReadingFlag`
  value, written to raise coverage. Three of them failed, and the reason was a real hole in
  the product rather than a gap in the tests.
- **The naira sign kept causing trouble in a new way.** The thin space that stops its
  crossbars running into the first digit is a *breaking* space, so a wrapped line in the PDF
  printed the sign at the end of one line and the amount at the start of the next. U+202F
  kerns identically and does not break.

- **Driving the app found what the tests could not.** Two of the day's worst defects surfaced
  only from actually using it: the accessibility overflow, which is a stated definition-of-done
  item that had never been checked, and a crash on recording a case reference. The crash came
  from the most ordinary code in the whole session — create a `TextEditingController`, await a
  bottom sheet, dispose it — and the assertion it throws mentions neither text fields nor
  controllers. Both were found by opening the app and pressing things, which no amount of unit
  testing was going to substitute for.
- **The onboarding button did not do what it said.** "Log my first reading" went to the home
  screen. It had been that way since phase 1, through a design review and a QA pass, because
  the screen it lands on looks fine. The failure is only visible if you read the button and
  then watch what happens.

### Where we stopped

- 268 tests, 98% coverage on the domain engines, all gates green.
- Phase 3's exit gate is met with its scope stated (ADR-0010). Phase 2's accuracy gate is
  still carried against physical hardware. Phase 5's regulatory verification is open and
  gates release.
- Not built: F1 token vault, F5 vendor watch, F2 bill capture, F3 cap check, and the reading
  streak. The roadmap says so rather than implying otherwise.

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
