import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_app/shared/providers/providers.dart';
import '../../models/chat_models.dart';

class ScheduledMessagesList extends ConsumerWidget {
  final String conversationId;
  const ScheduledMessagesList({super.key, required this.conversationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<ChatMessagesPage>(
      future: ref.read(chatRepositoryProvider).fetchMessages(conversationId, isScheduled: true),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final messages = snapshot.data?.messages ?? [];
        if (messages.isEmpty) {
          return const Center(child: Text('No scheduled messages.'));
        }
        return ListView.builder(
          reverse: true,
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final msg = messages[index];
            return ListTile(
              title: Text(msg.content.isNotEmpty ? msg.content : (msg.hasAttachment ? 'Attachment' : '')),
              subtitle: Text(msg.createdAt.toLocal().toString()),
            );
          },
        );
      },
    );
  }
}
