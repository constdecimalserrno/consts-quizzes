import 'package:cloud_firestore/cloud_firestore.dart';

/// The Question currently on screen. Never carries the correct Choice.
class OpenQuestion {
  const OpenQuestion({
    required this.slot,
    required this.prompt,
    required this.choices,
    required this.difficulty,
    required this.opensAt,
    required this.closesAt,
  });

  final int slot;
  final String prompt;
  final List<String> choices;
  final String difficulty;

  /// Absolute server times, in milliseconds. The client does no arithmetic on
  /// the schedule beyond comparing it to a corrected clock.
  final int opensAt;
  final int closesAt;

  static OpenQuestion? fromMap(Map<String, dynamic>? m) {
    if (m == null) return null;
    return OpenQuestion(
      slot: (m['slot'] as num).toInt(),
      prompt: m['prompt'] as String,
      choices: (m['choices'] as List).cast<String>(),
      difficulty: m['difficulty'] as String? ?? 'easy',
      opensAt: (m['opensAt'] as num).toInt(),
      closesAt: (m['closesAt'] as num).toInt(),
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
