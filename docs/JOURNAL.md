# Working journal

What we did, what we decided, and what surprised us — newest first.

The changelog says what shipped. This says what it was like to build, which is the part
nobody remembers a month later and everybody needs. The surprises section earns its place:
it is where the hours go.

New entry: `make journal T="what this session was about"`.

---

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
