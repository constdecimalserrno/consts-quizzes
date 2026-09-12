import 'package:cloud_firestore/cloud_firestore.dart';

class Standing {
  const Standing({
    required this.uid,
    required this.handle,
    required this.score,
  });

  final String uid;
  final String handle;
  final int score;
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
          ),
      ],
    );
  }
}
