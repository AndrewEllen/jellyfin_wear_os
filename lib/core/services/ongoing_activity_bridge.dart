import 'package:flutter/services.dart';

/// Bridge for managing OngoingActivity state.
///
/// OngoingActivity is driven by session state:
/// - Start when a session has media loaded (playing OR paused)
/// - Stop when media is stopped, session cleared, or Stop button pressed
///
/// This bridge serializes calls to prevent race conditions from polling overlap.
class OngoingActivityBridge {
  static const _channel = MethodChannel('com.jellywear.jellyfin_wear_os/ongoing_activity');

  bool _shown = false;
  String? _lastTitle;

  // Serialize calls to prevent race conditions from polling overlap
  Future<void> _queue = Future.value();

  Future<void> _enqueue(Future<void> Function() op) {
    _queue = _queue.then((_) => op()).catchError((_) {});
    return _queue;
  }

  /// Syncs OngoingActivity state based on API-reported session state.
  ///
  /// Call this after each polling update when a session is selected.
  /// - [hasMedia]: true if NowPlayingItem != null (playing OR paused counts)
  /// - [title]: The media title to display
  Future<void> syncFromApi({
    required bool hasMedia,
    required String title,
  }) => _enqueue(() async {
    if (hasMedia) {
      if (!_shown || _lastTitle != title) {
        try {
          await _channel.invokeMethod('startOngoingActivity', {'title': title});
          _shown = true;
          _lastTitle = title;
        } catch (_) {
          // Ignore errors on non-Wear devices
        }
      }
    } else {
      if (_shown) {
        try {
          await _channel.invokeMethod('stopOngoingActivity');
        } catch (_) {
          // Ignore errors on non-Wear devices
        }
        _shown = false;
        _lastTitle = null;
      }
    }
  });

  /// Force stops the OngoingActivity regardless of current state.
  ///
  /// Call this when:
  /// - User presses Stop button (always, regardless of Jellyfin response)
  /// - User navigates back to session picker
  /// - Session is cleared
  Future<void> forceStop() => _enqueue(() async {
    try {
      await _channel.invokeMethod('stopOngoingActivity');
    } catch (_) {
      // Ignore errors on non-Wear devices
    }
    _shown = false;
    _lastTitle = null;
  });
}
