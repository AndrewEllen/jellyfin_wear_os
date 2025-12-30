import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/wear_theme.dart';

/// Full-screen volume overlay designed for round watch screens.
///
/// This widget shows a local (optimistic) volume immediately, while
/// rate-limiting outbound volume commands to avoid request backlogs.
class VolumePopup extends StatefulWidget {
  /// Current volume level (0-100) from parent.
  final int volume;
  final bool isMuted;
  final void Function(int level) onVolumeChanged;
  final VoidCallback onDismiss;

  /// Pixels of drag needed to change volume by 1%.
  final double dragSensitivity;

  const VolumePopup({
    super.key,
    required this.volume,
    required this.isMuted,
    required this.onVolumeChanged,
    required this.onDismiss,
    this.dragSensitivity = 2.0,
  });

  @override
  State<VolumePopup> createState() => _VolumePopupState();
}

class _VolumePopupState extends State<VolumePopup> {
  double _dragStartY = 0;
  int _dragStartVolume = 0;

  // Local, immediate UI volume. Parent volume may lag due to network/polling.
  late int _uiVolume;

  // Rate-limit outbound volume commands (avoid request backlogs).
  static const Duration _sendInterval = Duration(milliseconds: 60);
  Timer? _sendTimer;
  int? _pendingVolumeToSend;
  int? _lastSentVolume;

  bool _isInteracting = false;

  @override
  void initState() {
    super.initState();
    _uiVolume = widget.volume;
    _lastSentVolume = widget.volume;
  }

  @override
  void didUpdateWidget(covariant VolumePopup oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Only adopt parent volume when we're not actively dragging.
    if (!_isInteracting && widget.volume != oldWidget.volume) {
      _uiVolume = widget.volume;
      _lastSentVolume = widget.volume;
    }
  }

  @override
  void dispose() {
    _sendTimer?.cancel();
    super.dispose();
  }

  void _onPanStart(DragStartDetails details) {
    _isInteracting = true;
    _dragStartY = details.globalPosition.dy;
    _dragStartVolume = _uiVolume;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    // Drag up = increase volume, drag down = decrease
    final dragDelta = _dragStartY - details.globalPosition.dy;
    final volumeDelta = (dragDelta / widget.dragSensitivity).round();
    final newVolume = (_dragStartVolume + volumeDelta).clamp(0, 100);

    if (newVolume != _uiVolume) {
      HapticFeedback.selectionClick();
      setState(() => _uiVolume = newVolume);
      _queueSend(newVolume);
    }
  }

  void _onPanEnd(DragEndDetails details) {
    _isInteracting = false;
    _flushSend();
    widget.onDismiss();
  }

  void _queueSend(int level) {
    _pendingVolumeToSend = level;

    // Throttle: send immediately, then at most once per interval with latest value.
    if (_sendTimer != null) return;
    _flushSend();
    _sendTimer = Timer(_sendInterval, _onSendTimer);
  }

  void _onSendTimer() {
    _sendTimer = null;

    if (_pendingVolumeToSend != null && _pendingVolumeToSend != _lastSentVolume) {
      _flushSend();
      _sendTimer = Timer(_sendInterval, _onSendTimer);
    } else {
      _pendingVolumeToSend = null;
    }
  }

  void _flushSend() {
    final v = _pendingVolumeToSend;
    if (v == null || v == _lastSentVolume) return;

    _lastSentVolume = v;
    widget.onVolumeChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      onTapUp: (_) {
        _isInteracting = false;
        _flushSend();
        widget.onDismiss();
      },
      child: Container(
        color: Colors.black.withValues(alpha: 0.92),
        child: Stack(
          children: [
            // Circular volume arc around the edge
            CustomPaint(
              size: screenSize,
              painter: _VolumeArcPainter(
                volume: _uiVolume,
                isMuted: widget.isMuted,
              ),
            ),
            // Center content
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.isMuted ? Icons.volume_off : _volumeIcon,
                    size: 48,
                    color: WearTheme.jellyfinPurple,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.isMuted ? 'MUTED' : '${_uiVolume}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Drag up/down',
                    style: TextStyle(
                      color: WearTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData get _volumeIcon {
    if (_uiVolume == 0) return Icons.volume_mute;
    if (_uiVolume < 50) return Icons.volume_down;
    return Icons.volume_up;
  }
}

class _VolumeArcPainter extends CustomPainter {
  final int volume;
  final bool isMuted;

  _VolumeArcPainter({
    required this.volume,
    required this.isMuted,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 12;

    final trackPaint = Paint()
      ..color = WearTheme.surface
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    if (!isMuted && volume > 0) {
      final progressPaint = Paint()
        ..color = const Color(0xFFFFD700)
        ..strokeWidth = 10
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      const startAngle = math.pi / 2;
      final sweepAngle = 2 * math.pi * (volume / 100);

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VolumeArcPainter oldDelegate) {
    return oldDelegate.volume != volume || oldDelegate.isMuted != isMuted;
  }
}
