import 'package:flutter/material.dart';

import '../theme/broadcast.dart';
import 'linking.dart';

/// The offer to keep a Player's progress.
///
/// Shown at the end of a Round they did well in, never on arrival. Demanding
/// an account from a stranger who has answered nothing kills the drop-in-and-
/// play property the whole game rests on; asking somebody who has just scored
/// fourteen thousand is asking at the one moment they care.
///
/// Anonymous progress is far more fragile than it looks — browser storage
/// eviction loses more accounts than any reaper ever will — so this is the
/// real answer to that, and its timing is the whole design.
class SavePrompt extends StatefulWidget {
  const SavePrompt({
    super.key,
    required this.score,
    required this.onDismiss,
    this.linker = link,
  });

  final int score;
  final VoidCallback onDismiss;

  /// Injected so a test never opens a popup.
  final Future<LinkOutcome> Function(Provider) linker;

  @override
  State<SavePrompt> createState() => _SavePromptState();
}

class _SavePromptState extends State<SavePrompt> {
  String? _message;
  bool _busy = false;

  Future<void> _try(Provider provider) async {
    setState(() => _busy = true);
    final outcome = await widget.linker(provider);
    if (!mounted) return;

    setState(() {
      _busy = false;
      _message = switch (outcome) {
        LinkOutcome.linked => 'Saved. This score is yours for good.',
        LinkOutcome.switchedAndMerged =>
          'Welcome back — your scores have been combined.',
        LinkOutcome.switchedOnly =>
          "Signed in, but this round's score didn't transfer.",
        LinkOutcome.cancelled => null,
        LinkOutcome.unavailable =>
          '${provider.label} sign-in is not switched on yet.',
        LinkOutcome.failed => "That didn't work. Try again?",
      };
    });

    if (outcome == LinkOutcome.linked ||
        outcome == LinkOutcome.switchedAndMerged) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted) widget.onDismiss();
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Broadcast.setNavy,
      border: Border.all(color: Broadcast.gold, width: 2),
      boxShadow: Broadcast.bevel,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'You scored ${widget.score}. Keep it?',
          textAlign: TextAlign.center,
          style: Broadcast.body(15, weight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Without an account this disappears when your browser forgets you.',
          textAlign: TextAlign.center,
          style: Broadcast.body(11, color: Broadcast.chalkDim),
        ),
        const SizedBox(height: 12),
        if (_message != null)
          Text(
            _message!,
            textAlign: TextAlign.center,
            style: Broadcast.body(12, color: Broadcast.cyan),
          )
        else if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final p in Provider.values)
                _SaveButton(label: p.label, onTap: () => _try(p)),
            ],
          ),
        const SizedBox(height: 8),
        InkWell(
          onTap: widget.onDismiss,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Text(
              'not now',
              style: Broadcast.body(11, color: Broadcast.chalkDim),
            ),
          ),
        ),
      ],
    ),
  );
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Broadcast.podium,
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Broadcast.podiumEdge, width: 2),
        ),
        child: Text(label, style: Broadcast.body(13)),
      ),
    ),
  );
}
