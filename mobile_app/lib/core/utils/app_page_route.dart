import 'package:flutter/material.dart';

class AppPageRoute<T> extends PageRouteBuilder<T> {
  AppPageRoute({required Widget page, super.settings})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOutCubic,
          );

          // Slide from right to left (handles RTL automatically if we use standard offsets)
          // Actually, for proper RTL support with SlideTransition, we use textDirection
          // inside SlideTransition, but Offset(1,0) is visually right-to-left.
          // To be safe with RTL, we can use Directionality:
          return SlideTransition(
            textDirection: Directionality.of(context),
            position: Tween<Offset>(
              begin: const Offset(
                1.0,
                0.0,
              ), // Starts from the "end" (Right in LTR, Left in RTL)
              end: Offset.zero,
            ).animate(curvedAnimation),
            child: FadeTransition(
              opacity: Tween<double>(
                begin: 0.0,
                end: 1.0,
              ).animate(curvedAnimation),
              child: child,
            ),
          );
        },
      );
}
