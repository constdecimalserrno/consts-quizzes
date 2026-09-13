import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/save_prompt.dart';
import '../theme/broadcast.dart';
import 'answering.dart';
import 'leaderboard.dart';
import 'seating.dart';
import 'round.dart';
import 'server_clock.dart';

/// The live broadcast.
///
/// Driven entirely by a stream of Rounds and a corrected clock, so a widget
/// test can play a whole Round with no Firebase anywhere near it.
class RoundView extends StatefulWidget {
  const RoundView({
    super.key,
    required this.rounds,
    required this.clock,
    this.handle,
    this.sink,
    this.boards,
    this.uid,
    this.seating,
    this.allTime,
    this.anonymous = false,
    this.bots,
    this.points = (max: 1000, min: 100),
  });

  final Stream<LiveRound?> rounds;
  final ServerClock clock;
  final String? handle;

  /// Absent for a visitor who is only watching.
  final AnswerSink? sink;

  final Stream<LiveBoard>? boards;

  /// Used only to pick this Player out of the standings.
  final String? uid;

  /// Takes a seat in each new Round. Absent for a visitor who is only
  /// watching.
  final Seating? seating;

  final Stream<AllTimeBoard>? allTime;

  /// Whether to offer to save this Player's progress once a Round ends well.
  final bool anonymous;

  final Stream<AllTimeBoard>? bots;

  /// Scoring bounds, so the meter counts down real points.
  final ({int max, int min}) points;

  @override
  State<RoundView> createState() => _RoundViewState();
}

class _RoundViewState extends State<RoundView> {
  /// Repaints the clock. The Round itself arrives on its own stream; this only
  /// moves the countdown between those arrivals.
  late final Timer _ticker = Timer.periodic(
    const Duration(milliseconds: 250),
    (_) => setState(() {}),
  );

  /// What this Player picked, keyed by Round and Slot so that moving on always
  /// clears it and a reconnect mid-Slot does not forget it.
  String? _pickedKey;
  String? _picked;
  Answered _state = Answered.no;

  /// Asked once. A prompt that comes back every Round is a nag, and a nag is
  /// how a drop-in game loses the people who dropped in.
  bool _promptDismissed = false;

  /// Subscribed here rather than inside the board panel, because the
  /// Intermission needs this Player's own line out of it too, and one listener
  /// is one document read where two would be two.
  StreamSubscription<LiveBoard>? _boardSub;
  LiveBoard _live = LiveBoard.empty;

  /// A seat is per Round, so this is retaken every time the Round changes.
  Seat? _seat;
  String? _seatingFor;

  @override
  void initState() {
    super.initState();
    _ticker;
    _boardSub = widget.boards?.listen((b) {
      if (mounted) setState(() => _live = b);
    });
  }

  /// This Player's own line in the standings, and where it places.
  ({int score, int correct, int rank})? get _mine {
    final uid = widget.uid;
    if (uid == null) return null;
    final at = _live.top.indexWhere((s) => s.uid == uid);
    if (at < 0) return null;
    final row = _live.top[at];
    return (score: row.score, correct: row.correct, rank: at + 1);
  }

  Future<void> _answer(LiveRound round, String choice) async {
    final sink = widget.sink;
    if (sink == null || _state != Answered.no) return;

    setState(() {
      _pickedKey = '${round.id}:${round.openSlot}';
      _picked = choice;
      _state = Answered.sending;
    });
    try {
      await sink.submit(round, choice);
      if (mounted) setState(() => _state = Answered.sent);
    } catch (_) {
      // The rules refused it: the Window closed under them, or they already
      // answered from another tab. Either way the Answer did not land, and
      // saying so is better than a podium that looks chosen but is not.
      if (mounted) setState(() => _state = Answered.rejected);
    }
  }

  /// Takes a seat in the Round on screen, once per Round.
  void _seatFor(LiveRound round) {
    final seating = widget.seating;
    if (seating == null || _seatingFor == round.id) return;
    _seatingFor = round.id;
    seating.take(round.id).then((seat) {
      if (mounted && _seatingFor == seat.roundId) setState(() => _seat = seat);
    });
  }

  void _resetIfNewSlot(LiveRound round) {
    final key = '${round.id}:${round.openSlot}';
    if (_pickedKey != key && _state != Answered.no) {
      _pickedKey = null;
      _picked = null;
      _state = Answered.no;
    }
  }

  @override
  void dispose() {
    _ticker.cancel();
    _boardSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: DecoratedBox(
      decoration: Broadcast.set,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            child: StreamBuilder<LiveRound?>(
              stream: widget.rounds,
              builder: (context, snap) {
                if (!snap.hasData) return const _Standby();
                final round = snap.data!;
                _seatFor(round);
                _resetIfNewSlot(round);
                return _Broadcast(
                  round: round,
                  clock: widget.clock,
                  handle: widget.handle,
                  picked: _picked,
                  state: _state,
                  // Nothing to press without a seat: the write would be
                  // refused, and a refusal a Player cannot see the cause of is
                  // worse than a podium that simply does not respond.
                  onPick: widget.sink == null || _seat?.seated != true
                      ? null
                      : (choice) => _answer(round, choice),
                  boards: widget.boards,
                  uid: widget.uid,
                  refusal: _seat?.refusal,
                  allTime: widget.allTime,
                  bots: widget.bots,
                  points: widget.points,
                  mine: _mine,
                  live: _live,
                  savePrompt: widget.anonymous && !_promptDismissed
                      ? (score) => _SavePromptSlot(
                          score: score,
                          onDismiss: () =>
                              setState(() => _promptDismissed = true),
                        )
                      : null,
                );
              },
            ),
          ),
          const Scanlines(),
        ],
      ),
    ),
  );
}

class _Standby extends StatelessWidget {
  const _Standby();

  @override
  Widget build(BuildContext context) =>
      Center(child: Text('Tuning in…', style: Broadcast.display(22)));
}

class _Broadcast extends StatelessWidget {
  const _Broadcast({
    required this.round,
    required this.clock,
    required this.handle,
    required this.picked,
    required this.state,
    required this.onPick,
    required this.boards,
    required this.uid,
    required this.refusal,
    required this.allTime,
    required this.bots,
    required this.savePrompt,
    required this.points,
    required this.mine,
    required this.live,
  });

  final LiveRound round;
  final ServerClock clock;
  final String? handle;
  final String? picked;
  final Answered state;
  final void Function(String choice)? onPick;
  final Stream<LiveBoard>? boards;
  final String? uid;
  final String? refusal;
  final Stream<AllTimeBoard>? allTime;
  final Stream<AllTimeBoard>? bots;

  /// Built with the Player's score when a Round ends, if they should be asked
  /// to keep it.
  final Widget Function(int score)? savePrompt;

  /// Scoring bounds, so the meter counts down real points.
  final ({int max, int min}) points;

  /// This Player's own result for the Round that just ended.
  final ({int score, int correct, int rank})? mine;
  final LiveBoard live;

  @override
  Widget build(BuildContext context) {
    final q = round.question;
    // The whole broadcast is one block, centred on the set. Letting the stage
    // expand to fill the window left a few hundred pixels of nothing between
    // the theme strip and the question on an ordinary desktop.
    return LayoutBuilder(
      builder: (context, box) {
        final hasRail =
            boards != null && box.maxWidth >= Broadcast.railBreakpoint;

        final board = boards == null
            ? null
            : _Board(
                live: live,
                allTime: allTime,
                bots: bots,
                uid: uid,
                // In the rail there is room for the whole board all the time;
                // stacked under the stage there is only room for the top few
                // until a Round ends.
                compact: !hasRail && !round.inIntermission,
                savePrompt: round.inIntermission ? savePrompt : null,
                fill: hasRail,
              );

        // Below this the podiums stack four deep and the stage is taller than
        // any fixed box worth setting; it scrolls instead.
        final narrow = box.maxWidth < 560;

        final stage = ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: narrow ? 0 : Broadcast.stageBox,
          ),
          child: round.inIntermission
              ? _Intermission(
                  round: round,
                  clock: clock,
                  mine: mine,
                  slots: round.slotCount,
                )
              : _Stage(
                  question: q!,
                  clock: clock,
                  picked: picked,
                  state: state,
                  onPick: onPick,
                  points: points,
                  isLastSlot: q.slot >= round.slotCount - 1,
                ),
        );

        // Above centre rather than dead centre: the podiums are the thing you
        // reach for, and they should not sit at the bottom of the window.
        return Align(
          alignment: const Alignment(0, -0.35),
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: hasRail ? Broadcast.wideWithRail : Broadcast.wide,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Marquee(handle: handle),
                    const SizedBox(height: 14),
                    // The Theme strip spans both columns: it belongs to the
                    // broadcast, not to the stage.
                    _ThemeStrip(round: round),
                    if (refusal != null) _Refused(reason: refusal!),
                    if (hasRail)
                      // Both columns get the stage's height, so they read as
                      // one set rather than a panel parked beside it.
                      SizedBox(
                        height: Broadcast.stageBox,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(width: Broadcast.rail, child: board),
                            const SizedBox(width: 18),
                            Expanded(child: stage),
                          ],
                        ),
                      )
                    else ...[
                      stage,
                      ?board,
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The show's name, and the light that says this is happening right now.
class _Marquee extends StatelessWidget {
  const _Marquee({required this.handle});

  final String? handle;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final narrow = box.maxWidth < 460;
      final title = FittedBox(
        alignment: Alignment.centerLeft,
        fit: BoxFit.scaleDown,
        child: Text(
          "const's quizzes",
          style: Broadcast.display(narrow ? 24 : 30).copyWith(
            shadows: const [
              Shadow(color: Broadcast.goldDeep, offset: Offset(0, 3)),
              Shadow(color: Broadcast.magenta, offset: Offset(2, 5)),
            ],
          ),
        ),
      );
      final onAir = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(
              color: Broadcast.magenta,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text('on air', style: Broadcast.body(12, color: Broadcast.chalkDim)),
        ],
      );
      final who = handle == null
          ? const SizedBox.shrink()
          : Text(
              handle!,
              overflow: TextOverflow.ellipsis,
              style: Broadcast.body(12, color: Broadcast.cyan),
            );

      // At phone width the title, the light and a Handle do not fit on one
      // line, and squeezing them truncates the Handle to nothing useful.
      if (narrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(child: title),
                onAir,
              ],
            ),
            if (handle != null) ...[const SizedBox(height: 3), who],
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: title),
          const SizedBox(width: 12),
          onAir,
          if (handle != null) ...[
            const SizedBox(width: 14),
            Flexible(child: who),
          ],
        ],
      );
    },
  );
}

class _ThemeStrip extends StatelessWidget {
  const _ThemeStrip({required this.round});

  final LiveRound round;

  @override
  Widget build(BuildContext context) {
    final slot = round.openSlot;
    final counter = slot < 0
        ? 'between rounds'
        : 'question ${slot + 1} of ${round.slotCount}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Broadcast.podium,
        border: Border.all(color: Broadcast.podiumEdge, width: 2),
        boxShadow: Broadcast.bevel,
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final theme = Text(
            round.theme,
            overflow: TextOverflow.ellipsis,
            style: Broadcast.body(13, color: Broadcast.cyan),
          );
          final count = Text(
            counter,
            style: Broadcast.body(13, color: Broadcast.chalkDim),
          );
          // Side by side, a long Theme ellipsises straight into the counter
          // with no gap between them. Below a certain width they stack instead.
          if (box.maxWidth < 420) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [theme, const SizedBox(height: 2), count],
            );
          }
          return Row(
            children: [
              Flexible(child: theme),
              const SizedBox(width: 16),
              count,
            ],
          );
        },
      ),
    );
  }
}

/// The stage: prompt, clock, podiums — one of four phases at a time.
class _Stage extends StatelessWidget {
  const _Stage({
    required this.question,
    required this.clock,
    required this.picked,
    required this.state,
    required this.onPick,
    required this.points,
    required this.isLastSlot,
  });

  final OpenQuestion question;
  final ServerClock clock;
  final String? picked;
  final Answered state;
  final void Function(String choice)? onPick;

  /// Scoring bounds, so the meter shows real numbers rather than a guess.
  final ({int max, int min}) points;

  /// Nothing follows this Slot but the Intermission.
  final bool isLastSlot;

  @override
  Widget build(BuildContext context) {
    final now = clock.nowMs;
    final phase = question.phaseAt(now);

    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth < 520;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            // A prompt is read fastest at roughly 40 characters a line; the
            // full width of the stage runs long enough that the eye loses the
            // start of the next line.
            //
            // The box is a fixed height because Questions are one, two or three
            // lines and everything below would otherwise sit somewhere
            // different for every Question. A very long one scales down inside
            // it rather than pushing the podiums about.
            SizedBox(
              height: Broadcast.promptBox,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 580),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 580),
                      child: Text(
                        question.prompt,
                        textAlign: TextAlign.center,
                        style: Broadcast.body(
                          narrow ? 20 : 25,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            _PhaseBar(
              question: question,
              phase: phase,
              now: now,
              points: points,
              isLastSlot: isLastSlot,
            ),
            const SizedBox(height: 10),
            // Choices stay hidden while the prompt is being read. Showing them
            // greyed out just means everyone reads them anyway and the read
            // phase becomes a stare. The podiums are still drawn, empty, so
            // that the Choices arriving does not shove the whole screen
            // upward three seconds into every Question.
            _Podiums(
              ghost: phase == Phase.read,
              choices: question.choices,
              narrow: narrow,
              picked: picked,
              state: state,
              phase: phase,
              correct: question.correct,
              onPick: phase == Phase.answer ? onPick : null,
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

/// The one loud thing on screen, and what it says depends on the phase.
class _PhaseBar extends StatelessWidget {
  const _PhaseBar({
    required this.question,
    required this.phase,
    required this.now,
    required this.points,
    required this.isLastSlot,
  });

  final OpenQuestion question;
  final Phase phase;
  final int now;
  final ({int max, int min}) points;
  final bool isLastSlot;

  /// Fixed, because a counter and the points meter are not the same height and
  /// the difference would nudge the whole page every time a Slot changed
  /// phase — four times a Question.
  static const height = Broadcast.phaseBox;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Center(child: _forPhase()),
  );

  Widget _forPhase() => switch (phase) {
    Phase.read => _Counter(
      seconds: ((question.opensAt - now) / 1000).ceil().clamp(0, 999),
      label: 'read it',
      colour: Broadcast.cyan,
    ),
    Phase.answer => _PointsMeter(question: question, now: now, points: points),
    Phase.reveal => _Counter(
      seconds: ((question.revealUntil - now) / 1000).ceil().clamp(0, 999),
      label: question.settlingAt(now) ? 'checking…' : 'the answer is',
      colour: Broadcast.gold,
    ),
    // After the last Slot there is no next Question, and counting down to one
    // — then sitting on nought while the scores are worked out — says the
    // wrong thing twice over.
    Phase.idle when isLastSlot => Text(
      "that's the round",
      style: Broadcast.display(20, color: Broadcast.cyan),
    ),
    Phase.idle => _Counter(
      seconds: ((question.endsAt - now) / 1000).ceil().clamp(0, 999),
      label: 'next question in',
      colour: Broadcast.chalkDim,
    ),
  };
}

class _Counter extends StatelessWidget {
  const _Counter({
    required this.seconds,
    required this.label,
    required this.colour,
  });

  final int seconds;
  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        '$seconds',
        style: Broadcast.display(40, color: colour).copyWith(
          shadows: [
            Shadow(color: colour.withValues(alpha: 0.5), blurRadius: 18),
          ],
        ),
      ),
      Text(label, style: Broadcast.body(11, color: Broadcast.chalkDim)),
    ],
  );
}

/// The draining points meter, carried over from the terminal game.
///
/// It is the whole reason answering fast matters, and a bare countdown does
/// not show it: what is running out is money, not time.
class _PointsMeter extends StatelessWidget {
  const _PointsMeter({
    required this.question,
    required this.now,
    required this.points,
  });

  final OpenQuestion question;
  final int now;
  final ({int max, int min}) points;

  static const _cells = 28;

  @override
  Widget build(BuildContext context) {
    final left = question.remainingAt(now);
    final worth = (points.min + (points.max - points.min) * left).round();
    final seconds = ((question.clientClosesAt - now) / 1000).ceil().clamp(
      0,
      999,
    );

    // Warm as it empties, exactly as the terminal version did.
    final colour = left > 0.66
        ? Broadcast.gold
        : left > 0.33
        ? const Color(0xFFFF9A3C)
        : Broadcast.magenta;
    final filled = (left * _cells).round().clamp(0, _cells);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$worth',
          style: Broadcast.display(30, color: colour).copyWith(
            shadows: [
              Shadow(color: colour.withValues(alpha: 0.5), blurRadius: 16),
            ],
          ),
        ),
        Text(
          'points, ${seconds}s left',
          style: Broadcast.body(11, color: Broadcast.chalkDim),
        ),
        const SizedBox(height: 7),
        Semantics(
          label: 'worth $worth points, $seconds seconds left',
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Broadcast.setDeep,
              border: Border.all(color: Broadcast.podiumEdge, width: 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _cells; i++)
                  Container(
                    width: 7,
                    height: 14,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    // The empty cells have to be visible, or the meter reads as
                    // a floating blob drifting left rather than a gauge
                    // emptying inside a track.
                    color: i < filled ? colour : const Color(0xFF243070),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Podiums extends StatelessWidget {
  const _Podiums({
    required this.choices,
    required this.narrow,
    required this.picked,
    required this.state,
    required this.phase,
    required this.correct,
    required this.onPick,
    this.ghost = false,
  });

  final List<String> choices;
  final bool narrow;
  final String? picked;
  final Answered state;
  final Phase phase;
  final String? correct;
  final void Function(String choice)? onPick;

  /// Draw the podiums with their Choices withheld, at exactly the size they
  /// will be once shown.
  final bool ghost;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      for (final (i, choice) in choices.indexed)
        _Podium(
          index: i,
          label: choice,
          ghost: ghost,
          chosen: picked == choice,
          state: state,
          phase: phase,
          isCorrect: correct != null && choice == correct,
          onTap: onPick == null || state != Answered.no
              ? null
              : () => onPick!(choice),
        ),
    ];
    if (narrow) {
      return Column(
        children: [
          for (final t in tiles)
            Padding(padding: const EdgeInsets.only(bottom: 10), child: t),
        ],
      );
    }
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: [for (final t in tiles) SizedBox(width: 330, child: t)],
    );
  }
}

/// A contestant's podium: a face, a bevel, and a hard shadow under it.
///
/// During the reveal it stops being a button and becomes a result: the right
/// answer lights up whether or not anybody picked it, and a wrong pick is
/// marked as wrong rather than quietly dropped.
class _Podium extends StatelessWidget {
  const _Podium({
    required this.index,
    required this.label,
    required this.chosen,
    required this.state,
    required this.phase,
    required this.isCorrect,
    required this.onTap,
    this.ghost = false,
  });

  final int index;
  final String label;
  final bool chosen;
  final Answered state;
  final Phase phase;
  final bool isCorrect;
  final VoidCallback? onTap;

  /// Same podium, Choice withheld — the read phase.
  final bool ghost;

  static const _keys = ['1', '2', '3', '4'];
  static const _right = Color(0xFF35D17E);

  bool get _revealing => phase == Phase.reveal || phase == Phase.idle;

  Color get _edge {
    if (ghost) return Broadcast.podiumEdge.withValues(alpha: 0.45);
    if (_revealing) {
      if (isCorrect) return _right;
      if (chosen) return Broadcast.magenta;
      return Broadcast.podiumEdge;
    }
    if (!chosen) return Broadcast.podiumEdge;
    return state == Answered.rejected ? Broadcast.magenta : Broadcast.gold;
  }

  double get _dim {
    if (ghost) return 1;
    if (!_revealing) return 1;
    // Everything that is neither the answer nor your guess steps back.
    return isCorrect || chosen ? 1 : 0.55;
  }

  String? get _tag {
    if (ghost) return null;
    if (_revealing) {
      if (isCorrect && chosen) return 'you got it';
      if (isCorrect) return 'correct';
      if (chosen) return 'not this one';
      return null;
    }
    if (!chosen) return null;
    return switch (state) {
      Answered.sending => 'sending',
      Answered.sent => 'locked in',
      Answered.rejected => 'too late',
      Answered.no => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final tag = _tag;
    return Semantics(
      button: onTap != null,
      selected: chosen,
      label: label,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: _dim,
        child: Material(
          color: _revealing && isCorrect
              ? const Color(0xFF14402C)
              : chosen
              ? Broadcast.setNavy
              : Broadcast.podium,
          child: InkWell(
            onTap: onTap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _edge,
                  width: chosen || (_revealing && isCorrect) ? 3 : 2,
                ),
                boxShadow: Broadcast.bevel,
              ),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _revealing && isCorrect
                          ? _right
                          : chosen
                          ? Broadcast.magenta
                          : Broadcast.gold,
                    ),
                    child: Text(
                      _keys[index],
                      style: Broadcast.body(
                        13,
                        color: Broadcast.setDeep,
                        weight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ghost
                        // The Choice is withheld, but its line still occupies
                        // the space, so nothing moves when it arrives.
                        ? Opacity(
                            opacity: 0,
                            child: Text(label, style: Broadcast.body(15)),
                          )
                        : Text(label, style: Broadcast.body(15)),
                  ),
                  if (tag != null)
                    Text(
                      tag,
                      style: Broadcast.body(
                        11,
                        color: _revealing && isCorrect
                            ? _right
                            : chosen && _revealing
                            ? Broadcast.magenta
                            : state == Answered.rejected
                            ? Broadcast.magenta
                            : Broadcast.gold,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How a Round is graded, carried over from the terminal game.
///
/// The line is the only thing on the screen that talks back, so it earns its
/// place: nought out of twenty deserves something other than silence.
String banterFor(int correct, int total) {
  if (total <= 0) return 'Stick around — the next one starts shortly.';
  final pct = correct / total;
  if (pct == 1) return 'A perfect round. Nobody does that.';
  if (pct >= 0.8) return 'Outstanding — a whisker off the lot.';
  if (pct >= 0.5) return 'Solid showing. The trophy is in sight.';
  if (correct > 0) return 'A few on the board. Warm up and go again.';
  return 'Everyone starts somewhere. Run it back.';
}

/// Between Rounds: how you did, what is next, and how long you have.
class _Intermission extends StatelessWidget {
  const _Intermission({
    required this.round,
    required this.clock,
    required this.mine,
    required this.slots,
  });

  final LiveRound round;
  final ServerClock clock;

  /// This Player's own result, absent if they did not answer anything.
  final ({int score, int correct, int rank})? mine;
  final int slots;

  @override
  Widget build(BuildContext context) {
    final left = ((round.nextRoundAt - clock.nowMs) / 1000).ceil().clamp(
      0,
      9999,
    );
    final next = round.nextTheme;
    final me = mine;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          if (me != null) ...[
            Text(
              'that round',
              style: Broadcast.body(12, color: Broadcast.chalkDim),
            ),
            const SizedBox(height: 6),
            Text(
              '${me.score}',
              style: Broadcast.display(42, color: Broadcast.gold),
            ),
            const SizedBox(height: 4),
            Text(
              '${me.correct} of $slots right'
              '${me.rank > 0 ? '  ·  #${me.rank}' : ''}',
              style: Broadcast.body(13),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                banterFor(me.correct, slots),
                textAlign: TextAlign.center,
                style: Broadcast.body(13, color: Broadcast.cyan),
              ),
            ),
          ] else
            Text(
              'final scores',
              style: Broadcast.body(14, color: Broadcast.chalkDim),
            ),
          const SizedBox(height: 16),
          if (next != null) ...[
            Text(
              'next up',
              style: Broadcast.body(11, color: Broadcast.chalkDim),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  next,
                  textAlign: TextAlign.center,
                  style: Broadcast.display(22, color: Broadcast.gold),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Text('$left', style: Broadcast.display(34, color: Broadcast.cyan)),
          Text('seconds', style: Broadcast.body(11, color: Broadcast.chalkDim)),
        ],
      ),
    );
  }
}

/// The standings, as a ticker under the stage during a Round and opened out
/// during the Intermission, when there is nothing else to look at.
class _Board extends StatefulWidget {
  const _Board({
    required this.live,
    required this.allTime,
    required this.bots,
    required this.uid,
    required this.compact,
    required this.savePrompt,
    this.fill = false,
  });

  final LiveBoard live;
  final Stream<AllTimeBoard>? allTime;
  final Stream<AllTimeBoard>? bots;
  final String? uid;
  final bool compact;
  final Widget Function(int score)? savePrompt;

  /// In the rail, run the full height of the stage rather than shrinking to
  /// the handful of names on it.
  final bool fill;

  @override
  State<_Board> createState() => _BoardState();
}

/// Holds both boards open at once and renders whichever is being looked at.
///
/// Switching view does not resubscribe: a Firestore listener re-attached on
/// every toggle costs a fresh document read each time, and the two boards
/// together are two documents whatever the viewer does.
class _BoardState extends State<_Board> {
  StreamSubscription<AllTimeBoard>? _careerSub;
  StreamSubscription<AllTimeBoard>? _botSub;

  AllTimeBoard _careers = AllTimeBoard.empty;
  AllTimeBoard _botBoard = AllTimeBoard.empty;

  /// 0 this Round, 1 all time, 2 the Bots.
  int _view = 0;

  @override
  void initState() {
    super.initState();
    _careerSub = widget.allTime?.listen((b) {
      if (mounted) setState(() => _careers = b);
    });
    _botSub = widget.bots?.listen((b) {
      if (mounted) setState(() => _botBoard = b);
    });
  }

  @override
  void dispose() {
    _careerSub?.cancel();
    _botSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The other boards are only worth the room when a Round is not using it.
    final canSwitch = widget.allTime != null && !widget.compact;
    if (canSwitch && _view != 0) {
      final other = _AllTimePanel(
        careers: _view == 1 ? _careers : _botBoard,
        uid: widget.uid,
        title: _view == 1
            ? 'all time, by average round'
            : 'bots, by average round',
        emptyLine: _view == 1
            ? 'Nobody has finished enough rounds yet.'
            : 'No bot has finished enough rounds yet.',
        nextLabel: _view == 1 ? 'bots' : 'this round',
        onNext: () => setState(() => _view = _view == 1 ? 2 : 0),
        onBack: () => setState(() => _view = 0),
      );
      return widget.fill ? Column(children: [Expanded(child: other)]) : other;
    }
    final mine = widget.live.top.where((s) => s.uid == widget.uid).firstOrNull;
    final prompt = widget.savePrompt;
    final panel = _RoundPanel(
      board: widget.live,
      uid: widget.uid,
      compact: widget.compact,
      onAllTime: canSwitch ? () => setState(() => _view = 1) : null,
    );
    return Column(
      mainAxisSize: widget.fill ? MainAxisSize.max : MainAxisSize.min,
      children: [
        widget.fill ? Expanded(child: panel) : panel,
        // Only worth asking somebody who actually scored something.
        if (prompt != null && mine != null && mine.score > 0)
          prompt(mine.score),
      ],
    );
  }
}

class _RoundPanel extends StatelessWidget {
  const _RoundPanel({
    required this.board,
    required this.uid,
    required this.compact,
    required this.onAllTime,
  });

  final LiveBoard board;
  final String? uid;
  final bool compact;
  final VoidCallback? onAllTime;

  @override
  Widget build(BuildContext context) {
    // The panel is drawn whether or not anyone has scored. An empty board used
    // to collapse to a bare line of grey text, which in the rail read as a
    // stray caption rather than the standings waiting to fill up.
    // Three fits under the stage; the rail has room for a real list.
    final shown = compact
        ? board.top.take(3).toList()
        : board.top.take(12).toList();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Broadcast.setDeep.withValues(alpha: 0.55),
        border: Border.all(color: Broadcast.podiumEdge, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('leaders', style: Broadcast.body(12, color: Broadcast.gold)),
              Row(
                children: [
                  Text(
                    '${board.playing} playing',
                    style: Broadcast.body(12, color: Broadcast.chalkDim),
                  ),
                  if (onAllTime != null) ...[
                    const SizedBox(width: 10),
                    _BoardLink(label: 'all time', onTap: onAllTime!),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'nobody has answered yet',
                style: Broadcast.body(12, color: Broadcast.chalkDim),
              ),
            ),
          for (final (i, s) in shown.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      '${i + 1}',
                      style: Broadcast.body(12, color: Broadcast.chalkDim),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      s.handle,
                      overflow: TextOverflow.ellipsis,
                      style: Broadcast.body(
                        13,
                        color: s.uid == uid
                            ? Broadcast.magenta
                            : Broadcast.chalk,
                      ),
                    ),
                  ),
                  Text(
                    '${s.score}',
                    style: Broadcast.body(13, color: Broadcast.gold),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BoardLink extends StatelessWidget {
  const _BoardLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Text(label, style: Broadcast.body(12, color: Broadcast.cyan)),
    ),
  );
}

/// Careers, ranked on average score.
class _AllTimePanel extends StatelessWidget {
  const _AllTimePanel({
    required this.careers,
    required this.uid,
    required this.title,
    required this.emptyLine,
    required this.nextLabel,
    required this.onNext,
    required this.onBack,
  });

  final AllTimeBoard careers;
  final String? uid;
  final String title;
  final String emptyLine;
  final String nextLabel;
  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final top = careers.top;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Broadcast.setDeep.withValues(alpha: 0.55),
        border: Border.all(color: Broadcast.podiumEdge, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: Broadcast.body(12, color: Broadcast.gold),
                ),
              ),
              Row(
                children: [
                  _BoardLink(label: nextLabel, onTap: onNext),
                  const SizedBox(width: 8),
                  _BoardLink(label: 'close', onTap: onBack),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (top.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                emptyLine,
                style: Broadcast.body(12, color: Broadcast.chalkDim),
              ),
            ),
          for (final (i, c) in top.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      '${i + 1}',
                      style: Broadcast.body(12, color: Broadcast.chalkDim),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      c.handle,
                      overflow: TextOverflow.ellipsis,
                      style: Broadcast.body(
                        13,
                        color: c.uid == uid
                            ? Broadcast.magenta
                            : Broadcast.chalk,
                      ),
                    ),
                  ),
                  Text(
                    'best ${c.bestRound}',
                    style: Broadcast.body(11, color: Broadcast.chalkDim),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${c.averageScore}',
                    style: Broadcast.body(13, color: Broadcast.gold),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Why this visitor is watching rather than playing.
///
/// A refused seat is not an error and should not read as one: the broadcast is
/// still there, they simply are not scoring this Round.
class _Refused extends StatelessWidget {
  const _Refused({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      border: Border.all(color: Broadcast.magenta, width: 2),
    ),
    child: Text(switch (reason) {
      'full' =>
        "const's quizzes is at capacity — you're watching. "
            'A seat opens when the next round starts.',
      'busy' =>
        'Lots of people arriving at once. '
            'Reload in a moment to take a seat.',
      _ =>
        "The show is on a break. You're watching; "
            'answering is off for now.',
    }, style: Broadcast.body(12, color: Broadcast.chalk)),
  );
}

/// Wraps [SavePrompt] so the Round view can hand it a score without importing
/// its state.
class _SavePromptSlot extends StatelessWidget {
  const _SavePromptSlot({required this.score, required this.onDismiss});

  final int score;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) =>
      SavePrompt(score: score, onDismiss: onDismiss);
}
