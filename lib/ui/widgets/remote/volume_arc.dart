import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wearable_rotary/wearable_rotary.dart';

import '../../../core/theme/wear_theme.dart';

/// A volume control arc positioned at the top of the screen.
///
/// Features:
/// - 120° arc centered at the top
/// - Sits directly under (inside) the playback ring
/// - Yellow/gold color for visibility
/// - Touch drag to change volume
/// - Rotary input support
/// - Inflates while adjusting, shows percentage text
/// - Deflates after idle
///
/// Usage:
/// ```dart
/// VolumeArc(
///   volumeLevel: 75,
///   isMuted: false,
///   onVolumeChanged: (level) => remoteState.setVolume(level),
/// )
/// ```
class VolumeArc extends StatefulWidget {
  /// Current volume level from 0 to 100.
  final int volumeLevel;

  /// Whether the volume is muted.
  final bool isMuted;

  /// Called when volume changes via interaction.
  final void Function(int level)? onVolumeChanged;

  /// Whether rotary input should control this arc.
  final bool handleRotary;

  /// Duration to wait after interaction before deflating.
  final Duration deflateDelay;

  /// Outer edge padding (should match playback ring's inner edge).
  final double edgePadding;

  /// Normal stroke width.
  final double strokeWidth;

  /// Stroke width when inflated (active).
  final double inflatedStrokeWidth;

  const VolumeArc({
    super.key,
    required this.volumeLevel,
    this.isMuted = false,
    this.onVolumeChanged,
    this.handleRotary = true,
    this.deflateDelay = const Duration(milliseconds: 500),
    this.edgePadding = 20.0,
    this.strokeWidth = 6.0,
    this.inflatedStrokeWidth = 12.0,
  });

  @override
  State<VolumeArc> createState() => _VolumeArcState();
}

class _VolumeArcState extends State<VolumeArc>
    with SingleTickerProviderStateMixin {
  late AnimationController _inflateController;
  late Animation<double> _strokeAnimation;
  late Animation<double> _textOpacityAnimation;

  StreamSubscription<RotaryEvent>? _rotarySubscription;
  Timer? _deflateTimer;
  bool _isInteracting = false;

  // Arc spans 120 degrees centered at top
  // Top is -90 degrees (-pi/2)
  // So we go from -150 degrees to -30 degrees
  static const double _startAngle = -150 * math.pi / 180; // -150 degrees
  static const double _sweepAngle = 120 * math.pi / 180; // 120 degrees

  @override
  void initState() {
    super.initState();

    _inflateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      reverseDuration: const Duration(milliseconds: 250),
    );

    _strokeAnimation = Tween<double>(
      begin: widget.strokeWidth,
      end: widget.inflatedStrokeWidth,
    ).animate(CurvedAnimation(
      parent: _inflateController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    ));

    _textOpacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _inflateController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    ));

    if (widget.handleRotary) {
      _rotarySubscription = rotaryEvents.listen(_onRotaryEvent);
    }
  }

  @override
  void didUpdateWidget(VolumeArc oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.handleRotary != oldWidget.handleRotary) {
      if (widget.handleRotary) {
        _rotarySubscription ??= rotaryEvents.listen(_onRotaryEvent);
      } else {
        _rotarySubscription?.cancel();
        _rotarySubscription = null;
      }
    }
  }

  @override
  void dispose() {
    _deflateTimer?.cancel();
    _rotarySubscription?.cancel();
    _inflateController.dispose();
    super.dispose();
  }

  void _onRotaryEvent(RotaryEvent event) {
    if (widget.onVolumeChanged == null) return;

    _onInteractionStart();

    final delta = event.direction == RotaryDirection.clockwise ? 5 : -5;
    final newLevel = (widget.volumeLevel + delta).clamp(0, 100);

    if (newLevel != widget.volumeLevel) {
      HapticFeedback.lightImpact();
      widget.onVolumeChanged?.call(newLevel);
    }

    _scheduleDeflate();
  }

  void _onInteractionStart() {
    if (!_isInteracting) {
      _isInteracting = true;
      _deflateTimer?.cancel();
      _inflateController.forward();
    }
  }

  void _scheduleDeflate() {
    _deflateTimer?.cancel();
    _deflateTimer = Timer(widget.deflateDelay, () {
      if (mounted) {
        _isInteracting = false;
        _inflateController.reverse();
      }
    });
  }

  void _onPanStart(DragStartDetails details) {
    _onInteractionStart();
    _updateVolumeFromPosition(details.localPosition);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _updateVolumeFromPosition(details.localPosition);
  }

  void _onPanEnd(DragEndDetails details) {
    _scheduleDeflate();
  }

  void _updateVolumeFromPosition(Offset position) {
    final size = context.size;
    if (size == null) return;

    final center = Offset(size.width / 2, size.height / 2);
    final touchVector = position - center;

    // Calculate angle from center
    double angle = math.atan2(touchVector.dy, touchVector.dx);

    // Check if touch is within the arc region
    // Normalize angle to be relative to start angle
    double normalizedAngle = angle - _startAngle;
    while (normalizedAngle < 0) {
      normalizedAngle += 2 * math.pi;
    }
    while (normalizedAngle > 2 * math.pi) {
      normalizedAngle -= 2 * math.pi;
    }

    // Only respond if within the arc sweep
    if (normalizedAngle > _sweepAngle && normalizedAngle < 2 * math.pi - 0.1) {
      return;
    }

    // Calculate progress
    double progress = (normalizedAngle / _sweepAngle).clamp(0.0, 1.0);
    int newLevel = (progress * 100).round().clamp(0, 100);

    if (newLevel != widget.volumeLevel) {
      HapticFeedback.selectionClick();
      widget.onVolumeChanged?.call(newLevel);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayLevel = widget.isMuted ? 0 : widget.volumeLevel;
    final progress = displayLevel / 100.0;

    return GestureDetector(
      onPanStart: widget.onVolumeChanged != null ? _onPanStart : null,
      onPanUpdate: widget.onVolumeChanged != null ? _onPanUpdate : null,
      onPanEnd: widget.onVolumeChanged != null ? _onPanEnd : null,
      behavior: HitTestBehavior.translucent,
      child: AnimatedBuilder(
        animation: _inflateController,
        builder: (context, child) {
          return Stack(
            children: [
              // Arc painter
              CustomPaint(
                painter: _VolumeArcPainter(
                  progress: progress,
                  startAngle: _startAngle,
                  sweepAngle: _sweepAngle,
                  strokeWidth: _strokeAnimation.value,
                  isMuted: widget.isMuted,
                  edgePadding: widget.edgePadding,
                ),
                size: Size.infinite,
              ),
              // Volume percentage text (visible when inflated)
              if (_textOpacityAnimation.value > 0.01)
                Positioned(
                  top: widget.edgePadding + widget.inflatedStrokeWidth + 8,
                  left: 0,
                  right: 0,
                  child: Opacity(
                    opacity: _textOpacityAnimation.value,
                    child: Text(
                      widget.isMuted ? 'MUTED' : '${widget.volumeLevel}%',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: widget.isMuted
                            ? WearTheme.textSecondary
                            : _volumeColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Color get _volumeColor => const Color(0xFFFFD700); // Gold/yellow
}

class _VolumeArcPainter extends CustomPainter {
  final double progress;
  final double startAngle;
  final double sweepAngle;
  final double strokeWidth;
  final bool isMuted;
  final double edgePadding;

  static const Color _trackColor = Color(0xFF2A2A2A);
  static const Color _volumeColor = Color(0xFFFFD700); // Gold/yellow
  static const Color _mutedColor = Color(0xFF666666);

  _VolumeArcPainter({
    required this.progress,
    required this.startAngle,
    required this.sweepAngle,
    required this.strokeWidth,
    required this.isMuted,
    required this.edgePadding,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - edgePadding;

    // Track paint
    final trackPaint = Paint()
      ..color = _trackColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Progress paint
    final progressPaint = Paint()
      ..color = isMuted ? _mutedColor : _volumeColor
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
    if (progress > 0 && !isMuted) {
      final progressSweep = sweepAngle * progress;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        progressSweep,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VolumeArcPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.isMuted != isMuted;
  }
}
