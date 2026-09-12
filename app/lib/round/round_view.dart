import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/save_prompt.dart';
import '../theme/broadcast.dart';
import 'answering.dart';
import 'leaderboard.dart';
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
    this.refusal,
    this.allTime,
    this.anonymous = false,
  });

  final Stream<LiveRound?> rounds;
  final ServerClock clock;
  final String? handle;

  /// Absent for a visitor who is only watching.
  final AnswerSink? sink;

  final Stream<LiveBoard>? boards;

  /// Used only to pick this Player out of the standings.
  final String? uid;

  /// Why this visitor cannot answer: 'full', 'closed', or absent if they can.
  final String? refusal;

  final Stream<AllTimeBoard>? allTime;

  /// Whether to offer to save this Player's progress once a Round ends well.
  final bool anonymous;

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

  @override
  void initState() {
    super.initState();
    _ticker;
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
                    _resetIfNewSlot(round);
                    return _Broadcast(
                      round: round,
                      clock: widget.clock,
                      handle: widget.handle,
                      picked: _picked,
                      state: _state,
                      onPick: widget.sink == null
                          ? null
                          : (choice) => _answer(round, choice),
                      boards: widget.boards,
                      uid: widget.uid,
                      refusal: widget.refusal,
                      allTime: widget.allTime,
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
  Widget build(BuildContext context) => Center(
        child: Text('Tuning in…', style: Broadcast.display(22)),
      );
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
    required this.savePrompt,
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

  /// Built with the Player's score when a Round ends, if they should be asked
  /// to keep it.
  final Widget Function(int score)? savePrompt;

  @override
  Widget build(BuildContext context) {
    final q = round.question;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Broadcast.wide),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              _Marquee(handle: handle),
              const SizedBox(height: 14),
              _ThemeStrip(round: round),
              if (refusal != null) _Refused(reason: refusal!),
              const SizedBox(height: 8),
              Expanded(
                child: round.inIntermission
                    ? _Intermission(round: round, clock: clock)
                    : _Stage(
                        question: q!,
                        clock: clock,
                        picked: picked,
                        state: state,
                        onPick: onPick,
                      ),
              ),
              if (boards != null)
                _Board(
                  boards: boards!,
                  allTime: allTime,
                  uid: uid,
                  compact: !round.inIntermission,
                  savePrompt: round.inIntermission ? savePrompt : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The show's name, and the light that says this is happening right now.
class _Marquee extends StatelessWidget {
  const _Marquee({required this.handle});

  final String? handle;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text(
                "const's quizzes",
                style: Broadcast.display(30).copyWith(
                  shadows: const [
                    Shadow(color: Broadcast.goldDeep, offset: Offset(0, 3)),
                    Shadow(color: Broadcast.magenta, offset: Offset(2, 5)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
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
          if (handle != null) ...[
            const SizedBox(width: 14),
            Flexible(
              child: Text(
                handle!,
                overflow: TextOverflow.ellipsis,
                style: Broadcast.body(12, color: Broadcast.cyan),
              ),
            ),
          ],
        ],
      );
}

class _ThemeStrip extends StatelessWidget {
  const _ThemeStrip({required this.round});

  final LiveRound round;

  @override
  Widget build(BuildContext context) {
    final slot = round.openSlot;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Broadcast.podium,
        border: Border.all(color: Broadcast.podiumEdge, width: 2),
        boxShadow: Broadcast.bevel,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              round.theme,
              overflow: TextOverflow.ellipsis,
              style: Broadcast.body(13, color: Broadcast.cyan),
            ),
          ),
          Text(
            slot < 0 ? 'between rounds' : 'question ${slot + 1} of ${round.slotCount}',
            style: Broadcast.body(13, color: Broadcast.chalkDim),
          ),
        ],
      ),
    );
  }
}

/// Question, clock, podiums.
class _Stage extends StatelessWidget {
  const _Stage({
    required this.question,
    required this.clock,
    required this.picked,
    required this.state,
    required this.onPick,
  });

  final OpenQuestion question;
  final ServerClock clock;
  final String? picked;
  final Answered state;
  final void Function(String choice)? onPick;

  @override
  Widget build(BuildContext context) {
    final now = clock.nowMs;
    final locked = now < question.opensAt;
    final remaining = ((question.closesAt - now) / 1000).ceil().clamp(0, 999);

    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth < 520;
        return Column(
          children: [
            const SizedBox(height: 18),
            Flexible(
              child: Center(
                child: Text(
                  question.prompt,
                  textAlign: TextAlign.center,
                  style: Broadcast.body(
                    narrow ? 21 : 27,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _Clock(seconds: remaining, locked: locked),
            const SizedBox(height: 16),
            _Podiums(
              choices: question.choices,
              narrow: narrow,
              locked: locked,
              picked: picked,
              state: state,
              onPick: onPick,
            ),
            const SizedBox(height: 10),
          ],
        );
      },
    );
  }
}

/// The one loud thing on screen.
class _Clock extends StatelessWidget {
  const _Clock({required this.seconds, required this.locked});

  final int seconds;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final colour = locked
        ? Broadcast.cyan
        : seconds <= 3
            ? Broadcast.magenta
            : Broadcast.gold;
    return Column(
      children: [
        Text(
          '$seconds',
          style: Broadcast.display(54, color: colour).copyWith(
            shadows: [Shadow(color: colour.withValues(alpha: 0.55), blurRadius: 22)],
          ),
        ),
        Text(
          locked ? 'read it' : 'answering',
          style: Broadcast.body(11, color: Broadcast.chalkDim),
        ),
      ],
    );
  }
}

class _Podiums extends StatelessWidget {
  const _Podiums({
    required this.choices,
    required this.narrow,
    required this.locked,
    required this.picked,
    required this.state,
    required this.onPick,
  });

  final List<String> choices;
  final bool narrow;
  final bool locked;
  final String? picked;
  final Answered state;
  final void Function(String choice)? onPick;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      for (final (i, choice) in choices.indexed)
        _Podium(
          index: i,
          label: choice,
          dimmed: locked,
          chosen: picked == choice,
          state: state,
          onTap: locked || onPick == null || state != Answered.no
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
      children: [
        for (final t in tiles) SizedBox(width: 330, child: t),
      ],
    );
  }
}

/// A contestant's podium: a face, a bevel, and a hard shadow under it.
class _Podium extends StatelessWidget {
  const _Podium({
    required this.index,
    required this.label,
    required this.dimmed,
    required this.chosen,
    required this.state,
    required this.onTap,
  });

  final int index;
  final String label;
  final bool dimmed;
  final bool chosen;
  final Answered state;
  final VoidCallback? onTap;

  static const _keys = ['1', '2', '3', '4'];

  Color get _edge {
    if (!chosen) return Broadcast.podiumEdge;
    return switch (state) {
      Answered.rejected => Broadcast.magenta,
      _ => Broadcast.gold,
    };
  }

  @override
  Widget build(BuildContext context) => Semantics(
        button: onTap != null,
        selected: chosen,
        label: label,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: dimmed ? 0.45 : 1,
          child: Material(
            color: chosen ? Broadcast.setNavy : Broadcast.podium,
            child: InkWell(
              onTap: onTap,
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: _edge, width: chosen ? 3 : 2),
                  boxShadow: Broadcast.bevel,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: chosen ? Broadcast.magenta : Broadcast.gold,
                      ),
                      child: Text(
                        _keys[index],
                        style: Broadcast.body(13,
                            color: Broadcast.setDeep, weight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(label, style: Broadcast.body(15))),
                    if (chosen)
                      Text(
                        switch (state) {
                          Answered.sending => 'sending',
                          Answered.sent => 'locked in',
                          Answered.rejected => 'too late',
                          Answered.no => '',
                        },
                        style: Broadcast.body(11,
                            color: state == Answered.rejected
                                ? Broadcast.magenta
                                : Broadcast.gold),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class _Intermission extends StatelessWidget {
  const _Intermission({required this.round, required this.clock});

  final LiveRound round;
  final ServerClock clock;

  @override
  Widget build(BuildContext context) {
    final left = ((round.nextRoundAt - clock.nowMs) / 1000).ceil().clamp(0, 9999);
    final next = round.nextTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('final scores',
              style: Broadcast.body(16, color: Broadcast.chalkDim)),
          const SizedBox(height: 14),
          if (next != null) ...[
            Text('next up', style: Broadcast.body(12, color: Broadcast.chalkDim)),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  next,
                  textAlign: TextAlign.center,
                  style: Broadcast.display(24, color: Broadcast.gold),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Text('$left', style: Broadcast.display(48, color: Broadcast.cyan)),
          Text('seconds', style: Broadcast.body(12, color: Broadcast.chalkDim)),
        ],
      ),
    );
  }
}


/// The standings, as a ticker under the stage during a Round and opened out
/// during the Intermission, when there is nothing else to look at.
class _Board extends StatefulWidget {
  const _Board({
    required this.boards,
    required this.allTime,
    required this.uid,
    required this.compact,
    required this.savePrompt,
  });

  final Stream<LiveBoard> boards;
  final Stream<AllTimeBoard>? allTime;
  final String? uid;
  final bool compact;
  final Widget Function(int score)? savePrompt;

  @override
  State<_Board> createState() => _BoardState();
}

/// Holds both boards open at once and renders whichever is being looked at.
///
/// Switching view does not resubscribe: a Firestore listener re-attached on
/// every toggle costs a fresh document read each time, and the two boards
/// together are two documents whatever the viewer does.
class _BoardState extends State<_Board> {
  late final StreamSubscription<LiveBoard> _liveSub;
  StreamSubscription<AllTimeBoard>? _careerSub;

  LiveBoard _live = LiveBoard.empty;
  AllTimeBoard _careers = AllTimeBoard.empty;
  bool _showAllTime = false;

  @override
  void initState() {
    super.initState();
    _liveSub = widget.boards.listen((b) {
      if (mounted) setState(() => _live = b);
    });
    _careerSub = widget.allTime?.listen((b) {
      if (mounted) setState(() => _careers = b);
    });
  }

  @override
  void dispose() {
    _liveSub.cancel();
    _careerSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The all-time board is only worth the room when a Round is not using it.
    final canSwitch = widget.allTime != null && !widget.compact;
    if (_showAllTime && canSwitch) {
      return _AllTimePanel(
        careers: _careers,
        uid: widget.uid,
        onBack: () => setState(() => _showAllTime = false),
      );
    }
    final mine = _live.top.where((s) => s.uid == widget.uid).firstOrNull;
    final prompt = widget.savePrompt;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RoundPanel(
          board: _live,
          uid: widget.uid,
          compact: widget.compact,
          onAllTime: canSwitch ? () => setState(() => _showAllTime = true) : null,
        ),
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
    if (board.top.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          board.playing == 0
              ? 'nobody has answered yet'
              : '${board.playing} playing',
          style: Broadcast.body(12, color: Broadcast.chalkDim),
        ),
      );
    }
    final shown = compact ? board.top.take(3).toList() : board.top;
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
              Text('leaders', style: Broadcast.body(12, color: Broadcast.gold)),
              Row(
                children: [
                  Text('${board.playing} playing',
                      style: Broadcast.body(12, color: Broadcast.chalkDim)),
                  if (onAllTime != null) ...[
                    const SizedBox(width: 10),
                    _BoardLink(label: 'all time', onTap: onAllTime!),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final (i, s) in shown.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text('${i + 1}',
                        style: Broadcast.body(12, color: Broadcast.chalkDim)),
                  ),
                  Expanded(
                    child: Text(
                      s.handle,
                      overflow: TextOverflow.ellipsis,
                      style: Broadcast.body(
                        13,
                        color: s.uid == uid ? Broadcast.magenta : Broadcast.chalk,
                      ),
                    ),
                  ),
                  Text('${s.score}',
                      style: Broadcast.body(13, color: Broadcast.gold)),
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
    required this.onBack,
  });

  final AllTimeBoard careers;
  final String? uid;
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
              Text('all time, by average round',
                  style: Broadcast.body(12, color: Broadcast.gold)),
              _BoardLink(label: 'this round', onTap: onBack),
            ],
          ),
          const SizedBox(height: 6),
          if (top.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Nobody has finished enough rounds yet.',
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
                    child: Text('${i + 1}',
                        style: Broadcast.body(12, color: Broadcast.chalkDim)),
                  ),
                  Expanded(
                    child: Text(
                      c.handle,
                      overflow: TextOverflow.ellipsis,
                      style: Broadcast.body(13,
                          color: c.uid == uid
                              ? Broadcast.magenta
                              : Broadcast.chalk),
                    ),
                  ),
                  Text('best ${c.bestRound}',
                      style: Broadcast.body(11, color: Broadcast.chalkDim)),
                  const SizedBox(width: 10),
                  Text('${c.averageScore}',
                      style: Broadcast.body(13, color: Broadcast.gold)),
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
        child: Text(
          switch (reason) {
            'full' => "This round is full — you're watching. "
                'A seat opens when the next round starts.',
            _ => "The show is on a break. You're watching; "
                'answering is off for now.',
          },
          style: Broadcast.body(12, color: Broadcast.chalk),
        ),
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
