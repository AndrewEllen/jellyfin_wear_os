import '../../core/constants/jellyfin_constants.dart';

/// Model representing a library item (movie, episode, song, etc.).
class LibraryItem {
  final String id;
  final String name;
  final String type;
  final String? seriesId;
  final String? seriesName;
  final String? albumId;
  final String? albumName;
  final String? artistName;
  final int? indexNumber;
  final int? parentIndexNumber;
  final int? runTimeTicks;
  final String? overview;
  final int? productionYear;
  final String? imagePrimaryTag;
  final String? imageBackdropTag;
  final double? communityRating;

  const LibraryItem({
    required this.id,
    required this.name,
    required this.type,
    this.seriesId,
    this.seriesName,
    this.albumId,
    this.albumName,
    this.artistName,
    this.indexNumber,
    this.parentIndexNumber,
    this.runTimeTicks,
    this.overview,
    this.productionYear,
    this.imagePrimaryTag,
    this.imageBackdropTag,
    this.communityRating,
  });

  /// Whether this item can be played directly.
  bool get isPlayable {
    return type == 'Movie' ||
        type == 'Episode' ||
        type == 'Audio' ||
        type == 'MusicVideo' ||
        type == 'Trailer';
  }

  /// Whether this item is a folder/container.
  bool get isFolder {
    return type == 'Series' ||
        type == 'Season' ||
        type == 'MusicAlbum' ||
        type == 'MusicArtist' ||
        type == 'Folder' ||
        type == 'CollectionFolder' ||
        type == 'Playlist' ||
        type == 'BoxSet';
  }

  /// Returns a formatted runtime string (e.g., "1h 30m").
  String? get formattedRuntime {
    if (runTimeTicks == null) return null;

    final totalSeconds = runTimeTicks! ~/ JellyfinConstants.ticksPerSecond;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  /// Returns a subtitle string based on item type.
  String? get subtitle {
    switch (type) {
      case 'Episode':
        if (seriesName != null && indexNumber != null) {
          final seasonEp = parentIndexNumber != null
              ? 'S${parentIndexNumber}E$indexNumber'
              : 'E$indexNumber';
          return '$seriesName • $seasonEp';
        }
        return seriesName;
      case 'Audio':
        return artistName ?? albumName;
      case 'Season':
        return seriesName;
      case 'MusicAlbum':
        return artistName;
      default:
        if (productionYear != null) {
          return productionYear.toString();
        }
        return null;
    }
  }

  /// Creates a LibraryItem from raw JSON (Jellyfin uses PascalCase keys).
  factory LibraryItem.fromJson(Map<String, dynamic> json) {
    final artists = json['Artists'] as List<dynamic>?;
    final imageTags = json['ImageTags'] as Map<String, dynamic>?;
    final backdropTags = json['BackdropImageTags'] as List<dynamic>?;

    return LibraryItem(
      id: (json['Id'] ?? '').toString(),
      name: (json['Name'] ?? 'Unknown').toString(),
      type: (json['Type'] ?? '').toString(),
      seriesId: json['SeriesId']?.toString(),
      seriesName: json['SeriesName']?.toString(),
      albumId: json['AlbumId']?.toString(),
      artistName: json['AlbumArtist']?.toString() ??
          (artists?.isNotEmpty == true ? artists!.first?.toString() : null),
      indexNumber: json['IndexNumber'] as int?,
      parentIndexNumber: json['ParentIndexNumber'] as int?,
      runTimeTicks: json['RunTimeTicks'] as int?,
      overview: json['Overview']?.toString(),
      productionYear: json['ProductionYear'] as int?,
      imagePrimaryTag: imageTags?['Primary']?.toString(),
      imageBackdropTag: backdropTags?.isNotEmpty == true
          ? backdropTags!.first?.toString()
          : null,
      communityRating: (json['CommunityRating'] as num?)?.toDouble(),
    );
  }

  @override
  String toString() => 'LibraryItem(id: $id, name: $name, type: $type)';
}

/// Represents a user's library view (Movies, TV Shows, Music, etc.).
class LibraryView {
  final String id;
  final String name;
  final String? collectionType;

  const LibraryView({
    required this.id,
    required this.name,
    this.collectionType,
  });

  /// Creates a LibraryView from raw JSON (Jellyfin uses PascalCase keys).
  factory LibraryView.fromJson(Map<String, dynamic> json) {
    return LibraryView(
      id: (json['Id'] ?? '').toString(),
      name: (json['Name'] ?? 'Unknown').toString(),
      collectionType: json['CollectionType']?.toString(),
    );
  }

  @override
  String toString() => 'LibraryView(id: $id, name: $name, type: $collectionType)';
}
