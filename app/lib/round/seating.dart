import 'package:cloud_functions/cloud_functions.dart';

/// Whether this Player may answer in the Round on screen.
class Seat {
  const Seat({required this.roundId, required this.seated, this.refusal});

  final String roundId;
  final bool seated;

  /// 'full', 'closed', 'busy', or null when seated.
  final String? refusal;
}

/// Takes a seat in whichever Round is live.
///
/// Seats belong to a Round, not to a session. Asking once when the page loads
/// seats you in the Round that happened to be running then, and every Round
/// after it refuses your Answers — which the screen reported as "too late",
/// because from the client a refusal looks the same whatever caused it.
abstract interface class Seating {
  Future<Seat> take(String roundId);
}

class CallableSeating implements Seating {
  CallableSeating({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Seat> take(String roundId) async {
    try {
      final result = await _functions.httpsCallable('ensurePlayer').call();
      final data = result.data as Map;
      return Seat(
        roundId: roundId,
        seated: data['seated'] as bool? ?? false,
        refusal: data['reason'] as String?,
      );
    } catch (_) {
      // Worth retrying on the next Round rather than locking the Player out.
      return Seat(roundId: roundId, seated: false, refusal: 'busy');
    }
  }
}
