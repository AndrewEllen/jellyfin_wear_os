import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wearable_rotary/wearable_rotary.dart';

/// A Wear-style wheel list with center item scaling and rotary support.
///
/// Features:
/// - Center item scales up (1.0), off-center items scale down and fade
/// - Smooth pixel scrolling during touch/rotary
/// - Snap to nearest item after 250ms idle
/// - Medium haptic every ~60px of rotary scroll
/// - Heavy haptic at boundaries with lockout
///
/// Usage:
/// ```dart
/// RotaryWheelList<MyType>(
///   items: items,
///   itemExtent: 84,
///   onItemTap: (item, index) => ...,
///   itemBuilder: (context, item, index, isCentered) => YourCard(...),
/// )
/// ```
class RotaryWheelList<T> extends StatefulWidget {
  /// The list of items to display.
  final List<T> items;

  /// Height of each wheel item.
  final double itemExtent;

  /// Builds the inner content for each item.
  /// The widget applies scaling/opacity and tap handling.
  final Widget Function(
    BuildContext context,
    T item,
    int index,
    bool isCentered,
  ) itemBuilder;

  /// Called when the user taps an item.
  final void Function(T item, int index)? onItemTap;

  /// Called when the centered item changes (after snap).
  final void Function(T item, int index)? onCenteredItemChanged;

  /// Optional external controller.
  final FixedExtentScrollController? controller;

  /// Pixels to scroll per rotary detent.
  final double rotaryScrollDeltaPx;

  /// Pixels between medium haptic ticks during rotary.
  final double hapticTickEveryPx;

  /// Duration to wait after rotary stops before snapping.
  final Duration rotaryDebounceDuration;

  /// Minimum scale for off-center items.
  final double minScale;

  /// Minimum opacity for off-center items.
  final double minOpacity;

  /// How much scale drops per item distance from center.
  final double scaleDropPerItem;

  /// How much opacity drops per item distance from center.
  final double opacityDropPerItem;

  /// Diameter ratio for the wheel effect.
  final double diameterRatio;

  /// Perspective for the wheel effect.
  final double perspective;

  /// Whether to show the edge scroll indicator.
  final bool showScrollIndicator;

  /// Initial item index to scroll to.
  final int initialItem;

  const RotaryWheelList({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.onItemTap,
    this.onCenteredItemChanged,
    this.controller,
    this.itemExtent = 84.0,
    this.rotaryScrollDeltaPx = 8.0,
    this.hapticTickEveryPx = 60.0,
    this.rotaryDebounceDuration = const Duration(milliseconds: 250),
    this.minScale = 0.75,
    this.minOpacity = 0.5,
    this.scaleDropPerItem = 0.25,
    this.opacityDropPerItem = 0.5,
    this.diameterRatio = 2.5,
    this.perspective = 0.001,
    this.showScrollIndicator = true,
    this.initialItem = 0,
  });

  @override
  State<RotaryWheelList<T>> createState() => _RotaryWheelListState<T>();
}

class _RotaryWheelListState<T> extends State<RotaryWheelList<T>> {
  late FixedExtentScrollController _controller;
  late StreamSubscription<RotaryEvent> _rotarySubscription;

  Timer? _rotaryDebounce;
  bool _snapEnabled = true;
  bool _boundaryLock = false;
  double _pixelAccum = 0;
  int _lastReportedIndex = -1;

  @override
  void initState() {
    super.initState();

    _controller = widget.controller ??
        FixedExtentScrollController(initialItem: widget.initialItem);

    _controller.addListener(_onScrollUpdate);

    _rotarySubscription = rotaryEvents.listen(_onRotaryEvent);
  }

  void _onScrollUpdate() {
    if (!mounted) return;
    setState(() {});
  }

  void _onRotaryEvent(RotaryEvent event) {
    if (!_controller.hasClients) return;
    if (widget.items.isEmpty) return;

    final position = _controller.position;
    if (position.maxScrollExtent <= 0) return;

    // Disable snapping during rotary so scroll feels smooth
    if (_snapEnabled) {
      setState(() => _snapEnabled = false);
    }

    _rotaryDebounce?.cancel();

    final int direction = event.direction == RotaryDirection.clockwise ? 1 : -1;

    final double target =
        (position.pixels + direction * widget.rotaryScrollDeltaPx)
            .clamp(position.minScrollExtent, position.maxScrollExtent);

    position.jumpTo(target);

    // Haptic tick every N px
    _pixelAccum += widget.rotaryScrollDeltaPx.abs();
    if (_pixelAccum >= widget.hapticTickEveryPx) {
      HapticFeedback.mediumImpact();
      _pixelAccum = 0;
    }

    // Boundary bump with lockout
    final bool atTop = target <= position.minScrollExtent + 1;
    final bool atBottom = target >= position.maxScrollExtent - 1;

    if ((atTop || atBottom) && !_boundaryLock) {
      _boundaryLock = true;
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 250), () {
        _boundaryLock = false;
      });
    }

    // When rotary stops: restore snapping + snap to nearest item
    _rotaryDebounce = Timer(widget.rotaryDebounceDuration, () {
      if (!mounted) return;

      if (!_snapEnabled) {
        setState(() => _snapEnabled = true);
      }
      _snapToNearestItem();
    });
  }

  void _snapToNearestItem() {
    if (!_controller.hasClients) return;
    if (widget.items.isEmpty) return;

    final double offset = _controller.offset;
    final int nearestIndex =
        (offset / widget.itemExtent).round().clamp(0, widget.items.length - 1);

    _controller.animateToItem(
      nearestIndex,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );

    // Notify listener of centered item change
    if (nearestIndex != _lastReportedIndex && nearestIndex < widget.items.length) {
      _lastReportedIndex = nearestIndex;
      widget.onCenteredItemChanged?.call(widget.items[nearestIndex], nearestIndex);
    }
  }

  double _centerIndex() {
    if (!_controller.hasClients) return 0.0;
    return _controller.offset / widget.itemExtent;
  }

  double get _scrollProgress {
    if (!_controller.hasClients || widget.items.length <= 1) return 0;
    final centerIdx = _centerIndex();
    return centerIdx / (widget.items.length - 1);
  }

  @override
  void dispose() {
    _rotaryDebounce?.cancel();
    _rotarySubscription.cancel();
    _controller.removeListener(_onScrollUpdate);
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const SizedBox.shrink();
    }

    final centerIndex = _centerIndex();

    return Stack(
      children: [
        NotificationListener<ScrollEndNotification>(
          onNotification: (notification) {
            // For finger scrolling, snap when user stops
            if (_snapEnabled) {
              _snapToNearestItem();
            }
            return false;
          },
          child: ListWheelScrollView.useDelegate(
            controller: _controller,
            itemExtent: widget.itemExtent,
            diameterRatio: widget.diameterRatio,
            perspective: widget.perspective,
            useMagnifier: false, // scaling handled manually
            physics: _snapEnabled
                ? const FixedExtentScrollPhysics()
                : const ClampingScrollPhysics(),
            onSelectedItemChanged: (index) {
              if (index < 0 || index >= widget.items.length) return;
              if (_snapEnabled && index != _lastReportedIndex) {
                _lastReportedIndex = index;
                widget.onCenteredItemChanged
                    ?.call(widget.items[index], index);
              }
            },
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: widget.items.length,
              builder: (context, index) {
                if (index < 0 || index >= widget.items.length) return null;

                final distanceFromCenter = (index - centerIndex).abs();
                final scale = (1.0 - (distanceFromCenter * widget.scaleDropPerItem))
                    .clamp(widget.minScale, 1.0);
                final opacity =
                    (1.0 - (distanceFromCenter * widget.opacityDropPerItem))
                        .clamp(widget.minOpacity, 1.0);

                final isCentered = distanceFromCenter < 0.5;

                return Transform.scale(
                  scale: scale,
                  child: Opacity(
                    opacity: opacity,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onItemTap == null
                          ? null
                          : () {
                              HapticFeedback.lightImpact();
                              widget.onItemTap!(widget.items[index], index);
                            },
                      child: widget.itemBuilder(
                        context,
                        widget.items[index],
                        index,
                        isCentered,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        // Scroll indicator
        if (widget.showScrollIndicator && widget.items.length > 1)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _WheelScrollIndicatorPainter(
                  progress: _scrollProgress.clamp(0.0, 1.0),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Simple scroll indicator painter for the wheel list.
class _WheelScrollIndicatorPainter extends CustomPainter {
  final double progress;

  _WheelScrollIndicatorPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Track arc at the right edge
    const startAngle = -0.4; // ~-23 degrees from right
    const sweepAngle = 0.8; // ~46 degrees total

    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      trackPaint,
    );

    // Thumb indicator
    final thumbAngle = startAngle + sweepAngle * progress;
    final thumbX = center.dx + radius * _cos(thumbAngle);
    final thumbY = center.dy + radius * _sin(thumbAngle);

    final thumbPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(thumbX, thumbY), 4, thumbPaint);
  }

  double _cos(double radians) => radians.isNaN ? 1 : _cosine(radians);
  double _sin(double radians) => radians.isNaN ? 0 : _sine(radians);

  // Simple cos/sin without importing dart:math
  double _cosine(double x) {
    // Taylor series approximation isn't ideal, use identity
    // cos(x) = sin(x + pi/2)
    return _sine(x + 1.5707963267948966);
  }

  double _sine(double x) {
    // Normalize to [-pi, pi]
    const twoPi = 6.283185307179586;
    const pi = 3.141592653589793;
    x = x % twoPi;
    if (x > pi) x -= twoPi;
    if (x < -pi) x += twoPi;

    // Taylor series for sin
    final x2 = x * x;
    final x3 = x2 * x;
    final x5 = x3 * x2;
    final x7 = x5 * x2;
    return x - x3 / 6 + x5 / 120 - x7 / 5040;
  }

  @override
  bool shouldRepaint(covariant _WheelScrollIndicatorPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
