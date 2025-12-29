import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/prefs_keys.dart';
import '../jellyfin/jellyfin_client_wrapper.dart';
import '../models/server_info.dart';

/// Repository for authentication and server management.
class AuthRepository {
  final JellyfinClientWrapper _client;

  AuthRepository(this._client);

  /// Attempts to restore a previous session.
  /// Returns true if successful, false otherwise.
  Future<bool> tryRestoreSession() async {
    final prefs = await SharedPreferences.getInstance();

    final serverUrl = prefs.getString(PrefsKeys.serverUrl);
    final authToken = prefs.getString(PrefsKeys.authToken);
    final userId = prefs.getString(PrefsKeys.userId);

    if (serverUrl == null || authToken == null || userId == null) {
      return false;
    }

    try {
      await _client.initialize(serverUrl);
      _client.setAuthentication(accessToken: authToken, userId: userId);

      // Verify the token is still valid by making a simple API call
      final response = await _client.get('/Users/$userId');
      if (response.statusCode == 200) {
        return true;
      }
    } catch (e) {
      // Token invalid or server unreachable
      await clearCredentials();
    }

    return false;
  }

  /// Logs in to a server with username and password.
  Future<bool> login({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    await _client.initialize(serverUrl);

    final result = await _client.login(username, password);

    if (result != null && _client.accessToken != null) {
      final user = result['User'] as Map<String, dynamic>?;
      await _saveCredentials(
        serverUrl: serverUrl,
        authToken: _client.accessToken!,
        userId: _client.userId!,
        userName: user?['Name']?.toString() ?? username,
      );
      return true;
    }

    return false;
  }

  /// Logs out and clears stored credentials.
  Future<void> logout() async {
    await _client.logout();
    await clearCredentials();
  }

  /// Saves authentication credentials to persistent storage.
  Future<void> _saveCredentials({
    required String serverUrl,
    required String authToken,
    required String userId,
    required String userName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefsKeys.serverUrl, serverUrl);
    await prefs.setString(PrefsKeys.authToken, authToken);
    await prefs.setString(PrefsKeys.userId, userId);
    await prefs.setString(PrefsKeys.userName, userName);
  }

  /// Clears stored credentials.
  Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PrefsKeys.serverUrl);
    await prefs.remove(PrefsKeys.authToken);
    await prefs.remove(PrefsKeys.userId);
    await prefs.remove(PrefsKeys.userName);
  }

  /// Gets the list of saved servers.
  Future<List<ServerInfo>> getSavedServers() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(PrefsKeys.savedServers);

    if (jsonString == null) return [];

    try {
      final jsonList = jsonDecode(jsonString) as List;
      return jsonList
          .map((json) => ServerInfo.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Saves a server to the saved servers list.
  Future<void> saveServer(ServerInfo server) async {
    final servers = await getSavedServers();

    // Remove existing entry with same ID
    servers.removeWhere((s) => s.id == server.id);

    // Add new entry at the beginning
    servers.insert(0, server.copyWith(lastConnected: DateTime.now()));

    // Keep only last 5 servers
    final trimmedServers = servers.take(5).toList();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      PrefsKeys.savedServers,
      jsonEncode(trimmedServers.map((s) => s.toJson()).toList()),
    );
  }

  /// Removes a server from the saved servers list.
  Future<void> removeServer(String serverId) async {
    final servers = await getSavedServers();
    servers.removeWhere((s) => s.id == serverId);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      PrefsKeys.savedServers,
      jsonEncode(servers.map((s) => s.toJson()).toList()),
    );
  }

  /// Gets the currently stored user name.
  Future<String?> getCurrentUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(PrefsKeys.userName);
  }

  /// Gets the currently stored server URL.
  Future<String?> getCurrentServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(PrefsKeys.serverUrl);
  }
}
