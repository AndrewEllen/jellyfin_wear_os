import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/constants/jellyfin_constants.dart';
import '../core/services/ongoing_activity_bridge.dart';
import '../data/jellyfin/jellyfin_client_wrapper.dart';
import '../data/models/playback_state.dart';
import '../data/models/session_device.dart';

/// State for remote control functionality.
class RemoteState extends ChangeNotifier {
  final JellyfinClientWrapper _client;
  final OngoingActivityBridge _ongoingBridge = OngoingActivityBridge();

  SessionDevice? _targetSession;
  PlaybackState _playbackState = const PlaybackState();
  final bool _isLoading = false;
  String? _errorMessage;
  Timer? _pollTimer;

  RemoteState(this._client);

  /// Current target session.
  SessionDevice? get targetSession => _targetSession;

  /// Current playback state.
  PlaybackState get playbackState => _playbackState;

  /// Whether data is loading.
  bool get isLoading => _isLoading;

  /// Error message if an operation failed.
  String? get errorMessage => _errorMessage;

  /// Whether we're connected to a target session.
  bool get hasTarget => _targetSession != null;

  /// Whether something is playing.
  bool get isPlaying => _playbackState.isPlaying;

  /// Sets the target session and starts polling.
  void setTargetSession(SessionDevice session) {
    JellyfinConstants.log(
      '========== RemoteState.setTargetSession() ==========\n'
      '  sessionId=${session.sessionId}\n'
      '  deviceName=${session.deviceName}\n'
      '  deviceId=${session.deviceId}\n'
      '  client=${session.client} v${session.applicationVersion}\n'
      '  userName=${session.userName} (userId=${session.userId})\n'
      '  supportsRemoteControl=${session.supportsRemoteControl}\n'
      '  supportsMediaControl=${session.supportsMediaControl}\n'
      '  supportedCommands=${session.supportedCommands}\n'
      '  playableMediaTypes=${session.playableMediaTypes}\n'
      '  nowPlaying=${session.nowPlayingItemName} (${session.nowPlayingItemType})\n'
      '  isPaused=${session.isPaused}',
    );
    _targetSession = session;
    _startPolling();
    notifyListeners();
  }

  /// Clears the target session and stops polling.
  void clearTargetSession() {
    _stopPolling();
    unawaited(_ongoingBridge.forceStop());
    _targetSession = null;
    _playbackState = const PlaybackState();
    notifyListeners();
  }

  /// Starts polling (call when remote screen becomes visible).
  void startPolling() {
    if (_targetSession != null) {
      _startPolling();
    }
  }

  /// Stops polling (call when remote screen is disposed).
  void stopPolling() {
    _stopPolling();
  }

  /// Starts polling for playback state updates.
  void _startPolling() {
    _stopPolling();
    _pollTimer = Timer.periodic(
      JellyfinConstants.playbackPollInterval,
      (_) => _refreshPlaybackState(),
    );
    // Immediate first poll
    _refreshPlaybackState();
  }

  /// Stops polling.
  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Refreshes the current playback state.
  /// Uses raw HTTP with ControllableByUserId filter.
  Future<void> _refreshPlaybackState() async {
    if (_targetSession == null) {
      JellyfinConstants.log('_refreshPlaybackState(): No target session');
      return;
    }

    try {
      final userId = _client.userId;

      // Use ControllableByUserId to get only controllable sessions
      final queryParams = <String, dynamic>{};
      if (userId != null) {
        queryParams['ControllableByUserId'] = userId;
      }

      final response = await _client.rawGet('/Sessions', queryParameters: queryParams);
      if (response.statusCode != 200) {
        JellyfinConstants.log(
          '_refreshPlaybackState(): Failed with status ${response.statusCode}',
        );
        return;
      }

      final sessions = response.data as List<dynamic>;
      JellyfinConstants.log(
        '_refreshPlaybackState(): Got ${sessions.length} sessions, looking for ${_targetSession!.sessionId}',
      );

      final sessionJson = sessions.firstWhere(
        (s) => s['Id'] == _targetSession!.sessionId,
        orElse: () => null,
      );

      if (sessionJson == null) {
        JellyfinConstants.log(
          '_refreshPlaybackState(): Target session ${_targetSession!.sessionId} NOT FOUND in ${sessions.length} sessions',
        );
        _errorMessage = 'Session not found';
        notifyListeners();
        return;
      }

      final prevState = _playbackState;
      _playbackState = PlaybackState.fromJson(sessionJson as Map<String, dynamic>);

      // Log state changes
      if (_playbackState.isPlaying != prevState.isPlaying ||
          _playbackState.nowPlayingItemName != prevState.nowPlayingItemName) {
        JellyfinConstants.log(
          '_refreshPlaybackState(): State updated\n'
          '  isPlaying: ${prevState.isPlaying} -> ${_playbackState.isPlaying}\n'
          '  itemName: ${prevState.nowPlayingItemName} -> ${_playbackState.nowPlayingItemName}\n'
          '  isPaused: ${_playbackState.isPaused}\n'
          '  position: ${_playbackState.positionTicks}/${_playbackState.durationTicks}',
        );
      }

      _errorMessage = null;

      // Sync OngoingActivity with current media state
      if (_targetSession != null) {
        unawaited(_ongoingBridge.syncFromApi(
          hasMedia: _playbackState.hasMedia,
          title: _playbackState.nowPlayingItemName ?? 'Jellyfin Remote',
        ));
      }

      notifyListeners();
    } catch (e, st) {
      JellyfinConstants.log('_refreshPlaybackState() FAILED', error: e, stack: st);
      _errorMessage = 'Lost connection to device';
    }
  }

  // Playstate Commands

  /// Toggles play/pause.
  Future<void> playPause() async {
    await _sendPlaystateCommand('PlayPause');
  }

  /// Pauses playback.
  Future<void> pause() async {
    await _sendPlaystateCommand('Pause');
  }

  /// Resumes playback.
  Future<void> unpause() async {
    await _sendPlaystateCommand('Unpause');
  }

  /// Stops playback.
  Future<void> stop() async {
    try {
      await _sendPlaystateCommand('Stop');
    } finally {
      await _ongoingBridge.forceStop();
    }
  }

  /// Skips to next track.
  Future<void> next() async {
    await _sendPlaystateCommand('NextTrack');
  }

  /// Goes to previous track.
  Future<void> previous() async {
    await _sendPlaystateCommand('PreviousTrack');
  }

  /// Seeks to a specific position.
  Future<void> seek(int positionTicks) async {
    await _sendPlaystateCommand('Seek', seekPositionTicks: positionTicks);

    // Optimistically update local state
    _playbackState = _playbackState.copyWithPosition(positionTicks);
    notifyListeners();
  }

  /// Seeks forward by a number of seconds.
  Future<void> seekForward(int seconds) async {
    final newPosition = _playbackState.positionTicks +
        (seconds * JellyfinConstants.ticksPerSecond);
    final maxPosition = _playbackState.durationTicks ?? newPosition;
    await seek(newPosition.clamp(0, maxPosition));
  }

  /// Seeks backward by a number of seconds.
  Future<void> seekBackward(int seconds) async {
    final newPosition = _playbackState.positionTicks -
        (seconds * JellyfinConstants.ticksPerSecond);
    await seek(newPosition.clamp(0, _playbackState.durationTicks ?? 0));
  }

  /// Rewinds (fast backward).
  Future<void> rewind() async {
    await _sendPlaystateCommand('Rewind');
  }

  /// Fast forwards.
  Future<void> fastForward() async {
    await _sendPlaystateCommand('FastForward');
  }

  /// Sends a playstate command via raw HTTP.
  /// Uses POST /Sessions/{sessionId}/Playing/{command}
  Future<void> _sendPlaystateCommand(
    String command, {
    int? seekPositionTicks,
  }) async {
    if (_targetSession == null) {
      JellyfinConstants.log(
        '_sendPlaystateCommand($command): ABORTED - no target session',
      );
      return;
    }

    final sessionId = _targetSession!.sessionId;
    final userId = _client.userId;

    JellyfinConstants.log(
      '========== PLAYSTATE COMMAND ==========\n'
      '  command: $command\n'
      '  sessionId: $sessionId\n'
      '  deviceName: ${_targetSession!.deviceName}\n'
      '  client: ${_targetSession!.client}\n'
      '  seekPositionTicks: $seekPositionTicks\n'
      '  controllingUserId: $userId',
    );

    try {
      final queryParams = <String, dynamic>{};
      if (seekPositionTicks != null) {
        queryParams['seekPositionTicks'] = seekPositionTicks;
      }
      // Add controllingUserId - some server versions require this
      if (userId != null) {
        queryParams['controllingUserId'] = userId;
      }

      final path = '/Sessions/$sessionId/Playing/$command';
      JellyfinConstants.log('Sending POST $path with params: $queryParams');

      await _client.post(
        path,
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      JellyfinConstants.log('Playstate command SUCCESS: $command');
      _errorMessage = null;
    } catch (e, st) {
      _errorMessage = 'Command failed';
      JellyfinConstants.log(
        'Playstate command FAILED: $command',
        error: e,
        stack: st,
      );
    }

    notifyListeners();
  }

  // General Commands

  /// Increases volume.
  Future<void> volumeUp() async {
    await _sendGeneralCommand('VolumeUp');
  }

  /// Decreases volume.
  Future<void> volumeDown() async {
    await _sendGeneralCommand('VolumeDown');
  }

  /// Sets volume to a specific level (0-100).
  Future<void> setVolume(int level) async {
    await _sendGeneralCommand(
      'SetVolume',
      arguments: {'Volume': level.toString()},
    );
  }

  /// Toggles mute.
  Future<void> toggleMute() async {
    await _sendGeneralCommand('ToggleMute');
  }

  /// Mutes the session.
  Future<void> mute() async {
    await _sendGeneralCommand('Mute');
  }

  /// Unmutes the session.
  Future<void> unmute() async {
    await _sendGeneralCommand('Unmute');
  }

  /// Sets the audio stream index.
  Future<void> setAudioStream(int index) async {
    await _sendGeneralCommand(
      'SetAudioStreamIndex',
      arguments: {'Index': index.toString()},
    );
  }

  /// Sets the subtitle stream index. Use -1 to disable subtitles.
  Future<void> setSubtitleStream(int index) async {
    await _sendGeneralCommand(
      'SetSubtitleStreamIndex',
      arguments: {'Index': index.toString()},
    );
  }

  /// Sends a general command via raw HTTP.
  /// Uses POST /Sessions/{sessionId}/Command/{command} for simple commands
  /// or POST /Sessions/{sessionId}/Command with body for commands with arguments.
  Future<void> _sendGeneralCommand(
    String command, {
    Map<String, String>? arguments,
  }) async {
    if (_targetSession == null) {
      JellyfinConstants.log(
        '_sendGeneralCommand($command): ABORTED - no target session',
      );
      return;
    }

    final sessionId = _targetSession!.sessionId;

    JellyfinConstants.log(
      '========== GENERAL COMMAND ==========\n'
      '  command: $command\n'
      '  sessionId: $sessionId\n'
      '  deviceName: ${_targetSession!.deviceName}\n'
      '  client: ${_targetSession!.client}\n'
      '  arguments: $arguments',
    );

    try {
      if (arguments != null && arguments.isNotEmpty) {
        // Commands with arguments use POST body
        final path = '/Sessions/$sessionId/Command';
        final body = {'Name': command, 'Arguments': arguments};
        JellyfinConstants.log('Sending POST $path with body: $body');

        await _client.post(path, data: body);
      } else {
        // Simple commands use URL path
        final path = '/Sessions/$sessionId/Command/$command';
        JellyfinConstants.log('Sending POST $path');

        await _client.post(path);
      }

      JellyfinConstants.log('General command SUCCESS: $command');
      _errorMessage = null;
    } catch (e, st) {
      _errorMessage = 'Command failed';
      JellyfinConstants.log(
        'General command FAILED: $command',
        error: e,
        stack: st,
      );
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}
