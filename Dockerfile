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
# The base image is used for its **Android SDK**, not its Flutter. Upstream
# publishes no tag for every Flutter release — `3.47.1` returns
# `manifest unknown` — and its `stable` tag currently ships 3.44.0, which
# cannot resolve this project's Dart constraint at all. So the Android
# toolchain is inherited and Flutter is checked out at the exact tag the
# project is developed against.
#
# The version is then *asserted* rather than trusted, because a base image can
# move underneath a pinned checkout. The build fails loudly on drift rather
# than quietly compiling on a different SDK — which is precisely what the first
# run of this Dockerfile caught.
# `--platform=linux/amd64` is not optional on an Apple Silicon host. Flutter
# publishes no arm64 Linux SDK, so the arm64 variant of this image carries a
# Flutter that upstream builds specially — currently 3.44 — while the official
# tarball this file installs is x86_64 only. Mixing them fails at the dynamic
# linker with `rosetta error: failed to open elf`, which reads like a corrupt
# download and is not one. Pinning the platform keeps both halves x86_64 and
# lets Rosetta do its job.
FROM --platform=linux/amd64 ghcr.io/cirruslabs/flutter:stable AS base

# The base image is here for its **Android SDK**, not its Flutter. Upstream
# publishes no tag per Flutter release — `3.47.1` returns `manifest unknown` —
# and its `stable` currently ships 3.44.0, whose Dart 3.12 cannot even resolve
# this project's `^3.13.1` constraint.
#
# Checking the bundled SDK out at a tag does not work either: `flutter --version`
# keeps reporting the version its cache was built for, so the checkout appears
# to succeed and the toolchain does not move. The official tarball is
# unambiguous, so that is what is installed, and the bundled one is left where
# it is rather than half-replaced.
# Deliberately NOT named FLUTTER_VERSION. The base image sets that as an ENV,
# and an ENV beats an ARG default — so `ARG FLUTTER_VERSION=3.47.1` silently
# resolved to the image's own 3.44.0, and the build downloaded, installed and
# then "verified" the wrong SDK without a word about it.
ARG GRID_FLUTTER=3.47.1

RUN set -eux; \
    curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${GRID_FLUTTER}-stable.tar.xz" \
      | tar -xJ -C /opt; \
    git config --global --add safe.directory /opt/flutter

ENV FLUTTER_ROOT=/opt/flutter
ENV PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:$PATH

# Asserted, not trusted. A base image can move under a pinned install, and the
# first run of this file caught exactly that.
RUN set -eu; \
    have="$(flutter --version | head -1 | awk '{print $2}')"; \
    if [ "$have" != "$GRID_FLUTTER" ]; then \
      echo "TOOLCHAIN DRIFT: got Flutter $have, expected $GRID_FLUTTER" >&2; \
      exit 1; \
    fi; \
    echo "Flutter $have — as expected"; \
    flutter precache --android --no-ios --no-linux --no-windows --no-macos --no-web

# The base image sets ANDROID_SDK_ROOT but not ANDROID_HOME, and the Gradle
# plugin reads whichever it finds first — so `sdkmanager` installed platform 37
# into one root during the build and Gradle then failed to find `android-37` in
# the other. Both are set here, to the same place, and the platform is
# pre-installed rather than fetched mid-build: a 16-minute failure that ends in
# "target not found" seconds after "install complete" is a bad way to learn
# that two variables disagreed.
ENV ANDROID_HOME=$ANDROID_SDK_ROOT

# Gradle installs the platform it needs on first build. Pre-installing it with
# `sdkmanager` does not work — the bundled command-line tools cannot see
# `platforms;android-37` even after `--update`, while Gradle downloads the very
# same package without complaint. The original failure was never a missing
# platform: it was Gradle installing into one SDK root and looking in the
# other, which the ENV above fixes.

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
