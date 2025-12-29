import 'package:flutter/material.dart';

/// Model representing an active Jellyfin session/device.
class SessionDevice {
  final String sessionId;
  final String deviceName;
  final String deviceId;
  final String client;
  final String? applicationVersion;
  final String? userName;
  final String? userId;
  final bool supportsRemoteControl;
  final bool supportsMediaControl;
  final String? nowPlayingItemId;
  final String? nowPlayingItemName;
  final String? nowPlayingItemType;
  final bool? isPaused;
  final int? positionTicks;

  /// From Capabilities object - list of supported commands.
  final List<String> supportedCommands;

  /// From Capabilities object - list of playable media types.
  final List<String> playableMediaTypes;

  const SessionDevice({
    required this.sessionId,
    required this.deviceName,
    required this.deviceId,
    required this.client,
    this.applicationVersion,
    this.userName,
    this.userId,
    this.supportsRemoteControl = false,
    this.supportsMediaControl = false,
    this.nowPlayingItemId,
    this.nowPlayingItemName,
    this.nowPlayingItemType,
    this.isPaused,
    this.positionTicks,
    this.supportedCommands = const [],
    this.playableMediaTypes = const [],
  });

  /// Returns an appropriate icon for the client type.
  IconData get icon {
    final clientLower = client.toLowerCase();

    if (clientLower.contains('android') || clientLower.contains('mobile')) {
      return Icons.phone_android;
    }
    if (clientLower.contains('ios') || clientLower.contains('iphone') || clientLower.contains('ipad')) {
      return Icons.phone_iphone;
    }
    if (clientLower.contains('tv') || clientLower.contains('roku') || clientLower.contains('fire')) {
      return Icons.tv;
    }
    if (clientLower.contains('web') || clientLower.contains('browser')) {
      return Icons.language;
    }
    if (clientLower.contains('kodi') || clientLower.contains('infuse')) {
      return Icons.connected_tv;
    }
    if (clientLower.contains('chromecast') || clientLower.contains('cast')) {
      return Icons.cast;
    }
    if (clientLower.contains('windows') || clientLower.contains('mac') || clientLower.contains('desktop')) {
      return Icons.computer;
    }

    return Icons.devices;
  }

  /// Whether this session is currently playing something.
  bool get isPlaying => nowPlayingItemId != null;

  static String? _toDisplayType(dynamic value) {
    if (value == null) return null;

    // Prefer Enum.name if present (Dart enums).
    try {
      final dynamic name = (value as dynamic).name;
      if (name is String && name.isNotEmpty) return name;
    } catch (_) {
      // ignore
    }

    // Fallback: "BaseItemKind.movie" -> "movie"
    final s = value.toString();
    if (s.contains('.')) return s.split('.').last;
    return s;
  }

  /// Creates a SessionDevice from Jellyfin session dto (jellyfin_dart typed).
  factory SessionDevice.fromDto(dynamic dto) {
    final nowPlaying = dto.nowPlayingItem;

    final dynamic rawType = nowPlaying?.type;
    final String? typeString = _toDisplayType(rawType);

    return SessionDevice(
      sessionId: (dto.id ?? '').toString(),
      deviceName: (dto.deviceName ?? 'Unknown Device').toString(),
      deviceId: (dto.deviceId ?? '').toString(),
      client: (dto.client ?? 'Unknown Client').toString(),
      userName: dto.userName?.toString(),
      supportsRemoteControl: dto.supportsRemoteControl ?? false,
      supportsMediaControl: dto.supportsMediaControl ?? false,
      nowPlayingItemId: nowPlaying?.id?.toString(),
      nowPlayingItemName: nowPlaying?.name?.toString(),
      nowPlayingItemType: typeString,
    );
  }

  /// Creates a SessionDevice from raw JSON (Jellyfin uses PascalCase keys).
  /// Use this to bypass jellyfin_dart's broken DTO parsing.
  factory SessionDevice.fromJson(Map<String, dynamic> json) {
    final nowPlaying = json['NowPlayingItem'] as Map<String, dynamic>?;
    final playState = json['PlayState'] as Map<String, dynamic>?;
    final capabilities = json['Capabilities'] as Map<String, dynamic>?;

    // Parse SupportedCommands from Capabilities
    List<String> supportedCommands = [];
    final rawCommands = capabilities?['SupportedCommands'];
    if (rawCommands is List) {
      supportedCommands = rawCommands.map((e) => e.toString()).toList();
    }

    // Parse PlayableMediaTypes from Capabilities
    List<String> playableMediaTypes = [];
    final rawMediaTypes = capabilities?['PlayableMediaTypes'];
    if (rawMediaTypes is List) {
      playableMediaTypes = rawMediaTypes.map((e) => e.toString()).toList();
    }

    return SessionDevice(
      sessionId: (json['Id'] ?? '').toString(),
      deviceName: (json['DeviceName'] ?? 'Unknown Device').toString(),
      deviceId: (json['DeviceId'] ?? '').toString(),
      client: (json['Client'] ?? 'Unknown Client').toString(),
      applicationVersion: json['ApplicationVersion']?.toString(),
      userName: json['UserName']?.toString(),
      userId: json['UserId']?.toString(),
      supportsRemoteControl: json['SupportsRemoteControl'] == true,
      supportsMediaControl: json['SupportsMediaControl'] == true ||
          capabilities?['SupportsMediaControl'] == true,
      nowPlayingItemId: nowPlaying?['Id']?.toString(),
      nowPlayingItemName: nowPlaying?['Name']?.toString(),
      nowPlayingItemType: nowPlaying?['Type']?.toString(),
      isPaused: playState?['IsPaused'] as bool?,
      positionTicks: playState?['PositionTicks'] as int?,
      supportedCommands: supportedCommands,
      playableMediaTypes: playableMediaTypes,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SessionDevice && other.sessionId == sessionId;
  }

  @override
  int get hashCode => sessionId.hashCode;

  @override
  String toString() => 'SessionDevice(id: $sessionId, device: $deviceName, client: $client)';
}
