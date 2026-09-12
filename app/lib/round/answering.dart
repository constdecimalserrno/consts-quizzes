import 'package:cloud_firestore/cloud_firestore.dart';

import 'round.dart';

/// What this Player has done about the Slot on screen.
enum Answered { no, sending, sent, rejected }

/// Submits an Answer for the open Slot.
///
/// The write goes straight to Firestore rather than through a callable: the
/// rules already enforce the Window, one Answer per Slot, and the server's own
/// clock as the time of the Answer, so a function in the middle would add a
/// cold start and a bill without adding a guarantee.
abstract interface class AnswerSink {
  Future<void> submit(LiveRound round, String choice);
}

class FirestoreAnswerSink implements AnswerSink {
  FirestoreAnswerSink({required this.db, required this.uid});

  final FirebaseFirestore db;
  final String uid;

  @override
  Future<void> submit(LiveRound round, String choice) => db
      .doc(round.answerPath(uid))
      .set({
        'uid': uid,
        'slot': round.openSlot,
        'choice': choice,
        'answeredAt': FieldValue.serverTimestamp(),
      });
}
