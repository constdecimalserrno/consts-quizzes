import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/broadcast.dart';

/// What the game can show about a Player.
///
/// Everything beyond the Handle is optional, because most Players are
/// anonymous and always will be. An anonymous Player is not an incomplete one:
/// they get a generated look rather than an empty frame.
class Profile {
  const Profile({
    required this.uid,
    required this.handle,
    this.xUsername,
    this.xName,
    this.photoUrl,
    this.bannerUrl,
    this.roundsPlayed = 0,
    this.averageScore = 0,
    this.bestRound = 0,
    this.anonymous = true,
  });

  final String uid;
  final String handle;

  final String? xUsername;
  final String? xName;
  final String? photoUrl;
  final String? bannerUrl;

  final int roundsPlayed;
  final int averageScore;
  final int bestRound;
  final bool anonymous;

  bool get hasX => xUsername != null;

  /// What to call them: their X name if they have connected one, else the
  /// Handle they were given.
  String get displayName => xName ?? handle;

  static Profile? fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final d = snap.data();
    if (d == null) return null;
    final x = (d['x'] as Map?)?.cast<String, dynamic>();
    final career = (d['career'] as Map?)?.cast<String, dynamic>() ?? const {};
    return Profile(
      uid: snap.id,
      handle: d['handle'] as String? ?? 'someone',
      xUsername: x?['username'] as String?,
      xName: x?['name'] as String?,
      photoUrl: x?['photoUrl'] as String?,
      bannerUrl: x?['bannerUrl'] as String?,
      roundsPlayed: (career['roundsPlayed'] as num?)?.toInt() ?? 0,
      averageScore: (career['averageScore'] as num?)?.toInt() ?? 0,
      bestRound: (career['bestRound'] as num?)?.toInt() ?? 0,
      anonymous: d['anonymous'] as bool? ?? true,
    );
  }

  /// A colour derived from the Handle.
  ///
  /// A Player with no picture still needs to look like somebody, and the
  /// Handle is the only thing everyone has. The same Handle always produces
  /// the same colour, so the avatar is recognisable before you read the name.
  Color get seedColour {
    var hash = 0;
    for (final unit in handle.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    const palette = [
      Broadcast.magenta,
      Broadcast.cyan,
      Broadcast.gold,
      Color(0xFF7B5BE6),
      Color(0xFF35D17E),
      Color(0xFFFF9A3C),
    ];
    return palette[hash % palette.length];
  }

  /// The letters on a generated avatar: the first of each word in the Handle.
  String get monogram {
    final parts = handle.split('-').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }
}

Stream<Profile?> watchProfile(String uid) => FirebaseFirestore.instance
    .doc('players/$uid')
    .snapshots()
    .map(Profile.fromSnapshot);
