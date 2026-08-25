# ADR-0008 — One custom design language on both platforms, not Material and Cupertino

**Status:** accepted
**Date:** 2026-08-25

## Context

The default advice for a cross-platform app is to look native on each platform: Material on
Android, Cupertino on iOS. Users are said to expect it, and Flutter ships both.

Grid's surfaces are mostly not standard controls. The capture screen is a camera with a
custom overlay. The consumption charts are `CustomPainter`. The supply strip and timeline are
bespoke. The numeric keypad is deliberately not the system keyboard, because it is used
one-handed outdoors at 64 dp targets. The parts that *are* standard — lists, buttons, sheets —
are a minority of the product and the least interesting part of it.

Maintaining two visual systems over that means two sets of design decisions, two golden-test
baselines and two QA passes, for a product whose identity is "a measurement instrument you
can trust".

## Decision

One custom design language on both platforms, defined in `DESIGN.md` and implemented as
`ThemeExtension`s (`GridColors`, `GridTypography`). Material widgets are used as substrate —
`InkWell`, `Scaffold`, `TextField` — but themed to the token set rather than to Material
defaults.

Platform **conventions** are respected where they carry real user expectation and cost
nothing: back-swipe on iOS, system back on Android, platform share sheets, platform date
pickers, platform haptics.

Layout is driven by **available width only**, never by `Platform.isIOS`. A foldable phone
gets the tablet layout when unfolded, which is correct, and an iPad and an Android tablet at
the same width get the same layout.

## Consequences

**What it buys.** One design decision per problem. Golden tests have one baseline, and any
divergence in golden output between iOS and Android is treated as a defect rather than as
expected. The identity is consistent — which matters for a product whose output is meant to
look like an instrument reading rather than an app screen.

**What it costs.** The app does not feel iOS-native to an iOS user, and some will notice.
The judgement is that in this category — closer to a utility meter than to a social app —
trustworthiness reads louder than platform familiarity. If usability testing contradicts
that, this decision is the one to revisit, not the tokens.

**What it forbids.** `Platform.isIOS` in any layout or styling decision. It is legitimate
only in the platform façades, where behaviour genuinely differs.

**One thing it does not excuse.** Ignoring platform *behaviour*. Back-swipe, keyboard
avoidance, safe areas, dynamic type and reduce-motion are not styling — they are how the
platform works, and the design language does not get to override them.
