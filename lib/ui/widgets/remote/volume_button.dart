import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/wear_theme.dart';

/// Volume button with percentage indicator bar.
///
/// Tap: open volume popup overlay.
/// Long-press: mute/unmute (handled by parent via callback).
class VolumeButton extends StatelessWidget {
  final int volumeLevel;
  final bool isMuted;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const VolumeButton({
    super.key,
    required this.volumeLevel,
    required this.isMuted,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      onLongPress: onLongPress == null
          ? null
          : () {
        HapticFeedback.mediumImpact();
        onLongPress!();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Speaker icon
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
