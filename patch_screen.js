const fs = require('fs');
const lines = fs.readFileSync('mobile_app/lib/features/chat/presentation/conversation_screen.dart', 'utf8').split('\n');
const idx = lines.findIndex(l => l.includes('void _showScheduledMessagesSheet() {'));
lines.splice(idx, 0, \  void _showMessageDetails(ChatMessage message) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'من شاهد الرسالة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(),
              Expanded(
                child: FutureBuilder<Map<String, dynamic>>(
                  future: ref.read(chatRepositoryProvider).getReadReceipts(message.id),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('خطأ: \\\'));
                    }
                    final seenBy = snapshot.data?['seenBy'] as List<dynamic>? ?? [];
                    if (seenBy.isEmpty) {
                      return const Center(child: Text('لم يشاهدها أحد بعد.'));
                    }
                    return ListView.builder(
                      controller: scrollController,
                      itemCount: seenBy.length,
                      itemBuilder: (context, index) {
                        final user = seenBy[index] as Map<String, dynamic>;
                        return ListTile(
                          leading: ChatAvatar(
                            avatarUrl: user['avatarUrl']?.toString() ?? '',
                            radius: 20,
                            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                            fallback: Text(
                              user['displayName']?.toString().isNotEmpty == true 
                                  ? user['displayName'].toString()[0].toUpperCase() 
                                  : '?',
                            ),
                          ),
                          title: Text(user['displayName']?.toString() ?? 'مستخدم'),
                          subtitle: user['seenAt'] != null 
                              ? Text(DateTime.parse(user['seenAt'].toString()).toLocal().toString()) 
                              : null,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
\);
fs.writeFileSync('mobile_app/lib/features/chat/presentation/conversation_screen.dart', lines.join('\n'), 'utf8');
