import 'package:flutter/foundation.dart';

import '../../core/constants/jellyfin_constants.dart';
import '../jellyfin/jellyfin_client_wrapper.dart';
import '../models/library_item.dart';

/// Repository for browsing Jellyfin libraries.
class LibraryRepository {
  final JellyfinClientWrapper _client;

  LibraryRepository(this._client);

  /// Gets the user's library views (Movies, TV Shows, Music, etc.).
  Future<List<LibraryView>> getLibraries() async {
    final userId = _client.userId;
    debugPrint('[LibraryRepo] getLibraries - userId: $userId, isAuth: ${_client.isAuthenticated}');

    if (userId == null) {
      debugPrint('[LibraryRepo] userId is null');
      return [];
    }

    try {
      final response = await _client.get('/Users/$userId/Views');
      debugPrint('[LibraryRepo] Response: ${response.statusCode}');

      final data = response.data as Map<String, dynamic>;
      final items = data['Items'] as List<dynamic>? ?? [];

      return items.map((json) {
        debugPrint('[LibraryRepo] Processing: ${json['Name']}, collectionType: ${json['CollectionType']}');
        return LibraryView.fromJson(json as Map<String, dynamic>);
      }).toList();
    } catch (e, stack) {
      debugPrint('[LibraryRepo] Error: $e\n$stack');
      return [];
    }
  }

  /// Gets items from a library or folder.
  Future<List<LibraryItem>> getItems({
    required String parentId,
    List<String>? includeItemTypes,
    int startIndex = 0,
    int limit = JellyfinConstants.defaultPageSize,
    String? sortBy,
    String? sortOrder,
  }) async {
    final userId = _client.userId;
    if (userId == null) return [];

    try {
      final queryParams = <String, dynamic>{
        'parentId': parentId,
        'startIndex': startIndex,
        'limit': limit,
        'sortBy': sortBy ?? 'SortName',
        'sortOrder': sortOrder ?? 'Ascending',
        'fields': 'Overview,PrimaryImageAspectRatio',
        'imageTypeLimit': 1,
        'enableImageTypes': 'Primary,Backdrop',
      };

      if (includeItemTypes != null && includeItemTypes.isNotEmpty) {
        queryParams['includeItemTypes'] = includeItemTypes.join(',');
      }

      final response = await _client.get(
        '/Users/$userId/Items',
        queryParameters: queryParams,
      );

      final data = response.data as Map<String, dynamic>;
      final items = data['Items'] as List<dynamic>? ?? [];

      return items.map((json) => LibraryItem.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Gets seasons for a TV series.
  Future<List<LibraryItem>> getSeasons(String seriesId) async {
    final userId = _client.userId;
    if (userId == null) return [];

    try {
      final response = await _client.get(
        '/Shows/$seriesId/Seasons',
        queryParameters: {'userId': userId},
      );

      final data = response.data as Map<String, dynamic>;
      final items = data['Items'] as List<dynamic>? ?? [];

      return items.map((json) => LibraryItem.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Gets episodes for a TV series season.
  Future<List<LibraryItem>> getEpisodes({
    required String seriesId,
    String? seasonId,
    int? seasonNumber,
  }) async {
    final userId = _client.userId;
    if (userId == null) return [];

    try {
      final queryParams = <String, dynamic>{
        'userId': userId,
        'fields': 'Overview',
      };
      if (seasonId != null) queryParams['seasonId'] = seasonId;
      if (seasonNumber != null) queryParams['season'] = seasonNumber;

      final response = await _client.get(
        '/Shows/$seriesId/Episodes',
        queryParameters: queryParams,
      );

      final data = response.data as Map<String, dynamic>;
      final items = data['Items'] as List<dynamic>? ?? [];

      return items.map((json) => LibraryItem.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Gets tracks for a music album.
  Future<List<LibraryItem>> getAlbumTracks(String albumId) async {
    return getItems(
      parentId: albumId,
      includeItemTypes: ['Audio'],
      sortBy: 'IndexNumber',
    );
  }

  /// Gets albums for an artist.
  Future<List<LibraryItem>> getArtistAlbums(String artistId) async {
    final userId = _client.userId;
    if (userId == null) return [];

    try {
      final response = await _client.get(
        '/Users/$userId/Items',
        queryParameters: {
          'albumArtistIds': artistId,
          'includeItemTypes': 'MusicAlbum',
          'sortBy': 'ProductionYear,SortName',
          'sortOrder': 'Descending,Ascending',
        },
      );

      final data = response.data as Map<String, dynamic>;
      final items = data['Items'] as List<dynamic>? ?? [];

      return items.map((json) => LibraryItem.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Gets a single item by ID.
  Future<LibraryItem?> getItem(String itemId) async {
    final userId = _client.userId;
    if (userId == null) return null;

    try {
      final response = await _client.get('/Users/$userId/Items/$itemId');
      final data = response.data as Map<String, dynamic>;
      return LibraryItem.fromJson(data);
    } catch (e) {
      // Item not found
      return null;
    }
  }

  /// Searches for items by name.
  Future<List<LibraryItem>> search({
    required String query,
    List<String>? includeItemTypes,
    int limit = 20,
  }) async {
    final userId = _client.userId;
    if (userId == null) return [];

    try {
      final queryParams = <String, dynamic>{
        'searchTerm': query,
        'limit': limit,
        'recursive': true,
      };

      if (includeItemTypes != null && includeItemTypes.isNotEmpty) {
        queryParams['includeItemTypes'] = includeItemTypes.join(',');
      }

      final response = await _client.get(
        '/Users/$userId/Items',
        queryParameters: queryParams,
      );

      final data = response.data as Map<String, dynamic>;
      final items = data['Items'] as List<dynamic>? ?? [];

      return items.map((json) => LibraryItem.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Gets the image URL for an item.
  String? getImageUrl(
    String itemId, {
    String imageType = 'Primary',
    int maxWidth = JellyfinConstants.imageMaxWidth,
  }) {
    return _client.getImageUrl(
      itemId,
      imageType: imageType,
      maxWidth: maxWidth,
    );
  }
}
