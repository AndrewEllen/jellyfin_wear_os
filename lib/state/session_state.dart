import 'package:flutter/foundation.dart';

import '../core/constants/jellyfin_constants.dart';
import '../data/models/session_device.dart';
import '../data/repositories/session_repository.dart';

/// State for managing target session selection.
class SessionState extends ChangeNotifier {
  final SessionRepository _repository;

  List<SessionDevice> _sessions = [];
  SessionDevice? _targetSession;
  bool _isLoading = false;
  String? _errorMessage;

  SessionState(this._repository);

  List<SessionDevice> get sessions => _sessions;
  SessionDevice? get targetSession => _targetSession;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasTarget => _targetSession != null;

  Future<void> refreshSessions() async {
    _setLoading(true);

    try {
      JellyfinConstants.log('SessionState.refreshSessions() start');

      _sessions = await _repository.getActiveSessions();
      _errorMessage = null;

      JellyfinConstants.log('SessionState.refreshSessions(): ${_sessions.length} sessions');

      if (_targetSession == null) {
        await _tryRestoreLastSession();
      } else {
        final stillAvailable = _sessions.any((s) => s.sessionId == _targetSession!.sessionId);
        if (!stillAvailable) {
          JellyfinConstants.log(
            'SessionState.refreshSessions(): targetSession no longer available '
            'targetSession=${_targetSession!.sessionId}',
          );
          _targetSession = null;
          await _repository.clearLastSession();
        }
      }
    } catch (e, st) {
      JellyfinConstants.log('SessionState.refreshSessions() failed', error: e, stack: st);
      _errorMessage = 'Failed to load sessions: $e';
    }

    _setLoading(false);
  }

  Future<void> setTargetSession(SessionDevice session) async {
    JellyfinConstants.log('SessionState.setTargetSession(): ${session.sessionId}');
    _targetSession = session;
    await _repository.saveLastSession(session.sessionId);
    notifyListeners();
  }

  Future<void> clearTargetSession() async {
    JellyfinConstants.log('SessionState.clearTargetSession()');
    _targetSession = null;
    await _repository.clearLastSession();
    notifyListeners();
  }

  Future<bool> playOnTarget(List<String> itemIds) async {
    if (_targetSession == null) return false;
    return _repository.play(sessionId: _targetSession!.sessionId, itemIds: itemIds);
  }

  Future<bool> queueNextOnTarget(List<String> itemIds) async {
    if (_targetSession == null) return false;
    return _repository.queueNext(sessionId: _targetSession!.sessionId, itemIds: itemIds);
  }

  Future<void> _tryRestoreLastSession() async {
    final lastSessionId = await _repository.getLastSessionId();
    JellyfinConstants.log('SessionState._tryRestoreLastSession(): lastSessionId=$lastSessionId');

    if (lastSessionId == null) return;

    SessionDevice? match;
    for (final s in _sessions) {
      if (s.sessionId == lastSessionId) {
        match = s;
        break;
      }
    }

    if (match != null) {
      _targetSession = match;
      JellyfinConstants.log('SessionState._tryRestoreLastSession(): restored targetSession=${match.sessionId}');
    } else {
      JellyfinConstants.log('SessionState._tryRestoreLastSession(): lastSession not found in active sessions');
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
