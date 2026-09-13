import 'dart:async';

import 'package:consts_quizzes/round/answering.dart';
import 'package:consts_quizzes/round/leaderboard.dart';
import 'package:consts_quizzes/round/round.dart';
import 'package:consts_quizzes/round/seating.dart';
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

/// A Slot laid out as the server lays one out: read, answer, reveal, idle.
const readMs = 3000;
const answerMs = 10000;
const revealMs = 4000;
const idleMs = 2000;

LiveRound _round({
  required int openSlot,
  required int now,
  String theme = 'Geography',
  String? nextTheme,
  String? correct,
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
              startsAt: now,
              opensAt: now + readMs,
              closesAt: now + readMs + answerMs,
              revealUntil: now + readMs + answerMs + revealMs,
              endsAt: now + readMs + answerMs + revealMs + idleMs,
              correct: correct,
            ),
      nextRoundAt: now + 60000,
    );

/// A moment inside each phase of a Slot that started at zero.
const inRead = 1000;
const inAnswer = readMs + 2000;
const inReveal = readMs + answerMs + 1000;
const inIdle = readMs + answerMs + revealMs + 500;

/// Whether a Choice is actually on screen.
///
/// During the read phase the podiums are drawn at full size with their Choices
/// at zero opacity, so the text is in the tree but invisible. Presence is the
/// wrong question — the Choices are in the document the client already
/// downloaded, and concealment was never what paced the game.
bool _choiceVisible(WidgetTester tester, String text) {
  final finder = find.text(text);
  if (finder.evaluate().isEmpty) return false;
  var visible = true;
  tester.element(finder).visitAncestorElements((e) {
    final w = e.widget;
    if (w is Opacity && w.opacity == 0) {
      visible = false;
      return false;
    }
    return true;
  });
  return visible;
}

/// Firestore's snapshot streams are broadcast, and the board panels subscribe
/// and unsubscribe as the viewer switches between them. A single-subscription
/// stream would throw on the second listen, which is a property of the test
/// double rather than of the widget.
Stream<T> _broadcast<T>(T value) => Stream<T>.value(value).asBroadcastStream();

/// Seats whoever asks, in whatever Round they ask about.
class _FakeSeating implements Seating {
  _FakeSeating({this.seated = true, this.refusal});
  final bool seated;
  final String? refusal;
  final asked = <String>[];

  @override
  Future<Seat> take(String roundId) async {
    asked.add(roundId);
    return Seat(roundId: roundId, seated: seated, refusal: refusal);
  }
}

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
  Seating? seating,
  Stream<AllTimeBoard>? allTime,
  Stream<AllTimeBoard>? bots,
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
        // A sink is not enough to answer any more: a seat is needed too, so
        // tests that submit an Answer default to holding one.
        seating: seating ?? _FakeSeating(),
        allTime: allTime,
        bots: bots,
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

  testWidgets('shows the prompt but hides the Choices while reading',
      (tester) async {
    await _pump(
      tester,
      Stream.value(_round(openSlot: 6, now: 0)),
      _FixedClock(inRead),
    );

    expect(find.text('What is the capital of France?'), findsOneWidget);
    // Greying them out would just mean everyone reads them anyway.
    for (final c in ['Paris', 'London', 'Rome', 'Berlin']) {
      expect(_choiceVisible(tester, c), isFalse, reason: c);
    }
    expect(find.text('read it'), findsOneWidget);
  });

  testWidgets('does not shift the page when the Choices arrive', (tester) async {
    // The podiums are drawn unlit during the read phase precisely so that the
    // Choices appearing is text filling in, not the whole screen jumping.
    final clock = _FixedClock(inRead);
    final controller = StreamController<LiveRound?>();
    addTearDown(controller.close);
    await _pump(tester, controller.stream, clock);

    controller.add(_round(openSlot: 6, now: 0));
    await tester.pump(Duration.zero);
    await tester.pump();
    final whileReading =
        tester.getTopLeft(find.text('What is the capital of France?'));
    expect(_choiceVisible(tester, 'Paris'), isFalse);

    clock.fixed = inAnswer;
    controller.add(_round(openSlot: 6, now: 0));
    await tester.pump(Duration.zero);
    await tester.pump();
    final whileAnswering = tester.getTopLeft(find.text('What is the capital of France?'));

    expect(_choiceVisible(tester, 'Paris'), isTrue);
    expect(whileAnswering, whileReading);
  });

  testWidgets('brings the Choices out when the Window opens', (tester) async {
    await _pump(
      tester,
      Stream.value(_round(openSlot: 6, now: 0)),
      _FixedClock(inAnswer),
    );

    for (final c in ['Paris', 'London', 'Rome', 'Berlin']) {
      expect(find.text(c), findsOneWidget);
    }
  });

  testWidgets('numbers the Slot for the audience, counting from one',
      (tester) async {
    await _pump(
      tester,
      Stream.value(_round(openSlot: 6, now: 0)),
      _FixedClock(inAnswer),
    );
    expect(find.text('question 7 of 20'), findsOneWidget);
  });

  testWidgets('shows the Theme', (tester) async {
    await _pump(
      tester,
      Stream.value(_round(openSlot: 0, now: 0, theme: 'Mythology')),
      _FixedClock(inAnswer),
    );
    expect(find.text('Mythology'), findsOneWidget);
  });

  testWidgets('shows what the Answer is worth, falling as time runs out',
      (tester) async {
    await _pump(
      tester,
      Stream.value(_round(openSlot: 0, now: 0)),
      _FixedClock(inAnswer),
    );

    // The client's Window is a fraction shorter than the server's, so a tap is
    // never taken so late that the write lands after the deadline.
    expect(find.textContaining('points,'), findsOneWidget);
    expect(find.textContaining('s left'), findsOneWidget);
  });

  testWidgets('stops taking Answers before the server deadline',
      (tester) async {
    final sink = _FakeSink();
    // Quarter of a second before the Window shuts: too late for a write from a
    // browser to get there, so the Choices are already gone.
    await _pump(
      tester,
      Stream.value(_round(openSlot: 0, now: 0)),
      _FixedClock(readMs + answerMs - 250),
      sink: sink,
        seating: _FakeSeating(),
    );

    await tester.tap(find.text('Paris'), warnIfMissed: false);
    await tester.pump();

    // The Choices are still on screen — the reveal is about to show which was
    // right — but they no longer take a tap.
    expect(sink.submitted, isEmpty);
    expect(find.text('checking…'), findsOneWidget);
  });

  testWidgets('the meter is worth less later in the Window', (tester) async {
    await _pump(
      tester,
      Stream.value(_round(openSlot: 0, now: 0)),
      _FixedClock(readMs + 8000),
    );

    expect(find.textContaining('points,'), findsOneWidget);
  });

  testWidgets('joins at whatever Slot is open, not the start of the Round',
      (tester) async {
    await _pump(
      tester,
      Stream.value(_round(openSlot: 17, now: 0)),
      _FixedClock(inAnswer),
    );
    expect(find.text('question 18 of 20'), findsOneWidget);
  });

  group('reveal', () {
    testWidgets('says which Choice was right', (tester) async {
      await _pump(
        tester,
        Stream.value(_round(openSlot: 0, now: 0, correct: 'Paris')),
        _FixedClock(inReveal),
      );

      expect(find.text('the answer is'), findsOneWidget);
      expect(find.text('correct'), findsOneWidget);
    });

    testWidgets('congratulates a Player who got it', (tester) async {
      final sink = _FakeSink();
      final controller = StreamController<LiveRound?>();
      addTearDown(controller.close);
      final clock = _FixedClock(inAnswer);
      await _pump(tester, controller.stream, clock, sink: sink);

      controller.add(_round(openSlot: 0, now: 0));
      await tester.pump(Duration.zero);
      await tester.pump();
      await tester.tap(find.text('Paris'));
      await tester.pump();

      clock.fixed = inReveal;
      controller.add(_round(openSlot: 0, now: 0, correct: 'Paris'));
      await tester.pump(Duration.zero);
      await tester.pump();

      expect(find.text('you got it'), findsOneWidget);
    });

    testWidgets('marks a wrong pick as wrong rather than dropping it',
        (tester) async {
      final sink = _FakeSink();
      final controller = StreamController<LiveRound?>();
      addTearDown(controller.close);
      final clock = _FixedClock(inAnswer);
      await _pump(tester, controller.stream, clock, sink: sink);

      controller.add(_round(openSlot: 0, now: 0));
      await tester.pump(Duration.zero);
      await tester.pump();
      await tester.tap(find.text('London'));
      await tester.pump();

      clock.fixed = inReveal;
      controller.add(_round(openSlot: 0, now: 0, correct: 'Paris'));
      await tester.pump(Duration.zero);
      await tester.pump();

      expect(find.text('not this one'), findsOneWidget);
      expect(find.text('correct'), findsOneWidget);
    });

    testWidgets('refuses Answers once the Window has shut', (tester) async {
      final sink = _FakeSink();
      await _pump(
        tester,
        Stream.value(_round(openSlot: 0, now: 0, correct: 'Paris')),
        _FixedClock(inReveal),
        sink: sink,
        seating: _FakeSeating(),
      );

      await tester.tap(find.text('Rome'), warnIfMissed: false);
      await tester.pump();

      expect(sink.submitted, isEmpty);
    });

    testWidgets('says it is checking before the answer arrives', (tester) async {
      // The Window has shut but the server has not published the answer yet.
      await _pump(
        tester,
        Stream.value(_round(openSlot: 0, now: 0)),
        _FixedClock(inReveal),
      );

      expect(find.text('checking…'), findsOneWidget);
      expect(find.text('next question in'), findsNothing);
    });

    testWidgets('does not promise a next Question after the last one',
        (tester) async {
      await _pump(
        tester,
        Stream.value(_round(openSlot: 19, now: 0, correct: 'Paris')),
        _FixedClock(inIdle),
      );

      expect(find.text("that's the round"), findsOneWidget);
      expect(find.text('next question in'), findsNothing);
    });

    testWidgets('counts down to the next Question after the reveal',
        (tester) async {
      await _pump(
        tester,
        Stream.value(_round(openSlot: 0, now: 0, correct: 'Paris')),
        _FixedClock(inIdle),
      );

      expect(find.text('next question in'), findsOneWidget);
    });
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
    // Without this the ratio leaks into every later test, which then run at
    // 2400 logical pixels wide — wide enough to lay out the standings rail.
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(
      tester,
      Stream.value(_round(openSlot: 3, now: 0)),
      _FixedClock(inAnswer),
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
        _FixedClock(inAnswer),
        sink: sink,
        seating: _FakeSeating(),
      );

      await tester.tap(find.text('Rome'));
      await tester.pump();

      expect(sink.submitted, ['Rome']);
      expect(find.text('locked in'), findsOneWidget);
    });

    testWidgets('gives nothing to tap during the read phase', (tester) async {
      final sink = _FakeSink();
      await _pump(
        tester,
        Stream.value(_round(openSlot: 0, now: 0)),
        _FixedClock(inRead),
        sink: sink,
        seating: _FakeSeating(),
      );

      await tester.tap(find.text('Rome'), warnIfMissed: false);
      await tester.pump();

      expect(_choiceVisible(tester, 'Rome'), isFalse);
      expect(sink.submitted, isEmpty);
    });

    testWidgets('accepts only one Answer per Slot', (tester) async {
      final sink = _FakeSink();
      await _pump(
        tester,
        Stream.value(_round(openSlot: 0, now: 0)),
        _FixedClock(inAnswer),
        sink: sink,
        seating: _FakeSeating(),
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
        _FixedClock(inAnswer),
        sink: sink,
        seating: _FakeSeating(),
      );

      await tester.tap(find.text('Rome'));
      await tester.pump();

      expect(find.text('too late'), findsOneWidget);
    });

    testWidgets('clears the Answer when the next Slot opens', (tester) async {
      final controller = StreamController<LiveRound?>();
      addTearDown(controller.close);
      final sink = _FakeSink();
      await _pump(tester, controller.stream, _FixedClock(inAnswer), sink: sink);

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
        _FixedClock(inAnswer),
      );

      await tester.tap(find.text('Rome'), warnIfMissed: false);
      await tester.pump();

      expect(find.text('locked in'), findsNothing);
    });
  });

  group('game over', () {
    LiveBoard withMe(int score, int correct) => LiveBoard(
          playing: 12,
          slot: 19,
          top: [
            const Standing(uid: 'other', handle: 'somebody-1', score: 9999),
            Standing(uid: 'me', handle: 'me-2', score: score, correct: correct),
          ],
        );

    testWidgets('breaks down how this Player did', (tester) async {
      await _pump(
        tester,
        Stream.value(_round(openSlot: -1, now: 0)),
        _FixedClock(30000),
        boards: _broadcast(withMe(8400, 14)),
        uid: 'me',
      );

      // Twice on purpose: once as the headline, once in the standings row.
      expect(find.text('8400'), findsNWidgets(2));
      expect(find.text('14 of 20 right  ·  #2'), findsOneWidget);
    });

    testWidgets('grades the round', (tester) async {
      await _pump(
        tester,
        Stream.value(_round(openSlot: -1, now: 0)),
        _FixedClock(30000),
        boards: _broadcast(withMe(20000, 20)),
        uid: 'me',
      );

      expect(find.text('A perfect round. Nobody does that.'), findsOneWidget);
    });

    testWidgets('has something to say about nought out of twenty',
        (tester) async {
      await _pump(
        tester,
        Stream.value(_round(openSlot: -1, now: 0)),
        _FixedClock(30000),
        boards: _broadcast(withMe(0, 0)),
        uid: 'me',
      );

      expect(find.text('Everyone starts somewhere. Run it back.'), findsOneWidget);
    });

    testWidgets('shows a watcher the standings without a personal line',
        (tester) async {
      await _pump(
        tester,
        Stream.value(_round(openSlot: -1, now: 0)),
        _FixedClock(30000),
        boards: _broadcast(withMe(8400, 14)),
        uid: 'someone-who-did-not-play',
      );

      expect(find.text('final scores'), findsOneWidget);
      expect(find.textContaining('of 20 right'), findsNothing);
    });
  });

  group('standings rail', () {
    testWidgets('puts the standings beside the stage when there is room',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pump(
        tester,
        Stream.value(_round(openSlot: 0, now: 0)),
        _FixedClock(inAnswer),
        boards: _broadcast(
          LiveBoard(playing: 3, slot: 0, top: [
            for (final h in ['a-1', 'b-2', 'c-3', 'd-4'])
              Standing(uid: h, handle: h, score: 100),
          ]),
        ),
      );

      // To the left of the Question, and showing more than the three that fit
      // underneath it.
      final board = tester.getTopLeft(find.text('leaders'));
      final prompt =
          tester.getTopLeft(find.text('What is the capital of France?'));
      expect(board.dx, lessThan(prompt.dx));
      expect(find.text('d-4'), findsOneWidget);
    });

    testWidgets('runs the rail the full height of the stage', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pump(
        tester,
        Stream.value(_round(openSlot: 0, now: 0)),
        _FixedClock(inAnswer),
        boards: _broadcast(
          const LiveBoard(playing: 0, slot: 0, top: []),
        ),
      );

      // A short panel with a column of nothing under it reads as unfinished.
      final rail = tester.getSize(find.ancestor(
        of: find.text('leaders'),
        matching: find.byType(DecoratedBox),
      ).first);
      expect(rail.height, greaterThan(300));
    });

    testWidgets('stacks the standings under the stage at phone width',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pump(
        tester,
        Stream.value(_round(openSlot: 0, now: 0)),
        _FixedClock(inAnswer),
        boards: _broadcast(
          LiveBoard(playing: 3, slot: 0, top: [
            for (final h in ['a-1', 'b-2', 'c-3'])
              Standing(uid: h, handle: h, score: 100),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      final board = tester.getTopLeft(find.text('leaders'));
      final prompt =
          tester.getTopLeft(find.text('What is the capital of France?'));
      expect(board.dy, greaterThan(prompt.dy));
      expect(tester.takeException(), isNull);
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
        _FixedClock(inAnswer),
        boards: _broadcast(board(0, [])),
      );
      expect(find.text('nobody has answered yet'), findsOneWidget);
    });

    testWidgets('names the leaders and counts everyone playing',
        (tester) async {
      await _pump(
        tester,
        Stream.value(_round(openSlot: 0, now: 0)),
        _FixedClock(inAnswer),
        boards: _broadcast(
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
        _FixedClock(inAnswer),
        boards: _broadcast(
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
        boards: _broadcast(
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

    testWidgets('offers the all-time board only during the Intermission',
        (tester) async {
      await _pump(
        tester,
        Stream.value(_round(openSlot: 0, now: 0)),
        _FixedClock(inAnswer),
        boards: _broadcast(board(3, [('a-1', 900)])),
        allTime: _broadcast(const AllTimeBoard(top: [])),
      );
      expect(find.text('all time'), findsNothing);

      await _pump(
        tester,
        Stream.value(_round(openSlot: -1, now: 0)),
        _FixedClock(30000),
        boards: _broadcast(board(3, [('a-1', 900)])),
        allTime: _broadcast(const AllTimeBoard(top: [])),
      );
      expect(find.text('all time'), findsOneWidget);
    });

    testWidgets('switches to careers and back', (tester) async {
      await _pump(
        tester,
        Stream.value(_round(openSlot: -1, now: 0)),
        _FixedClock(30000),
        boards: _broadcast(board(3, [('a-1', 900)])),
        allTime: _broadcast(
          const AllTimeBoard(
            top: [
              CareerStanding(
                uid: 'v-1',
                handle: 'veteran-1',
                averageScore: 742,
                bestRound: 1200,
                roundsPlayed: 40,
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.text('all time'));
      await tester.pump();
      await tester.pump(Duration.zero);
      await tester.pump();

      expect(find.text('veteran-1'), findsOneWidget);
      expect(find.text('742'), findsOneWidget);
      expect(find.text('best 1200'), findsOneWidget);

      await tester.tap(find.text('close'));
      await tester.pump();
      await tester.pump(Duration.zero);
      await tester.pump();
      expect(find.text('a-1'), findsOneWidget);
    });

    testWidgets('says so when nobody has qualified all-time yet',
        (tester) async {
      await _pump(
        tester,
        Stream.value(_round(openSlot: -1, now: 0)),
        _FixedClock(30000),
        boards: _broadcast(board(3, [('a-1', 900)])),
        allTime: _broadcast(const AllTimeBoard(top: [])),
      );

      await tester.tap(find.text('all time'));
      await tester.pump();
      await tester.pump(Duration.zero);
      await tester.pump();

      expect(
        find.textContaining('Nobody has finished enough rounds'),
        findsOneWidget,
      );
    });

    testWidgets('keeps Bots on their own board', (tester) async {
      await _pump(
        tester,
        Stream.value(_round(openSlot: -1, now: 0)),
        _FixedClock(30000),
        boards: _broadcast(board(3, [('a-1', 900)])),
        allTime: _broadcast(
          const AllTimeBoard(
            top: [
              CareerStanding(
                uid: 'h-1',
                handle: 'human-1',
                averageScore: 600,
                bestRound: 900,
                roundsPlayed: 10,
              ),
            ],
          ),
        ),
        bots: _broadcast(
          const AllTimeBoard(
            top: [
              CareerStanding(
                uid: 'b-1',
                handle: 'robot-1',
                averageScore: 998,
                bestRound: 1000,
                roundsPlayed: 400,
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.text('all time'));
      await tester.pump();
      await tester.pump(Duration.zero);
      await tester.pump();
      expect(find.text('human-1'), findsOneWidget);
      expect(find.text('robot-1'), findsNothing);

      await tester.tap(find.text('bots'));
      await tester.pump();
      await tester.pump(Duration.zero);
      await tester.pump();
      expect(find.text('robot-1'), findsOneWidget);
      expect(find.text('human-1'), findsNothing);
    });

    testWidgets('picks this Player out of the standings', (tester) async {
      await _pump(
        tester,
        Stream.value(_round(openSlot: 0, now: 0)),
        _FixedClock(inAnswer),
        boards: _broadcast(board(2, [('alpha-1', 900), ('me-2', 700)])),
        uid: 'me-2',
      );

      final me = tester.widget<Text>(find.text('me-2'));
      final them = tester.widget<Text>(find.text('alpha-1'));
      expect(me.style!.color, isNot(them.style!.color));
    });
  });

  group('seats', () {
    testWidgets('takes a seat again when a new Round starts', (tester) async {
      // Seats belong to a Round. Asking once at page load seated the Player in
      // whatever Round was running then, and every Round after it refused
      // their Answers — which the screen reported as "too late".
      final seating = _FakeSeating();
      final controller = StreamController<LiveRound?>();
      addTearDown(controller.close);
      await _pump(tester, controller.stream, _FixedClock(inAnswer),
          seating: seating);

      controller.add(_round(openSlot: 0, now: 0));
      await tester.pump(Duration.zero);
      await tester.pump();
      expect(seating.asked, ['r1']);

      // Same Round, next Slot: no need to ask again.
      controller.add(_round(openSlot: 1, now: 0));
      await tester.pump(Duration.zero);
      await tester.pump();
      expect(seating.asked, ['r1']);

      controller.add(LiveRound(
        id: 'r2',
        theme: 'Geography',
        slotCount: 20,
        openSlot: 0,
        nextRoundAt: 60000,
        question: const OpenQuestion(
          slot: 0,
          prompt: 'Another Question?',
          choices: ['a', 'b'],
          difficulty: 'easy',
          startsAt: 0,
          opensAt: readMs,
          closesAt: readMs + answerMs,
          revealUntil: readMs + answerMs + revealMs,
          endsAt: readMs + answerMs + revealMs + idleMs,
        ),
      ));
      await tester.pump(Duration.zero);
      await tester.pump();
      expect(seating.asked, ['r1', 'r2']);
    });

    testWidgets('will not take a tap without a seat', (tester) async {
      final sink = _FakeSink();
      await _pump(
        tester,
        Stream.value(_round(openSlot: 0, now: 0)),
        _FixedClock(inAnswer),
        sink: sink,
        seating: _FakeSeating(seated: false, refusal: 'full'),
      );

      await tester.tap(find.text('Rome'), warnIfMissed: false);
      await tester.pump();

      // Better an inert podium than a write the rules throw away.
      expect(sink.submitted, isEmpty);
      expect(find.text('locked in'), findsNothing);
    });

    testWidgets('says why a visitor is only watching when the Round is full',
        (tester) async {
      await _pump(
        tester,
        Stream.value(_round(openSlot: 0, now: 0)),
        _FixedClock(inAnswer),
        seating: _FakeSeating(seated: false, refusal: 'full'),
      );

      expect(find.textContaining('is at capacity'), findsOneWidget);
    });

    testWidgets('tells a visitor to retry when joins are contending',
        (tester) async {
      await _pump(
        tester,
        Stream.value(_round(openSlot: 0, now: 0)),
        _FixedClock(inAnswer),
        seating: _FakeSeating(seated: false, refusal: 'busy'),
      );

      // Not "full": there is room, they just collided with everyone else.
      expect(find.textContaining('Reload in a moment'), findsOneWidget);
      expect(find.textContaining('at capacity'), findsNothing);
    });

    testWidgets('says the show is on a break when the game is closed',
        (tester) async {
      await _pump(
        tester,
        Stream.value(_round(openSlot: 0, now: 0)),
        _FixedClock(inAnswer),
        seating: _FakeSeating(seated: false, refusal: 'closed'),
      );

      expect(find.textContaining('on a break'), findsOneWidget);
    });

    testWidgets('says nothing to a visitor who holds a seat', (tester) async {
      await _pump(
        tester,
        Stream.value(_round(openSlot: 0, now: 0)),
        _FixedClock(inAnswer),
      );

      expect(find.textContaining('is at capacity'), findsNothing);
      expect(find.textContaining('on a break'), findsNothing);
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
