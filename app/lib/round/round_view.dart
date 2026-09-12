import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/broadcast.dart';
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
  });

  final Stream<LiveRound?> rounds;
  final ServerClock clock;
  final String? handle;

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

  @override
  void initState() {
    super.initState();
    _ticker;
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
                    return _Broadcast(
                      round: snap.data!,
                      clock: widget.clock,
                      handle: widget.handle,
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
  });

  final LiveRound round;
  final ServerClock clock;
  final String? handle;

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
              const SizedBox(height: 8),
              Expanded(
                child: round.inIntermission
                    ? _Intermission(round: round, clock: clock)
                    : _Stage(question: q!, clock: clock),
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
  const _Stage({required this.question, required this.clock});

  final OpenQuestion question;
  final ServerClock clock;

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
            _Podiums(choices: question.choices, narrow: narrow, locked: locked),
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
  });

  final List<String> choices;
  final bool narrow;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      for (final (i, choice) in choices.indexed)
        _Podium(index: i, label: choice, dimmed: locked),
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
  });

  final int index;
  final String label;
  final bool dimmed;

  static const _keys = ['1', '2', '3', '4'];

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: dimmed ? 0.45 : 1,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: Broadcast.podium,
            border: Border.all(color: Broadcast.podiumEdge, width: 2),
            boxShadow: Broadcast.bevel,
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: Broadcast.gold),
                child: Text(
                  _keys[index],
                  style: Broadcast.body(13,
                      color: Broadcast.setDeep, weight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: Broadcast.body(15))),
            ],
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('that round is over',
              style: Broadcast.body(16, color: Broadcast.chalkDim)),
          const SizedBox(height: 12),
          Text('$left', style: Broadcast.display(48, color: Broadcast.cyan)),
          const SizedBox(height: 6),
          Text('until the next one', style: Broadcast.body(14)),
        ],
      ),
    );
  }
}
