import 'package:consts_quizzes/auth/linking.dart';
import 'package:consts_quizzes/profile/profile.dart';
import 'package:consts_quizzes/profile/profile_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _anon = Profile(
  uid: 'u1',
  handle: 'jolly-teal-otter-777',
  roundsPlayed: 12,
  averageScore: 640,
  bestRound: 9100,
);

const _linked = Profile(
  uid: 'u2',
  handle: 'grumpy-red-emu-193',
  xUsername: 'const',
  xName: 'Const',
  photoUrl: 'https://pbs.twimg.com/a_400x400.jpg',
  bannerUrl: 'https://pbs.twimg.com/banner',
  anonymous: false,
);

Future<void> _pump(
  WidgetTester tester,
  Profile? profile, {
  bool isMe = true,
  VoidCallback? onDisconnectX,
  void Function(Provider)? onConnect,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ProfileDrawer(
        profile: profile,
        isMe: isMe,
        onConnect: onConnect ?? (_) {},
        onDisconnectX: onDisconnectX ?? () {},
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('an anonymous Player is somebody, not a gap', (tester) async {
    await _pump(tester, _anon);

    // No X account, so the Handle is the name and the avatar is generated —
    // and the Handle appears once, not printed under itself.
    expect(find.text('jolly-teal-otter-777'), findsOneWidget);
    expect(find.text('JT'), findsOneWidget);
  });

  testWidgets('shows a career once there is one', (tester) async {
    await _pump(tester, _anon);

    expect(find.text('12'), findsOneWidget);
    expect(find.text('640'), findsOneWidget);
    expect(find.text('9100'), findsOneWidget);
  });

  testWidgets('says so before any Round is finished', (tester) async {
    await _pump(tester, const Profile(uid: 'u1', handle: 'a-b-c-001'));

    expect(find.text('No finished rounds yet.'), findsOneWidget);
  });

  testWidgets('a connected Player is named by X', (tester) async {
    await _pump(tester, _linked);

    expect(find.text('Const'), findsOneWidget);
    // The Handle is still shown: it is what they are called in the game.
    expect(find.text('@const  ·  grumpy-red-emu-193'), findsOneWidget);
  });

  testWidgets('offers to disconnect only when X is connected', (tester) async {
    await _pump(tester, _linked);
    expect(find.text('Disconnect X'), findsOneWidget);
    expect(find.text('Connect X'), findsNothing);

    await _pump(tester, _anon);
    expect(find.text('Disconnect X'), findsNothing);
    expect(find.text('Connect X'), findsOneWidget);
  });

  testWidgets('warns what disconnecting removes', (tester) async {
    await _pump(tester, _linked);

    expect(
      find.textContaining('removes your X name, picture and banner'),
      findsOneWidget,
    );
  });

  testWidgets('disconnecting is wired up', (tester) async {
    var asked = false;
    await _pump(tester, _linked, onDisconnectX: () => asked = true);

    await tester.tap(find.text('Disconnect X'));
    await tester.pump();

    expect(asked, isTrue);
  });

  testWidgets('offers no account controls on somebody else`s page',
      (tester) async {
    await _pump(tester, _linked, isMe: false);

    expect(find.text('Disconnect X'), findsNothing);
    expect(find.textContaining('Connect'), findsNothing);
    // Their name and career are still the point of looking.
    expect(find.text('Const'), findsOneWidget);
  });

  testWidgets('tells an anonymous Player what they stand to lose',
      (tester) async {
    await _pump(tester, _anon);

    expect(
      find.text('Your scores live in this browser only.'),
      findsOneWidget,
    );
  });

  testWidgets('says nothing alarming to a signed-in Player', (tester) async {
    await _pump(tester, _linked);

    expect(
      find.text('Your scores are saved to your account.'),
      findsOneWidget,
    );
  });

  testWidgets('handles having nothing to show', (tester) async {
    await _pump(tester, null);

    expect(find.text('Nothing to show yet.'), findsOneWidget);
  });

  test('the same Handle always gets the same colour', () {
    const a = Profile(uid: '1', handle: 'jolly-teal-otter-777');
    const b = Profile(uid: '2', handle: 'jolly-teal-otter-777');
    const c = Profile(uid: '3', handle: 'grumpy-red-emu-193');

    expect(a.seedColour, b.seedColour);
    expect(a.monogram, 'JT');
    expect(c.monogram, 'GR');
  });
}
