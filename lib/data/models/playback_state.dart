import '../../core/constants/jellyfin_constants.dart';

/// Model representing the current playback state of a session.
class PlaybackState {
  /// Safely converts an enum or dynamic value to a String.
  static String? _asString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;

    // Try Dart enum .name property first
    try {
      final dynamic d = value;
      final n = d.name;
      if (n is String) return n;
    } catch (_) {
      // ignore - not a Dart enum with .name
    }

    // Fallback: parse "EnumType.value" format
    final s = value.toString();
    final dot = s.lastIndexOf('.');
    return dot >= 0 ? s.substring(dot + 1) : s;
  }

  final int positionTicks;
  final int? durationTicks;
  final bool isPaused;
  final bool isMuted;
  final int volumeLevel;
  final String? nowPlayingItemId;
  final String? nowPlayingItemName;
  final String? nowPlayingItemType;
  final String? nowPlayingArtist;
  final String? nowPlayingAlbum;
  final List<MediaStream> audioStreams;
  final List<MediaStream> subtitleStreams;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;
  final String? playMethod;

  const PlaybackState({
    this.positionTicks = 0,
    this.durationTicks,
    this.isPaused = true,
    this.isMuted = false,
    this.volumeLevel = 100,
    this.nowPlayingItemId,
    this.nowPlayingItemName,
    this.nowPlayingItemType,
    this.nowPlayingArtist,
    this.nowPlayingAlbum,
    this.audioStreams = const [],
    this.subtitleStreams = const [],
    this.audioStreamIndex,
    this.subtitleStreamIndex,
    this.playMethod,
  });

  /// Whether something is currently playing.
  bool get isPlaying => !isPaused && nowPlayingItemId != null;

  /// Whether there is any media loaded.
  bool get hasMedia => nowPlayingItemId != null;

  /// Progress as a value from 0.0 to 1.0.
  double get progress {
    if (durationTicks == null || durationTicks! <= 0) return 0;
    return positionTicks / durationTicks!;
  }

  /// Current position in seconds.
  int get positionSeconds => positionTicks ~/ JellyfinConstants.ticksPerSecond;

  /// Total duration in seconds.
  int? get durationSeconds => durationTicks != null
      ? durationTicks! ~/ JellyfinConstants.ticksPerSecond
      : null;

  /// Formatted position string (e.g., "1:23:45" or "23:45").
  String get formattedPosition => _formatDuration(positionSeconds);

  /// Formatted duration string.
  String get formattedDuration => _formatDuration(durationSeconds ?? 0);

  /// Formatted remaining time string.
  String get formattedRemaining {
    final remaining = (durationSeconds ?? 0) - positionSeconds;
    return '-${_formatDuration(remaining)}';
  }

  String _formatDuration(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Creates a PlaybackState from session info DTO.
  factory PlaybackState.fromSessionDto(dynamic sessionDto) {
    final playState = sessionDto.playState;
    final nowPlaying = sessionDto.nowPlayingItem;

    List<MediaStream> audioStreams = [];
    List<MediaStream> subtitleStreams = [];

    if (nowPlaying?.mediaStreams != null) {
      for (final stream in nowPlaying.mediaStreams!) {
        final mediaStream = MediaStream.fromDto(stream);
        final streamType = _asString(stream.type)?.toLowerCase();
        if (streamType == 'audio') {
          audioStreams.add(mediaStream);
        } else if (streamType == 'subtitle') {
          subtitleStreams.add(mediaStream);
        }
      }
    }

    return PlaybackState(
      positionTicks: playState?.positionTicks ?? 0,
      durationTicks: nowPlaying?.runTimeTicks,
      isPaused: playState?.isPaused ?? true,
      isMuted: playState?.isMuted ?? false,
      volumeLevel: playState?.volumeLevel ?? 100,
      nowPlayingItemId: _asString(nowPlaying?.id),
      nowPlayingItemName: nowPlaying?.name,
      nowPlayingItemType: _asString(nowPlaying?.type),
      nowPlayingArtist: nowPlaying?.albumArtist ??
          (nowPlaying?.artists?.isNotEmpty == true ? nowPlaying.artists!.first : null),
      nowPlayingAlbum: nowPlaying?.album,
      audioStreams: audioStreams,
      subtitleStreams: subtitleStreams,
      audioStreamIndex: playState?.audioStreamIndex,
      subtitleStreamIndex: playState?.subtitleStreamIndex,
      playMethod: _asString(playState?.playMethod),
    );
  }

  /// Creates a PlaybackState from raw JSON (Jellyfin uses PascalCase keys).
  /// Use this to bypass jellyfin_dart's broken DTO parsing.
  factory PlaybackState.fromJson(Map<String, dynamic> json) {
    final playState = json['PlayState'] as Map<String, dynamic>?;
    final nowPlaying = json['NowPlayingItem'] as Map<String, dynamic>?;

    List<MediaStream> audioStreams = [];
    List<MediaStream> subtitleStreams = [];

    final mediaStreams = nowPlaying?['MediaStreams'] as List<dynamic>? ?? [];
    for (final stream in mediaStreams) {
      final ms = MediaStream.fromJson(stream as Map<String, dynamic>);
      final streamType = ms.type.toLowerCase();
      if (streamType == 'audio') {
        audioStreams.add(ms);
      } else if (streamType == 'subtitle') {
        subtitleStreams.add(ms);
      }
    }

    return PlaybackState(
      positionTicks: playState?['PositionTicks'] ?? 0,
      durationTicks: nowPlaying?['RunTimeTicks'],
      isPaused: playState?['IsPaused'] ?? true,
      isMuted: playState?['IsMuted'] ?? false,
      volumeLevel: playState?['VolumeLevel'] ?? 100,
      nowPlayingItemId: nowPlaying?['Id']?.toString(),
      nowPlayingItemName: nowPlaying?['Name']?.toString(),
      nowPlayingItemType: nowPlaying?['Type']?.toString(),
      nowPlayingArtist: nowPlaying?['AlbumArtist']?.toString() ??
          ((nowPlaying?['Artists'] as List<dynamic>?)?.isNotEmpty == true
              ? (nowPlaying!['Artists'] as List<dynamic>).first?.toString()
              : null),
      nowPlayingAlbum: nowPlaying?['Album']?.toString(),
      audioStreams: audioStreams,
      subtitleStreams: subtitleStreams,
      audioStreamIndex: playState?['AudioStreamIndex'],
      subtitleStreamIndex: playState?['SubtitleStreamIndex'],
      playMethod: playState?['PlayMethod']?.toString(),
    );
  }

  /// Returns a copy with updated position.
  PlaybackState copyWithPosition(int newPositionTicks) {
    return PlaybackState(
      positionTicks: newPositionTicks,
      durationTicks: durationTicks,
      isPaused: isPaused,
      isMuted: isMuted,
      volumeLevel: volumeLevel,
      nowPlayingItemId: nowPlayingItemId,
      nowPlayingItemName: nowPlayingItemName,
      nowPlayingItemType: nowPlayingItemType,
      nowPlayingArtist: nowPlayingArtist,
      nowPlayingAlbum: nowPlayingAlbum,
      audioStreams: audioStreams,
      subtitleStreams: subtitleStreams,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
      playMethod: playMethod,
    );
  }

  @override
  String toString() =>
      'PlaybackState(item: $nowPlayingItemName, position: $formattedPosition/$formattedDuration, paused: $isPaused)';
}

/// Represents an audio or subtitle stream.
class MediaStream {
  final int index;
  final String type;
  final String? codec;
  final String? language;
  final String? displayTitle;
  final bool isDefault;
  final bool isForced;
  final bool isExternal;
  final int? channels;

  const MediaStream({
    required this.index,
    required this.type,
    this.codec,
    this.language,
    this.displayTitle,
    this.isDefault = false,
    this.isForced = false,
    this.isExternal = false,
    this.channels,
  });

  /// User-friendly display name.
  String get name {
    if (displayTitle != null && displayTitle!.isNotEmpty) {
      return displayTitle!;
    }

    final parts = <String>[];
    if (language != null) parts.add(language!);
    if (codec != null) parts.add(codec!.toUpperCase());
    if (channels != null && type == 'Audio') {
      parts.add('${channels}ch');
    }
    if (isDefault) parts.add('Default');
    if (isForced) parts.add('Forced');

    return parts.isNotEmpty ? parts.join(' • ') : 'Track ${index + 1}';
  }

  factory MediaStream.fromDto(dynamic dto) {
    return MediaStream(
      index: dto.index ?? 0,
      type: PlaybackState._asString(dto.type) ?? '',
      codec: dto.codec,
      language: dto.language,
      displayTitle: dto.displayTitle,
      isDefault: dto.isDefault ?? false,
      isForced: dto.isForced ?? false,
      isExternal: dto.isExternal ?? false,
      channels: dto.channels,
    );
  }

  /// Creates a MediaStream from raw JSON (Jellyfin uses PascalCase keys).
  factory MediaStream.fromJson(Map<String, dynamic> json) {
    return MediaStream(
      index: json['Index'] ?? 0,
      type: json['Type']?.toString() ?? '',
      codec: json['Codec']?.toString(),
      language: json['Language']?.toString(),
      displayTitle: json['DisplayTitle']?.toString(),
      isDefault: json['IsDefault'] == true,
      isForced: json['IsForced'] == true,
      isExternal: json['IsExternal'] == true,
      channels: json['Channels'],
    );
  }

  @override
  String toString() => 'MediaStream(index: $index, type: $type, name: $name)';
}
