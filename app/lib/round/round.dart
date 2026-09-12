import 'package:cloud_firestore/cloud_firestore.dart';

/// The Question currently on screen. Never carries the correct Choice.
/// The four phases a Slot passes through.
///
/// Read before you can answer, answer against a draining clock, learn what the
/// answer was, then a beat before the next one.
enum Phase { read, answer, reveal, idle }

/// The Question currently on screen.
///
/// Carries the correct Choice only once the Window has shut — before that the
/// field is simply absent.
class OpenQuestion {
  const OpenQuestion({
    required this.slot,
    required this.prompt,
    required this.choices,
    required this.difficulty,
    required this.startsAt,
    required this.opensAt,
    required this.closesAt,
    required this.revealUntil,
    required this.endsAt,
    this.correct,
  });

  final int slot;
  final String prompt;
  final List<String> choices;
  final String difficulty;

  /// Absolute server times, in milliseconds. The client does no arithmetic on
  /// the schedule beyond comparing it to a corrected clock.
  final int startsAt;
  final int opensAt;
  final int closesAt;
  final int revealUntil;
  final int endsAt;

  final String? correct;

  /// How early the client stops taking Answers.
  ///
  /// The server refuses anything that arrives after `closesAt`, and a write
  /// from a browser takes a couple of hundred milliseconds to get there. Taking
  /// taps right up to the deadline means the last one a Player makes is the one
  /// that gets thrown away, which is where "too late" was coming from.
  static const graceMs = 700;

  /// The instant the client stops offering the Choices.
  int get clientClosesAt => closesAt - graceMs;

  Phase phaseAt(int now) {
    if (now < opensAt) return Phase.read;
    if (now < clientClosesAt) return Phase.answer;
    // The reveal phase begins when the Window shuts, not when the answer
    // turns up — the server takes a moment to publish it. Falling through to
    // idle in that gap made the screen say "next question in" and then jump
    // back to the answer, which reads as a glitch.
    if (now < revealUntil) return Phase.reveal;
    return Phase.idle;
  }

  /// True in the beat between the Window shutting and the answer arriving.
  bool settlingAt(int now) =>
      now >= clientClosesAt && now < revealUntil && correct == null;

  /// How much of the answer Window is left, as a fraction.
  double remainingAt(int now) {
    final span = clientClosesAt - opensAt;
    if (span <= 0) return 0;
    return ((clientClosesAt - now) / span).clamp(0.0, 1.0);
  }

  static OpenQuestion? fromMap(Map<String, dynamic>? m) {
    if (m == null || m['slot'] == null) return null;
    int n(Object? v, int fallback) => (v as num?)?.toInt() ?? fallback;
    final startsAt = n(m['startsAt'], 0);
    return OpenQuestion(
      slot: n(m['slot'], 0),
      prompt: m['prompt'] as String? ?? '',
      choices: ((m['choices'] as List?) ?? const []).cast<String>(),
      difficulty: m['difficulty'] as String? ?? 'easy',
      startsAt: startsAt,
      opensAt: n(m['opensAt'], startsAt),
      closesAt: n(m['closesAt'], startsAt),
      revealUntil: n(m['revealUntil'], n(m['closesAt'], startsAt)),
      endsAt: n(m['endsAt'], n(m['closesAt'], startsAt)),
      correct: m['correct'] as String?,
    );
  }
}

/// The live Round, as the whole audience sees it.
class LiveRound {
  const LiveRound({
    required this.id,
    required this.theme,
    required this.slotCount,
    required this.openSlot,
    required this.question,
    required this.nextRoundAt,
    this.nextTheme,
  });

  final String id;
  final String theme;
  final int slotCount;

  /// -1 during the Intermission.
  final int openSlot;
  final OpenQuestion? question;
  final int nextRoundAt;

  /// Announced when the Round ends, so the Intermission has something to sell.
  final String? nextTheme;

  bool get inIntermission => openSlot < 0 || question == null;

  /// How the Answer for the open Slot is addressed.
  ///
  /// The id is fixed by the Player and the Slot, which is what lets the rules
  /// say "once, and only for the Slot that is open" without trusting anything
  /// the client sends.
  String answerPath(String uid) =>
      'rounds/$id/answers/${openSlot}_$uid';

  static LiveRound? fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final d = snap.data();
    if (d == null) return null;
    return LiveRound(
      id: d['id'] as String? ?? snap.id,
      theme: d['theme'] as String? ?? '',
      slotCount: (d['slots'] as List?)?.length ?? 0,
      openSlot: (d['openSlot'] as num?)?.toInt() ?? -1,
      question: OpenQuestion.fromMap(
        (d['question'] as Map?)?.cast<String, dynamic>(),
      ),
      nextRoundAt: (d['nextRoundAt'] as num?)?.toInt() ?? 0,
      nextTheme: d['nextTheme'] as String?,
    );
  }
}
