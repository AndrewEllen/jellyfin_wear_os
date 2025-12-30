import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wearable_rotary/wearable_rotary.dart';

import '../../core/theme/wear_theme.dart';
import '../../state/remote_state.dart';

/// Seek screen with arc progress ring UI and rotary/touch control.
///
/// Features:
/// - Full draggable ring UI to select timestamp
/// - Center shows the selected time
/// - Rotary increments/decrements timestamp
/// - Auto-applies seek when interaction ends
/// - Inflate/deflate animation while adjusting
class SeekScreen extends StatefulWidget {
  /// Seek increment in seconds per rotary tick.
  final int rotarySeekSeconds;

  const SeekScreen({
    super.key,
    this.rotarySeekSeconds = 5,
  });

  @override
  State<SeekScreen> createState() => _SeekScreenState();
}

class _SeekScreenState extends State<SeekScreen>
    with SingleTickerProviderStateMixin {
  StreamSubscription<RotaryEvent>? _rotarySubscription;
  Timer? _applySeekTimer;

  late AnimationController _inflateController;
  late Animation<double> _strokeAnimation;

  // Playback state
  int _positionTicks = 0;
  int _originalPositionTicks = 0;
  int _durationTicks = 0;
  bool _isInteracting = false;
  bool _hasChanged = false;

  // Stroke widths
  static const double _normalStroke = 8.0;
  static const double _inflatedStroke = 14.0;

  @override
  void initState() {
    super.initState();

    _inflateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      reverseDuration: const Duration(milliseconds: 250),
    );

    _strokeAnimation = Tween<double>(
      begin: _normalStroke,
      end: _inflatedStroke,
    ).animate(CurvedAnimation(
      parent: _inflateController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    ));

    // Initialize with current playback position
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final remoteState = context.read<RemoteState>();
      final playback = remoteState.playbackState;
      setState(() {
        _positionTicks = playback.positionTicks;
        _originalPositionTicks = playback.positionTicks;
        _durationTicks = playback.durationTicks ?? 0;
      });
    });

    _rotarySubscription = rotaryEvents.listen(_onRotaryEvent);
  }

  @override
  void dispose() {
    _applySeekTimer?.cancel();
    _rotarySubscription?.cancel();
    _inflateController.dispose();
    super.dispose();
  }

  void _onRotaryEvent(RotaryEvent event) {
    _onInteractionStart();

    // Convert seconds to ticks (10,000,000 ticks per second)
    final seekIncrement = widget.rotarySeekSeconds * 10000000;

    setState(() {
      if (event.direction == RotaryDirection.clockwise) {
        _positionTicks = math.min(_positionTicks + seekIncrement, _durationTicks);
      } else {
        _positionTicks = math.max(_positionTicks - seekIncrement, 0);
      }
      _hasChanged = _positionTicks != _originalPositionTicks;
    });

    HapticFeedback.lightImpact();
    _scheduleApplySeek();
  }

  void _onInteractionStart() {
    _applySeekTimer?.cancel();
    if (!_isInteracting) {
      setState(() => _isInteracting = true);
      _inflateController.forward();
    }
  }

  void _scheduleApplySeek() {
    _applySeekTimer?.cancel();
    _applySeekTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted && _hasChanged) {
        _applySeek();
      } else if (mounted) {
        setState(() => _isInteracting = false);
        _inflateController.reverse();
      }
    });
  }

  Future<void> _applySeek() async {
    if (!_hasChanged) return;

    HapticFeedback.mediumImpact();

    final remoteState = context.read<RemoteState>();
    await remoteState.seek(_positionTicks);

    if (mounted) {
      setState(() {
        _originalPositionTicks = _positionTicks;
        _hasChanged = false;
        _isInteracting = false;
      });
      _inflateController.reverse();
    }
  }

  void _onPanStart(DragStartDetails details) {
    _onInteractionStart();
    _updatePositionFromTouch(details.localPosition);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _updatePositionFromTouch(details.localPosition);
  }

  void _onPanEnd(DragEndDetails details) {
    _scheduleApplySeek();
  }

  void _updatePositionFromTouch(Offset position) {
    final screenSize = MediaQuery.of(context).size;
    if (_durationTicks <= 0) return;

    final center = Offset(screenSize.width / 2, screenSize.height / 2);
    final touchVector = position - center;

    // Calculate angle from center (0 = right, -pi/2 = top)
    double angle = math.atan2(touchVector.dy, touchVector.dx);

    // Normalize to start from top (add pi/2 to shift from right-start to top-start)
    double normalizedAngle = angle + math.pi / 2;

    // Ensure positive angle (0 to 2*pi)
    if (normalizedAngle < 0) {
      normalizedAngle += 2 * math.pi;
    }

    // Calculate progress (0 to 1)
    double progress = normalizedAngle / (2 * math.pi);
    progress = progress.clamp(0.0, 1.0);

    // Convert to ticks
    final newPosition = (progress * _durationTicks).round();

    if (newPosition != _positionTicks) {
      HapticFeedback.selectionClick();
      setState(() {
        _positionTicks = newPosition;
        _hasChanged = _positionTicks != _originalPositionTicks;
      });
    }
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

  double get _progress {
    if (_durationTicks <= 0) return 0;
    return _positionTicks / _durationTicks;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: WearTheme.background,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Stack(
          children: [
            // Arc progress ring
            AnimatedBuilder(
              animation: _strokeAnimation,
              builder: (context, child) {
                return CustomPaint(
                  size: size,
                  painter: _SeekArcPainter(
                    progress: _progress,
                    strokeWidth: _strokeAnimation.value,
                    isInteracting: _isInteracting,
                  ),
                );
              },
            ),
            // Center content
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Current position
                  Text(
                    _formatTime(_positionTicks),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _isInteracting ? WearTheme.jellyfinPurple : null,
                        ),
                  ),
                  const SizedBox(height: 4),
                  // Duration
                  Text(
                    _formatTime(_durationTicks),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: WearTheme.textSecondary,
                        ),
                  ),
                  const SizedBox(height: 12),
                  // Instruction / status
                  Text(
                    _hasChanged ? 'Release to seek' : 'Drag or rotate',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _hasChanged ? WearTheme.jellyfinPurple : WearTheme.textSecondary,
                          fontSize: 11,
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
}

class _SeekArcPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final bool isInteracting;

  _SeekArcPainter({
    required this.progress,
    required this.strokeWidth,
    required this.isInteracting,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;

    // Track
    final trackPaint = Paint()
      ..color = WearTheme.surfaceVariant
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Full circle track
    canvas.drawCircle(center, radius, trackPaint);

    // Progress arc
    final progressPaint = Paint()
      ..color = isInteracting ? WearTheme.jellyfinPurple : WearTheme.jellyfinPurpleDark
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Draw progress arc from top (- pi/2)
    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * progress;

    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        progressPaint,
      );
    }

    // Draw position indicator dot
    final indicatorAngle = startAngle + sweepAngle;
    final indicatorX = center.dx + radius * math.cos(indicatorAngle);
    final indicatorY = center.dy + radius * math.sin(indicatorAngle);

    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(indicatorX, indicatorY), isInteracting ? 8 : 6, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _SeekArcPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.isInteracting != isInteracting;
  }
}
