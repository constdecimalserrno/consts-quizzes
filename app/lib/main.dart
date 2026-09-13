import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'round/answering.dart';
import 'round/leaderboard.dart';
import 'round/round.dart';
import 'round/seating.dart';
import 'round/round_view.dart';
import 'auth/linking.dart';
import 'profile/profile.dart';
import 'profile/profile_drawer.dart';
import 'round/server_clock.dart';
import 'theme/broadcast.dart';

const _region = 'us-central1';
final _serverTime = Uri.parse(
  'https://$_region-consts-quizzes.cloudfunctions.net/serverTime',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ConstsQuizzesApp());
}

/// Signs the visitor in anonymously, corrects the clock, and gets their Handle.
///
/// Sign-in and `ensurePlayer` are both idempotent: a returning visitor keeps
/// the uid the SDK persisted and the Handle minted the first time.
typedef TunedIn = ({String handle, ServerClock clock, String uid});

Future<TunedIn> _tuneIn() async {
  final auth = FirebaseAuth.instance;
  if (auth.currentUser == null) await auth.signInAnonymously();

  final clock = await ServerClock.sync(_serverTime);
  // Left running for the life of the page: see `keepSynced`.
  clock.keepSynced(_serverTime);
  final result = await FirebaseFunctions.instance
      .httpsCallable('ensurePlayer')
      .call();
  final data = result.data as Map;
  return (
    handle: data['handle'] as String,
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

Stream<AllTimeBoard> _allTimeBoard() => FirebaseFirestore.instance
    .doc('leaderboards/allTime')
    .snapshots()
    .map(AllTimeBoard.fromSnapshot);

Stream<AllTimeBoard> _botBoard() => FirebaseFirestore.instance
    .doc('leaderboards/bots')
    .snapshots()
    .map(AllTimeBoard.fromSnapshot);

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
  late final Future<TunedIn> _ready = _tuneIn();

  @override
  Widget build(BuildContext context) => FutureBuilder<TunedIn>(
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
      return _WithDrawer(
        me: ready?.uid,
        child: (openProfile) => RoundView(
          onOpenProfile: openProfile,
          rounds: _liveRounds(),
          clock: ready?.clock ?? ServerClock(),
          handle: ready?.handle,
          // Absent until sign-in lands: podiums stay inert rather than
          // accepting taps the rules would refuse anyway.
          sink: ready == null
              ? null
              : FirestoreAnswerSink(
                  db: FirebaseFirestore.instance,
                  uid: ready.uid,
                ),
          // A seat belongs to a Round, so it is retaken every Round.
          seating: ready == null ? null : CallableSeating(),
          boards: _liveBoard(),
          allTime: _allTimeBoard(),
          bots: _botBoard(),
          uid: ready?.uid,
          anonymous: FirebaseAuth.instance.currentUser?.isAnonymous ?? false,
          points: (max: 1000, min: 100),
        ),
      );
    },
  );
}

/// Holds the Player page that slides in from the left.
///
/// One drawer serves both the person watching and anybody they tap in the
/// standings, because it is the same page either way — only the buttons on it
/// differ.
class _WithDrawer extends StatefulWidget {
  const _WithDrawer({required this.me, required this.child});

  final String? me;
  final Widget Function(void Function(String? uid) open) child;

  @override
  State<_WithDrawer> createState() => _WithDrawerState();
}

class _WithDrawerState extends State<_WithDrawer> {
  final _scaffold = GlobalKey<ScaffoldState>();

  /// Whose page is open. Null means the Player watching.
  String? _showing;
  bool _busy = false;
  String? _message;

  void _open(String? uid) {
    setState(() {
      _showing = uid;
      _message = null;
    });
    _scaffold.currentState?.openDrawer();
  }

  Future<void> _connect(Provider provider) async {
    setState(() => _busy = true);
    final outcome = await link(provider);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = switch (outcome) {
        LinkOutcome.linked => 'Connected. Your scores are saved now.',
        LinkOutcome.switchedAndMerged =>
          'Welcome back — your scores have been combined.',
        LinkOutcome.switchedOnly =>
          "Signed in, but this round didn't transfer.",
        LinkOutcome.cancelled => null,
        LinkOutcome.unavailable =>
          '${provider.label} sign-in is not switched on yet.',
        LinkOutcome.failed => "That didn't work. Try again?",
      };
    });
  }

  Future<void> _disconnectX() async {
    setState(() => _busy = true);
    final done = await disconnectX();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = done ? 'X disconnected.' : "Couldn't disconnect. Try again?";
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = _showing ?? widget.me;
    final isMe = _showing == null || _showing == widget.me;

    return Scaffold(
      key: _scaffold,
      backgroundColor: Broadcast.setDeep,
      drawerEnableOpenDragGesture: false,
      drawer: uid == null
          ? null
          : StreamBuilder<Profile?>(
              stream: watchProfile(uid),
              builder: (context, snap) => ProfileDrawer(
                profile: snap.data,
                isMe: isMe,
                onConnect: isMe ? _connect : null,
                onDisconnectX: isMe ? _disconnectX : null,
                busy: _busy,
                message: _message,
              ),
            ),
      body: widget.child(_open),
    );
  }
}
