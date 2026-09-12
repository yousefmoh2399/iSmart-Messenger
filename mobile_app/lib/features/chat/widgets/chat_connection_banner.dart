import 'package:flutter/material.dart';

import '../presentation/chat_realtime_controller.dart';

class ChatConnectionBanner extends StatelessWidget {
  const ChatConnectionBanner({super.key, required this.state});

  final ChatRealtimeState state;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (background, foreground, icon) = switch (state.status) {
      ChatConnectionStatus.connected => (
        colorScheme.primaryContainer,
        colorScheme.onPrimaryContainer,
        Icons.wifi,
      ),
      ChatConnectionStatus.connecting => (
        colorScheme.secondaryContainer,
        colorScheme.onSecondaryContainer,
        Icons.cloud_sync_outlined,
      ),
      ChatConnectionStatus.reconnecting => (
        const Color(0xFFFFF3E0),
        const Color(0xFF7A4B00),
        Icons.sync_problem_outlined,
      ),
      ChatConnectionStatus.disconnected => (
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
        Icons.portable_wifi_off_outlined,
      ),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: foreground, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              state.message ?? 'حالة الاتصال غير معروفة',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
