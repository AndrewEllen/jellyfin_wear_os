import 'package:flutter/foundation.dart';

/// Jellyfin-specific constants for API and discovery.
abstract class JellyfinConstants {
  /// Toggle debug logging on/off.
  static const bool enableDebugLogs = true;

  /// Logs a debug message with optional error and stack trace.
  static void log(String message, {Object? error, StackTrace? stack}) {
    if (!enableDebugLogs) return;

    final ts = DateTime.now().toIso8601String();
    debugPrint('[JF][$ts] $message');

    if (error != null) {
      debugPrint('[JF][$ts] ERROR: $error');
    }
    if (stack != null) {
      debugPrint('[JF][$ts] STACK:\n$stack');
    }
  }

  // UDP server discovery
  static const int discoveryPort = 7359;
  static const Duration discoveryTimeout = Duration(seconds: 5);
  static const List<String> discoveryProbeStrings = [
    'Who is Jellyfin Server?',
    'Who is JellyfinServer?',
  ];

  // Client identification
  static const String clientName = 'Jellyfin Wear';
  static const String clientVersion = '1.0.0';
  static const String deviceName = 'Wear OS Watch';

  // API defaults
  static const int defaultPageSize = 50;
  static const int imageMaxWidth = 150; // Appropriate for watch display

  // Polling intervals
  static const Duration playbackPollInterval = Duration(seconds: 1);
  static const Duration sessionRefreshInterval = Duration(seconds: 10);

  // Time conversion (Jellyfin uses ticks: 10,000,000 ticks = 1 second)
  static const int ticksPerSecond = 10000000;
  static const int ticksPerMillisecond = 10000;
}
