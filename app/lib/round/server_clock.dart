import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// The difference between this device's clock and the server's.
///
/// The Slot schedule is absolute server time. A visitor whose machine is a
/// minute fast would see the wrong Question and have their Answers rejected as
/// late, with nothing on screen to explain it — and wrong clocks are common
/// enough that this is not a theoretical case.
// ignore_for_file: prefer_initializing_formals
class ServerClock {
  ServerClock({int offsetMs = 0}) : _offsetMs = offsetMs;

  int _offsetMs;

  int get offsetMs => _offsetMs;

  int get nowMs => DateTime.now().millisecondsSinceEpoch + _offsetMs;

  /// Measures the offset, discounting half the round trip.
  ///
  /// Returns false if the measurement failed, leaving the previous offset in
  /// place: being a few seconds out is far better than not rendering at all.
  Future<bool> resync(Uri endpoint) async {
    try {
      final sentAt = DateTime.now().millisecondsSinceEpoch;
      final response = await http
          .get(endpoint)
          .timeout(const Duration(seconds: 5));
      final receivedAt = DateTime.now().millisecondsSinceEpoch;
      final serverNow = (jsonDecode(response.body) as Map)['now'] as int;

      final latency = (receivedAt - sentAt) ~/ 2;
      _offsetMs = serverNow + latency - receivedAt;
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<ServerClock> sync(Uri endpoint) async {
    final clock = ServerClock();
    await clock.resync(endpoint);
    return clock;
  }

  /// Keeps measuring, because this page is meant to be left open.
  ///
  /// A single reading at load is enough for a page somebody closes again;
  /// a broadcast that runs all day drifts, and a suspended laptop comes back
  /// with a clock that is wrong by however long it slept. Drift shows up as
  /// Answers refused for no visible reason.
  Timer keepSynced(
    Uri endpoint, {
    Duration every = const Duration(minutes: 5),
  }) => Timer.periodic(every, (_) => resync(endpoint));
}
