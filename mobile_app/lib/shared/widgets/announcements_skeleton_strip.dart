import 'package:flutter/material.dart';

import 'shimmer_skeleton.dart';

/// Matches the layout of announcement cards on the home screen while loading.
class AnnouncementsSkeletonStrip extends StatelessWidget {
  const AnnouncementsSkeletonStrip({
    super.key,
    this.itemCount = 2,
    this.cardHeight = 92,
    this.borderRadius = 24,
    this.spacing = 12,
  });

  final int itemCount;
  final double cardHeight;
  final double borderRadius;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(itemCount, (i) {
        return Padding(
          padding: EdgeInsets.only(bottom: i == itemCount - 1 ? 0 : spacing),
          child: ShimmerSkeleton(
            height: cardHeight,
            borderRadius: borderRadius,
            asCard: true,
          ),
        );
      }),
    );
  }
}
