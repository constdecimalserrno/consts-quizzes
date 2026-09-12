import 'package:consts_quizzes/auth/linking.dart';
import 'package:consts_quizzes/auth/save_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester,
  Future<LinkOutcome> Function(Provider) linker, {
  VoidCallback? onDismiss,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SavePrompt(
          score: 14200,
          onDismiss: onDismiss ?? () {},
          linker: linker,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('leads with what the Player stands to lose', (tester) async {
    await _pump(tester, (_) async => LinkOutcome.linked);

    expect(find.text('You scored 14200. Keep it?'), findsOneWidget);
    expect(
      find.textContaining('disappears when your browser forgets you'),
      findsOneWidget,
    );
  });

  testWidgets('offers all three providers', (tester) async {
    await _pump(tester, (_) async => LinkOutcome.linked);

    for (final label in ['Google', 'Apple', 'X']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('confirms a successful link', (tester) async {
    await _pump(tester, (_) async => LinkOutcome.linked);

    await tester.tap(find.text('Google'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Saved. This score is yours for good.'), findsOneWidget);

    // The prompt dismisses itself a moment later; let that timer run out or
    // the test ends with it still pending.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('explains a merge when the account already existed',
      (tester) async {
    await _pump(tester, (_) async => LinkOutcome.switchedAndMerged);

    await tester.tap(find.text('Google'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Welcome back — your scores have been combined.'),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('says plainly when a score did not transfer', (tester) async {
    await _pump(tester, (_) async => LinkOutcome.switchedOnly);

    await tester.tap(find.text('X'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining("didn't transfer"), findsOneWidget);
  });

  testWidgets('says when a provider is not switched on yet', (tester) async {
    await _pump(tester, (_) async => LinkOutcome.unavailable);

    await tester.tap(find.text('Apple'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Apple sign-in is not switched on yet.'),
      findsOneWidget,
    );
  });

  testWidgets('says nothing extra when the Player backs out', (tester) async {
    await _pump(tester, (_) async => LinkOutcome.cancelled);

    await tester.tap(find.text('Google'));
    await tester.pump();
    await tester.pump();

    // Back to the buttons, no scolding.
    expect(find.text('Google'), findsOneWidget);
  });

  testWidgets('can be waved away', (tester) async {
    var dismissed = false;
    await _pump(
      tester,
      (_) async => LinkOutcome.linked,
      onDismiss: () => dismissed = true,
    );

    await tester.tap(find.text('not now'));
    await tester.pump();

    expect(dismissed, isTrue);
  });
}
