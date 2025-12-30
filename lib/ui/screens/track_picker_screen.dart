import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/jellyfin_constants.dart';
import '../../core/theme/wear_theme.dart';
import '../../data/models/playback_state.dart';
import '../../navigation/app_router.dart';
import '../../state/remote_state.dart';
import '../widgets/common/rotary_wheel_list.dart';

/// Screen for selecting audio or subtitle tracks.
///
/// Uses RotaryWheelList for a Wear-style wheel list with scale/fade effect.
class TrackPickerScreen extends StatefulWidget {
  final TrackPickerArgs? args;

  const TrackPickerScreen({super.key, this.args});

  @override
  State<TrackPickerScreen> createState() => _TrackPickerScreenState();
}

class _TrackPickerScreenState extends State<TrackPickerScreen> {
  bool _isLoading = true;
  final List<_Track> _tracks = [];
  int _selectedIndex = -1;

  bool get isAudio => widget.args?.isAudio ?? true;

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  void _loadTracks() {
    final remoteState = context.read<RemoteState>();
    final playbackState = remoteState.playbackState;

    JellyfinConstants.log(
      '========== LOAD TRACKS ==========\n'
      '  isAudio: $isAudio\n'
      '  audioStreams: ${playbackState.audioStreams.length}\n'
      '  subtitleStreams: ${playbackState.subtitleStreams.length}\n'
      '  currentAudioIndex: ${playbackState.audioStreamIndex}\n'
      '  currentSubtitleIndex: ${playbackState.subtitleStreamIndex}',
    );

    final List<MediaStream> streams;
    final int? currentIndex;

    if (isAudio) {
      streams = playbackState.audioStreams;
      currentIndex = playbackState.audioStreamIndex;
    } else {
      streams = playbackState.subtitleStreams;
      currentIndex = playbackState.subtitleStreamIndex;
    }

    setState(() {
      _isLoading = false;

      // For subtitles, add "None" option first
      if (!isAudio) {
        _tracks.add(_Track(index: -1, name: 'None', language: ''));
      }

      // Add all available tracks
      for (final stream in streams) {
        _tracks.add(_Track(
          index: stream.index,
          name: stream.name,
          language: stream.language ?? '',
        ));

        JellyfinConstants.log(
          '  Track: index=${stream.index} name=${stream.name} lang=${stream.language}',
        );
      }

      // Set current selection
      _selectedIndex = currentIndex ?? (isAudio ? 0 : -1);
    });

    JellyfinConstants.log('Loaded ${_tracks.length} tracks, selected=$_selectedIndex');
  }

  Future<void> _selectTrack(_Track track) async {
    HapticFeedback.mediumImpact();

    final remoteState = context.read<RemoteState>();

    JellyfinConstants.log(
      '========== SELECT TRACK ==========\n'
      '  isAudio: $isAudio\n'
      '  trackIndex: ${track.index}\n'
      '  trackName: ${track.name}',
    );

    setState(() => _selectedIndex = track.index);

    // Send track selection command to Jellyfin
    if (isAudio) {
      await remoteState.setAudioStream(track.index);
    } else {
      await remoteState.setSubtitleStream(track.index);
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final title = isAudio ? 'Audio' : 'Subtitles';

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: WearTheme.background,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_tracks.isEmpty) {
      return Scaffold(
        backgroundColor: WearTheme.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isAudio ? Icons.audiotrack : Icons.closed_caption,
                  size: 32,
                  color: WearTheme.textSecondary,
                ),
                const SizedBox(height: 8),
                Text(
                  'No $title',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'No tracks available',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: WearTheme.background,
      body: RotaryWheelList<_Track>(
        items: _tracks,
        itemExtent: 80,
        onItemTap: (track, index) => _selectTrack(track),
        itemBuilder: (context, track, index, isCentered) {
          return _buildTrackCard(track, isCentered);
        },
      ),
    );
  }

  Widget _buildTrackCard(_Track track, bool isCentered) {
    final isSelected = track.index == _selectedIndex;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSelected
            ? WearTheme.jellyfinPurple.withValues(alpha: 0.2)
            : (isCentered ? WearTheme.surface : WearTheme.surfaceVariant),
        borderRadius: BorderRadius.circular(16),
        border: isSelected
            ? Border.all(color: WearTheme.jellyfinPurple, width: 2)
            : (isCentered
                ? Border.all(color: WearTheme.textSecondary.withValues(alpha: 0.3), width: 1)
                : null),
      ),
      child: Row(
        children: [
          if (isSelected)
            const Icon(
              Icons.check_circle,
              size: 24,
              color: WearTheme.jellyfinPurple,
            )
          else
            Icon(
              Icons.circle_outlined,
              size: 24,
              color: isCentered ? WearTheme.textSecondary : WearTheme.textDisabled,
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: isSelected || isCentered ? FontWeight.bold : null,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (track.language.isNotEmpty)
                  Text(
                    track.language,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: WearTheme.textSecondary,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Track {
  final int index;
  final String name;
  final String language;

  _Track({
    required this.index,
    required this.name,
    required this.language,
  });
}
