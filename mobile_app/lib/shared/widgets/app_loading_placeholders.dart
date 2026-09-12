import 'package:flutter/material.dart';

import 'shimmer_skeleton.dart';

class AppMediaLoadingPlaceholder extends StatelessWidget {
  const AppMediaLoadingPlaceholder({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 16,
    this.icon = Icons.image_outlined,
  });

  final double? width;
  final double? height;
  final double borderRadius;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final resolvedHeight = height ?? 200;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        width: width,
        height: resolvedHeight,
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ShimmerSkeleton(
              width: width,
              height: resolvedHeight,
              borderRadius: borderRadius,
            ),
            Center(
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.7),
                  ),
                ),
                child: Icon(
                  icon,
                  color: colorScheme.onSurfaceVariant,
                  size: 22,
                ),
              ),
            ),
            PositionedDirectional(
              start: 14,
              end: 14,
              bottom: 12,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: colorScheme.surface.withValues(alpha: 0.44),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    colorScheme.primary.withValues(alpha: 0.78),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppDownloadProgressBanner extends StatelessWidget {
  const AppDownloadProgressBanner({
    super.key,
    required this.fileName,
    required this.progress,
    this.icon = Icons.download_rounded,
  });

  final String? fileName;
  final double progress;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final value = progress <= 0 ? null : progress.clamp(0, 1).toDouble();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Material(
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        color: colorScheme.surface,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: colorScheme.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'جاري تنزيل ${fileName ?? 'الملف'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: value,
                        minHeight: 5,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
