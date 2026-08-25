# Grid — Design System

The full rationale lives in the UX specification, which is not tracked. This file carries
the parts that are load-bearing: the tokens, the rules that are easy to break by accident,
and the voice.

## Principles

**1. Evidence, not opinion.** Every number is traceable to how it was derived. Tapping any
figure reveals its inputs. A user who cannot explain a number will not defend it to a DisCo.

**2. Measured and modelled are never confused.** Measurements are solid. Estimates are
dashed, tinted `estimate`, and labelled. This is not decoration — mistaking an estimate for
a measurement is the failure mode this product most needs to prevent.

**3. The meter is outdoors, at night, in the rain.** The capture flow is the most
constrained environment in the product and it sets the floor for the whole app.

**4. Never block.** No warning is a wall. Every validation, permission denial and OCR
failure has a path forward. The user is standing at a meter; a dead end costs the reading.

**5. Value before account.** Nothing in the first session asks who the user is.

**6. Honest about gaps.** Where the app does not know, it says `unknown`. Coverage is
displayed, not hidden.

## Colour

Electricity has states, and states have colours: available, unavailable, unknown. Everything
else is neutral so those three read instantly.

| Token | Light | Dark | Use |
|---|---|---|---|
| `surface` | `#FFFFFF` | `#0E1114` | Page background |
| `surfaceDim` | `#F4F5F7` | `#181D22` | Cards, input fill |
| `surfaceInverse` | `#101418` | `#F4F5F7` | Camera scrim, tooltips |
| `outline` | `#D7DBE0` | `#2A3138` | Dividers, borders |
| `textPrimary` | `#101418` | `#EDEFF2` | Body, figures |
| `textSecondary` | `#5A626B` | `#A2AAB3` | Labels, captions |
| `textTertiary` | `#8B939C` | `#6D767F` | Disabled, placeholder |
| `accent` | `#0B7A4B` | `#3FBF83` | Primary action, brand |
| `accentSoft` | `#E4F3EB` | `#122A20` | Selected state |
| `supplyOn` | `#0B7A4B` | `#3FBF83` | Power available |
| `supplyOff` | `#7E1A13` | `#C4544A` | Power unavailable |
| `supplyUnknown` | `#B6BCC3` | `#3A424A` | No data |
| `warning` | `#B4690E` | `#E0A44A` | Validation warnings, anomalies |
| `danger` | `#C2352B` | `#E8695E` | Destructive, breach |
| `estimate` | `#7A6BC4` | `#9E90DE` | Modelled or interpolated values |

**Rules**

- Dark is authored, not a dimmed light theme. Users read meters at night.
- Every state carries an icon and a label. **Colour is never the sole carrier of meaning.**
- `supplyUnknown` is deliberately low-salience. Missing data is normal and must not read as
  an error.
- **`supplyOn` and `supplyOff` are offset in lightness, not only in hue.** Green and red at
  matching luminance are indistinguishable in greyscale and to a red-green colour-blind
  viewer — the commonest form, and the exact pair this product would naively reach for. A
  test in `test/widget_test.dart` asserts the separation, and a second asserts each state
  clears 3:1 against its surface.
- All body text meets 4.5:1 in both themes. Asserted in CI, not assumed.

## Type

**Inter** for UI. **Roboto Mono, tabular** for meter readings and any figure in an evidence
context — a column of readings must align so the user can compare the screen against a
physical meter face.

| Style | Size / Line | Use |
|---|---|---|
| `display` | 40 / 44 | The one number that matters on a screen |
| `headline` | 28 / 34 | Screen titles |
| `title` | 20 / 26 | Section headers, card titles |
| `body` | 16 / 24 | Default |
| `bodyStrong` | 16 / 24 | Emphasis |
| `label` | 14 / 20 | Form labels, chips |
| `caption` | 12 / 16 | Metadata, timestamps, coverage notes |
| `meter` | 32 / 36 mono tabular | Meter readings |
| `figure` | 20 / 26 mono tabular | Table figures, statement arithmetic |

Minimum body size is 16 sp. Every P0 screen survives 200% OS text scaling — no fixed-height
containers around text, no single-line constraints on labels.

## Space, shape, targets

4 dp base: `xs 4 · sm 8 · md 12 · lg 16 · xl 24 · 2xl 32 · 3xl 48`. Screen padding is `lg`
on compact, `xl` from medium up.

Radius: `sm 8` inputs and chips · `md 12` cards · `lg 20` sheets.

Elevation is used sparingly. Cards are delineated by `outline` and `surfaceDim`, not shadow —
flat surfaces render faster on low-end GPUs, which is the second reason.

**Targets: 48 dp minimum. 64 dp on the capture screen and any control used outdoors. The
capture button is 80 dp.**

## Breakpoints

```
compact < 600dp   |   medium 600–1023dp   |   expanded ≥ 1024dp
```

Layout is driven by **available width only, never by `Platform.isIOS`**. A foldable gets the
tablet layout when unfolded, which is correct.

## Platform look and feel

One custom design language on **both** platforms — not Material on Android and Cupertino on
iOS. The surfaces are mostly custom-painted anyway, and maintaining two visual systems
doubles design and QA cost for no user benefit in this category.

Platform *conventions* are respected where they carry real user expectation: back-swipe on
iOS, system back on Android, platform share sheets, platform date pickers, platform haptics.

## Motion

Fast and functional. Animation costs frames on the reference device.

| Transition | Duration | Curve |
|---|---|---|
| Page push | 220 ms | `easeOutCubic` |
| Sheet present | 260 ms | `easeOutCubic` |
| Value change | 400 ms | `easeOutQuart` |
| Chart data change | 300 ms | `easeInOutCubic` |
| Capture shutter | 120 ms | `easeOut` |

One exception: the first-value screen after onboarding animates over 600 ms. That moment is
the product's promise and it earns the time.

All motion respects the OS reduce-motion setting.

## Voice

Plain, direct, specific. Never cheerful about bad news, never technical about simple things.

| Instead of | Write |
|---|---|
| "Insufficient data for forecast" | "Log two more readings and we can tell you when your units finish" |
| "Error: OCR confidence below threshold" | "Couldn't read that clearly. Check the digits below" |
| "Anomaly detected in consumption" | "You used about twice your usual yesterday. Anything new plugged in?" |
| "Band A SLA breach" | "You're on Band A, which promises 20 hours a day. You've been getting 11.2" |
| "Sync failed" | *(nothing — queue it silently)* |

Currency is `₦` with thousands separators, no kobo. Energy is `kWh` to one decimal. Dates
are spelled out with the weekday — "finishes Thursday 14th" lands, "14/08" does not.
