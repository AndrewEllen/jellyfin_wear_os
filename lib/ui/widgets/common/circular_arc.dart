import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A reusable circular arc widget with touch drag support and inflate/deflate animation.
///
/// Features:
/// - Configurable start angle and sweep angle
/// - Track + progress painting with customizable stroke width
/// - Touch drag detection (pan gestures converted to angle)
/// - Inflate/deflate animation (stroke width grows when active)
/// - Optional indicator dot at progress position
///
/// Usage:
/// ```dart
/// CircularArc(
///   progress: 0.5,
///   startAngle: -math.pi / 2,  // Top
///   sweepAngle: 2 * math.pi,   // Full circle
///   interactive: true,
///   onValueChanged: (progress) => setState(() => _progress = progress),
/// )
/// ```
class CircularArc extends StatefulWidget {
  /// Current progress value from 0.0 to 1.0.
  final double progress;

  /// Start angle in radians. -pi/2 is top, 0 is right, pi/2 is bottom, pi is left.
  final double startAngle;

  /// Sweep angle in radians. 2*pi for full circle.
  final double sweepAngle;

  /// Normal stroke width.
  final double strokeWidth;

  /// Stroke width when inflated (active).
  final double inflatedStrokeWidth;

  /// Duration of inflate animation.
  final Duration inflateDuration;

  /// Duration of deflate animation.
  final Duration deflateDuration;

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

  /// Whether the arc is interactive (responds to touch drag).
  final bool interactive;

  /// Called when the progress value changes via interaction.
  final void Function(double progress)? onValueChanged;

  /// Called when interaction starts.
  final VoidCallback? onInteractionStart;

  /// Called when interaction ends.
  final VoidCallback? onInteractionEnd;

  /// Whether the arc is currently in the inflated state.
  /// If null, inflation is controlled by touch interaction.
  final bool? isInflated;

  /// Padding from the edge of the widget.
  final double edgePadding;

  const CircularArc({
    super.key,
    required this.progress,
    this.startAngle = -math.pi / 2,
    this.sweepAngle = 2 * math.pi,
    this.strokeWidth = 8.0,
    this.inflatedStrokeWidth = 14.0,
    this.inflateDuration = const Duration(milliseconds: 150),
    this.deflateDuration = const Duration(milliseconds: 200),
    this.trackColor = const Color(0xFF2A2A2A),
    this.progressColor = const Color(0xFF00A4DC),
    this.showIndicatorDot = true,
    this.indicatorDotRadius = 6.0,
    this.indicatorDotColor = Colors.white,
    this.interactive = false,
    this.onValueChanged,
    this.onInteractionStart,
    this.onInteractionEnd,
    this.isInflated,
    this.edgePadding = 8.0,
  });

  @override
  State<CircularArc> createState() => _CircularArcState();
}

class _CircularArcState extends State<CircularArc>
    with SingleTickerProviderStateMixin {
  late AnimationController _inflateController;
  late Animation<double> _strokeAnimation;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();

    _inflateController = AnimationController(
      vsync: this,
      duration: widget.inflateDuration,
      reverseDuration: widget.deflateDuration,
    );

    _strokeAnimation = Tween<double>(
      begin: widget.strokeWidth,
      end: widget.inflatedStrokeWidth,
    ).animate(CurvedAnimation(
      parent: _inflateController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    ));

    // If externally controlled inflation, set initial state
    if (widget.isInflated == true) {
      _inflateController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(CircularArc oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Update animation values if stroke widths changed
    if (oldWidget.strokeWidth != widget.strokeWidth ||
        oldWidget.inflatedStrokeWidth != widget.inflatedStrokeWidth) {
      _strokeAnimation = Tween<double>(
        begin: widget.strokeWidth,
        end: widget.inflatedStrokeWidth,
      ).animate(CurvedAnimation(
        parent: _inflateController,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      ));
    }

    // Handle external inflation control
    if (widget.isInflated != null && widget.isInflated != oldWidget.isInflated) {
      if (widget.isInflated!) {
        _inflateController.forward();
      } else {
        _inflateController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _inflateController.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails details) {
    if (!widget.interactive) return;
    if (!_isOnArc(details.localPosition)) return;

    _isDragging = true;
    widget.onInteractionStart?.call();

    if (widget.isInflated == null) {
      _inflateController.forward();
    }

    _updateProgressFromPosition(details.localPosition);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!widget.interactive || !_isDragging) return;
    _updateProgressFromPosition(details.localPosition);
  }

  void _onPanEnd(DragEndDetails details) {
    if (!widget.interactive || !_isDragging) return;

    _isDragging = false;
    widget.onInteractionEnd?.call();

    if (widget.isInflated == null) {
      _inflateController.reverse();
    }
  }

  bool _isOnArc(Offset position) {
    final size = context.size;
    if (size == null) return false;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - widget.edgePadding;
    final distance = (position - center).distance;

    // Allow some tolerance around the arc
    final tolerance = widget.inflatedStrokeWidth * 1.5;
    return distance >= radius - tolerance && distance <= radius + tolerance;
  }

  void _updateProgressFromPosition(Offset position) {
    final size = context.size;
    if (size == null) return;

    final center = Offset(size.width / 2, size.height / 2);
    final touchVector = position - center;

    // Calculate angle from center to touch point
    double angle = math.atan2(touchVector.dy, touchVector.dx);

    // Normalize angle relative to start angle
    double normalizedAngle = angle - widget.startAngle;

    // Ensure angle is positive and within sweep
    while (normalizedAngle < 0) {
      normalizedAngle += 2 * math.pi;
    }
    while (normalizedAngle > 2 * math.pi) {
      normalizedAngle -= 2 * math.pi;
    }

    // Calculate progress
    double progress;
    if (widget.sweepAngle.abs() >= 2 * math.pi - 0.01) {
      // Full circle - use full range
      progress = normalizedAngle / (2 * math.pi);
    } else {
      // Partial arc
      progress = normalizedAngle / widget.sweepAngle.abs();
    }

    progress = progress.clamp(0.0, 1.0);
    widget.onValueChanged?.call(progress);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: widget.interactive ? _onPanStart : null,
      onPanUpdate: widget.interactive ? _onPanUpdate : null,
      onPanEnd: widget.interactive ? _onPanEnd : null,
      child: AnimatedBuilder(
        animation: _strokeAnimation,
        builder: (context, child) {
          return CustomPaint(
            painter: _CircularArcPainter(
              progress: widget.progress.clamp(0.0, 1.0),
              startAngle: widget.startAngle,
              sweepAngle: widget.sweepAngle,
              strokeWidth: _strokeAnimation.value,
              trackColor: widget.trackColor,
              progressColor: widget.progressColor,
              showIndicatorDot: widget.showIndicatorDot,
              indicatorDotRadius: widget.indicatorDotRadius,
              indicatorDotColor: widget.indicatorDotColor,
              edgePadding: widget.edgePadding,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _CircularArcPainter extends CustomPainter {
  final double progress;
  final double startAngle;
  final double sweepAngle;
  final double strokeWidth;
  final Color trackColor;
  final Color progressColor;
  final bool showIndicatorDot;
  final double indicatorDotRadius;
  final Color indicatorDotColor;
  final double edgePadding;

  _CircularArcPainter({
    required this.progress,
    required this.startAngle,
    required this.sweepAngle,
    required this.strokeWidth,
    required this.trackColor,
    required this.progressColor,
    required this.showIndicatorDot,
    required this.indicatorDotRadius,
    required this.indicatorDotColor,
    required this.edgePadding,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - edgePadding;

    // Track paint
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

    // Draw track arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      trackPaint,
    );

    // Draw progress arc
    if (progress > 0) {
      final progressSweep = sweepAngle * progress;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        progressSweep,
        false,
        progressPaint,
      );
    }

    // Draw indicator dot
    if (showIndicatorDot && progress > 0) {
      final indicatorAngle = startAngle + sweepAngle * progress;
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
  bool shouldRepaint(covariant _CircularArcPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.startAngle != startAngle ||
        oldDelegate.sweepAngle != sweepAngle ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.showIndicatorDot != showIndicatorDot ||
        oldDelegate.indicatorDotRadius != indicatorDotRadius ||
        oldDelegate.indicatorDotColor != indicatorDotColor;
  }
}
