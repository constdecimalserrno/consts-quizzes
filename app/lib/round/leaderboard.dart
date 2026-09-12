import 'package:cloud_firestore/cloud_firestore.dart';

class Standing {
  const Standing({
    required this.uid,
    required this.handle,
    required this.score,
    this.correct = 0,
  });

  final String uid;
  final String handle;
  final int score;

  /// How many Questions this Player got right, for their end-of-Round line.
  final int correct;
}

/// The live standings, as published by the Tick.
///
/// One document for the whole audience: a board where everyone watched
/// everyone would cost a read per Player per Player per Slot.
class LiveBoard {
  const LiveBoard({
    required this.playing,
    required this.top,
    required this.slot,
  });

  final int playing;
  final List<Standing> top;
  final int slot;

  static const empty = LiveBoard(playing: 0, top: [], slot: -1);

  static LiveBoard fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final d = snap.data();
    if (d == null) return empty;
    return LiveBoard(
      playing: (d['playing'] as num?)?.toInt() ?? 0,
      slot: (d['slot'] as num?)?.toInt() ?? -1,
      top: [
        for (final t in (d['top'] as List? ?? []))
          Standing(
            uid: t['uid'] as String? ?? '',
            handle: t['handle'] as String? ?? 'someone',
            score: (t['score'] as num?)?.toInt() ?? 0,
            correct: (t['correct'] as num?)?.toInt() ?? 0,
          ),
      ],
    );
  }
}


/// A Player's standing across every Round they have played.
class CareerStanding {
  const CareerStanding({
    required this.uid,
    required this.handle,
    required this.averageScore,
    required this.bestRound,
    required this.roundsPlayed,
  });

  final String uid;
  final String handle;
  final int averageScore;
  final int bestRound;
  final int roundsPlayed;
}

/// The all-time board: ranked on average score, not lifetime total.
class AllTimeBoard {
  const AllTimeBoard({required this.top});

  final List<CareerStanding> top;

  static const empty = AllTimeBoard(top: []);

  static AllTimeBoard fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    final d = snap.data();
    if (d == null) return empty;
    return AllTimeBoard(
      top: [
        for (final t in (d['top'] as List? ?? []))
          CareerStanding(
            uid: t['uid'] as String? ?? '',
            handle: t['handle'] as String? ?? 'someone',
            averageScore: (t['averageScore'] as num?)?.toInt() ?? 0,
            bestRound: (t['bestRound'] as num?)?.toInt() ?? 0,
            roundsPlayed: (t['roundsPlayed'] as num?)?.toInt() ?? 0,
          ),
      ],
    );
  }
}
