import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/theme/wear_theme.dart';

/// A full-circle playback progress ring at the screen edge.
///
/// Features:
/// - Outer ring, full 360°
/// - Shows playback progress from top, clockwise
/// - Indicator dot at current position
/// - Non-interactive (use SeekScreen for seeking)
///
/// Usage:
/// ```dart
/// PlaybackRing(
///   progress: 0.5,  // 50% through playback
/// )
/// ```
class PlaybackRing extends StatelessWidget {
  /// Current playback progress from 0.0 to 1.0.
  final double progress;

  /// Stroke width of the ring.
  final double strokeWidth;

  /// Padding from the edge of the widget.
  final double edgePadding;

  /// Track (background) color.
  final Color trackColor;

  /// Progress (foreground) color.
  final Color progressColor;

  /// Whether to show an indicator dot at the progress position.
  final bool showIndicatorDot;

  /// Indicator dot radius.
  final double indicatorDotRadius;

  /// Indicator dot color.
  final Color indicatorDotColor;

  const PlaybackRing({
    super.key,
    required this.progress,
    this.strokeWidth = 8.0,
    this.edgePadding = 8.0,
    this.trackColor = const Color(0xFF2A2A2A),
    this.progressColor = WearTheme.jellyfinPurple,
    this.showIndicatorDot = true,
    this.indicatorDotRadius = 5.0,
    this.indicatorDotColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PlaybackRingPainter(
        progress: progress.clamp(0.0, 1.0),
        strokeWidth: strokeWidth,
        edgePadding: edgePadding,
        trackColor: trackColor,
        progressColor: progressColor,
        showIndicatorDot: showIndicatorDot,
        indicatorDotRadius: indicatorDotRadius,
        indicatorDotColor: indicatorDotColor,
      ),
      size: Size.infinite,
    );
  }
}

class _PlaybackRingPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final double edgePadding;
  final Color trackColor;
  final Color progressColor;
  final bool showIndicatorDot;
  final double indicatorDotRadius;
  final Color indicatorDotColor;

  // Start at top (-90 degrees = -pi/2)
  static const double _startAngle = -math.pi / 2;
  // Full circle
  static const double _sweepAngle = 2 * math.pi;

  _PlaybackRingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.edgePadding,
    required this.trackColor,
    required this.progressColor,
    required this.showIndicatorDot,
    required this.indicatorDotRadius,
    required this.indicatorDotColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - edgePadding;

    // Track paint (full circle background)
    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Progress paint
    final progressPaint = Paint()
      ..color = progressColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Draw full circle track
    canvas.drawCircle(center, radius, trackPaint);

    // Draw progress arc
    if (progress > 0) {
      final progressSweep = _sweepAngle * progress;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        _startAngle,
        progressSweep,
        false,
        progressPaint,
      );
    }

    // Draw indicator dot
    if (showIndicatorDot && progress > 0) {
      final indicatorAngle = _startAngle + _sweepAngle * progress;
      final indicatorX = center.dx + radius * math.cos(indicatorAngle);
      final indicatorY = center.dy + radius * math.sin(indicatorAngle);

      final dotPaint = Paint()
        ..color = indicatorDotColor
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(indicatorX, indicatorY),
        indicatorDotRadius,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PlaybackRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.showIndicatorDot != showIndicatorDot;
  }
}
