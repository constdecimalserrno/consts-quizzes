import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/save_prompt.dart';
import '../theme/backdrop.dart';
import '../theme/broadcast.dart';
import '../theme/theme_icon.dart';
import 'answering.dart';
import 'leaderboard.dart';
import 'seating.dart';
import 'round.dart';
import 'server_clock.dart';

/// The live broadcast.
///
/// Driven entirely by a stream of Rounds and a corrected clock, so a widget
/// test can play a whole Round with no Firebase anywhere near it.
///
/// Two layouts, chosen on width and nothing else. Wide, it is a studio floor:
/// a header band, the stage filling everything under it, and the standings
/// running down the right-hand edge. Narrow, it is a cabinet: one upright
/// column with the set visible around it. They are not the same layout at two
/// sizes — a rail that becomes a stack is a rail that spends most of its life
/// wrong — and picking between them is the only thing width decides.
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
    this.onOpenProfile,
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

  /// Opens a Player's page. Null uid means whoever is watching.
  final void Function(String? uid)? onOpenProfile;

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

  /// What the meter read at the instant they committed.
  ///
  /// The server scores from its own clock, so this can be a point or two out;
  /// it is the number the Player watched themselves take, which is the number
  /// they will feel cheated of if it is not the one shown back.
  int _lockedPoints = 0;

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

    final q = round.question;
    setState(() {
      _pickedKey = '${round.id}:${round.openSlot}';
      _picked = choice;
      _state = Answered.sending;
      _lockedPoints = q == null
          ? 0
          : (widget.points.min +
                    (widget.points.max - widget.points.min) *
                        q.remainingAt(widget.clock.nowMs))
                .round();
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
      _lockedPoints = 0;
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
    body: SetBackdrop(
      child: SafeArea(
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
              onOpenProfile: widget.onOpenProfile,
              picked: _picked,
              state: _state,
              lockedPoints: _lockedPoints,
              // Nothing to press without a seat: the write would be refused,
              // and a refusal a Player cannot see the cause of is worse than a
              // podium that simply does not respond.
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
                      onDismiss: () => setState(() => _promptDismissed = true),
                    )
                  : null,
            );
          },
        ),
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

/// Picks a layout and hands it the Round.
class _Broadcast extends StatelessWidget {
  const _Broadcast({
    required this.round,
    required this.clock,
    required this.handle,
    required this.onOpenProfile,
    required this.picked,
    required this.state,
    required this.lockedPoints,
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
  final void Function(String? uid)? onOpenProfile;
  final String? picked;
  final Answered state;
  final int lockedPoints;
  final void Function(String choice)? onPick;
  final Stream<LiveBoard>? boards;
  final String? uid;
  final String? refusal;
  final Stream<AllTimeBoard>? allTime;
  final Stream<AllTimeBoard>? bots;

  /// Built with the Player's score when a Round ends, if they should be asked
  /// to keep it.
  final Widget Function(int score)? savePrompt;

  /// Scoring bounds, so the meter shows real numbers rather than a guess.
  final ({int max, int min}) points;

  /// This Player's own result for the Round that just ended.
  final ({int score, int correct, int rank})? mine;
  final LiveBoard live;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final wide = boards != null && box.maxWidth >= Broadcast.floorBreakpoint;

      final board = boards == null
          ? null
          : _Board(
              live: live,
              allTime: allTime,
              bots: bots,
              uid: uid,
              onOpenProfile: onOpenProfile,
              // In the rail there is room for the whole board all the time;
              // in the cabinet there is only room for the top few until a
              // Round ends.
              compact: !wide && !round.inIntermission,
              savePrompt: round.inIntermission ? savePrompt : null,
            );

      final stage = round.inIntermission
          ? _Intermission(
              round: round,
              clock: clock,
              mine: mine,
              slots: round.slotCount,
              compact: !wide,
            )
          : _Stage(
              question: round.question!,
              clock: clock,
              picked: picked,
              state: state,
              lockedPoints: lockedPoints,
              onPick: onPick,
              points: points,
              isLastSlot: round.question!.slot >= round.slotCount - 1,
              wide: wide,
            );

      return wide
          ? _StudioFloor(
              round: round,
              handle: handle,
              onOpenProfile: onOpenProfile,
              refusal: refusal,
              stage: stage,
              board: board!,
            )
          : _Cabinet(
              round: round,
              handle: handle,
              onOpenProfile: onOpenProfile,
              refusal: refusal,
              stage: stage,
              board: board,
            );
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Studio floor
// ─────────────────────────────────────────────────────────────────────────────

/// The wide layout: a header band, the stage under it, the standings running
/// down the right-hand edge for the full height of the set.
///
/// Everything fills the window. The old layout centred a fixed-height block
/// and left a third of a desktop screen as empty set below it, which on a
/// broadcast reads as the picture having stopped.
class _StudioFloor extends StatelessWidget {
  const _StudioFloor({
    required this.round,
    required this.handle,
    required this.onOpenProfile,
    required this.refusal,
    required this.stage,
    required this.board,
  });

  final LiveRound round;
  final String? handle;
  final void Function(String? uid)? onOpenProfile;
  final String? refusal;
  final Widget stage;
  final Widget board;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Broadcast.podiumEdge, width: 2),
          ),
        ),
        child: Row(
          children: [
            const _Wordmark(size: 26),
            const SizedBox(width: 18),
            const _OnAir(),
            Expanded(child: _ThemeChip(round: round)),
            if (onOpenProfile != null) ...[
              const SizedBox(width: 22),
              _YouButton(handle: handle ?? '', onTap: onOpenProfile),
            ],
          ],
        ),
      ),
      if (refusal != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
          child: _Refused(reason: refusal!),
        ),
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _BackWall(theme: round.theme, size: 420),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 22, 6, 22),
                    child: stage,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 16, 18, 18),
              child: SizedBox(
                width: Broadcast.rail,
                child: SingleChildScrollView(child: board),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Cabinet
// ─────────────────────────────────────────────────────────────────────────────

/// The narrow layout: one upright column with the set visible around it.
///
/// The same screen on a phone and on a laptop in a small window, so there is
/// only ever one narrow design to keep honest.
class _Cabinet extends StatelessWidget {
  const _Cabinet({
    required this.round,
    required this.handle,
    required this.onOpenProfile,
    required this.refusal,
    required this.stage,
    required this.board,
  });

  final LiveRound round;
  final String? handle;
  final void Function(String? uid)? onOpenProfile;
  final String? refusal;
  final Widget stage;
  final Widget? board;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      // Flush to the edges on a phone; a standing cabinet once there is set
      // either side of it to stand against.
      final framed = box.maxWidth > Broadcast.cabinet + 40;
      return Center(
        child: Container(
          width: framed ? Broadcast.cabinet : double.infinity,
          margin: framed
              ? const EdgeInsets.symmetric(vertical: 16)
              : EdgeInsets.zero,
          decoration: framed
              ? BoxDecoration(
                  color: Broadcast.setDeep.withValues(alpha: 0.7),
                  border: Border.all(color: Broadcast.podiumEdge, width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x88000512),
                      blurRadius: 40,
                      spreadRadius: 8,
                    ),
                  ],
                )
              : null,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Broadcast.podiumEdge, width: 2),
                  ),
                ),
                child: Row(
                  children: [
                    const Flexible(child: _Wordmark(size: 20)),
                    const SizedBox(width: 10),
                    const _OnAir(),
                    const Spacer(),
                    if (onOpenProfile != null)
                      Flexible(
                        child: _YouButton(
                          handle: handle ?? '',
                          onTap: onOpenProfile,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                  child: Column(
                    children: [
                      _ThemeChip(round: round, centred: true),
                      if (refusal != null) _Refused(reason: refusal!),
                      const SizedBox(height: 12),
                      stage,
                      if (board != null) ...[
                        const SizedBox(height: 14),
                        board!,
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// The stage
// ─────────────────────────────────────────────────────────────────────────────

/// Prompt, readout, podiums — one of four phases at a time.
///
/// Every element has a fixed box, so nothing moves when a Question is two
/// lines instead of three, or when the Choices arrive, or when a phase
/// changes. Things appearing should not shove what is already on screen.
class _Stage extends StatelessWidget {
  const _Stage({
    required this.question,
    required this.clock,
    required this.picked,
    required this.state,
    required this.lockedPoints,
    required this.onPick,
    required this.points,
    required this.isLastSlot,
    required this.wide,
  });

  final OpenQuestion question;
  final ServerClock clock;
  final String? picked;
  final Answered state;
  final int lockedPoints;
  final void Function(String choice)? onPick;

  /// Scoring bounds, so the readout shows real numbers rather than a guess.
  final ({int max, int min}) points;

  /// Nothing follows this Slot but the Intermission.
  final bool isLastSlot;

  final bool wide;

  @override
  Widget build(BuildContext context) {
    final now = clock.nowMs;
    final phase = question.phaseAt(now);

    final podiums = _Podiums(
      // Choices stay hidden while the prompt is being read. Showing them
      // greyed out just means everyone reads them anyway and the read phase
      // becomes a stare. The podiums are still drawn, empty, so that the
      // Choices arriving does not shove the screen upward.
      ghost: phase == Phase.read,
      settling: question.settlingAt(now),
      choices: question.choices,
      grid: wide,
      picked: picked,
      state: state,
      phase: phase,
      correct: question.correct,
      lockedPoints: lockedPoints,
      onPick: phase == Phase.answer ? onPick : null,
    );

    final readout = _PhaseReadout(
      question: question,
      phase: phase,
      now: now,
      points: points,
      isLastSlot: isLastSlot,
      size: wide ? 52 : 38,
    );

    // A prompt is read fastest at roughly forty characters a line; the full
    // width of the stage runs long enough that the eye loses the start of the
    // next line.
    final prompt = _Prompt(text: question.prompt, size: wide ? 30 : 21);

    if (!wide) {
      return Column(
        children: [
          SizedBox(
            height: Broadcast.promptBox,
            child: Center(child: prompt),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: Broadcast.phaseBox,
            child: Center(child: readout),
          ),
          const SizedBox(height: 12),
          podiums,
        ],
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxHeight: Broadcast.stageHeight,
          maxWidth: Broadcast.stageWidth,
        ),
        child: Column(
          children: [
            Expanded(flex: 4, child: Center(child: prompt)),
            Expanded(flex: 3, child: Center(child: readout)),
            podiums,
          ],
        ),
      ),
    );
  }
}

class _Prompt extends StatelessWidget {
  const _Prompt({required this.text, required this.size});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 680),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Broadcast.body(size, weight: FontWeight.w700).copyWith(
            height: 1.2,
            shadows: const [
              Shadow(
                color: Color(0xCC00030F),
                offset: Offset(0, 2),
                blurRadius: 10,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The one loud thing on screen, and what it says depends on the phase.
class _PhaseReadout extends StatelessWidget {
  const _PhaseReadout({
    required this.question,
    required this.phase,
    required this.now,
    required this.points,
    required this.isLastSlot,
    required this.size,
  });

  final OpenQuestion question;
  final Phase phase;
  final int now;
  final ({int max, int min}) points;
  final bool isLastSlot;
  final double size;

  @override
  Widget build(BuildContext context) => switch (phase) {
    Phase.read => _Counter(
      seconds: ((question.opensAt - now) / 1000).ceil().clamp(0, 999),
      label: 'read it',
      colour: Broadcast.cyan,
      size: size,
    ),
    Phase.answer => _PointsMeter(
      question: question,
      now: now,
      points: points,
      size: size,
    ),
    // The moment the clock stops, the screen says the answer is coming. There
    // used to be a "checking…" stage in between while the server scored the
    // Round; the server publishes the answer first now, so announcing a stage
    // that lasts a few hundred milliseconds only puts a flicker where the
    // reveal should be.
    Phase.reveal => _Counter(
      seconds: ((question.revealUntil - now) / 1000).ceil().clamp(0, 999),
      label: 'the answer is',
      colour: Broadcast.gold,
      size: size,
    ),
    // After the last Slot there is no next Question, and counting down to one
    // — then sitting on nought while the scores are worked out — says the
    // wrong thing twice over.
    Phase.idle when isLastSlot => Text(
      "that's the round",
      style: Broadcast.display(size * 0.42, color: Broadcast.cyan),
    ),
    Phase.idle => _Counter(
      seconds: ((question.endsAt - now) / 1000).ceil().clamp(0, 999),
      label: 'next question in',
      colour: Broadcast.chalkDim,
      size: size,
    ),
  };
}

class _Counter extends StatelessWidget {
  const _Counter({
    required this.seconds,
    required this.label,
    required this.colour,
    required this.size,
  });

  final int seconds;
  final String label;
  final Color colour;
  final double size;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '$seconds',
        style: Broadcast.display(size, color: colour).copyWith(
          shadows: [
            Shadow(color: colour.withValues(alpha: 0.5), blurRadius: 20),
          ],
        ),
      ),
      const SizedBox(height: 2),
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
    required this.size,
  });

  final OpenQuestion question;
  final int now;
  final ({int max, int min}) points;
  final double size;

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
          style: Broadcast.display(size, color: colour).copyWith(
            shadows: [
              Shadow(color: colour.withValues(alpha: 0.5), blurRadius: 20),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'points, ${seconds}s left',
          style: Broadcast.body(11, color: Broadcast.chalkDim),
        ),
        const SizedBox(height: 8),
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
                    // The empty cells have to be visible, or the meter reads
                    // as a floating blob drifting left rather than a gauge
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
    required this.grid,
    required this.picked,
    required this.state,
    required this.phase,
    required this.correct,
    required this.lockedPoints,
    required this.onPick,
    this.ghost = false,
    this.settling = false,
  });

  final List<String> choices;

  /// Two across, two down. Otherwise they stack.
  final bool grid;
  final String? picked;
  final Answered state;
  final Phase phase;
  final String? correct;
  final int lockedPoints;
  final void Function(String choice)? onPick;

  /// Draw the podiums with their Choices withheld, at exactly the size they
  /// will be once shown.
  final bool ghost;

  /// The Window has shut but the answer has not arrived. Nothing is right or
  /// wrong yet.
  final bool settling;

  Widget _tile(int i) => _Podium(
    index: i,
    label: choices[i],
    ghost: ghost,
    settling: settling,
    lockedPoints: lockedPoints,
    chosen: picked == choices[i],
    state: state,
    phase: phase,
    isCorrect: correct != null && choices[i] == correct,
    onTap: onPick == null || state != Answered.no
        ? null
        : () => onPick!(choices[i]),
  );

  @override
  Widget build(BuildContext context) {
    if (!grid) {
      return Column(
        children: [
          for (var i = 0; i < choices.length; i++) ...[
            if (i > 0) const SizedBox(height: 9),
            _tile(i),
          ],
        ],
      );
    }
    return Column(
      children: [
        for (var row = 0; row * 2 < choices.length; row++) ...[
          if (row > 0) const SizedBox(height: 11),
          // Both podiums in a row take the taller one's height, so a Choice
          // that wraps to two lines does not leave its neighbour short.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var col = 0; col < 2; col++) ...[
                  if (col > 0) const SizedBox(width: 11),
                  Expanded(
                    child: row * 2 + col < choices.length
                        ? _tile(row * 2 + col)
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
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
    required this.lockedPoints,
    this.ghost = false,
    this.settling = false,
  });

  final int index;
  final String label;
  final bool chosen;
  final Answered state;
  final Phase phase;
  final bool isCorrect;
  final int lockedPoints;
  final VoidCallback? onTap;

  /// Same podium, Choice withheld — the read phase.
  final bool ghost;

  /// Waiting for the answer: hold the pre-reveal look rather than calling
  /// every Choice wrong because none of them is marked right yet.
  final bool settling;

  static const _keys = ['1', '2', '3', '4'];
  static const _right = Color(0xFF35D17E);

  /// A verdict needs an answer to compare against.
  ///
  /// Between the Window shutting and the answer being published, `correct` is
  /// null — and treating that as a reveal marked the Player's own pick "not
  /// this one" a second before the right Choice lit up.
  bool get _revealing =>
      !settling && (phase == Phase.reveal || phase == Phase.idle);

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

  /// The numbered cap.
  ///
  /// Locking in is not a verdict, so it stays gold: the colour only changes
  /// when there is something to say, which is green for the answer and magenta
  /// for a pick that missed.
  Color get _cap {
    if (_revealing) {
      if (isCorrect) return _right;
      if (chosen) return Broadcast.magenta;
      return Broadcast.gold;
    }
    if (chosen && state == Answered.rejected) return Broadcast.magenta;
    return Broadcast.gold;
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
      // The score pops instead for a Choice that came good.
      if (isCorrect && chosen) return null;
      if (isCorrect) return 'correct';
      if (chosen) return 'not this one';
      return null;
    }
    if (!chosen) return null;
    return switch (state) {
      // The number is what was at stake, so it is what gets shown back.
      Answered.sending => 'locked in',
      Answered.sent => 'locked in $lockedPoints',
      Answered.rejected => 'too late',
      Answered.no => null,
    };
  }

  /// The moment a locked-in Choice turns out to be right.
  bool get _won => _revealing && isCorrect && chosen && lockedPoints > 0;

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
                    decoration: BoxDecoration(color: _cap),
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
                            child: Text(label, style: Broadcast.body(17)),
                          )
                        : Text(
                            label,
                            style: Broadcast.body(17, weight: FontWeight.w600),
                          ),
                  ),
                  if (_won)
                    _ScorePop(points: lockedPoints)
                  else if (tag != null)
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

// ─────────────────────────────────────────────────────────────────────────────
// Header parts
// ─────────────────────────────────────────────────────────────────────────────

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => FittedBox(
    alignment: Alignment.centerLeft,
    fit: BoxFit.scaleDown,
    child: Text(
      "const's quizzes",
      style: Broadcast.display(size).copyWith(
        shadows: const [
          Shadow(color: Broadcast.goldDeep, offset: Offset(0, 3)),
          Shadow(color: Broadcast.magenta, offset: Offset(2, 5)),
        ],
      ),
    ),
  );
}

/// The light that says this is happening right now.
class _OnAir extends StatelessWidget {
  const _OnAir();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: const BoxDecoration(
          color: Broadcast.magenta,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Broadcast.magenta, blurRadius: 10)],
        ),
      ),
      const SizedBox(width: 6),
      Text('on air', style: Broadcast.body(12, color: Broadcast.chalkDim)),
    ],
  );
}

/// The Theme and how far through the Round it is, stated once.
///
/// It used to be stated twice — a strip across the top and a card in the rail
/// saying the same three facts thirty pixels apart.
class _ThemeChip extends StatelessWidget {
  const _ThemeChip({required this.round, this.centred = false});

  final LiveRound round;
  final bool centred;

  @override
  Widget build(BuildContext context) {
    final slot = round.openSlot;
    final counter = slot < 0
        ? 'between rounds'
        : 'question ${slot + 1} of ${round.slotCount}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: centred
          ? MainAxisAlignment.center
          : MainAxisAlignment.end,
      children: [
        if (!centred) const SizedBox(width: 24),
        ThemeIcon(theme: round.theme, size: 20, color: Broadcast.cyan),
        const SizedBox(width: 9),
        Flexible(
          child: Text(
            round.theme,
            overflow: TextOverflow.ellipsis,
            style: Broadcast.body(14, color: Broadcast.cyan),
          ),
        ),
        const SizedBox(width: 14),
        Text(counter, style: Broadcast.body(13, color: Broadcast.chalkDim)),
      ],
    );
  }
}

/// The Theme's mark, blown up on the back wall of the set.
///
/// A game show puts the category on the wall behind the contestants. Here it
/// does the work a duplicate card used to: it says what the Round is about,
/// and it gives the widest part of the set something to be.
class _BackWall extends StatelessWidget {
  const _BackWall({required this.theme, required this.size});

  final String theme;
  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Opacity(
      opacity: 0.05,
      child: ThemeIcon(theme: theme, size: size, color: Broadcast.chalk),
    ),
  );
}

/// The way in to your own page.
///
/// Your Handle doubles as the button: it is already the thing on screen that
/// means "you", so adding a separate icon beside it would be two of the same
/// signpost.
class _YouButton extends StatelessWidget {
  const _YouButton({required this.handle, required this.onTap});

  final String handle;
  final void Function(String? uid)? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'your page',
    child: InkWell(
      onTap: onTap == null ? null : () => onTap!(null),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person, size: 15, color: Broadcast.cyan),
            if (handle.isNotEmpty) ...[
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  handle,
                  overflow: TextOverflow.ellipsis,
                  style: Broadcast.body(12, color: Broadcast.cyan),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Intermission
// ─────────────────────────────────────────────────────────────────────────────

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
    required this.compact,
  });

  final LiveRound round;
  final ServerClock clock;

  /// This Player's own result, absent if they did not answer anything.
  final ({int score, int correct, int rank})? mine;
  final int slots;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final left = ((round.nextRoundAt - clock.nowMs) / 1000).ceil().clamp(
      0,
      9999,
    );
    final next = round.nextTheme;
    final me = mine;

    final card = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (me != null) ...[
          Text(
            'that round',
            style: Broadcast.body(12, color: Broadcast.chalkDim),
          ),
          const SizedBox(height: 4),
          Text(
            '${me.score}',
            style: Broadcast.display(compact ? 40 : 54, color: Broadcast.gold)
                .copyWith(
                  shadows: [
                    Shadow(
                      color: Broadcast.gold.withValues(alpha: 0.4),
                      blurRadius: 26,
                    ),
                  ],
                ),
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
        SizedBox(height: compact ? 18 : 28),
        if (next != null) ...[
          Text('next up', style: Broadcast.body(11, color: Broadcast.chalkDim)),
          const SizedBox(height: 10),
          ThemeIcon(theme: next, size: compact ? 42 : 52),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                next,
                textAlign: TextAlign.center,
                style: Broadcast.display(
                  compact ? 19 : 22,
                  color: Broadcast.gold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        Text(
          '$left',
          style: Broadcast.display(compact ? 30 : 36, color: Broadcast.cyan),
        ),
        Text('seconds', style: Broadcast.body(11, color: Broadcast.chalkDim)),
      ],
    );
    return compact ? card : Center(child: SingleChildScrollView(child: card));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Standings
// ─────────────────────────────────────────────────────────────────────────────

/// The standings, as a short list in the cabinet and a full-height rail on the
/// studio floor.
class _Board extends StatefulWidget {
  const _Board({
    required this.live,
    required this.allTime,
    required this.bots,
    required this.uid,
    required this.compact,
    required this.savePrompt,
    this.onOpenProfile,
  });

  final LiveBoard live;
  final Stream<AllTimeBoard>? allTime;
  final Stream<AllTimeBoard>? bots;
  final String? uid;
  final bool compact;
  final Widget Function(int score)? savePrompt;

  /// Opens the page of whoever is tapped in the standings.
  final void Function(String? uid)? onOpenProfile;

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
      return _AllTimePanel(
        careers: _view == 1 ? _careers : _botBoard,
        uid: widget.uid,
        onOpenProfile: widget.onOpenProfile,
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
    }
    final mine = widget.live.top.where((s) => s.uid == widget.uid).firstOrNull;
    final prompt = widget.savePrompt;
    final panel = _RoundPanel(
      board: widget.live,
      uid: widget.uid,
      onOpenProfile: widget.onOpenProfile,
      compact: widget.compact,
      onAllTime: canSwitch ? () => setState(() => _view = 1) : null,
    );
    // Only worth asking somebody who actually scored something.
    final ask = prompt != null && mine != null && mine.score > 0
        ? prompt(mine.score)
        : null;
    if (ask == null) return panel;
    return Column(mainAxisSize: MainAxisSize.min, children: [panel, ask]);
  }
}

/// The frame every standings panel shares: a lit box with a ruled heading.
class _Panel extends StatelessWidget {
  const _Panel({required this.heading, required this.rows});

  final Widget heading;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    decoration: BoxDecoration(
      color: Broadcast.setDeep.withValues(alpha: 0.62),
      border: Border.all(color: Broadcast.podiumEdge, width: 2),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading,
        const SizedBox(height: 5),
        Container(height: 2, color: Broadcast.podiumEdge),
        const SizedBox(height: 6),
        ...rows,
      ],
    ),
  );
}

class _RoundPanel extends StatelessWidget {
  const _RoundPanel({
    required this.board,
    required this.uid,
    required this.onOpenProfile,
    required this.compact,
    required this.onAllTime,
  });

  final LiveBoard board;
  final String? uid;
  final void Function(String? uid)? onOpenProfile;
  final bool compact;
  final VoidCallback? onAllTime;

  @override
  Widget build(BuildContext context) {
    // The panel is drawn whether or not anyone has scored. An empty board used
    // to collapse to a bare line of grey text, which in the rail read as a
    // stray caption rather than the standings waiting to fill up.
    // Three fits in the cabinet mid-Round; the rail has room for a real list.
    final shown = board.top.take(compact ? 3 : 12).toList();
    return _Panel(
      heading: Row(
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
      rows: [
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'nobody has answered yet',
              style: Broadcast.body(12, color: Broadcast.chalkDim),
            ),
          ),
        for (final (i, s) in shown.indexed)
          _StandingRow(
            place: i + 1,
            handle: s.handle,
            trailing: '${s.score}',
            isMe: s.uid == uid,
            onTap: onOpenProfile == null ? null : () => onOpenProfile!(s.uid),
          ),
      ],
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
    required this.onOpenProfile,
    required this.title,
    required this.emptyLine,
    required this.nextLabel,
    required this.onNext,
    required this.onBack,
  });

  final AllTimeBoard careers;
  final String? uid;
  final void Function(String? uid)? onOpenProfile;
  final String title;
  final String emptyLine;
  final String nextLabel;
  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => _Panel(
    heading: Row(
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
    rows: [
      if (careers.top.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            emptyLine,
            style: Broadcast.body(12, color: Broadcast.chalkDim),
          ),
        ),
      for (final (i, c) in careers.top.indexed)
        _StandingRow(
          place: i + 1,
          handle: c.handle,
          subtitle: 'best ${c.bestRound}',
          trailing: '${c.averageScore}',
          isMe: c.uid == uid,
          onTap: onOpenProfile == null ? null : () => onOpenProfile!(c.uid),
        ),
    ],
  );
}

/// One line of the standings, and a way into that Player's page.
///
/// A name on a leaderboard is the one place you actually wonder who somebody
/// is, so the row is the button rather than putting a separate control beside
/// it.
class _StandingRow extends StatelessWidget {
  const _StandingRow({
    required this.place,
    required this.handle,
    required this.trailing,
    required this.isMe,
    required this.onTap,
    this.subtitle,
  });

  final int place;
  final String handle;
  final String trailing;
  final String? subtitle;
  final bool isMe;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    label: '$handle, $trailing',
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3.5),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(
                '$place',
                style: Broadcast.body(
                  12,
                  color: place <= 3 ? Broadcast.gold : Broadcast.chalkDim,
                ),
              ),
            ),
            Expanded(
              child: Text(
                handle,
                overflow: TextOverflow.ellipsis,
                style: Broadcast.body(
                  13,
                  color: isMe ? Broadcast.magenta : Broadcast.chalk,
                ),
              ),
            ),
            if (subtitle != null) ...[
              Text(
                subtitle!,
                style: Broadcast.body(11, color: Broadcast.chalkDim),
              ),
              const SizedBox(width: 10),
            ],
            Text(trailing, style: Broadcast.body(13, color: Broadcast.gold)),
          ],
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Odds and ends
// ─────────────────────────────────────────────────────────────────────────────

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
        'Lots of people arriving at once. Reload in a moment to take a seat.',
      _ => "The show is on a break. You're watching; answering is off for now.",
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

/// The points landing, the way a hit lands in a role-playing game.
///
/// It rises and fades rather than simply appearing, because the whole appeal
/// of answering fast is watching the number you beat the clock for actually
/// arrive. A static label says the same thing and none of the same thing.
class _ScorePop extends StatelessWidget {
  const _ScorePop({required this.points});

  final int points;

  static const _right = Color(0xFF35D17E);

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    key: ValueKey(points),
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 900),
    curve: Curves.easeOutCubic,
    builder: (context, t, child) {
      // Up and out: full opacity almost all the way, then a quick fade, so
      // the number is readable for as long as it is moving.
      final rise = -18 * Curves.easeOutBack.transform(t.clamp(0, 1));
      final fade = t < 0.7 ? 1.0 : 1 - ((t - 0.7) / 0.3);
      return Transform.translate(
        offset: Offset(0, rise),
        child: Opacity(opacity: fade.clamp(0, 1), child: child),
      );
    },
    child: Text(
      '+$points',
      style: Broadcast.display(19, color: _right).copyWith(
        shadows: [Shadow(color: _right.withValues(alpha: 0.6), blurRadius: 14)],
      ),
    ),
  );
}
