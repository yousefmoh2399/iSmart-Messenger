import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A global, synchronized controller for shimmer widgets.
/// It drives all [ShimmerSkeleton] widgets using a single [Ticker],
/// ensuring perfect visual synchrony and minimal CPU/GPU overhead.
class GlobalShimmer {
  GlobalShimmer._() {
    _ticker = Ticker(_onTick);
  }

  static final GlobalShimmer instance = GlobalShimmer._();

  late final Ticker _ticker;
  final ValueNotifier<double> shimmerValue = ValueNotifier(0.0);
  int _listenerCount = 0;

  void addListener() {
    _listenerCount++;
    if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  void removeListener() {
    _listenerCount--;
    if (_listenerCount <= 0 && _ticker.isActive) {
      _listenerCount = 0;
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    const period = 1500;
    final elapsedMs = elapsed.inMilliseconds % period;
    shimmerValue.value = elapsedMs / period;
  }
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform({required this.slidePercent});

  final double slidePercent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    // The gradient sweeps from left (-100%) to right (+100%)
    final offset = bounds.width * (slidePercent * 3 - 1.5);
    return Matrix4.translationValues(offset, 0.0, 0.0);
  }
}

class ShimmerSkeleton extends StatefulWidget {
  const ShimmerSkeleton({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 12,
    this.padding,
    this.asCard = false,
  });

  final double? width;
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;

  /// Elevated surface + clip so announcement-style skeletons match real cards.
  final bool asCard;

  @override
  State<ShimmerSkeleton> createState() => _ShimmerSkeletonState();
}

class _ShimmerSkeletonState extends State<ShimmerSkeleton> {
  @override
  void initState() {
    super.initState();
    GlobalShimmer.instance.addListener();
  }

  @override
  void dispose() {
    GlobalShimmer.instance.removeListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Premium Apple iOS Shimmer Colors
    final baseColor = isDark
        ? const Color(0xFF1C1C1E)
        : const Color(0xFFE5E5EA);

    final highlightColor = isDark
        ? const Color(0xFF2C2C2E)
        : const Color(0xFFF2F2F7);

    Widget shape = Container(
      width: widget.width ?? double.infinity,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors
            .white, // This solid color is replaced entirely by the ShaderMask
        borderRadius: BorderRadius.circular(widget.borderRadius),
      ),
    );

    if (widget.asCard) {
      shape = Material(
        elevation: isDark ? 2 : 1,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
        borderRadius: BorderRadius.circular(widget.borderRadius),
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        child: shape,
      );
    }

    Widget child = ValueListenableBuilder<double>(
      valueListenable: GlobalShimmer.instance.shimmerValue,
      builder: (context, value, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: [baseColor, highlightColor, baseColor],
              stops: const [0.0, 0.5, 1.0],
              begin: const Alignment(-1.0, -0.3),
              end: const Alignment(1.0, 0.3),
              transform: _SlidingGradientTransform(slidePercent: value),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: shape,
    );

    if (widget.padding != null) {
      child = Padding(padding: widget.padding!, child: child);
    }

    return child;
  }
}
