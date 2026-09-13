import 'package:flutter/material.dart';

import '../auth/linking.dart';
import '../theme/broadcast.dart';
import 'profile.dart';

/// A Player's page, in the drawer.
///
/// The same panel serves two jobs: looking at yourself, where you can connect
/// an account, and looking at somebody you saw on the leaderboard, where you
/// cannot. Only the buttons differ, because the thing being described is the
/// same thing.
class ProfileDrawer extends StatelessWidget {
  const ProfileDrawer({
    super.key,
    required this.profile,
    required this.isMe,
    this.onConnect,
    this.onDisconnectX,
    this.busy = false,
    this.message,
  });

  final Profile? profile;
  final bool isMe;
  final void Function(Provider provider)? onConnect;
  final VoidCallback? onDisconnectX;
  final bool busy;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return Drawer(
      backgroundColor: Broadcast.setDeep,
      width: 340,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: p == null
            ? Center(
                child: Text(
                  'Nothing to show yet.',
                  style: Broadcast.body(13, color: Broadcast.chalkDim),
                ),
              )
            : ListView(
                padding: EdgeInsets.zero,
                children: [
                  _Banner(profile: p),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.displayName,
                          style: Broadcast.body(19, weight: FontWeight.w800),
                        ),
                        // Only a connected Player has a second name to show.
                        // Printing the Handle under itself made an anonymous
                        // page look like a rendering fault.
                        if (p.hasX) ...[
                          const SizedBox(height: 2),
                          Text(
                            '@${p.xUsername}  ·  ${p.handle}',
                            style: Broadcast.body(
                              12,
                              color: Broadcast.chalkDim,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        _Stats(profile: p),
                        if (isMe) ...[
                          const SizedBox(height: 20),
                          _Account(
                            profile: p,
                            onConnect: onConnect,
                            onDisconnectX: onDisconnectX,
                            busy: busy,
                            message: message,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Banner and avatar.
///
/// Without an X account both are generated from the Handle, so an anonymous
/// Player looks like somebody rather than like a gap.
class _Banner extends StatelessWidget {
  const _Banner({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final banner = profile.bannerUrl;
    final photo = profile.photoUrl;
    final seed = profile.seedColour;

    return SizedBox(
      height: 150,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            bottom: 36,
            child: banner == null
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [seed.withValues(alpha: 0.75), Broadcast.setNavy],
                      ),
                    ),
                  )
                : Image.network(
                    banner,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => ColoredBox(color: seed),
                  ),
          ),
          Positioned(
            left: 18,
            bottom: 0,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: seed,
                border: Border.all(color: Broadcast.setDeep, width: 3),
              ),
              alignment: Alignment.center,
              clipBehavior: Clip.antiAlias,
              child: photo == null
                  ? Text(
                      profile.monogram,
                      style: Broadcast.display(24, color: Broadcast.setDeep),
                    )
                  : Image.network(
                      photo,
                      fit: BoxFit.cover,
                      width: 72,
                      height: 72,
                      errorBuilder: (_, _, _) => Text(
                        profile.monogram,
                        style: Broadcast.display(24, color: Broadcast.setDeep),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    if (profile.roundsPlayed == 0) {
      return Text(
        'No finished rounds yet.',
        style: Broadcast.body(12, color: Broadcast.chalkDim),
      );
    }
    return Row(
      children: [
        _Stat(label: 'rounds', value: '${profile.roundsPlayed}'),
        _Stat(label: 'average', value: '${profile.averageScore}'),
        _Stat(label: 'best', value: '${profile.bestRound}'),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: Broadcast.display(19)),
            Text(label, style: Broadcast.body(11, color: Broadcast.chalkDim)),
          ],
        ),
      );
}

/// The half of the drawer only you see.
class _Account extends StatelessWidget {
  const _Account({
    required this.profile,
    required this.onConnect,
    required this.onDisconnectX,
    required this.busy,
    required this.message,
  });

  final Profile profile;
  final void Function(Provider provider)? onConnect;
  final VoidCallback? onDisconnectX;
  final bool busy;
  final String? message;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 2, color: Broadcast.podiumEdge),
          const SizedBox(height: 16),
          Text(
            profile.anonymous
                ? 'Your scores live in this browser only.'
                : 'Your scores are saved to your account.',
            style: Broadcast.body(12, color: Broadcast.chalkDim),
          ),
          const SizedBox(height: 12),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final provider in Provider.values)
                  if (!(provider == Provider.x && profile.hasX))
                    _DrawerButton(
                      label: 'Connect ${provider.label}',
                      onTap: onConnect == null
                          ? null
                          : () => onConnect!(provider),
                    ),
              ],
            ),
            if (profile.hasX) ...[
              const SizedBox(height: 8),
              _DrawerButton(
                label: 'Disconnect X',
                danger: true,
                onTap: onDisconnectX,
              ),
              const SizedBox(height: 6),
              Text(
                'Disconnecting removes your X name, picture and banner.',
                style: Broadcast.body(11, color: Broadcast.chalkDim),
              ),
            ],
          ],
          if (message != null) ...[
            const SizedBox(height: 10),
            Text(message!, style: Broadcast.body(12, color: Broadcast.cyan)),
          ],
        ],
      );
}

class _DrawerButton extends StatelessWidget {
  const _DrawerButton({
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) => Material(
        color: Broadcast.podium,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(
                color: danger ? Broadcast.magenta : Broadcast.podiumEdge,
                width: 2,
              ),
            ),
            child: Text(
              label,
              style: Broadcast.body(
                12,
                color: danger ? Broadcast.magenta : Broadcast.chalk,
              ),
            ),
          ),
        ),
      );
}
