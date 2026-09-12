import 'dart:async';

import 'package:consts_quizzes/round/answering.dart';
import 'package:consts_quizzes/round/leaderboard.dart';
import 'package:consts_quizzes/round/round.dart';
import 'package:consts_quizzes/round/round_view.dart';
import 'package:consts_quizzes/round/server_clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A clock the test owns outright, so a Slot can be made to expire on demand.
class _FixedClock extends ServerClock {
  _FixedClock(this.fixed) : super(offsetMs: 0);
  int fixed;
  @override
  int get nowMs => fixed;
}

LiveRound _round({
  required int openSlot,
  required int now,
  String theme = 'Geography',
  String? nextTheme,
  int readMs = 4000,
  int slotMs = 15000,
}) =>
    LiveRound(
      id: 'r1',
      theme: theme,
      nextTheme: nextTheme,
      slotCount: 20,
      openSlot: openSlot,
      question: openSlot < 0
          ? null
          : OpenQuestion(
              slot: openSlot,
              prompt: 'What is the capital of France?',
              choices: const ['Paris', 'London', 'Rome', 'Berlin'],
              difficulty: 'easy',
              opensAt: now + readMs,
              closesAt: now + slotMs,
            ),
      nextRoundAt: now + 60000,
    );

/// Records what was submitted, and can be told to refuse.
class _FakeSink implements AnswerSink {
  final submitted = <String>[];
  bool refuse = false;

  @override
  Future<void> submit(LiveRound round, String choice) async {
    if (refuse) throw Exception('permission-denied');
    submitted.add(choice);
  }
}

Future<void> _pump(
  WidgetTester tester,
  Stream<LiveRound?> rounds,
  ServerClock clock, {
  AnswerSink? sink,
  Stream<LiveBoard>? boards,
  String? uid,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RoundView(
        rounds: rounds,
        clock: clock,
        handle: 'jolly-teal-otter-777',
        sink: sink,
        boards: boards,
        uid: uid,
      ),
    ),
  );
  // The board's StreamBuilder is nested inside the Round's, so it is not built
  // until the Round has been delivered — hence more than one frame.
  await tester.pump(Duration.zero);
  await tester.pump();
  await tester.pump(Duration.zero);
  await tester.pump();
}

void main() {
  testWidgets('shows standby until a Round arrives', (tester) async {
    await _pump(tester, const Stream<LiveRound?>.empty(), _FixedClock(0));
    expect(find.text('Tuning in…'), findsOneWidget);
  });

  testWidgets('renders the open Question and its Choices', (tester) async {
    await _pump(
      tester,
      Stream.value(_round(openSlot: 6, now: 0)),
      _FixedClock(0),
    );

    expect(find.text('What is the capital of France?'), findsOneWidget);
    for (final c in ['Paris', 'London', 'Rome', 'Berlin']) {
      expect(find.text(c), findsOneWidget);
    }
  });

  testWidgets('numbers the Slot for the audience, counting from one',
      (tester) async {
    await _pump(
      tester,
      Stream.value(_round(openSlot: 6, now: 0)),
      _FixedClock(0),
    );
    expect(find.text('question 7 of 20'), findsOneWidget);
  });

  testWidgets('shows the Theme', (tester) async {
    await _pump(
      tester,
      Stream.value(_round(openSlot: 0, now: 0, theme: 'Mythology')),
      _FixedClock(0),
    );
    expect(find.text('Mythology'), findsOneWidget);
  });

  testWidgets('holds Answers shut during the read phase', (tester) async {
    await _pump(
      tester,
      Stream.value(_round(openSlot: 0, now: 0)),
      _FixedClock(1000),
    );
    expect(find.text('read it'), findsOneWidget);
    expect(find.text('answering'), findsNothing);
  });

  testWidgets('opens Answers once the read phase is over', (tester) async {
    await _pump(
      tester,
      Stream.value(_round(openSlot: 0, now: 0)),
      _FixedClock(5000),
    );
    expect(find.text('answering'), findsOneWidget);
  });

  testWidgets('counts down in whole seconds to the Slot closing',
      (tester) async {
    await _pump(
      tester,
      Stream.value(_round(openSlot: 0, now: 0)),
      _FixedClock(5000),
    );
    expect(find.text('10'), findsOneWidget);
  });

  testWidgets('joins at whatever Slot is open, not the start of the Round',
      (tester) async {
    await _pump(
      tester,
      Stream.value(_round(openSlot: 17, now: 0)),
      _FixedClock(5000),
    );
    expect(find.text('question 18 of 20'), findsOneWidget);
  });

  testWidgets('advances when the Round stream emits the next Slot',
      (tester) async {
    final controller = StreamController<LiveRound?>();
    addTearDown(controller.close);
    await _pump(tester, controller.stream, _FixedClock(5000));

    // Two pumps: one to let the stream deliver, one to rebuild on it.
    controller.add(_round(openSlot: 0, now: 0));
    await tester.pump(Duration.zero);
    await tester.pump();
    expect(find.text('question 1 of 20'), findsOneWidget);

    controller.add(_round(openSlot: 1, now: 0));
    await tester.pump(Duration.zero);
    await tester.pump();
    expect(find.text('question 2 of 20'), findsOneWidget);
  });

  testWidgets('shows the Intermission countdown between Rounds',
      (tester) async {
    await _pump(
      tester,
      Stream.value(_round(openSlot: -1, now: 0)),
      _FixedClock(30000),
    );

    expect(find.text('between rounds'), findsOneWidget);
    expect(find.text('final scores'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
  });

  testWidgets('announces the next Theme during the Intermission',
      (tester) async {
    await _pump(
      tester,
      Stream.value(_round(openSlot: -1, now: 0, nextTheme: 'Mythology')),
      _FixedClock(30000),
    );

    expect(find.text('next up'), findsOneWidget);
    expect(find.text('Mythology'), findsOneWidget);
  });

  testWidgets('does not promise a next Theme before one is chosen',
      (tester) async {
    await _pump(
      tester,
      Stream.value(_round(openSlot: -1, now: 0)),
      _FixedClock(30000),
    );

    expect(find.text('next up'), findsNothing);
  });

  testWidgets('lays out at phone width without overflowing', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await _pump(
      tester,
      Stream.value(_round(openSlot: 3, now: 0)),
      _FixedClock(5000),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Paris'), findsOneWidget);
  });

  group('answering', () {
    testWidgets('sends the Choice that was tapped', (tester) async {
      final sink = _FakeSink();
      await _pump(
        tester,
        Stream.value(_round(openSlot: 0, now: 0)),
        _FixedClock(5000),
        sink: sink,
      );

      await tester.tap(find.text('Rome'));
      await tester.pump();

      expect(sink.submitted, ['Rome']);
      expect(find.text('locked in'), findsOneWidget);
    });

    testWidgets('ignores taps during the read phase', (tester) async {
      final sink = _FakeSink();
      await _pump(
        tester,
        Stream.value(_round(openSlot: 0, now: 0)),
        _FixedClock(1000),
        sink: sink,
      );

      await tester.tap(find.text('Rome'), warnIfMissed: false);
      await tester.pump();

      expect(sink.submitted, isEmpty);
    });

    testWidgets('accepts only one Answer per Slot', (tester) async {
      final sink = _FakeSink();
      await _pump(
        tester,
        Stream.value(_round(openSlot: 0, now: 0)),
        _FixedClock(5000),
        sink: sink,
      );

      await tester.tap(find.text('Rome'));
      await tester.pump();
      await tester.tap(find.text('Paris'), warnIfMissed: false);
      await tester.pump();

      expect(sink.submitted, ['Rome']);
    });

    testWidgets('says so when the rules refuse the Answer', (tester) async {
      final sink = _FakeSink()..refuse = true;
      await _pump(
        tester,
        Stream.value(_round(openSlot: 0, now: 0)),
        _FixedClock(5000),
        sink: sink,
      );

      await tester.tap(find.text('Rome'));
      await tester.pump();

      expect(find.text('too late'), findsOneWidget);
    });

    testWidgets('clears the Answer when the next Slot opens', (tester) async {
      final controller = StreamController<LiveRound?>();
      addTearDown(controller.close);
      final sink = _FakeSink();
      await _pump(tester, controller.stream, _FixedClock(5000), sink: sink);

      controller.add(_round(openSlot: 0, now: 0));
      await tester.pump(Duration.zero);
      await tester.pump();
      await tester.tap(find.text('Rome'));
      await tester.pump();
      expect(find.text('locked in'), findsOneWidget);

      controller.add(_round(openSlot: 1, now: 0));
      await tester.pump(Duration.zero);
      await tester.pump();
      expect(find.text('locked in'), findsNothing);

      await tester.tap(find.text('Paris'));
      await tester.pump();
      expect(sink.submitted, ['Rome', 'Paris']);
    });

    testWidgets('a watcher with no sink cannot answer', (tester) async {
      await _pump(
        tester,
        Stream.value(_round(openSlot: 0, now: 0)),
        _FixedClock(5000),
      );

      await tester.tap(find.text('Rome'), warnIfMissed: false);
      await tester.pump();

      expect(find.text('locked in'), findsNothing);
    });
  });

  group('leaderboard', () {
    LiveBoard board(int playing, List<(String, int)> top) => LiveBoard(
          playing: playing,
          slot: 3,
          top: [
            for (final (h, sc) in top)
              Standing(uid: h, handle: h, score: sc),
          ],
        );

    testWidgets('says nobody has answered before anyone has', (tester) async {
      await _pump(
        tester,
        Stream.value(_round(openSlot: 0, now: 0)),
        _FixedClock(5000),
        boards: Stream.value(board(0, [])),
      );
      expect(find.text('nobody has answered yet'), findsOneWidget);
    });

    testWidgets('names the leaders and counts everyone playing',
        (tester) async {
      await _pump(
        tester,
        Stream.value(_round(openSlot: 0, now: 0)),
        _FixedClock(5000),
        boards: Stream.value(
          board(1483, [('alpha-1', 900), ('beta-2', 700), ('gamma-3', 500)]),
        ),
      );

      expect(find.text('alpha-1'), findsOneWidget);
      expect(find.text('900'), findsOneWidget);
      expect(find.text('1483 playing'), findsOneWidget);
    });

    testWidgets('shows only the top few while a Slot is on screen',
        (tester) async {
      await _pump(
        tester,
        Stream.value(_round(openSlot: 0, now: 0)),
        _FixedClock(5000),
        boards: Stream.value(
          board(9, [
            ('a-1', 900),
            ('b-2', 800),
            ('c-3', 700),
            ('d-4', 600),
          ]),
        ),
      );

      expect(find.text('c-3'), findsOneWidget);
      expect(find.text('d-4'), findsNothing);
    });

    testWidgets('opens the full board during the Intermission', (tester) async {
      await _pump(
        tester,
        Stream.value(_round(openSlot: -1, now: 0)),
        _FixedClock(30000),
        boards: Stream.value(
          board(9, [
            ('a-1', 900),
            ('b-2', 800),
            ('c-3', 700),
            ('d-4', 600),
          ]),
        ),
      );

      expect(find.text('d-4'), findsOneWidget);
    });

    testWidgets('picks this Player out of the standings', (tester) async {
      await _pump(
        tester,
        Stream.value(_round(openSlot: 0, now: 0)),
        _FixedClock(5000),
        boards: Stream.value(board(2, [('alpha-1', 900), ('me-2', 700)])),
        uid: 'me-2',
      );

      final me = tester.widget<Text>(find.text('me-2'));
      final them = tester.widget<Text>(find.text('alpha-1'));
      expect(me.style!.color, isNot(them.style!.color));
    });
  });

  testWidgets('shows the visitor their Handle', (tester) async {
    await _pump(
      tester,
      Stream.value(_round(openSlot: 0, now: 0)),
      _FixedClock(5000),
    );
    expect(find.text('jolly-teal-otter-777'), findsOneWidget);
  });
}
