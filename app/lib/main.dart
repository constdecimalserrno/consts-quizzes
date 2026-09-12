import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ConstsQuizzesApp());
}

/// Signs the visitor in anonymously, then asks the server for their Player
/// document. Both are idempotent: a returning visitor keeps the uid the SDK
/// has already persisted, and `ensurePlayer` is a no-op once the document is
/// there.
Future<String> _signIn() async {
  final auth = FirebaseAuth.instance;
  final user = auth.currentUser ?? (await auth.signInAnonymously()).user!;
  await FirebaseFunctions.instance.httpsCallable('ensurePlayer').call();
  return user.uid;
}

class ConstsQuizzesApp extends StatelessWidget {
  const ConstsQuizzesApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: "const's quizzes",
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: const _Shell(),
      );
}

class _Shell extends StatefulWidget {
  const _Shell();

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  late final Future<String> _uid = _signIn();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: FutureBuilder<String>(
              future: _uid,
              builder: (context, snap) => switch (snap) {
                AsyncSnapshot(hasError: true, :final error) =>
                  Text("Couldn't sign in: $error", textAlign: TextAlign.center),
                AsyncSnapshot(hasData: true, :final data?) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text("const's quizzes",
                          style: TextStyle(fontSize: 32)),
                      const SizedBox(height: 12),
                      Text('signed in as $data'),
                    ],
                  ),
                _ => const CircularProgressIndicator(),
              },
            ),
          ),
        ),
      );
}
