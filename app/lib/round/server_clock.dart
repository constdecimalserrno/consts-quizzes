import 'dart:convert';

import 'package:http/http.dart' as http;

/// The difference between this device's clock and the server's.
///
/// The Slot schedule is absolute server time. A visitor whose machine is a
/// minute fast would see the wrong Question and have their Answers rejected as
/// late, with nothing on screen to explain it — and wrong clocks are common
/// enough that this is not a theoretical case.
class ServerClock {
  ServerClock({this.offsetMs = 0});

  final int offsetMs;

  int get nowMs => DateTime.now().millisecondsSinceEpoch + offsetMs;

  /// Measures the offset once, discounting half the round trip.
  ///
  /// Falls back to the local clock if the request fails: being a few seconds
  /// out is far better than not rendering at all.
  static Future<ServerClock> sync(Uri endpoint) async {
    try {
      final sentAt = DateTime.now().millisecondsSinceEpoch;
      final response = await http
          .get(endpoint)
          .timeout(const Duration(seconds: 5));
      final receivedAt = DateTime.now().millisecondsSinceEpoch;
      final serverNow = (jsonDecode(response.body) as Map)['now'] as int;

      final latency = (receivedAt - sentAt) ~/ 2;
      return ServerClock(offsetMs: serverNow + latency - receivedAt);
    } catch (_) {
      return ServerClock();
    }
  }
}
