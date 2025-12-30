import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/wear_theme.dart';
import '../../data/models/library_item.dart';
import '../../data/repositories/library_repository.dart';
import '../../navigation/app_router.dart';
import '../../state/session_state.dart';
import '../widgets/common/rotary_wheel_list.dart';

/// Media selection screen for browsing and playing content.
///
/// Features:
/// - Search bar for finding content
/// - Continue Watching section with horizontal image cards
/// - Recently Added section with horizontal image cards
/// - Media Library button
/// - Settings button
class MediaSelectionScreen extends StatefulWidget {
  const MediaSelectionScreen({super.key});

  @override
  State<MediaSelectionScreen> createState() => _MediaSelectionScreenState();
}

class _MediaSelectionScreenState extends State<MediaSelectionScreen> {
  List<LibraryItem> _continueWatching = [];
  List<LibraryItem> _recentlyAdded = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    final libraryRepo = context.read<LibraryRepository>();

    final results = await Future.wait([
      libraryRepo.getContinueWatching(limit: 10),
      libraryRepo.getRecentlyAdded(limit: 10),
    ]);

    if (mounted) {
      setState(() {
        _continueWatching = results[0];
        _recentlyAdded = results[1];
        _isLoading = false;
      });
    }
  }

  Future<void> _playItem(LibraryItem item) async {
    HapticFeedback.mediumImpact();

    final sessionState = context.read<SessionState>();
    await sessionState.playOnTarget([item.id]);

    if (mounted) {
      Navigator.pop(context); // Return to remote
    }
  }

  void _openSearch() {
    Navigator.pushNamed(context, AppRoutes.libraryPicker);
  }

  void _openLibrary() {
    Navigator.pushNamed(context, AppRoutes.libraryPicker);
  }

  void _openSettings() {
    Navigator.pushNamed(context, AppRoutes.settings);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: WearTheme.background,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Build the list of sections
    final sections = <_SectionData>[];

    // Search section (always first)
    sections.add(_SectionData(
      type: _SectionType.search,
      title: 'Search',
    ));

    // Continue Watching
    if (_continueWatching.isNotEmpty) {
      sections.add(_SectionData(
        type: _SectionType.media,
        title: 'Continue Watching',
        items: _continueWatching,
      ));
    }

    // Recently Added
    if (_recentlyAdded.isNotEmpty) {
      sections.add(_SectionData(
        type: _SectionType.media,
        title: 'Recently Added',
        items: _recentlyAdded,
      ));
    }

    // Media Library
    sections.add(_SectionData(
      type: _SectionType.button,
      title: 'Media Library',
      icon: Icons.video_library,
      onTap: _openLibrary,
    ));

    // Settings
    sections.add(_SectionData(
      type: _SectionType.button,
      title: 'Settings',
      icon: Icons.settings,
      onTap: _openSettings,
    ));

    return Scaffold(
      backgroundColor: WearTheme.background,
      body: RotaryWheelList<_SectionData>(
        items: sections,
        itemExtent: 100,
        showScrollIndicator: true,
        itemBuilder: (context, section, index, isCentered) {
          return _buildSection(section, isCentered);
        },
        onItemTap: (section, index) {
          if (section.type == _SectionType.search) {
            _openSearch();
          } else if (section.type == _SectionType.button && section.onTap != null) {
            section.onTap!();
          }
        },
      ),
    );
  }

  Widget _buildSection(_SectionData section, bool isCentered) {
    switch (section.type) {
      case _SectionType.search:
        return _buildSearchSection(isCentered);
      case _SectionType.media:
        return _buildMediaSection(section.title, section.items!, isCentered);
      case _SectionType.button:
        return _buildButtonSection(section.title, section.icon!, isCentered);
    }
  }

  Widget _buildSearchSection(bool isCentered) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isCentered ? WearTheme.surface : WearTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search,
            color: isCentered ? WearTheme.jellyfinPurple : WearTheme.textSecondary,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'Search...',
            style: TextStyle(
              color: isCentered ? WearTheme.textPrimary : WearTheme.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaSection(String title, List<LibraryItem> items, bool isCentered) {
    final libraryRepo = context.read<LibraryRepository>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 4),
          child: Text(
            title,
            style: TextStyle(
              color: isCentered ? WearTheme.textPrimary : WearTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: 70,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final imageUrl = libraryRepo.getImageUrl(item.id, maxWidth: 120);

              return GestureDetector(
                onTap: () => _playItem(item),
                child: Container(
                  width: 50,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: WearTheme.surfaceVariant,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Image
                      if (imageUrl != null)
                        CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => const Icon(
                            Icons.movie,
                            size: 24,
                            color: WearTheme.textSecondary,
                          ),
                          placeholder: (context, url) => const Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      else
                        const Icon(
                          Icons.movie,
                          size: 24,
                          color: WearTheme.textSecondary,
                        ),
                      // Title overlay at bottom
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.8),
                              ],
                            ),
                          ),
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildButtonSection(String title, IconData icon, bool isCentered) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: isCentered ? WearTheme.surface : WearTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: isCentered ? WearTheme.jellyfinPurple : WearTheme.textSecondary,
            size: 24,
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              color: isCentered ? WearTheme.textPrimary : WearTheme.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

enum _SectionType { search, media, button }

class _SectionData {
  final _SectionType type;
  final String title;
  final List<LibraryItem>? items;
  final IconData? icon;
  final VoidCallback? onTap;

  _SectionData({
    required this.type,
    required this.title,
    this.items,
    this.icon,
    this.onTap,
  });
}
