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

**Amber is the brand, and that is semantic before it is aesthetic.** This is a product about
electricity — current, warmth, sunlight, the moment the light comes back on. A cool corporate
blue or a clinical grey says "utility bill". Amber says "power", and it is the colour of the
thing the user is actually trying to get more of. The neutrals are warm greys throughout, so
the whole app reads as lit rather than as administrative.

| Token | Light | Dark | Use |
|---|---|---|---|
| `surface` | `#FFFFFF` | `#12100C` | Page background |
| `surfaceDim` | `#F7F5F1` | `#1D1A14` | Input fill, tracks |
| `surfaceRaised` | `#FFFFFF` | `#242019` | Cards that lift off the page |
| `outline` | `#E6E1D8` | `#332E25` | Dividers, borders |
| `outlineStrong` | `#CFC7B9` | `#4A4335` | Focused fields, selected cards |
| `textPrimary` | `#16130E` | `#F5F1EA` | Body, figures |
| `textSecondary` | `#565044` | `#B3AB9C` | Labels, captions |
| `textTertiary` | `#7D7566` | `#847C6D` | Disabled, placeholder |
| `brand` | `#F59E0B` | `#FFB020` | Fills, gradients, primary buttons |
| `brandDeep` | `#9A5B00` | `#FFC85C` | Brand colour **as text** |
| `brandSoft` | `#FFF3DC` | `#2E2211` | Selected states, tinted surfaces |
| `onBrand` | `#1A1206` | `#1A1206` | What sits on top of `brand` |
| `gradientStart` → `gradientEnd` | `#FFB020` → `#F06D1E` | `#FFB020` → `#E0601A` | The hero gradient |
| `accent` | `#1D4ED8` | `#7BA5F5` | The cool counterweight |
| `supplyOn` | `#067A4E` | `#3FCB8A` | Power available |
| `supplyOff` | `#7E1A13` | `#C4544A` | Power unavailable |
| `supplyUnknown` | `#BDB6A8` | `#3E382E` | No data |
| `warning` | `#9A5B00` | `#E8B057` | Validation warnings, anomalies |
| `danger` | `#B3261E` | `#E8695E` | Destructive, breach |
| `estimate` | `#6D4AC4` | `#A78BFA` | Modelled or interpolated values |

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
- **Amber never carries white text.** It is too light to reach 4.5:1. `onBrand` is a warm
  near-black, which is both legible and better-looking. `brandDeep` exists for the separate
  case of brand-coloured *text* on a light surface.
- The gradient appears on **exactly one card per screen**. That scarcity is what makes it
  read as "the thing you came for" rather than as decoration.

## Type

**Inter** for UI. **Roboto Mono, tabular** for meter readings and any figure in an evidence
context — a column of readings must align so the user can compare the screen against a
physical meter face.

| Style | Size / Line | Use |
|---|---|---|
| `display` | 30 / 36 | The one number that matters on a screen |
| `headline` | 22 / 28 | Screen titles |
| `title` | 17 / 23 | Section headers, card titles |
| `body` | 15 / 22 | Default |
| `bodyStrong` | 15 / 22 | Emphasis |
| `label` | 13 / 18 | Form labels, chips |
| `caption` | 12 / 16 | Metadata, timestamps, coverage notes |
| `meter` | 26 / 30 mono tabular | Meter readings |
| `figure` | 17 / 23 mono tabular | Table figures, statement arithmetic |

**The monospace face is for figures, never for words.** "Band A" set in a tabular font reads
as a wide, broken string; components that can carry either take an `isNumeric` flag.

**Both faces are bundled, not downloaded.** They are variable fonts, so every style sets
`fontVariations` on the `wght` axis — `fontWeight` alone is silently ignored on a variable
font and every weight comes out identical.

Every P0 screen survives 200% OS text scaling — no fixed-height containers around text, no
single-line constraints on labels.

## Space, shape, targets

4 dp base: `xs 4 · sm 8 · md 12 · lg 16 · xl 24 · 2xl 32 · 3xl 48`. Screen padding is `lg`
on compact, `xl` from medium up.

Radius: `sm 8` inputs and chips · `md 12` cards · `lg 20` sheets.

Elevation is used sparingly. Cards are delineated by `outline` and `surfaceDim`, not shadow —
flat surfaces render faster on low-end GPUs, which is the second reason.

**Targets.** 48 dp is the accessibility floor. Standard buttons and rows are **52 dp**
(`Targets.control`) — a full-width 64 dp button reads as a landing page, not as a tool.
**64 dp** (`Targets.outdoor`) is reserved for controls actually used at a meter: the capture
screen and the reading keypad. The capture button itself is 76 dp.

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
