import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

const _xProviderId = 'twitter.com';

/// The providers a Player can attach to keep their progress.
enum Provider { google, apple, x }

extension ProviderLabel on Provider {
  String get label => switch (this) {
    Provider.google => 'Google',
    Provider.apple => 'Apple',
    Provider.x => 'X',
  };

  AuthProvider get authProvider => switch (this) {
    Provider.google => GoogleAuthProvider(),
    Provider.apple => AppleAuthProvider(),
    // X keeps its own session, so without `force_login` whoever the
    // browser is already signed in as gets linked silently, under a name
    // the Player did not choose.
    Provider.x =>
      TwitterAuthProvider()..setCustomParameters({'force_login': 'true'}),
  };
}

enum LinkOutcome {
  /// The anonymous account kept its uid and gained a provider.
  linked,

  /// The provider already had an account; the Player is now signed in as it,
  /// and their anonymous history was folded in.
  switchedAndMerged,

  /// Signed in as the existing account, but the history could not be claimed.
  switchedOnly,

  cancelled,

  /// The provider is not turned on for this project yet.
  unavailable,

  failed,
}

/// Attaches a provider to the Player who is already signed in.
///
/// Linking, not signing in. A plain sign-in mints a new uid and strands
/// everything the anonymous Player did — exactly the trap the reference
/// project fell into for Google and Apple.
///
/// The awkward case is a provider that already belongs to an account. Linking
/// cannot succeed, so the Player is signed in as that account instead and the
/// anonymous history is claimed for it server-side — proved by the old
/// account's ID token rather than merely naming its uid.
Future<LinkOutcome> link(Provider provider, {FirebaseAuth? auth}) async {
  final a = auth ?? FirebaseAuth.instance;
  final before = a.currentUser;
  if (before == null) return LinkOutcome.failed;

  final abandonedToken = await before.getIdToken();

  try {
    final p = provider.authProvider;
    final credential = kIsWeb
        ? await before.linkWithPopup(p)
        : await before.linkWithProvider(p);
    if (provider == Provider.x) await syncXProfile(credential);
    return LinkOutcome.linked;
  } on FirebaseAuthException catch (e) {
    switch (e.code) {
      case 'credential-already-in-use':
      case 'email-already-in-use':
      case 'account-exists-with-different-credential':
        return _switchTo(a, e, abandonedToken);
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
      case 'user-cancelled':
        return LinkOutcome.cancelled;
      case 'operation-not-allowed':
        return LinkOutcome.unavailable;
      default:
        return LinkOutcome.failed;
    }
  } catch (_) {
    return LinkOutcome.failed;
  }
}

Future<LinkOutcome> _switchTo(
  FirebaseAuth auth,
  FirebaseAuthException e,
  String? abandonedToken,
) async {
  final credential = e.credential;
  if (credential == null || abandonedToken == null) return LinkOutcome.failed;

  try {
    await auth.signInWithCredential(credential);
    await FirebaseFunctions.instance
        .httpsCallable('claimAnonymousHistory')
        .call({'abandonedIdToken': abandonedToken});
    return LinkOutcome.switchedAndMerged;
  } catch (_) {
    // Signed in, but the claim failed. The old scores are still recoverable
    // server-side, so this is worth saying rather than swallowing.
    return auth.currentUser != null
        ? LinkOutcome.switchedOnly
        : LinkOutcome.failed;
  }
}


/// Pushes the X details of a link the server cannot see by itself.
///
/// The username and banner only exist in the credential X returns at link
/// time. Whether the Player has actually linked X is checked server-side, so
/// sending them is not the same as claiming them.
Future<void> syncXProfile(UserCredential credential) async {
  final info = credential.additionalUserInfo;
  final username = info?.username;
  if (username == null) return;

  await FirebaseFunctions.instance.httpsCallable('syncXProfile').call({
    'username': username,
    'bannerUrl': info?.profile?['profile_banner_url'],
  });
}

/// Disconnects X and removes what it contributed.
///
/// Both halves matter: unlinking without wiping leaves somebody looking at
/// their own face on a page they thought they had disconnected.
Future<bool> disconnectX({FirebaseAuth? auth}) async {
  final a = auth ?? FirebaseAuth.instance;
  final user = a.currentUser;
  if (user == null) return false;

  try {
    await FirebaseFunctions.instance.httpsCallable('disconnectXProfile').call();
    if (user.providerData.any((p) => p.providerId == _xProviderId)) {
      await user.unlink(_xProviderId);
    }
    return true;
  } catch (_) {
    return false;
  }
}
