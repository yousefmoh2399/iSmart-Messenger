import 'package:flutter/material.dart';

import 'shimmer_skeleton.dart';

/// Matches the layout of [_AnnouncementsSection] while loading.
class AnnouncementsSkeletonStrip extends StatelessWidget {
  const AnnouncementsSkeletonStrip({
    super.key,
    this.itemCount = 2,
    this.cardHeight = 76,
    this.borderRadius = 18,
    this.spacing = 10,
  });

  final int itemCount;
  final double cardHeight;
  final double borderRadius;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
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
      ),
    );
  }
}
