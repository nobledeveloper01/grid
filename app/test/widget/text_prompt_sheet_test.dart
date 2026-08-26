import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid/core/theme/theme.dart';
import 'package:grid/shared/widgets/text_prompt_sheet.dart';

/// Regression test for a crash on a primary flow.
///
/// Creating a `TextEditingController` at the call site, awaiting
/// `showModalBottomSheet` and disposing the controller afterwards looks
/// correct and throws `_dependents.isEmpty: is not true` — the sheet's route
/// is still animating out and its `TextField` is still mounted. The sheet
/// owns its controller now; this makes sure it stays that way.
void main() {
  Widget host(void Function(BuildContext) onPressed) => MaterialApp(
        theme: GridTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => onPressed(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  testWidgets('returns the typed text and tears down cleanly', (tester) async {
    String? result;
    await tester.pumpWidget(host((context) async {
      result = await promptForText(
        context,
        title: 'Reference',
        hintText: 'Optional',
      );
    }));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'IE/SUR/2026/8841');
    await tester.tap(find.text('Save'));

    // Pump through the dismissal animation rather than settling in one go:
    // the crash happened *during* the exit transition, so the frames in
    // between are the ones that matter.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(result, 'IE/SUR/2026/8841');
    expect(tester.takeException(), isNull);
  });

  testWidgets('dismissal without confirming yields null', (tester) async {
    var called = false;
    String? result = 'unset';
    await tester.pumpWidget(host((context) async {
      called = true;
      result = await promptForText(context, title: 'Reference');
    }));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Tap the scrim above the sheet.
    await tester.tapAt(const Offset(400, 40));
    await tester.pumpAndSettle();

    expect(called, isTrue);
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening and dismissing repeatedly never throws',
      (tester) async {
    await tester.pumpWidget(host((context) {
      promptForText(context, title: 'Reference');
    }));

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'x$i');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
