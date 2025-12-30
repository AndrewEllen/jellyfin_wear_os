import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wearable_rotary/wearable_rotary.dart';

import '../../core/services/hardware_button_service.dart';
import '../../core/services/ongoing_activity_service.dart';
import '../../core/theme/wear_theme.dart';
import '../../data/repositories/library_repository.dart';
import '../../navigation/app_router.dart';
import '../../state/remote_state.dart';
import '../widgets/remote/playback_ring.dart';
import '../widgets/remote/volume_button.dart';
import '../widgets/remote/volume_popup.dart';
import 'media_selection_screen.dart';
import 'seek_screen.dart';

/// Main remote control screen with transport controls, playback ring, and volume arc.
///
/// Features:
/// - 3-page PageView: Remote Controls, Seek, Media Selection
/// - Page 1: Blurred background, playback ring, volume controls
/// - Rotary controls volume on page 1
class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key});

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  // ============================================================
  // SENSITIVITY SETTINGS - Adjust these to tune responsiveness
  // ============================================================

  /// Pixels of rotary rotation needed to change volume by 1%.
  /// Higher = less sensitive, lower = more sensitive.
  static const double _volumeRotarySensitivity = 8;
  double _volumeRotaryAccum = 0.0;

  /// Pixels of drag needed to change volume by 1% in popup
  static const double _volumeDragSensitivity = 2.0;

  /// Seek increment in seconds per rotary tick on seek screen
  static const int _seekRotarySeconds = 5;

  // Local target volume while adjusting (avoids stale RemoteState base).
  int? _volumeTargetLevel;
  int? _volumePreviewLevel;
  int _lastAudibleVolume = 30;
  DateTime? _lastRotaryEventAt;

// Rate-limit outbound setVolume calls.
  static const Duration _volumeSendInterval = Duration(milliseconds: 60);

  Timer? _volumeSendTimer;
  int? _pendingVolumeToSend;
  int? _lastSentVolume;
  Timer? _volumePreviewFailsafeTimer;


  // ============================================================

  late PageController _pageController;
  Timer? _volumeDeflateTimer;
  bool _volumeActive = false;
  bool _showVolumePopup = false;
  double _volumeRotaryPixelAccum = 0.0;
  StreamSubscription<RotaryEvent>? _volumeRotarySubscription;
  StreamSubscription<int>? _buttonSubscription;

  @override
  void initState() {
    super.initState();
    OngoingActivityService.start(title: 'Jellyfin Remote');

    _pageController = PageController(initialPage: 0);

    // Start polling playback state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RemoteState>().startPolling();
    });

    // Subscribe to rotary for volume control on page 0
    _volumeRotarySubscription = rotaryEvents.listen(_onVolumeRotaryEvent);

    // Subscribe to hardware button for play/pause
    _buttonSubscription = HardwareButtonService.stemButtonEvents.listen((button) {
      if (button == 1) {
        _playPause();
      }
    });
  }

  @override
  void dispose() {
    _volumeDeflateTimer?.cancel();
    _volumeRotarySubscription?.cancel();
    _volumeSendTimer?.cancel();
    _volumePreviewFailsafeTimer?.cancel();
    _buttonSubscription?.cancel();
    _pageController.dispose();
    OngoingActivityService.stop();
    super.dispose();
  }

  void _toggleMuteLikeUser(RemoteState remoteState, int displayVolumeLevel) {
    final isMutedLike = displayVolumeLevel == 0 || remoteState.playbackState.isMuted;

    if (displayVolumeLevel > 0) {
      _lastAudibleVolume = displayVolumeLevel;
    }

    final int target = isMutedLike
        ? _lastAudibleVolume.clamp(1, 100)
        : 0;

    _volumeTargetLevel = target;
    _volumePreviewLevel = target;
    _queueVolumeSend(remoteState, target);

    if (!_volumeActive) {
      setState(() => _volumeActive = true);
    } else {
      setState(() {});
    }
    _scheduleVolumeDeflate();
  }


  void _onVolumeRotaryEvent(RotaryEvent event) {
    final page = _pageController.hasClients ? _pageController.page?.round() ?? 0 : 0;
    if (page != 0) return;

    final remoteState = context.read<RemoteState>();

    // magnitude can be null; docs say it's "magnitude of the rotation"
    final mag = event.magnitude ?? 1.0; // :contentReference[oaicite:1]{index=1}
    final dir = event.direction == RotaryDirection.clockwise ? 1.0 : -1.0;

    // Sensitivity: higher = less sensitive
    _volumeRotaryAccum += dir * (mag / _volumeRotarySensitivity);

    // Only apply whole "volume steps" when we've accumulated enough.
    final int delta = _volumeRotaryAccum.truncate(); // toward zero; good for +/-.
    if (delta == 0) {
      if (!_volumeActive) setState(() => _volumeActive = true);
      _scheduleVolumeDeflate();
      return;
    }
    _volumeRotaryAccum -= delta; // keep remainder for smooth control

    final base = _volumeTargetLevel ?? remoteState.playbackState.volumeLevel;
    final newVolume = (base + delta).clamp(0, 100);
    if (newVolume == base) return;

    HapticFeedback.selectionClick();

    _volumeTargetLevel = newVolume;
    _volumePreviewLevel = newVolume;
    _queueVolumeSend(remoteState, newVolume);

    if (!_volumeActive) {
      setState(() => _volumeActive = true);
    } else {
      setState(() {});
    }
    _scheduleVolumeDeflate();
  }


  void _queueVolumeSend(RemoteState remoteState, int level) {
    _pendingVolumeToSend = level;

    // Throttle: send immediately, then at most once per interval with latest.
    if (_volumeSendTimer != null) return;
    _flushVolumeSend(remoteState);
    _volumeSendTimer = Timer(_volumeSendInterval, () => _onVolumeSendTimer(remoteState));
  }

  void _onVolumeSendTimer(RemoteState remoteState) {
    _volumeSendTimer = null;

    if (_pendingVolumeToSend != null && _pendingVolumeToSend != _lastSentVolume) {
      _flushVolumeSend(remoteState);
      _volumeSendTimer = Timer(_volumeSendInterval, () => _onVolumeSendTimer(remoteState));
    } else {
      _pendingVolumeToSend = null;
    }
  }

  void _flushVolumeSend(RemoteState remoteState) {
    final v = _pendingVolumeToSend;
    if (v == null || v == _lastSentVolume) return;

    _lastSentVolume = v;
    remoteState.setVolume(v);
  }



  void _scheduleVolumeDeflate() {
    _volumeDeflateTimer?.cancel();
    _volumeDeflateTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() => _volumeActive = false);
    });

    // Failsafe: if playback never catches up, drop the preview eventually.
    _volumePreviewFailsafeTimer?.cancel();
    _volumePreviewFailsafeTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() {
        _volumePreviewLevel = null;
        _volumeTargetLevel = null;
      });
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

  Future<void> _skipNext() async {
    HapticFeedback.mediumImpact();
    await context.read<RemoteState>().next();
  }

  Future<void> _skipPrevious() async {
    HapticFeedback.mediumImpact();
    await context.read<RemoteState>().previous();
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
          return Stack(
            children: [
              // Main PageView content
              PageView(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                physics: const PageScrollPhysics(),
                onPageChanged: (index) {
                  // Clear volume active when switching pages
                  if (index != 0 && _volumeActive) {
                    setState(() => _volumeActive = false);
                  }
                },
                children: [
                  // Page 1: Remote Controls
                  _buildRemoteControlsPage(remoteState),
                  // Page 2: Seek Screen
                  SeekScreen(rotarySeekSeconds: _seekRotarySeconds),
                  // Page 3: Media Selection
                  const MediaSelectionScreen(),
                ],
              ),
              // Volume popup overlay (reads volume from RemoteState - single source of truth)
              if (_showVolumePopup)
                VolumePopup(
                  volume: _volumePreviewLevel ?? remoteState.playbackState.volumeLevel,
                  isMuted: remoteState.playbackState.isMuted,
                  onVolumeChanged: (level) => remoteState.setVolume(level),
                  onDismiss: () => setState(() => _showVolumePopup = false),
                  dragSensitivity: _volumeDragSensitivity,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRemoteControlsPage(RemoteState remoteState) {
    final playback = remoteState.playbackState;
    final isPlaying = playback.isPlaying;

    final volumeLevel = playback.volumeLevel;
    final displayVolumeLevel = _volumePreviewLevel ?? volumeLevel;

    // Treat "muted" as either remote mute OR volume 0 (works even if mute isn’t a separate API).
    final isMutedLike = playback.isMuted || displayVolumeLevel == 0;

    // Keep last audible volume updated (no setState needed).
    if (displayVolumeLevel > 0) {
      _lastAudibleVolume = displayVolumeLevel;
    }

    final progress = playback.progress;
    final positionTicks = playback.positionTicks;
    final durationTicks = playback.durationTicks ?? 0;

    // If playback has caught up to the preview, release preview/target.
    final preview = _volumePreviewLevel;
    if (preview != null && (volumeLevel - preview).abs() <= 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        final current = context.read<RemoteState>().playbackState.volumeLevel;
        final p = _volumePreviewLevel;
        if (p != null && (current - p).abs() <= 1) {
          _volumePreviewFailsafeTimer?.cancel();
          setState(() {
            _volumePreviewLevel = null;
            _volumeTargetLevel = null;
          });
        }
      });
    }

    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);

    // Inset keeps controls inside the round “safe” area.
    final edgeInset = size.shortestSide * 0.1;
    final top = padding.top + 16;
    final bottom = padding.bottom + 18;

    // Center controls slightly upward so bottom row doesn’t hit the clipped area.
    final centerOffsetY = -size.shortestSide * 0.05;

    final centerSecondaryText = _volumeActive
        ? (isMutedLike ? 'MUTED' : '$displayVolumeLevel%')
        : _formatTime(durationTicks);

    const sideSlotWidth = 64.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildBackground(playback.nowPlayingItemId),

        // Ring: progress normally, volume while actively adjusting.
        IgnorePointer(
          child: _volumeActive
              ? _VolumeRing(
            volume: displayVolumeLevel,
            isMuted: isMutedLike,
            strokeWidth: 8,
            edgePadding: 4,
          )
              : PlaybackRing(
            progress: progress,
            strokeWidth: 6,
            edgePadding: 4,
          ),
        ),

        // Top bar: volume (left), timestamp (center), skip next (right)
        Positioned(
          top: top,
          left: edgeInset,
          right: edgeInset,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SizedBox(
                width: sideSlotWidth,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: VolumeButton(
                    volumeLevel: displayVolumeLevel,
                    isMuted: isMutedLike,
                    onTap: () => setState(() => _showVolumePopup = true),
                    onLongPress: () => _toggleMuteLikeUser(remoteState, displayVolumeLevel),
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(positionTicks),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    centerSecondaryText,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _volumeActive
                          ? (isMutedLike ? WearTheme.textSecondary : const Color(0xFFFFD700))
                          : WearTheme.textSecondary,
                      fontWeight: _volumeActive ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
              SizedBox(
                width: sideSlotWidth,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _ControlButton(
                    icon: Icons.skip_next,
                    onTap: _skipNext,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Main transport: rewind/ff (wire these to your seek API) + play/pause
        Align(
          alignment: Alignment.center,
          child: Transform.translate(
            offset: Offset(0, centerOffsetY),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ControlButton(
                  icon: Icons.replay_10,
                  onTap: () {
                    // TODO: call the same seek method your SeekScreen uses (e.g. seekBySeconds(-10)).
                    HapticFeedback.mediumImpact();
                  },
                  size: 32,
                ),
                const SizedBox(width: 12),
                _ControlButton(
                  icon: isPlaying ? Icons.pause : Icons.play_arrow,
                  onTap: _playPause,
                  size: 44,
                  highlighted: true,
                ),
                const SizedBox(width: 12),
                _ControlButton(
                  icon: Icons.forward_10,
                  onTap: () {
                    // TODO: call the same seek method your SeekScreen uses (e.g. seekBySeconds(+10)).
                    HapticFeedback.mediumImpact();
                  },
                  size: 32,
                ),
              ],
            ),
          ),
        ),

        // Bottom row: CC / Audio / Stop
        Positioned(
          bottom: bottom,
          left: edgeInset,
          right: edgeInset,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ControlButton(
                icon: Icons.closed_caption,
                onTap: _openSubtitleTracks,
                size: 22,
              ),
              const SizedBox(width: 18),
              _ControlButton(
                icon: Icons.audiotrack,
                onTap: _openAudioTracks,
                size: 22,
              ),
              const SizedBox(width: 18),
              _ControlButton(
                icon: Icons.stop,
                onTap: _stop,
                size: 22,
              ),
            ],
          ),
        ),
      ],
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
          padding: const EdgeInsets.all(10),
          constraints: const BoxConstraints(),
        ),
      );
    }

    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: size),
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(),
    );
  }

}
class _VolumeRing extends StatelessWidget {
  final int volume;
  final bool isMuted;
  final double strokeWidth;
  final double edgePadding;

  const _VolumeRing({
    required this.volume,
    required this.isMuted,
    required this.strokeWidth,
    required this.edgePadding,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _VolumeRingPainter(
        volume: volume,
        isMuted: isMuted,
        strokeWidth: strokeWidth,
        edgePadding: edgePadding,
      ),
    );
  }
}

class _VolumeRingPainter extends CustomPainter {
  final int volume;
  final bool isMuted;
  final double strokeWidth;
  final double edgePadding;

  _VolumeRingPainter({
    required this.volume,
    required this.isMuted,
    required this.strokeWidth,
    required this.edgePadding,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final shortest = size.shortestSide;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (shortest / 2) - edgePadding - (strokeWidth / 2);

    final track = Paint()
      ..color = WearTheme.surface
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, track);

    if (isMuted || volume <= 0) return;

    final arc = Paint()
      ..color = const Color(0xFFFFD700)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final sweep = (volume.clamp(0, 100) / 100.0) * (2 * 3.141592653589793);
    final start = -3.141592653589793 / 2; // top

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      sweep,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _VolumeRingPainter oldDelegate) {
    return oldDelegate.volume != volume ||
        oldDelegate.isMuted != isMuted ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.edgePadding != edgePadding;
  }
}
