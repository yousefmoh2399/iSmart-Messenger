import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/chat/models/chat_models.dart';
import 'package:mobile_app/features/chat/presentation/widgets/chat_audio_attachment_player.dart';
import 'package:mobile_app/features/chat/presentation/widgets/message_reminder_sheet.dart';
import 'package:mobile_app/features/chat/presentation/widgets/quick_replies_sheet.dart';

void main() {
  group('ChatMessageReminder', () {
    test('serializes and deserializes accurately', () {
      final remindAt = DateTime.utc(2026, 11, 1, 9, 0);
      final createdAt = DateTime.utc(2026, 10, 31, 12, 30);

      final reminder = ChatMessageReminder(
        id: 'rem_m1',
        messageId: 'm1',
        conversationId: 'c1',
        conversationTitle: 'فريق المبيعات',
        senderName: 'أحمد علي',
        contentPreview: 'مراجعة تقرير المبيعات الشهري',
        remindAt: remindAt,
        createdAt: createdAt,
        note: 'الرد قبل الاجتماع',
      );

      final json = reminder.toJson();
      final restored = ChatMessageReminder.fromJson(json);

      expect(restored.id, 'rem_m1');
      expect(restored.messageId, 'm1');
      expect(restored.conversationId, 'c1');
      expect(restored.conversationTitle, 'فريق المبيعات');
      expect(restored.senderName, 'أحمد علي');
      expect(restored.contentPreview, 'مراجعة تقرير المبيعات الشهري');
      expect(restored.remindAt.toUtc(), remindAt);
      expect(restored.createdAt.toUtc(), createdAt);
      expect(restored.note, 'الرد قبل الاجتماع');
    });

    test('copyWith updates remindAt and note cleanly', () {
      final reminder = ChatMessageReminder(
        id: 'rem_m2',
        messageId: 'm2',
        conversationId: 'c2',
        conversationTitle: 'الإدارة',
        senderName: 'سارة',
        contentPreview: 'اعتماد الميزانية',
        remindAt: DateTime.utc(2026, 11, 1, 9, 0),
        createdAt: DateTime.utc(2026, 10, 31, 10, 0),
      );

      final updatedTime = DateTime.utc(2026, 11, 1, 9, 30);
      final snoozed = reminder.copyWith(
        remindAt: updatedTime,
        note: 'تم التأجيل 30 دقيقة',
      );

      expect(snoozed.remindAt, updatedTime);
      expect(snoozed.note, 'تم التأجيل 30 دقيقة');
      expect(snoozed.messageId, 'm2');
    });
  });

  group('GlobalVoiceSession & ChatAudioPlaybackCoordinator', () {
    test('stores voice message metadata for global mini player', () {
      final msg = ChatMessage(
        id: 'voice_1',
        conversationId: 'conv_99',
        senderId: 'u_2',
        sender: null,
        content: '',
        messageType: 'audio',
        fileName: 'voice_note.m4a',
        fileUrl: '/uploads/chat/voice_note.m4a',
        mimeType: 'audio/mp4',
        fileSize: 42000,
        replyToMessageId: null,
        metadata: const <String, dynamic>{},
        isDeleted: false,
        deliveredTo: const [],
        seenBy: const [],
        createdAt: DateTime.utc(2026, 10, 31, 8, 0),
        updatedAt: DateTime.utc(2026, 10, 31, 8, 0),
      );

      final session = GlobalVoiceSession(
        message: msg,
        conversationId: 'conv_99',
        conversationTitle: 'قسم الدعم الفني',
        senderName: 'محمد خالد',
        filePath: '/tmp/voice_note.m4a',
        totalDuration: const Duration(seconds: 45),
      );

      expect(session.message.id, 'voice_1');
      expect(session.conversationId, 'conv_99');
      expect(session.conversationTitle, 'قسم الدعم الفني');
      expect(session.senderName, 'محمد خالد');
      expect(session.totalDuration, const Duration(seconds: 45));
      expect(
        ChatAudioPlaybackCoordinator.activePlayerNotifier.value,
        isNull,
      );
    });
  });

  group('QuickReplyTemplate', () {
    test('normalizes shortcut, serializes, and matches slash queries', () {
      final template = QuickReplyTemplate(
        id: 'qr_1',
        shortcut: '/استلام',
        content: 'تم الاستلام وجاري المراجعة',
        createdAt: DateTime.utc(2026, 10, 31, 10, 0),
        usageCount: 3,
      );

      expect(template.cleanShortcut, 'استلام');
      expect(template.triggerCommand, '/استلام');
      expect(template.matchesQuery(''), isTrue);
      expect(template.matchesQuery('استلام'), isTrue);
      expect(template.matchesQuery('/است'), isTrue);
      expect(template.matchesQuery('المراجعة'), isTrue);
      expect(template.matchesQuery('غير_موجود'), isFalse);

      final restored = QuickReplyTemplate.fromJson(template.toJson());
      expect(restored.id, 'qr_1');
      expect(restored.cleanShortcut, 'استلام');
      expect(restored.content, 'تم الاستلام وجاري المراجعة');
      expect(restored.usageCount, 3);
    });
  });
}
