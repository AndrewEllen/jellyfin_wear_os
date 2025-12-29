import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/jellyfin_constants.dart';
import '../../core/constants/prefs_keys.dart';
import '../jellyfin/jellyfin_client_wrapper.dart';
import '../models/session_device.dart';

/// Repository for managing Jellyfin sessions.
class SessionRepository {
  final JellyfinClientWrapper _client;

  SessionRepository(this._client);

  /// Gets all active sessions (devices) that can be controlled by the current user.
  ///
  /// Uses raw HTTP to bypass jellyfin_dart's broken TranscodeReasons parsing.
  /// Adds ControllableByUserId filter to get only controllable sessions.
  Future<List<SessionDevice>> getActiveSessions() async {
    try {
      final userId = _client.userId;
      final deviceId = _client.deviceId;

      JellyfinConstants.log(
        '========== GET SESSIONS START ==========\n'
        '  userId=$userId\n'
        '  deviceId=$deviceId',
      );

      // Use ControllableByUserId to filter to sessions this user can control
      // This is critical for finding the right controllable session
      final queryParams = <String, dynamic>{};
      if (userId != null) {
        queryParams['ControllableByUserId'] = userId;
      }

      final response = await _client.get('/Sessions', queryParameters: queryParams);

      if (response.statusCode != 200) {
        throw Exception('Failed to get sessions: ${response.statusCode}');
      }

      final sessionsJson = response.data as List<dynamic>;
      JellyfinConstants.log(
        '/Sessions?ControllableByUserId=$userId returned ${sessionsJson.length} sessions',
      );

      // Log each session in detail for debugging
      for (int i = 0; i < sessionsJson.length; i++) {
        final s = sessionsJson[i];
        final playState = s['PlayState'] as Map<String, dynamic>?;
        final nowPlaying = s['NowPlayingItem'] as Map<String, dynamic>?;
        final capabilities = s['Capabilities'] as Map<String, dynamic>?;

        JellyfinConstants.log(
          '--- Session [$i] ---\n'
          '  Id: ${s['Id']}\n'
          '  DeviceId: ${s['DeviceId']}\n'
          '  DeviceName: ${s['DeviceName']}\n'
          '  Client: ${s['Client']} v${s['ApplicationVersion']}\n'
          '  UserName: ${s['UserName']} (UserId: ${s['UserId']})\n'
          '  IsActive: ${s['IsActive']}\n'
          '  SupportsRemoteControl: ${s['SupportsRemoteControl']}\n'
          '  SupportsMediaControl: ${s['SupportsMediaControl']}\n'
          '  Capabilities.SupportsMediaControl: ${capabilities?['SupportsMediaControl']}\n'
          '  Capabilities.SupportedCommands: ${capabilities?['SupportedCommands']}\n'
          '  NowPlayingItem: ${nowPlaying?['Name']} (Id: ${nowPlaying?['Id']}, Type: ${nowPlaying?['Type']})\n'
          '  PlayState.IsPaused: ${playState?['IsPaused']}\n'
          '  PlayState.PlayMethod: ${playState?['PlayMethod']}\n'
          '  PlayState.PositionTicks: ${playState?['PositionTicks']}',
        );
      }

      // Filter out empty IDs
      final nonEmpty = sessionsJson
          .where((s) => (s['Id'] ?? '').toString().isNotEmpty)
          .toList();
      JellyfinConstants.log('After filtering empty IDs: ${nonEmpty.length} sessions');

      // Filter out self (this watch device)
      final filtered = nonEmpty
          .where((s) => (s['DeviceId'] ?? '').toString() != (deviceId ?? ''))
          .toList();
      JellyfinConstants.log('After excluding self (deviceId=$deviceId): ${filtered.length} sessions');

      // Map to SessionDevice objects
      final mapped = filtered
          .map((json) => SessionDevice.fromJson(json as Map<String, dynamic>))
          .toList();

      // Sort: prefer sessions that support media control and have something playing
      mapped.sort((a, b) {
        // Prioritize sessions with media control support
        final aControllable = a.supportsMediaControl ? 1 : 0;
        final bControllable = b.supportsMediaControl ? 1 : 0;
        if (aControllable != bControllable) {
          return bControllable - aControllable;
        }
        // Then prioritize sessions with something playing
        final aPlaying = a.nowPlayingItemId != null ? 1 : 0;
        final bPlaying = b.nowPlayingItemId != null ? 1 : 0;
        return bPlaying - aPlaying;
      });

      JellyfinConstants.log(
        '========== GET SESSIONS END: ${mapped.length} controllable sessions ==========',
      );

      return mapped;
    } catch (e, st) {
      JellyfinConstants.log('getActiveSessions() FAILED', error: e, stack: st);
      return [];
    }
  }

  /// Starts playback on a session.
  /// Uses POST /Sessions/{sessionId}/Playing with query params.
  Future<bool> play({
    required String sessionId,
    required List<String> itemIds,
    int? startPositionTicks,
  }) async {
    try {
      final userId = _client.userId;

      JellyfinConstants.log(
        '========== PLAY COMMAND ==========\n'
        '  sessionId: $sessionId\n'
        '  itemIds: $itemIds\n'
        '  startPositionTicks: $startPositionTicks\n'
        '  controllingUserId: $userId',
      );

      final queryParams = <String, dynamic>{
        'itemIds': itemIds.join(','),
        'playCommand': 'PlayNow',
      };
      if (startPositionTicks != null) {
        queryParams['startPositionTicks'] = startPositionTicks;
      }
      // Add controllingUserId - some server versions require this
      if (userId != null) {
        queryParams['controllingUserId'] = userId;
      }

      final path = '/Sessions/$sessionId/Playing';
      JellyfinConstants.log('Sending POST $path with params: $queryParams');

      final resp = await _client.post(path, queryParameters: queryParams);

      JellyfinConstants.log('play() SUCCESS: statusCode=${resp.statusCode}');
      return true;
    } catch (e, st) {
      JellyfinConstants.log('play() FAILED', error: e, stack: st);
      return false;
    }
  }

  /// Queues items for playback on a session (play next).
  Future<bool> queueNext({
    required String sessionId,
    required List<String> itemIds,
  }) async {
    try {
      final userId = _client.userId;

      JellyfinConstants.log(
        '========== QUEUE NEXT COMMAND ==========\n'
        '  sessionId: $sessionId\n'
        '  itemIds: $itemIds\n'
        '  controllingUserId: $userId',
      );

      final queryParams = <String, dynamic>{
        'itemIds': itemIds.join(','),
        'playCommand': 'PlayNext',
      };
      if (userId != null) {
        queryParams['controllingUserId'] = userId;
      }

      final path = '/Sessions/$sessionId/Playing';
      JellyfinConstants.log('Sending POST $path with params: $queryParams');

      final resp = await _client.post(path, queryParameters: queryParams);

      JellyfinConstants.log('queueNext() SUCCESS: statusCode=${resp.statusCode}');
      return true;
    } catch (e, st) {
      JellyfinConstants.log('queueNext() FAILED', error: e, stack: st);
      return false;
    }
  }

  /// Queues items at the end of the playlist.
  Future<bool> queueLast({
    required String sessionId,
    required List<String> itemIds,
  }) async {
    try {
      final userId = _client.userId;

      JellyfinConstants.log(
        '========== QUEUE LAST COMMAND ==========\n'
        '  sessionId: $sessionId\n'
        '  itemIds: $itemIds\n'
        '  controllingUserId: $userId',
      );

      final queryParams = <String, dynamic>{
        'itemIds': itemIds.join(','),
        'playCommand': 'PlayLast',
      };
      if (userId != null) {
        queryParams['controllingUserId'] = userId;
      }

      final path = '/Sessions/$sessionId/Playing';
      JellyfinConstants.log('Sending POST $path with params: $queryParams');

      final resp = await _client.post(path, queryParameters: queryParams);

      JellyfinConstants.log('queueLast() SUCCESS: statusCode=${resp.statusCode}');
      return true;
    } catch (e, st) {
      JellyfinConstants.log('queueLast() FAILED', error: e, stack: st);
      return false;
    }
  }

  /// Saves the last used session ID.
  Future<void> saveLastSession(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.lastTargetSessionId, sessionId);
    JellyfinConstants.log('saveLastSession(): sessionId=$sessionId');
  }

  /// Gets the last used session ID.
  Future<String?> getLastSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(PrefsKeys.lastTargetSessionId);
    JellyfinConstants.log('getLastSessionId(): $id');
    return id;
  }

  /// Clears the last used session ID.
  Future<void> clearLastSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PrefsKeys.lastTargetSessionId);
    JellyfinConstants.log('clearLastSession()');
  }
}
