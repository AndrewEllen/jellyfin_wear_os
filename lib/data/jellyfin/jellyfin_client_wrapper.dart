import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/jellyfin_constants.dart';
import '../../core/constants/prefs_keys.dart';

/// Wrapper around Dio for Jellyfin API calls.
/// Uses raw HTTP instead of jellyfin_dart to avoid parsing bugs.
class JellyfinClientWrapper {
  Dio? _dio;
  String? _serverUrl;
  String? _accessToken;
  String? _userId;
  String? _deviceId;

  /// Whether the client is initialized and authenticated.
  bool get isAuthenticated => _dio != null && _accessToken != null;

  /// Current server URL.
  String? get serverUrl => _serverUrl;

  /// Current user ID.
  String? get userId => _userId;

  /// Current access token.
  String? get accessToken => _accessToken;

  /// Device ID for this app instance.
  String? get deviceId => _deviceId;

  /// Redacts token for logging (shows last 6 chars only).
  String _redactToken(String? token) {
    if (token == null || token.length < 10) return '***';
    return '***${token.substring(token.length - 6)}';
  }

  /// Builds the X-Emby-Authorization header required by Jellyfin.
  /// Format: MediaBrowser Client="...", Device="...", DeviceId="...", Version="...", Token="..."
  String _buildAuthHeader() {
    final parts = [
      'MediaBrowser Client="${JellyfinConstants.clientName}"',
      'Device="${JellyfinConstants.deviceName}"',
      'DeviceId="$_deviceId"',
      'Version="${JellyfinConstants.clientVersion}"',
    ];
    if (_accessToken != null) {
      parts.add('Token="$_accessToken"');
    }
    return parts.join(', ');
  }

  /// Initializes the client for a server URL.
  Future<void> initialize(String serverUrl) async {
    _serverUrl = serverUrl;
    _deviceId = await _getOrCreateDeviceId();

    JellyfinConstants.log(
      'JellyfinClient.initialize(): serverUrl=$serverUrl deviceId=$_deviceId',
    );

    _dio = Dio(BaseOptions(
      baseUrl: serverUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ));

    _dio!.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        options.headers['X-Emby-Authorization'] = _buildAuthHeader();
        handler.next(options);
      },
      onError: (error, handler) {
        JellyfinConstants.log(
          'HTTP ERROR: ${error.requestOptions.method} ${error.requestOptions.path} '
          '-> ${error.response?.statusCode ?? "NO_RESPONSE"} ${error.message}',
          error: error.response?.data,
        );
        handler.next(error);
      },
    ));
  }

  /// Sets the authentication token after login.
  void setAuthentication({
    required String accessToken,
    required String userId,
  }) {
    _accessToken = accessToken;
    _userId = userId;
    JellyfinConstants.log(
      'JellyfinClient.setAuthentication(): userId=$userId token=${_redactToken(accessToken)}',
    );
  }

  /// Authenticates with username and password.
  Future<Map<String, dynamic>?> login(String username, String password) async {
    if (_dio == null) {
      throw StateError('Client not initialized. Call initialize() first.');
    }

    JellyfinConstants.log('JellyfinClient.login(): username=$username');

    try {
      final response = await _dio!.post(
        '/Users/AuthenticateByName',
        data: {'Username': username, 'Pw': password},
      );

      final data = response.data as Map<String, dynamic>;
      _accessToken = data['AccessToken'] as String?;
      _userId = (data['User'] as Map<String, dynamic>?)?['Id'] as String?;

      JellyfinConstants.log(
        'JellyfinClient.login() SUCCESS: userId=$_userId token=${_redactToken(_accessToken)}',
      );
      return data;
    } catch (e) {
      JellyfinConstants.log('JellyfinClient.login() FAILED', error: e);
      rethrow;
    }
  }

  /// Logs out and clears authentication.
  Future<void> logout() async {
    JellyfinConstants.log('JellyfinClient.logout()');
    _accessToken = null;
    _userId = null;
    _dio = null;
    _serverUrl = null;
  }

  /// Gets or creates a persistent device ID.
  Future<String> _getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString(PrefsKeys.deviceId);

    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await prefs.setString(PrefsKeys.deviceId, deviceId);
      JellyfinConstants.log('JellyfinClient: Created new deviceId=$deviceId');
    }

    return deviceId;
  }

  // ===== Raw HTTP methods with heavy logging =====

  /// Makes a raw GET request to a Jellyfin API endpoint.
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    if (_dio == null) {
      throw StateError('Client not initialized');
    }

    final fullUrl = _buildFullUrl(path, queryParameters);
    final stopwatch = Stopwatch()..start();

    JellyfinConstants.log(
      'HTTP GET $fullUrl\n'
      '  Auth: MediaBrowser ...Token="${_redactToken(_accessToken)}"',
    );

    try {
      final response = await _dio!.get(path, queryParameters: queryParameters);
      stopwatch.stop();

      _logResponse('GET', path, response, stopwatch.elapsedMilliseconds);
      return response;
    } catch (e) {
      stopwatch.stop();
      JellyfinConstants.log(
        'HTTP GET $path FAILED after ${stopwatch.elapsedMilliseconds}ms',
        error: e,
      );
      rethrow;
    }
  }

  /// Makes a raw POST request to a Jellyfin API endpoint.
  Future<Response<dynamic>> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    if (_dio == null) {
      throw StateError('Client not initialized');
    }

    final fullUrl = _buildFullUrl(path, queryParameters);
    final stopwatch = Stopwatch()..start();

    JellyfinConstants.log(
      'HTTP POST $fullUrl\n'
      '  Auth: MediaBrowser ...Token="${_redactToken(_accessToken)}"\n'
      '  Body: ${_truncateJson(data)}',
    );

    try {
      final response = await _dio!.post(
        path,
        data: data,
        queryParameters: queryParameters,
      );
      stopwatch.stop();

      _logResponse('POST', path, response, stopwatch.elapsedMilliseconds);
      return response;
    } catch (e) {
      stopwatch.stop();
      JellyfinConstants.log(
        'HTTP POST $path FAILED after ${stopwatch.elapsedMilliseconds}ms',
        error: e,
      );
      rethrow;
    }
  }

  String _buildFullUrl(String path, Map<String, dynamic>? queryParameters) {
    if (queryParameters == null || queryParameters.isEmpty) {
      return '$_serverUrl$path';
    }
    final queryString = queryParameters.entries
        .map((e) => '${e.key}=${e.value}')
        .join('&');
    return '$_serverUrl$path?$queryString';
  }

  void _logResponse(
    String method,
    String path,
    Response response,
    int elapsedMs,
  ) {
    final statusCode = response.statusCode;
    final bodyPreview = _truncateJson(response.data);

    JellyfinConstants.log(
      'HTTP $method $path -> $statusCode (${elapsedMs}ms)\n'
      '  Response: $bodyPreview',
    );
  }

  String _truncateJson(dynamic data, {int maxLength = 500}) {
    if (data == null) return 'null';
    try {
      final jsonStr = data is String ? data : jsonEncode(data);
      if (jsonStr.length <= maxLength) return jsonStr;
      return '${jsonStr.substring(0, maxLength)}... (truncated)';
    } catch (e) {
      return data.toString();
    }
  }

  /// Backwards compatibility alias for get().
  Future<Response<dynamic>> rawGet(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) =>
      get(path, queryParameters: queryParameters);

  /// Constructs an image URL for an item.
  String? getImageUrl(
    String itemId, {
    String imageType = 'Primary',
    int? maxWidth,
    int? maxHeight,
  }) {
    if (_serverUrl == null) return null;

    final params = <String>[];
    if (maxWidth != null) params.add('maxWidth=$maxWidth');
    if (maxHeight != null) params.add('maxHeight=$maxHeight');

    final queryString = params.isNotEmpty ? '?${params.join('&')}' : '';

    return '$_serverUrl/Items/$itemId/Images/$imageType$queryString';
  }
}
