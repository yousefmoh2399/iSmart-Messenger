import 'package:flutter/material.dart';

import 'shimmer_skeleton.dart';

class AppLoadingIndicator extends StatelessWidget {
  const AppLoadingIndicator({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: ShimmerSkeleton(
          height: size,
          width: size,
          borderRadius: size / 2,
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
