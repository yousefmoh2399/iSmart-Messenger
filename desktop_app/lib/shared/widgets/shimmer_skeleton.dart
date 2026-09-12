import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A global, synchronized controller for shimmer widgets.
/// It drives all [ShimmerSkeleton] widgets using a single [Ticker],
/// ensuring perfect visual synchrony and minimal CPU/GPU overhead.
class GlobalShimmerController {
  GlobalShimmerController._() {
    _ticker = Ticker(_onTick);
  }

  static final GlobalShimmerController instance = GlobalShimmerController._();

  late final Ticker _ticker;
  double _value = 0.0;
  final List<VoidCallback> _listeners = [];

  double get value => _value;

  void addListener(VoidCallback listener) {
    _listeners.add(listener);
    if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
    if (_listeners.isEmpty && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    const period = Duration(milliseconds: 1800);
    final elapsedMs = elapsed.inMilliseconds % period.inMilliseconds;
    _value = elapsedMs / period.inMilliseconds;

    // Create a copy of the list to prevent concurrent modifications
    final activeListeners = List<VoidCallback>.from(_listeners);
    for (final listener in activeListeners) {
      listener();
    }
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
    GlobalShimmerController.instance.addListener(_onShimmerTick);
  }

  @override
  void dispose() {
    GlobalShimmerController.instance.removeListener(_onShimmerTick);
    super.dispose();
  }

  void _onShimmerTick() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Premium Slate Colors matching modern designs
    final base = isDark
        ? const Color(0xFF1E293B) // slate-800
        : const Color(0xFFE2E8F0); // slate-200

    final highlight = isDark
        ? const Color(0xFF334155) // slate-700
        : const Color(0xFFF1F5F9); // slate-100

    final value = GlobalShimmerController.instance.value;

    Widget child = Padding(
      padding: widget.padding ?? EdgeInsets.zero,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          gradient: LinearGradient(
            begin: Alignment(-2.0 + (value * 4.0), -1.0),
            end: Alignment(-1.0 + (value * 4.0), 1.0),
            colors: [base, highlight, base],
            stops: const [0.25, 0.5, 0.75],
          ),
        ),
      ),
    );

    if (widget.asCard) {
      child = Material(
        elevation: isDark ? 2 : 1,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
        borderRadius: BorderRadius.circular(widget.borderRadius),
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        child: child,
      );
    }

    return child;
  }
}
