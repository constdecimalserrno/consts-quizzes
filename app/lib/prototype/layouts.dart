// PROTOTYPE — throwaway. Not wired to Firebase, not shipped.
//
// Question it answers: what should the broadcast screen look like? Five
// structurally different layouts for the same Round, over six states of play,
// driven by fake data so every state can be held still and stared at.
//
// Run it:  flutter run -t lib/prototype/layouts.dart -d chrome
// Switch:  the bar at the bottom, or ← → for layout and ↑ ↓ for state.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/backdrop.dart';
import '../theme/broadcast.dart';
import '../theme/theme_icon.dart';

void main() => runApp(const PrototypeApp());

// ─────────────────────────────────────────────────────────────────────────────
// Fake state
// ─────────────────────────────────────────────────────────────────────────────

enum Shot { read, answer, locked, right, wrong, intermission }

extension ShotLabel on Shot {
  String get label => switch (this) {
    Shot.read => 'reading',
    Shot.answer => 'answering',
    Shot.locked => 'locked in',
    Shot.right => 'reveal · correct',
    Shot.wrong => 'reveal · wrong',
    Shot.intermission => 'intermission',
  };
}

/// Everything the layouts draw, pinned rather than clocked.
class Take {
  const Take(this.shot);

  final Shot shot;

  static const theme = 'Vehicles';
  static const nextTheme = 'Mythology';
  static const slot = 12;
  static const slots = 20;
  static const handle = 'peppy-jade-tiger-414';

  static const prompt =
      'What part of an automobile engine uses lobes to open and close intake '
      'and exhaust valves, and allows an air/fuel mixture into the engine?';

  static const choices = ['Piston', 'Drive shaft', 'Camshaft', 'Crankshaft'];

  bool get ghost => shot == Shot.read;
  bool get revealing => shot == Shot.right || shot == Shot.wrong;
  bool get live => shot == Shot.answer;
  bool get intermission => shot == Shot.intermission;

  String? get picked => switch (shot) {
    Shot.locked || Shot.right => 'Camshaft',
    Shot.wrong => 'Crankshaft',
    _ => null,
  };

  String? get correct => revealing ? 'Camshaft' : null;

  /// How much of the Window is left.
  double get remaining => switch (shot) {
    Shot.answer => 0.62,
    Shot.locked => 0.34,
    _ => 0,
  };

  int get worth => (100 + 900 * remaining).round();
  int get lockedPoints => 406;
  int get seconds => switch (shot) {
    Shot.read => 3,
    Shot.answer => 9,
    Shot.locked => 5,
    Shot.right || Shot.wrong => 4,
    Shot.intermission => 47,
  };

  /// The line under the loud number.
  String get phaseLabel => switch (shot) {
    Shot.read => 'read it',
    Shot.answer || Shot.locked => 'points, ${seconds}s left',
    Shot.right || Shot.wrong => 'the answer is',
    Shot.intermission => 'seconds',
  };

  static const board = [
    ('brisk-amber-lynx-902', 8420),
    ('peppy-jade-tiger-414', 7980),
    ('glum-rust-heron-117', 7310),
    ('sly-teal-otter-663', 6890),
    ('keen-plum-bison-245', 6240),
    ('drowsy-mint-crane-508', 5770),
    ('wry-coral-stoat-031', 5120),
    ('bold-slate-raven-877', 4680),
    ('daft-olive-shrew-390', 4150),
    ('sour-lilac-marten-726', 3890),
    ('brash-ochre-vole-284', 3460),
    ('calm-rose-ferret-955', 3010),
  ];

  static const playing = 214;
  static const myScore = 7980;
  static const myCorrect = 14;
  static const myRank = 2;
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared parts — components, never a layout
// ─────────────────────────────────────────────────────────────────────────────

/// One Choice. [big] fills a tile; otherwise it is a row you can stack.
class Podium extends StatelessWidget {
  const Podium({
    super.key,
    required this.index,
    required this.label,
    required this.take,
    this.big = false,
  });

  final int index;
  final String label;
  final Take take;
  final bool big;

  static const _keys = ['1', '2', '3', '4'];
  static const right = Color(0xFF35D17E);

  bool get _chosen => take.picked == label;
  bool get _isCorrect => take.correct == label;

  Color get _edge {
    if (take.ghost) return Broadcast.podiumEdge.withValues(alpha: 0.45);
    if (take.revealing) {
      if (_isCorrect) return right;
      if (_chosen) return Broadcast.magenta;
      return Broadcast.podiumEdge;
    }
    return _chosen ? Broadcast.gold : Broadcast.podiumEdge;
  }

  Color get _face => take.revealing && _isCorrect
      ? const Color(0xFF14402C)
      : _chosen
      ? Broadcast.setNavy
      : Broadcast.podium;

  /// Locking in is not a verdict, so the cap stays gold; only the reveal
  /// colours it — green for the answer, magenta for a pick that missed.
  Color get _key {
    if (!take.revealing) return Broadcast.gold;
    if (_isCorrect) return right;
    return _chosen ? Broadcast.magenta : Broadcast.gold;
  }

  double get _dim {
    if (take.ghost || !take.revealing) return 1;
    return _isCorrect || _chosen ? 1 : 0.5;
  }

  String? get _tag {
    if (take.ghost) return null;
    if (take.revealing) {
      if (_isCorrect && _chosen) return null;
      if (_isCorrect) return 'correct';
      if (_chosen) return 'not this one';
      return null;
    }
    return _chosen ? 'locked in ${take.lockedPoints}' : null;
  }

  @override
  Widget build(BuildContext context) {
    final won = take.revealing && _isCorrect && _chosen;
    final keyBox = big ? 34.0 : 26.0;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: _dim,
      child: Material(
        color: _face,
        child: InkWell(
          onTap: take.live ? () {} : null,
          child: Container(
            width: double.infinity,
            height: big ? double.infinity : null,
            padding: EdgeInsets.symmetric(
              horizontal: big ? 20 : 14,
              vertical: big ? 18 : 13,
            ),
            decoration: BoxDecoration(
              border: Border.all(
                color: _edge,
                width: _chosen || (take.revealing && _isCorrect) ? 3 : 2,
              ),
              boxShadow: Broadcast.bevel,
            ),
            child: big
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _keyCap(keyBox),
                          const Spacer(),
                          if (won)
                            ScorePop(points: take.lockedPoints)
                          else if (_tag != null)
                            Text(_tag!, style: Broadcast.body(12, color: _key)),
                        ],
                      ),
                      const Spacer(),
                      if (!take.ghost)
                        Text(
                          label,
                          style: Broadcast.body(24, weight: FontWeight.w700),
                        ),
                    ],
                  )
                : Row(
                    children: [
                      _keyCap(keyBox),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Opacity(
                          opacity: take.ghost ? 0 : 1,
                          child: Text(
                            label,
                            style: Broadcast.body(17, weight: FontWeight.w600),
                          ),
                        ),
                      ),
                      if (won)
                        ScorePop(points: take.lockedPoints)
                      else if (_tag != null)
                        Text(_tag!, style: Broadcast.body(11, color: _key)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _keyCap(double size) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: _key),
    child: Text(
      _keys[index],
      style: Broadcast.body(
        size * 0.5,
        color: Broadcast.setDeep,
        weight: FontWeight.w800,
      ),
    ),
  );
}

/// The points landing.
class ScorePop extends StatelessWidget {
  const ScorePop({super.key, required this.points});

  final int points;

  @override
  Widget build(BuildContext context) => Text(
    '+$points',
    style: Broadcast.display(20, color: Podium.right).copyWith(
      shadows: [
        Shadow(color: Podium.right.withValues(alpha: 0.6), blurRadius: 14),
      ],
    ),
  );
}

Color meterColour(double left) => left > 0.66
    ? Broadcast.gold
    : left > 0.33
    ? const Color(0xFFFF9A3C)
    : Broadcast.magenta;

/// The draining gauge, lying down.
class MeterBar extends StatelessWidget {
  const MeterBar({
    super.key,
    required this.left,
    this.cells = 28,
    this.cellWidth = 7,
    this.height = 14,
  });

  final double left;
  final int cells;
  final double cellWidth;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colour = meterColour(left);
    final filled = (left * cells).round().clamp(0, cells);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Broadcast.setDeep,
        border: Border.all(color: Broadcast.podiumEdge, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < cells; i++)
            Container(
              width: cellWidth,
              height: height,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              color: i < filled ? colour : const Color(0xFF243070),
            ),
        ],
      ),
    );
  }
}

/// The same gauge stood on end, for a layout that wants an edge to run it down.
class MeterColumn extends StatelessWidget {
  const MeterColumn({super.key, required this.left, this.cells = 22});

  final double left;
  final int cells;

  @override
  Widget build(BuildContext context) {
    final colour = meterColour(left);
    final filled = (left * cells).round().clamp(0, cells);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Broadcast.setDeep,
        border: Border.all(color: Broadcast.podiumEdge, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < cells; i++)
            Container(
              width: 16,
              height: 8,
              margin: const EdgeInsets.symmetric(vertical: 1),
              // Drains downward: the full cells sit at the bottom like a tank.
              color: i >= cells - filled ? colour : const Color(0xFF243070),
            ),
        ],
      ),
    );
  }
}

/// The loud number, whatever it currently counts.
class BigNumber extends StatelessWidget {
  const BigNumber({
    super.key,
    required this.value,
    required this.label,
    required this.colour,
    this.size = 46,
  });

  final String value;
  final String label;
  final Color colour;
  final double size;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        value,
        style: Broadcast.display(size, color: colour).copyWith(
          shadows: [
            Shadow(color: colour.withValues(alpha: 0.55), blurRadius: 22),
          ],
        ),
      ),
      const SizedBox(height: 2),
      Text(label, style: Broadcast.body(11, color: Broadcast.chalkDim)),
    ],
  );
}

/// What the phase is worth, in whichever form the layout asked for.
class PhaseReadout extends StatelessWidget {
  const PhaseReadout({
    super.key,
    required this.take,
    this.size = 46,
    this.meter = true,
    this.meterCells = 28,
  });

  final Take take;
  final double size;
  final bool meter;
  final int meterCells;

  @override
  Widget build(BuildContext context) {
    final showMeter = meter && (take.live || take.shot == Shot.locked);
    final colour = switch (take.shot) {
      Shot.read => Broadcast.cyan,
      Shot.answer || Shot.locked => meterColour(take.remaining),
      _ => Broadcast.gold,
    };
    final value = switch (take.shot) {
      Shot.read || Shot.right || Shot.wrong => '${take.seconds}',
      _ => '${take.worth}',
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BigNumber(
          value: value,
          label: take.phaseLabel,
          colour: colour,
          size: size,
        ),
        if (showMeter) ...[
          const SizedBox(height: 9),
          MeterBar(left: take.remaining, cells: meterCells),
        ],
      ],
    );
  }
}

/// The question itself, in a box that does not move between Questions.
class PromptBlock extends StatelessWidget {
  const PromptBlock({
    super.key,
    required this.text,
    this.size = 28,
    this.maxWidth = 660,
    this.align = TextAlign.center,
  });

  final String text;
  final double size;
  final double maxWidth;
  final TextAlign align;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth),
    child: Text(
      text,
      textAlign: align,
      style: Broadcast.body(size, weight: FontWeight.w700).copyWith(
        height: 1.2,
        shadows: const [
          Shadow(color: Color(0xCC00030F), offset: Offset(0, 2), blurRadius: 8),
        ],
      ),
    ),
  );
}

/// One line of the standings.
class StandingRow extends StatelessWidget {
  const StandingRow({
    super.key,
    required this.place,
    required this.handle,
    required this.score,
    this.isMe = false,
  });

  final int place;
  final String handle;
  final int score;
  final bool isMe;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3.5),
    child: Row(
      children: [
        SizedBox(
          width: 20,
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
        const SizedBox(width: 8),
        Text('$score', style: Broadcast.body(13, color: Broadcast.gold)),
      ],
    ),
  );
}

/// The standings as a panel, for layouts with a column to put it in.
class BoardPanel extends StatelessWidget {
  const BoardPanel({super.key, required this.rows, this.fill = false});

  final int rows;

  /// Stretch to the height offered, rather than sitting at its own height.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final list = Take.board.take(rows).toList();
    final body = Column(
      mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('leaders', style: Broadcast.body(12, color: Broadcast.gold)),
            Text(
              '${Take.playing} playing',
              style: Broadcast.body(12, color: Broadcast.chalkDim),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(height: 2, color: Broadcast.podiumEdge),
        const SizedBox(height: 6),
        for (final (i, row) in list.indexed)
          StandingRow(
            place: i + 1,
            handle: row.$1,
            score: row.$2,
            isMe: row.$1 == Take.handle,
          ),
        if (fill) const Spacer(),
        if (fill) ...[
          Container(height: 2, color: Broadcast.podiumEdge),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'this round',
                style: Broadcast.body(12, color: Broadcast.gold),
              ),
              const Spacer(),
              Text(
                'all time',
                style: Broadcast.body(12, color: Broadcast.cyan),
              ),
            ],
          ),
        ],
      ],
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Broadcast.setDeep.withValues(alpha: 0.62),
        border: Border.all(color: Broadcast.podiumEdge, width: 2),
      ),
      child: body,
    );
  }
}

/// The show's name.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 30});

  final double size;

  @override
  Widget build(BuildContext context) => Text(
    "const's quizzes",
    style: Broadcast.display(size).copyWith(
      shadows: const [
        Shadow(color: Broadcast.goldDeep, offset: Offset(0, 3)),
        Shadow(color: Broadcast.magenta, offset: Offset(2, 5)),
      ],
    ),
  );
}

class OnAir extends StatelessWidget {
  const OnAir({super.key});

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

class HandleChip extends StatelessWidget {
  const HandleChip({super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.person, size: 15, color: Broadcast.cyan),
      const SizedBox(width: 5),
      Text(Take.handle, style: Broadcast.body(12, color: Broadcast.cyan)),
    ],
  );
}

/// The Theme, stated once.
class ThemeChip extends StatelessWidget {
  const ThemeChip({super.key, this.take});

  final Take? take;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const ThemeIcon(theme: Take.theme, size: 20, color: Broadcast.cyan),
      const SizedBox(width: 9),
      Text(Take.theme, style: Broadcast.body(14, color: Broadcast.cyan)),
      const SizedBox(width: 14),
      Text(
        take?.intermission == true
            ? 'between rounds'
            : '${Take.slot} of ${Take.slots}',
        style: Broadcast.body(13, color: Broadcast.chalkDim),
      ),
    ],
  );
}

/// The Theme's mark, blown up on the back wall of the set.
class BackWall extends StatelessWidget {
  const BackWall({super.key, this.size = 460, this.theme = Take.theme});

  final double size;
  final String theme;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Opacity(
      opacity: 0.05,
      child: ThemeIcon(theme: theme, size: size, color: Broadcast.chalk),
    ),
  );
}

/// How a Round is graded.
String banterFor(int correct, int total) {
  final pct = correct / total;
  if (pct == 1) return 'A perfect round. Nobody does that.';
  if (pct >= 0.8) return 'Outstanding — a whisker off the lot.';
  if (pct >= 0.5) return 'Solid showing. The trophy is in sight.';
  if (correct > 0) return 'A few on the board. Warm up and go again.';
  return 'Everyone starts somewhere. Run it back.';
}

/// The Intermission card, shared because it is content rather than layout.
class IntermissionCard extends StatelessWidget {
  const IntermissionCard({super.key, required this.take, this.compact = false});

  final Take take;
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('that round', style: Broadcast.body(12, color: Broadcast.chalkDim)),
      const SizedBox(height: 4),
      Text(
        '${Take.myScore}',
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
        '${Take.myCorrect} of ${Take.slots} right   ·   #${Take.myRank}',
        style: Broadcast.body(13),
      ),
      const SizedBox(height: 8),
      Text(
        banterFor(Take.myCorrect, Take.slots),
        textAlign: TextAlign.center,
        style: Broadcast.body(13, color: Broadcast.cyan),
      ),
      SizedBox(height: compact ? 16 : 26),
      Text('next up', style: Broadcast.body(11, color: Broadcast.chalkDim)),
      const SizedBox(height: 10),
      ThemeIcon(theme: Take.nextTheme, size: compact ? 40 : 52),
      const SizedBox(height: 8),
      Text(
        Take.nextTheme,
        textAlign: TextAlign.center,
        style: Broadcast.display(compact ? 18 : 22, color: Broadcast.gold),
      ),
      const SizedBox(height: 14),
      BigNumber(
        value: '${take.seconds}',
        label: 'seconds',
        colour: Broadcast.cyan,
        size: compact ? 28 : 34,
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// A — Studio floor.  Full-height set: header band, stage left, standings rail
//     running the whole right edge, Theme mark painted on the back wall.
// ─────────────────────────────────────────────────────────────────────────────

class LayoutA extends StatelessWidget {
  const LayoutA({super.key, required this.take});

  static const name = 'Studio floor';
  final Take take;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final rail = box.maxWidth >= 980;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _stage()),
                if (rail) ...[
                  const SizedBox(width: 18),
                  SizedBox(width: 268, child: BoardPanel(rows: 12, fill: true)),
                ],
              ],
            ),
          ),
        ],
      );
    },
  );

  Widget _header() => Container(
    padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Broadcast.podiumEdge, width: 2)),
    ),
    child: Row(
      children: [
        const Wordmark(size: 26),
        const SizedBox(width: 18),
        const OnAir(),
        const Spacer(),
        const ThemeChip(),
        const SizedBox(width: 22),
        const HandleChip(),
      ],
    ),
  );

  Widget _stage() => Stack(
    alignment: Alignment.center,
    children: [
      const Positioned(top: 40, child: BackWall(size: 420)),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 4, 26),
        child: take.intermission
            ? Center(child: IntermissionCard(take: take))
            : Column(
                children: [
                  Expanded(
                    flex: 3,
                    child: Center(
                      child: PromptBlock(text: Take.prompt, size: 30),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Center(child: PhaseReadout(take: take, size: 52)),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 780),
                    child: Column(
                      children: [
                        for (var r = 0; r < 2; r++) ...[
                          if (r > 0) const SizedBox(height: 11),
                          Row(
                            children: [
                              for (var c = 0; c < 2; c++) ...[
                                if (c > 0) const SizedBox(width: 11),
                                Expanded(
                                  child: Podium(
                                    index: r * 2 + c,
                                    label: Take.choices[r * 2 + c],
                                    take: take,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// B — Lower third.  No rail at all: one centred column with the question given
//     the full width, and the standings crawling along the bottom edge the way
//     a broadcast puts them there.
// ─────────────────────────────────────────────────────────────────────────────

class LayoutB extends StatelessWidget {
  const LayoutB({super.key, required this.take});

  static const name = 'Lower third';
  final Take take;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        child: Row(
          children: [
            const Wordmark(size: 24),
            const Spacer(),
            const OnAir(),
            const SizedBox(width: 20),
            const HandleChip(),
          ],
        ),
      ),
      Expanded(
        child: Stack(
          alignment: Alignment.center,
          children: [
            const BackWall(size: 520),
            take.intermission
                ? Center(child: IntermissionCard(take: take))
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const ThemeChip(),
                        const SizedBox(height: 26),
                        PromptBlock(text: Take.prompt, size: 34, maxWidth: 820),
                        const SizedBox(height: 26),
                        PhaseReadout(take: take, size: 54, meterCells: 40),
                        const SizedBox(height: 26),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 860),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            alignment: WrapAlignment.center,
                            children: [
                              for (final (i, c) in Take.choices.indexed)
                                SizedBox(
                                  width: 418,
                                  child: Podium(index: i, label: c, take: take),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ],
        ),
      ),
      const _Ticker(),
    ],
  );
}

/// The standings as a broadcast crawl.
class _Ticker extends StatefulWidget {
  const _Ticker();

  @override
  State<_Ticker> createState() => _TickerState();
}

class _TickerState extends State<_Ticker> with SingleTickerProviderStateMixin {
  late final AnimationController _run = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 38),
  )..repeat();

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    height: 44,
    decoration: const BoxDecoration(
      color: Broadcast.podium,
      border: Border(top: BorderSide(color: Broadcast.podiumEdge, width: 2)),
    ),
    child: Row(
      children: [
        Container(
          height: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          color: Broadcast.magenta,
          alignment: Alignment.center,
          child: Text(
            'leaders',
            style: Broadcast.body(
              12,
              color: Broadcast.setDeep,
              weight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              maxWidth: double.infinity,
              child: AnimatedBuilder(
                animation: _run,
                // The list is laid twice end to end and slid by exactly half
                // its width, so the crawl loops with nothing to see at the
                // seam and never runs dry.
                builder: (context, child) => FractionalTranslation(
                  translation: Offset(-_run.value / 2, 0),
                  child: child,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var pass = 0; pass < 2; pass++)
                      for (final (i, row) in Take.board.indexed) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            children: [
                              Text(
                                '${i + 1}',
                                style: Broadcast.body(
                                  12,
                                  color: Broadcast.chalkDim,
                                ),
                              ),
                              const SizedBox(width: 7),
                              Text(
                                row.$1,
                                style: Broadcast.body(
                                  13,
                                  color: row.$1 == Take.handle
                                      ? Broadcast.magenta
                                      : Broadcast.chalk,
                                ),
                              ),
                              const SizedBox(width: 7),
                              Text(
                                '${row.$2}',
                                style: Broadcast.body(
                                  13,
                                  color: Broadcast.gold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 2,
                          height: 12,
                          color: Broadcast.podiumEdge,
                        ),
                      ],
                  ],
                ),
              ),
            ),
          ),
        ),
        Container(
          height: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Text(
            '${Take.playing} playing',
            style: Broadcast.body(12, color: Broadcast.chalkDim),
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// C — Answer board.  A hard split: the question owns the left half at size,
//     the four Choices stack down the right as a board being read out.
// ─────────────────────────────────────────────────────────────────────────────

class LayoutC extends StatelessWidget {
  const LayoutC({super.key, required this.take});

  static const name = 'Answer board';
  final Take take;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.fromLTRB(26, 14, 26, 14),
        color: Broadcast.setDeep.withValues(alpha: 0.5),
        child: Row(
          children: [
            const Wordmark(size: 24),
            const SizedBox(width: 16),
            const OnAir(),
            const Spacer(),
            const ThemeChip(),
            const SizedBox(width: 20),
            const HandleChip(),
          ],
        ),
      ),
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const BackWall(size: 400),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(34, 30, 26, 30),
                    child: take.intermission
                        ? Center(
                            child: IntermissionCard(take: take, compact: true),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              PromptBlock(
                                text: Take.prompt,
                                size: 32,
                                maxWidth: 560,
                                align: TextAlign.left,
                              ),
                              const SizedBox(height: 30),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: PhaseReadout(take: take, size: 56),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
            Container(width: 2, color: Broadcast.podiumEdge),
            SizedBox(
              width: 440,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Column(
                  children: [
                    for (final (i, c) in Take.choices.indexed) ...[
                      if (i > 0) const SizedBox(height: 11),
                      Expanded(
                        child: Podium(
                          index: i,
                          label: c,
                          take: take,
                          big: true,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const BoardPanel(rows: 4),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// D — The wall.  The four Choices are the screen: giant 2×2 tiles, the
//     question on a banner across the top, the gauge stood on end at the edge.
// ─────────────────────────────────────────────────────────────────────────────

class LayoutD extends StatelessWidget {
  const LayoutD({super.key, required this.take});

  static const name = 'The wall';
  final Take take;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 10),
            child: Row(
              children: [
                const Wordmark(size: 22),
                const Spacer(),
                const ThemeChip(),
                const SizedBox(width: 18),
                const OnAir(),
                const SizedBox(width: 18),
                const HandleChip(),
              ],
            ),
          ),
          // The banner: the question, on a lit board across the set.
          Container(
            margin: const EdgeInsets.fromLTRB(78, 0, 22, 14),
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
            decoration: BoxDecoration(
              color: Broadcast.podium,
              border: Border.all(color: Broadcast.gold, width: 2),
              boxShadow: Broadcast.bevel,
            ),
            child: Center(
              child: PromptBlock(
                text: take.intermission ? 'That is the round.' : Take.prompt,
                size: 26,
                maxWidth: 900,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(78, 0, 22, 22),
              child: take.intermission
                  ? Center(child: IntermissionCard(take: take, compact: true))
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              Expanded(
                                child: Podium(
                                  index: 0,
                                  label: Take.choices[0],
                                  take: take,
                                  big: true,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: Podium(
                                  index: 2,
                                  label: Take.choices[2],
                                  take: take,
                                  big: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            children: [
                              Expanded(
                                child: Podium(
                                  index: 1,
                                  label: Take.choices[1],
                                  take: take,
                                  big: true,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: Podium(
                                  index: 3,
                                  label: Take.choices[3],
                                  take: take,
                                  big: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
      // The gauge runs down the left edge of the set, beside the wall.
      if (!take.intermission)
        Positioned(
          left: 14,
          top: 86,
          bottom: 22,
          width: 52,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  take.shot == Shot.read || take.revealing
                      ? '${take.seconds}'
                      : '${take.worth}',
                  style: Broadcast.display(
                    24,
                    color: take.live || take.shot == Shot.locked
                        ? meterColour(take.remaining)
                        : Broadcast.cyan,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              MeterColumn(left: take.remaining, cells: 22),
              const SizedBox(height: 10),
              Text(
                take.live || take.shot == Shot.locked ? 'pts' : '',
                style: Broadcast.body(10, color: Broadcast.chalkDim),
              ),
            ],
          ),
        ),
      // The standings, parked in the corner rather than given a column.
      Positioned(
        right: 22,
        bottom: 22,
        width: 250,
        child: Opacity(opacity: 0.96, child: BoardPanel(rows: 5)),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// E — Cabinet.  One narrow upright column at every width, so the phone and the
//     desktop are the same screen and the set is what fills the rest.
// ─────────────────────────────────────────────────────────────────────────────

class LayoutE extends StatelessWidget {
  const LayoutE({super.key, required this.take});

  static const name = 'Cabinet';
  final Take take;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 540,
      margin: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: Broadcast.setDeep.withValues(alpha: 0.72),
        border: Border.all(color: Broadcast.podiumEdge, width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0x88000512), blurRadius: 40, spreadRadius: 8),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Broadcast.podiumEdge, width: 2),
              ),
            ),
            child: Row(
              children: [
                const Wordmark(size: 20),
                const Spacer(),
                const OnAir(),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: take.intermission
                  ? IntermissionCard(take: take, compact: true)
                  : Column(
                      children: [
                        const ThemeChip(),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 110,
                          child: Center(
                            child: PromptBlock(
                              text: Take.prompt,
                              size: 21,
                              maxWidth: 480,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        PhaseReadout(take: take, size: 40, meterCells: 24),
                        const SizedBox(height: 16),
                        for (final (i, c) in Take.choices.indexed) ...[
                          if (i > 0) const SizedBox(height: 9),
                          Podium(index: i, label: c, take: take),
                        ],
                        const SizedBox(height: 16),
                        const BoardPanel(rows: 5),
                      ],
                    ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// The switcher
// ─────────────────────────────────────────────────────────────────────────────

typedef Variant = ({String key, String name, Widget Function(Take) build});

const variants = <Variant>[
  (key: 'A', name: LayoutA.name, build: _a),
  (key: 'B', name: LayoutB.name, build: _b),
  (key: 'C', name: LayoutC.name, build: _c),
  (key: 'D', name: LayoutD.name, build: _d),
  (key: 'E', name: LayoutE.name, build: _e),
];

Widget _a(Take t) => LayoutA(take: t);
Widget _b(Take t) => LayoutB(take: t);
Widget _c(Take t) => LayoutC(take: t);
Widget _d(Take t) => LayoutD(take: t);
Widget _e(Take t) => LayoutE(take: t);

class PrototypeApp extends StatelessWidget {
  const PrototypeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: "const's quizzes · layouts",
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Broadcast.setDeep,
      useMaterial3: true,
    ),
    home: const Switcher(),
  );
}

class Switcher extends StatefulWidget {
  const Switcher({super.key});

  @override
  State<Switcher> createState() => _SwitcherState();
}

class _SwitcherState extends State<Switcher> {
  int _variant = 0;
  int _shot = Shot.answer.index;
  bool _barOpen = true;

  void _step(int by) =>
      setState(() => _variant = (_variant + by) % variants.length);

  void _stepShot(int by) =>
      setState(() => _shot = (_shot + by) % Shot.values.length);

  KeyEventResult _keys(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
        _step(1);
      case LogicalKeyboardKey.arrowLeft:
        _step(variants.length - 1);
      case LogicalKeyboardKey.arrowDown:
        _stepShot(1);
      case LogicalKeyboardKey.arrowUp:
        _stepShot(Shot.values.length - 1);
      case LogicalKeyboardKey.keyH:
        setState(() => _barOpen = !_barOpen);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final v = variants[_variant];
    final take = Take(Shot.values[_shot]);
    return Focus(
      autofocus: true,
      onKeyEvent: _keys,
      child: Scaffold(
        body: SetBackdrop(
          child: Stack(
            fit: StackFit.expand,
            children: [
              SafeArea(
                // Room for the switcher, which is prototype furniture rather
                // than part of the design being judged.
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 52),
                  child: v.build(take),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _bar(v, take),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bar(Variant v, Take take) {
    if (!_barOpen) {
      return _Pill(
        child: InkWell(
          onTap: () => setState(() => _barOpen = true),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              '${v.key} · ${take.shot.label}   (h)',
              style: Broadcast.body(12, color: Colors.black87),
            ),
          ),
        ),
      );
    }
    return _Pill(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Step(
            icon: Icons.chevron_left,
            onTap: () => _step(variants.length - 1),
          ),
          SizedBox(
            width: 190,
            child: Text(
              '${v.key} · ${v.name}',
              textAlign: TextAlign.center,
              style: Broadcast.body(
                13,
                color: Colors.black,
                weight: FontWeight.w800,
              ),
            ),
          ),
          _Step(icon: Icons.chevron_right, onTap: () => _step(1)),
          Container(
            width: 1,
            height: 24,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: Colors.black26,
          ),
          for (final s in Shot.values)
            InkWell(
              onTap: () => setState(() => _shot = s.index),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                color: s.index == _shot
                    ? Broadcast.magenta
                    : Colors.transparent,
                child: Text(
                  s.label,
                  style: Broadcast.body(
                    12,
                    color: s.index == _shot ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ),
          Container(
            width: 1,
            height: 24,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: Colors.black26,
          ),
          InkWell(
            onTap: () => setState(() => _barOpen = false),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Text(
                'hide',
                style: Broadcast.body(12, color: Colors.black54),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFEFEFF4),
    borderRadius: BorderRadius.circular(999),
    elevation: 12,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: child,
    ),
  );
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: Icon(icon, size: 20, color: Colors.black87),
    ),
  );
}
