import 'package:flutter/material.dart';
import 'shimmer_skeleton.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isError) ...[
                const ShimmerSkeleton(width: 96, height: 12, borderRadius: 8),
                const SizedBox(height: 10),
                const ShimmerSkeleton(width: 140, height: 12, borderRadius: 8),
              ],
              if (isError)
                const Icon(Icons.error_outline, size: 54, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
