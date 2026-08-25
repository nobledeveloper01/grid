# ADR-0004 — OCR sits behind a façade rather than a direct ML Kit dependency

**Status:** accepted
**Date:** 2026-08-26

## Context

Reading a meter by camera is the feature that makes logging take fifteen seconds instead of
ninety. The obvious implementation is `google_mlkit_text_recognition`: one package, on-device,
wraps each platform's accelerated recogniser, no model to ship.

We added it, and the first iOS build revealed the problem. **ML Kit's iOS pods ship no arm64
simulator slice.** The build succeeds, then the install fails:

```
App installation failed: "Grid" Needs to Be Updated
Failed to find matching arch for input file
```

Every current Mac is Apple Silicon. Taking a direct dependency on ML Kit therefore costs the
entire team simulator development on iOS — every UI iteration, every debugging session, every
screenshot — in exchange for one feature. Rosetta simulators are not a workable answer on
current Xcode, and "test on a physical device only" is not a workable answer for day-to-day UI
work.

The deeper problem is that this is a *cross-platform package constraining both platforms*.
Android's ML Kit is fine. iOS has a first-party alternative — the Vision framework — that is
free, on-device, faster, and has no such limitation. The shared package delivers the worse of
both.

## Decision

OCR is declared as an interface in `lib/core/platform/text_recogniser.dart`:

```dart
abstract interface class TextRecogniser {
  Future<bool> get isAvailable;
  Future<RecognisedDigits?> readDigits(String imagePath, {
    int? expectedDigitCount,
    Duration budget = const Duration(milliseconds: 1500),
  });
}
```

`NullTextRecogniser` reports itself unavailable and is what is wired in today. Phase 2 adds
ML Kit on Android and Vision via a platform channel on iOS.

The capture flow checks `isAvailable` and routes to manual entry when it is false — which it
must do anyway, because FR-2.2 forbids OCR from ever blocking. The fallback is a path the
product needs regardless; the façade just makes "no engine at all" one more case of it.

## Consequences

**What it buys.** Simulator development works. Each platform gets its better engine rather
than a shared lowest common denominator. The confidence threshold, the digit-run extraction
and the 1500 ms budget live in Dart and stay identical across both.

**What it costs.** Two native implementations instead of zero, and a platform channel to
maintain. Phase 2 is meaningfully larger than it would have been.

**What it means today.** OCR does not work. The camera path is hidden, not broken, and
manual entry carries the whole flow — which is why phase 1's exit gate is written in terms
of manual entry and says nothing about the camera.

**What a future reader should not do.** Re-adding the ML Kit Flutter package to "simplify"
this will silently break iOS simulator installs again, and the error message names an
architecture rather than a package. If you find yourself debugging `Failed to find matching
arch`, this is why.
