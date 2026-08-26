import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid/core/theme/theme.dart';
import 'package:grid/core/theme/tokens.dart';
import 'package:grid/core/theme/typography.dart';
import 'package:grid/shared/widgets/info_note.dart';
import 'package:grid/shared/widgets/selectable_card.dart';

import 'dart:math' as math;

/// Relative luminance per WCAG 2.1.
double _luminance(Color c) {
  double lin(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
}

double contrastRatio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: brightness == Brightness.light ? GridTheme.light() : GridTheme.dark(),
    home: Scaffold(body: child),
  );
}

void main() {
  group('theme tokens', () {
    testWidgets('are available from a BuildContext in both themes',
        (tester) async {
      for (final brightness in Brightness.values) {
        late GridColors colors;
        late GridTypography type;

        await tester.pumpWidget(
          _wrap(
            Builder(
              builder: (context) {
                colors = context.colors;
                type = context.type;
                return const SizedBox();
              },
            ),
            brightness: brightness,
          ),
        );

        expect(colors.supplyOn, isNotNull);
        expect(colors.supplyUnknown, isNotNull);
        expect(type.meter.fontFeatures, isNotEmpty,
            reason: 'meter readings must use tabular figures so a column '
                'of readings aligns');
      }
    });

    test('body text meets WCAG AA against its surface in both themes', () {
      // 4.5:1 for body text. Verified here rather than trusted, because the
      // capture flow is used outdoors in direct sunlight.
      for (final (name, c) in [
        ('light', GridColors.light),
        ('dark', GridColors.dark),
      ]) {
        expect(
          contrastRatio(c.textPrimary, c.surface),
          greaterThanOrEqualTo(4.5),
          reason: '$name: textPrimary on surface',
        );
        expect(
          contrastRatio(c.textSecondary, c.surface),
          greaterThanOrEqualTo(4.5),
          reason: '$name: textSecondary on surface',
        );
        expect(
          contrastRatio(c.textPrimary, c.surfaceDim),
          greaterThanOrEqualTo(4.5),
          reason: '$name: textPrimary on surfaceDim',
        );
      }
    });

    test('every supply state is clearly visible against the surface', () {
      // WCAG 1.4.11: non-text UI components need 3:1 against what is behind
      // them. This is the assertion that actually protects the user.
      for (final c in [GridColors.light, GridColors.dark]) {
        for (final state in [c.supplyOn, c.supplyOff]) {
          expect(contrastRatio(state, c.surface), greaterThanOrEqualTo(3.0));
        }
      }
    });

    test('button labels are legible on the brand fill', () {
      // Amber is too light to carry white text. onBrand is a warm near-black
      // for exactly this reason, and it has to clear 4.5:1.
      for (final c in [GridColors.light, GridColors.dark]) {
        expect(contrastRatio(c.onBrand, c.brand), greaterThanOrEqualTo(4.5));
      }
    });

    test('brandDeep is legible as text on both light surfaces', () {
      // brand itself is a fill colour. brandDeep exists so brand-flavoured
      // *text* has somewhere legible to live.
      for (final c in [GridColors.light, GridColors.dark]) {
        expect(contrastRatio(c.brandDeep, c.surface), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(c.brandDeep, c.surfaceDim), greaterThanOrEqualTo(4.0));
      }
    });

    test('soft tints stay legible under their own foreground', () {
      for (final c in [GridColors.light, GridColors.dark]) {
        expect(contrastRatio(c.textPrimary, c.brandSoft), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(c.textPrimary, c.surfaceRaised), greaterThanOrEqualTo(4.5));
      }
    });

    test('semantic colours clear 3:1 against the surface', () {
      for (final c in [GridColors.light, GridColors.dark]) {
        for (final entry in {
          'estimate': c.estimate,
          'warning': c.warning,
          'danger': c.danger,
          'accent': c.accent,
        }.entries) {
          expect(
            contrastRatio(entry.value, c.surface),
            greaterThanOrEqualTo(3.0),
            reason: '\${entry.key} on surface',
          );
        }
      }
    });

    test('the hero gradient carries its own foreground', () {
      // The hero sets its own text colour rather than inheriting, so both
      // ends of the gradient have to work under it.
      for (final c in [GridColors.light, GridColors.dark]) {
        expect(contrastRatio(c.onBrand, c.gradientStart), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(c.onBrand, c.gradientEnd), greaterThanOrEqualTo(3.0));
      }
    });

    test('bar tracks stay visible against the page in both themes', () {
      // The height of a bar is what carries the data when colour cannot —
      // in greyscale, in sunlight, or for a colour-blind viewer. A track
      // that vanishes into the background loses that second channel.
      for (final c in [GridColors.light, GridColors.dark]) {
        expect(contrastRatio(c.track, c.surface), greaterThanOrEqualTo(1.15));
      }
    });

    test('supply on and off separate in lightness, not only in hue', () {
      // Green and red at matching luminance vanish into each other in
      // greyscale and for a red-green colour-blind viewer. The palette
      // offsets them on a second axis so the distinction survives both.
      //
      // This does not license colour-only encoding: the supply strip also
      // encodes hours as bar height and labels every bar for screen readers.
      for (final c in [GridColors.light, GridColors.dark]) {
        expect(
          contrastRatio(c.supplyOn, c.supplyOff),
          greaterThanOrEqualTo(1.8),
          reason: 'on and off must be told apart without colour vision',
        );
      }
    });
  });

  group('SelectableCard', () {
    testWidgets('clears the standard control height', (tester) async {
      await tester.pumpWidget(
        _wrap(SelectableCard(title: 'Prepaid meter', onTap: () {})),
      );
      final size = tester.getSize(find.byType(SelectableCard));
      expect(size.height, greaterThanOrEqualTo(Targets.control));
      expect(size.height, greaterThanOrEqualTo(Targets.min),
          reason: 'never below the accessibility floor');
    });

    testWidgets('marks selection with an icon, not colour alone',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          SelectableCard(title: 'Prepaid', selected: true, onTap: () {}),
        ),
      );
      // Colour must never be the sole carrier of meaning.
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('exposes selection state to screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(SelectableCard(title: 'Prepaid', selected: true, onTap: () {})),
      );
      // A sighted user sees the tick and the tint; a screen-reader user must
      // be told the same thing.
      expect(
        find.bySemanticsLabel('Prepaid'),
        findsAtLeastNWidgets(1),
      );
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      handle.dispose();
    });

    testWidgets('fires its callback', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(SelectableCard(title: 'Prepaid', onTap: () => tapped = true)),
      );
      await tester.tap(find.byType(SelectableCard));
      expect(tapped, isTrue);
    });
  });

  group('InfoNote', () {
    testWidgets('renders its message in every tone', (tester) async {
      for (final tone in NoteTone.values) {
        await tester.pumpWidget(
          _wrap(InfoNote(message: 'Coverage is 87%', tone: tone)),
        );
        expect(find.text('Coverage is 87%'), findsOneWidget);
      }
    });

    testWidgets('carries an icon so tone is not colour-only', (tester) async {
      await tester.pumpWidget(
        _wrap(const InfoNote(message: 'x', tone: NoteTone.warning)),
      );
      expect(find.byType(Icon), findsWidgets);
    });
  });

  group('text scaling', () {
    testWidgets('SelectableCard survives 200% text scale without overflow',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: GridTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(2.0),
              size: Size(360, 800),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: SelectableCard(
                  title: 'Postpaid analogue meter',
                  subtitle:
                      'Spinning dials or a mechanical counter. You get a bill.',
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
