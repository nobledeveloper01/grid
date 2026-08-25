# Working journal

What we did, what we decided, and what surprised us — newest first.

The changelog says what shipped. This says what it was like to build, which is the part
nobody remembers a month later and everybody needs. The surprises section earns its place:
it is where the hours go.

New entry: `make journal T="what this session was about"`.

---

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
