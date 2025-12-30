import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wearable_rotary/wearable_rotary.dart';

import '../../core/services/ongoing_activity_service.dart';
import '../../core/theme/wear_theme.dart';
import '../../data/repositories/library_repository.dart';
import '../../navigation/app_router.dart';
import '../../state/remote_state.dart';
import '../widgets/remote/playback_ring.dart';
import '../widgets/remote/volume_arc.dart';

/// Main remote control screen with transport controls, playback ring, and volume arc.
///
/// Features:
/// - Blurred background from now-playing artwork
/// - Full-circle playback progress ring at screen edge
/// - Volume arc at top (120°) inside the playback ring
/// - Center controls: play/pause, CC, audio, stop
/// - Rotary controls volume
/// - Swipe left for Seek, swipe right for Media Selection
class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key});

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  StreamSubscription<RotaryEvent>? _rotarySubscription;
  Timer? _volumeDeflateTimer;
  bool _volumeActive = false;

  @override
  void initState() {
    super.initState();
    OngoingActivityService.start(title: 'Jellyfin Remote');

    // Start polling playback state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RemoteState>().startPolling();
    });

    // Rotary controls volume on this screen
    _rotarySubscription = rotaryEvents.listen(_onRotaryEvent);
  }

  @override
  void dispose() {
    _volumeDeflateTimer?.cancel();
    _rotarySubscription?.cancel();
    OngoingActivityService.stop();
    super.dispose();
  }

  void _onRotaryEvent(RotaryEvent event) {
    final remoteState = context.read<RemoteState>();
    final currentVolume = remoteState.playbackState.volumeLevel;

    final delta = event.direction == RotaryDirection.clockwise ? 5 : -5;
    final newVolume = (currentVolume + delta).clamp(0, 100);

    if (newVolume != currentVolume) {
      HapticFeedback.lightImpact();
      remoteState.setVolume(newVolume);

      // Activate volume indicator
      if (!_volumeActive) {
        setState(() => _volumeActive = true);
      }
      _scheduleVolumeDeflate();
    }
  }

  void _scheduleVolumeDeflate() {
    _volumeDeflateTimer?.cancel();
    _volumeDeflateTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() => _volumeActive = false);
      }
    });
  }

  Future<void> _playPause() async {
    HapticFeedback.mediumImpact();
    await context.read<RemoteState>().playPause();
  }

  Future<void> _stop() async {
    HapticFeedback.mediumImpact();
    await context.read<RemoteState>().stop();
  }

  void _openSeek() {
    Navigator.pushNamed(context, AppRoutes.seek);
  }

  void _openAudioTracks() {
    Navigator.pushNamed(
      context,
      AppRoutes.trackPicker,
      arguments: const TrackPickerArgs(isAudio: true),
    );
  }

  void _openSubtitleTracks() {
    Navigator.pushNamed(
      context,
      AppRoutes.trackPicker,
      arguments: const TrackPickerArgs(isAudio: false),
    );
  }

  void _openMediaSelection() {
    Navigator.pushNamed(context, AppRoutes.mediaSelection);
  }

  String _formatTime(int ticks) {
    final seconds = ticks ~/ 10000000;
    final minutes = seconds ~/ 60;
    final hours = minutes ~/ 60;

    if (hours > 0) {
      return '$hours:${(minutes % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    }
    return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WearTheme.background,
      body: Consumer<RemoteState>(
        builder: (context, remoteState, child) {
          final playback = remoteState.playbackState;
          final isPlaying = playback.isPlaying;
          final isMuted = playback.isMuted;
          final volumeLevel = playback.volumeLevel;
          final progress = playback.progress;
          final positionTicks = playback.positionTicks;
          final durationTicks = playback.durationTicks ?? 0;

          return GestureDetector(
            // Swipe left to open seek
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity != null) {
                if (details.primaryVelocity! < -200) {
                  // Swipe left
                  _openSeek();
                } else if (details.primaryVelocity! > 200) {
                  // Swipe right
                  _openMediaSelection();
                }
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Blurred background image
                _buildBackground(playback.nowPlayingItemId),

                // Playback progress ring (outer)
                PlaybackRing(
                  progress: progress,
                  strokeWidth: 6,
                  edgePadding: 4,
                ),

                // Volume arc (top, inside playback ring)
                VolumeArc(
                  volumeLevel: volumeLevel,
                  isMuted: isMuted,
                  handleRotary: false, // We handle rotary in this screen
                  onVolumeChanged: (level) {
                    remoteState.setVolume(level);
                    if (!_volumeActive) {
                      setState(() => _volumeActive = true);
                    }
                    _scheduleVolumeDeflate();
                  },
                  edgePadding: 14, // Inside the playback ring
                ),

                // Center content
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Timestamp (tap to open seek)
                        GestureDetector(
                          onTap: _openSeek,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _formatTime(positionTicks),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              Text(
                                _formatTime(durationTicks),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: WearTheme.textSecondary,
                                    ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Control buttons row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Subtitles button
                            _ControlButton(
                              icon: Icons.closed_caption,
                              onTap: _openSubtitleTracks,
                              size: 28,
                            ),

                            // Play/Pause button (larger, highlighted)
                            _ControlButton(
                              icon: isPlaying ? Icons.pause : Icons.play_arrow,
                              onTap: _playPause,
                              size: 40,
                              highlighted: true,
                            ),

                            // Audio tracks button
                            _ControlButton(
                              icon: Icons.audiotrack,
                              onTap: _openAudioTracks,
                              size: 28,
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // Stop button
                        _ControlButton(
                          icon: Icons.stop,
                          onTap: _stop,
                          size: 24,
                        ),
                      ],
                    ),
                  ),
                ),

                // Volume active indicator (shows when adjusting volume)
                if (_volumeActive)
                  Positioned(
                    top: 32,
                    left: 0,
                    right: 0,
                    child: Text(
                      isMuted ? 'MUTED' : '$volumeLevel%',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isMuted
                            ? WearTheme.textSecondary
                            : const Color(0xFFFFD700),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBackground(String? itemId) {
    if (itemId == null) {
      return Container(color: WearTheme.background);
    }

    final libraryRepo = context.read<LibraryRepository>();
    final imageUrl = libraryRepo.getImageUrl(
      itemId,
      imageType: 'Backdrop',
      maxWidth: 400,
    );

    if (imageUrl == null) {
      return Container(color: WearTheme.background);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Background image
        CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          errorWidget: (context, url, error) =>
              Container(color: WearTheme.background),
          placeholder: (context, url) =>
              Container(color: WearTheme.background),
        ),
        // Blur overlay
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            color: Colors.black.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final bool highlighted;

  const _ControlButton({
    required this.icon,
    required this.onTap,
    this.size = 28,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    if (highlighted) {
      return Container(
        decoration: const BoxDecoration(
          color: WearTheme.jellyfinPurple,
          shape: BoxShape.circle,
        ),
        child: IconButton(
          onPressed: onTap,
          icon: Icon(icon, size: size),
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(),
        ),
      );
    }

    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: size),
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(),
    );
  }
}
