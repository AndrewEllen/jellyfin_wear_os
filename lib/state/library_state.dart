import 'package:flutter/foundation.dart';

import '../data/models/library_item.dart';
import '../data/repositories/library_repository.dart';

/// State for library browsing.
class LibraryState extends ChangeNotifier {
  final LibraryRepository _repository;

  List<LibraryView> _libraries = [];
  List<LibraryItem> _items = [];
  LibraryItem? _selectedItem;
  bool _isLoading = false;
  String? _errorMessage;

  // Navigation stack for back navigation
  final List<_BrowseContext> _navigationStack = [];

  LibraryState(this._repository);

  /// Available libraries.
  List<LibraryView> get libraries => _libraries;

  /// Current items being displayed.
  List<LibraryItem> get items => _items;

  /// Currently selected item (for detail view).
  LibraryItem? get selectedItem => _selectedItem;

  /// Whether data is currently loading.
  bool get isLoading => _isLoading;

  /// Error message if loading failed.
  String? get errorMessage => _errorMessage;

  /// Whether we can navigate back.
  bool get canGoBack => _navigationStack.isNotEmpty;

  /// Current browse title.
  String get currentTitle {
    if (_navigationStack.isEmpty) return 'Library';
    return _navigationStack.last.title;
  }

  /// Loads the user's library views.
  Future<void> loadLibraries() async {
    _setLoading(true);

    try {
      _libraries = await _repository.getLibraries();
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Failed to load libraries';
    }

    _setLoading(false);
  }

  /// Browses a library or folder.
  Future<void> browse({
    required String parentId,
    required String title,
    String? mediaType,
  }) async {
    _setLoading(true);

    // Push to navigation stack
    _navigationStack.add(_BrowseContext(
      parentId: parentId,
      title: title,
      mediaType: mediaType,
    ));

    try {
      List<String>? itemTypes;

      // Filter by media type if specified
      if (mediaType == 'movies') {
        itemTypes = ['Movie'];
      } else if (mediaType == 'tvshows') {
        itemTypes = ['Series'];
      } else if (mediaType == 'music') {
        itemTypes = ['MusicArtist'];
      }

      _items = await _repository.getItems(
        parentId: parentId,
        includeItemTypes: itemTypes,
      );
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Failed to load items';
    }

    _setLoading(false);
  }

  /// Browses into an item (series, season, artist, album).
  Future<void> browseItem(LibraryItem item) async {
    if (!item.isFolder) {
      _selectedItem = item;
      notifyListeners();
      return;
    }

    _setLoading(true);

    _navigationStack.add(_BrowseContext(
      parentId: item.id,
      title: item.name,
      itemType: item.type,
    ));

    try {
      switch (item.type) {
        case 'Series':
          _items = await _repository.getSeasons(item.id);
          break;
        case 'Season':
          _items = await _repository.getEpisodes(
            seriesId: item.seriesId ?? item.id,
            seasonId: item.id,
          );
          break;
        case 'MusicArtist':
          _items = await _repository.getArtistAlbums(item.id);
          break;
        case 'MusicAlbum':
          _items = await _repository.getAlbumTracks(item.id);
          break;
        default:
          _items = await _repository.getItems(parentId: item.id);
      }
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Failed to load items';
    }

    _setLoading(false);
  }

  /// Selects an item for detail view.
  Future<void> selectItem(String itemId) async {
    _setLoading(true);

    try {
      _selectedItem = await _repository.getItem(itemId);
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Failed to load item';
    }

    _setLoading(false);
  }

  /// Clears the selected item.
  void clearSelection() {
    _selectedItem = null;
    notifyListeners();
  }

  /// Goes back in the navigation stack.
  Future<void> goBack() async {
    if (_navigationStack.isEmpty) return;

    _navigationStack.removeLast();

    if (_navigationStack.isEmpty) {
      _items = [];
      notifyListeners();
      return;
    }

    // Reload previous context
    final context = _navigationStack.removeLast();
    await browse(
      parentId: context.parentId,
      title: context.title,
      mediaType: context.mediaType,
    );
  }

  /// Clears navigation stack and items.
  void reset() {
    _navigationStack.clear();
    _items = [];
    _selectedItem = null;
    _errorMessage = null;
    notifyListeners();
  }

  /// Gets the image URL for an item.
  String? getImageUrl(String itemId) {
    return _repository.getImageUrl(itemId);
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}

/// Internal class to track navigation context.
class _BrowseContext {
  final String parentId;
  final String title;
  final String? mediaType;
  final String? itemType;

  _BrowseContext({
    required this.parentId,
    required this.title,
    this.mediaType,
    this.itemType,
  });
}
