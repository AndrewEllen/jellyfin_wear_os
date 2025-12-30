import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/wear_theme.dart';

/// Volume button with percentage indicator bar.
///
/// Tap to open volume popup overlay for drag-to-adjust.
/// Shows current volume level as a small bar above the speaker icon.
class VolumeButton extends StatelessWidget {
  final int volumeLevel;
  final bool isMuted;
  final VoidCallback onTap;

  const VolumeButton({
    super.key,
    required this.volumeLevel,
    required this.isMuted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Volume percentage bar
          Container(
            width: 36,
            height: 3,
            decoration: BoxDecoration(
              color: WearTheme.surface,
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: isMuted ? 0 : volumeLevel / 100,
              child: Container(
                decoration: BoxDecoration(
                  color: isMuted ? WearTheme.textSecondary : const Color(0xFFFFD700),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Speaker icon button
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: WearTheme.surface.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isMuted ? Icons.volume_off : _volumeIcon,
              size: 18,
              color: isMuted ? WearTheme.textSecondary : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  IconData get _volumeIcon {
    if (volumeLevel == 0) return Icons.volume_mute;
    if (volumeLevel < 50) return Icons.volume_down;
    return Icons.volume_up;
  }
}
