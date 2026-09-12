import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'round/answering.dart';
import 'round/leaderboard.dart';
import 'round/round.dart';
import 'round/round_view.dart';
import 'round/server_clock.dart';
import 'theme/broadcast.dart';

const _region = 'us-central1';
final _serverTime =
    Uri.parse('https://$_region-consts-quizzes.cloudfunctions.net/serverTime');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ConstsQuizzesApp());
}

/// Signs the visitor in anonymously, corrects the clock, and gets their Handle.
///
/// Sign-in and `ensurePlayer` are both idempotent: a returning visitor keeps
/// the uid the SDK persisted and the Handle minted the first time.
Future<({String handle, ServerClock clock, String uid})> _tuneIn() async {
  final auth = FirebaseAuth.instance;
  if (auth.currentUser == null) await auth.signInAnonymously();

  final clock = await ServerClock.sync(_serverTime);
  final result =
      await FirebaseFunctions.instance.httpsCallable('ensurePlayer').call();
  return (
    handle: (result.data as Map)['handle'] as String,
    clock: clock,
    uid: auth.currentUser!.uid,
  );
}

Stream<LiveRound?> _liveRounds() => FirebaseFirestore.instance
    .doc('rounds/current')
    .snapshots()
    .map(LiveRound.fromSnapshot);

Stream<LiveBoard> _liveBoard() => FirebaseFirestore.instance
    .doc('leaderboards/live')
    .snapshots()
    .map(LiveBoard.fromSnapshot);

class ConstsQuizzesApp extends StatelessWidget {
  const ConstsQuizzesApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: "const's quizzes",
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Broadcast.setDeep,
          useMaterial3: true,
        ),
        home: const _TuneIn(),
      );
}

class _TuneIn extends StatefulWidget {
  const _TuneIn();

  @override
  State<_TuneIn> createState() => _TuneInState();
}

class _TuneInState extends State<_TuneIn> {
  late final Future<({String handle, ServerClock clock, String uid})> _ready =
      _tuneIn();

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<({String handle, ServerClock clock, String uid})>(
        future: _ready,
        builder: (context, snap) {
          if (snap.hasError) {
            return Scaffold(
              body: DecoratedBox(
                decoration: Broadcast.set,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      "The broadcast didn't reach you. Reload to try again.",
                      textAlign: TextAlign.center,
                      style: Broadcast.body(16),
                    ),
                  ),
                ),
              ),
            );
          }
          final ready = snap.data;
          return RoundView(
            rounds: _liveRounds(),
            clock: ready?.clock ?? ServerClock(),
            handle: ready?.handle,
            // Absent until sign-in lands, so the podiums are inert rather than
            // accepting taps that would be refused.
            sink: ready == null
                ? null
                : FirestoreAnswerSink(
                    db: FirebaseFirestore.instance,
                    uid: ready.uid,
                  ),
            boards: _liveBoard(),
            uid: ready?.uid,
          );
        },
      );
}
