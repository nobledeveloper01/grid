# Reproducible Android builds, and the CI parity that comes with them.
#
# **This image cannot build the iOS half of the app, and nothing can.** Xcode
# runs only on macOS and Apple's licence does not permit macOS in a container
# on non-Apple hardware, so there is no image that produces an `.ipa` or runs a
# simulator. iOS stays on a Mac. Saying so here is cheaper than someone
# discovering it after an afternoon of trying.
#
# What this *does* give:
#
#   * `flutter analyze` and the full test suite on a pinned toolchain, so a
#     green run here means the same thing on any machine.
#   * A debug APK without installing the Flutter SDK or the Android SDK — the
#     point of a portfolio project is that somebody can run it, and "first
#     install a 12 GB toolchain" is where that stops.
#   * The Kotlin actually compiled. The supply monitor and the text recogniser
#     were written, reviewed and shipped without ever being built, because the
#     development machine had no Android SDK. That gap closes here.
#
# The tag is `stable`, which is a *moving* tag, and a floating toolchain turns
# "the tests pass" into a statement with a shelf life. The upstream image does
# not publish a tag for every Flutter release — `3.47.1` returns
# `manifest unknown` — so the version is asserted instead of pinned: the build
# fails loudly the day the tag moves past what this project was tested against,
# rather than quietly compiling on a different SDK.
#
# Bumping is a one-line change here plus a run of the suite. Discovering the
# drift from a mystery failure three weeks later is not.
FROM ghcr.io/cirruslabs/flutter:stable AS base

ARG EXPECTED_FLUTTER=3.47
RUN set -eu; \
    have="$(flutter --version | head -1 | awk '{print $2}')"; \
    case "$have" in \
      "$EXPECTED_FLUTTER"*) echo "Flutter $have — as expected" ;; \
      *) echo "TOOLCHAIN DRIFT: image ships Flutter $have, this project was" >&2; \
         echo "tested against ${EXPECTED_FLUTTER}.x. Run the suite, then bump" >&2; \
         echo "EXPECTED_FLUTTER in the Dockerfile. Override for a one-off with" >&2; \
         echo "  --build-arg EXPECTED_FLUTTER=$have" >&2; \
         exit 1 ;; \
    esac

WORKDIR /app

# Dependencies first, and only the manifests, so a source edit does not
# re-resolve the whole package graph on every build.
COPY app/pubspec.yaml app/pubspec.lock ./
RUN flutter pub get

# Generated sources are not committed (see CLAUDE.md), so the image has to
# produce them. This is also the step that fails loudly if a Drift table or a
# Riverpod provider changed without `make gen` — which is the failure mode
# that otherwise shows up as a missing symbol nobody can place.
COPY app/ ./
RUN dart run build_runner build --delete-conflicting-outputs

# --- verification -----------------------------------------------------------
# A stage rather than a RUN in the final image: `docker build --target verify`
# is the whole CI job, and it fails the build rather than printing a warning.
FROM base AS verify
RUN flutter analyze
RUN flutter test

# --- the artefact -----------------------------------------------------------
FROM base AS apk
RUN flutter build apk --debug

# A scratch-thin final stage holding only the APK, so
# `docker build --output` drops the file on the host without a container
# needing to run at all.
FROM scratch AS artefact
COPY --from=apk /app/build/app/outputs/flutter-apk/app-debug.apk /grid-debug.apk
