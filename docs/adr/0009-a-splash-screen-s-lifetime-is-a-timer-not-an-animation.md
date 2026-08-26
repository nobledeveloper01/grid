# ADR-0009 — A splash screen's lifetime is a timer, not an animation

**Status:** accepted
**Date:** 2026-08-26

## Context

Grid opens on a branded splash: the mark on the hero gradient, a warm bloom, the wordmark,
and a tagline. It runs 2.2 seconds — raised from 1.2 s, which was over before it read as
anything — and the app initialises *behind* it, so what it spends is time-to-first-tap
rather than load time. The cold-start budget is unaffected: the first real screen is already
built when the splash lifts.

The obvious implementation drives everything from one `AnimationController`:

```dart
_controller.forward().whenComplete(widget.onFinished);
```

One object owns both the visuals and the timing, the exit lands exactly when the last
element finishes, and there is no second source of truth. It is what almost every splash
tutorial shows.

It also produced a splash that never appeared. Not a flicker — no frame at all.

**When the platform reports `AccessibilityFeatures.disableAnimations`, Flutter completes
every `AnimationController` instantly.** `forward()` finishes in the same frame it starts,
`whenComplete` fires, the splash removes itself before it has drawn once. This is the
documented behaviour and it is correct: someone who has asked for less motion should not sit
through a 1.2-second animation.

What is not correct is that they lose the screen entirely. The setting says *reduce motion*,
not *skip the product*. And the failure is invisible in development — it depends on a device
accessibility setting, not on the code, so it reproduces on some machines and not others.
A fresh iOS simulator has it on, which is how this was caught at all.

## Decision

**The animation drives pixels. A `Timer` drives the lifetime.**

```dart
_exit ??= Timer(
  MediaQuery.disableAnimationsOf(context)
      ? SplashScreen.reducedTotal   // 1400ms
      : SplashScreen.total,         // 2200ms
  widget.onFinished,
);
```

The controller still runs and still drives the mark, the bloom and the wordmark. It no
longer decides when the splash ends. Under reduce-motion the composition is rendered at its
final state and held for 1400 ms — shorter, because there is nothing to watch, but not zero.

The timer is created in `didChangeDependencies`, not `initState`, because
`MediaQuery.disableAnimationsOf` needs an inherited widget; `??=` keeps it to one timer
across dependency changes, and `dispose` cancels it.

## Consequences

**What it buys.** The splash appears on every device, whatever the accessibility settings.
The reduce-motion path is a deliberate shorter experience rather than an accidental absence.
And the timing is now stated in one place as a number, which is the thing that actually
needs to be defended against the cold-start budget.

**What it costs.** Two sources of truth for duration. If the animation intervals are ever
extended past `total`, the splash will cut off mid-sequence — the curve intervals and the
timer have to be kept in agreement by hand.

**The general rule.** Anything whose *lifetime* matters — a splash, a toast, an auto-dismiss,
a minimum loading time — must not hang that lifetime off an `AnimationController`. The
platform is allowed to make animations instant, and it will, on exactly the devices whose
owners asked for it.
