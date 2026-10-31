import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:mobile_app/features/chat/data/chat_local_cache.dart';
import 'package:mobile_app/features/chat/data/chat_outbox_service.dart';
import 'package:mobile_app/features/chat/data/chat_repository.dart';
import 'package:mobile_app/features/chat/models/chat_models.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final Directory _dir;
  _FakePathProvider(this._dir);

  @override
  Future<String?> getApplicationSupportPath() async => _dir.path;

  @override
  Future<String?> getTemporaryPath() async => _dir.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _dir.path;
}

class _FakeChatRepository extends Fake implements ChatRepository {
  _FakeChatRepository({
    this.sendTextMessageFn,
    this.sendFileMessageFn,
  });

  final Future<ChatPostResult> Function({
    required String conversationId,
    required String content,
    String? clientMessageId,
    String? replyToMessageId,
    Map<String, dynamic>? metadata,
    String? messageType,
    String? fileUrl,
    bool isSilent,
    bool isScheduled,
    DateTime? scheduledFor,
  })? sendTextMessageFn;

  final Future<ChatPostResult> Function({
    required String conversationId,
    required String filePath,
    String? content,
    String? replyToMessageId,
    String? customFileName,
    Map<String, dynamic>? metadata,
    void Function(int sent, int total)? onProgress,
  })? sendFileMessageFn;

  @override
  Future<ChatPostResult> sendTextMessage({
    required String conversationId,
    required String content,
    String? clientMessageId,
    String? replyToMessageId,
    Map<String, dynamic>? metadata,
    String? messageType,
    String? fileUrl,
    bool isSilent = false,
    bool isScheduled = false,
    DateTime? scheduledFor,
  }) {
    if (sendTextMessageFn != null) {
      return sendTextMessageFn!(
        conversationId: conversationId,
        content: content,
        clientMessageId: clientMessageId,
        replyToMessageId: replyToMessageId,
        metadata: metadata,
        messageType: messageType,
        fileUrl: fileUrl,
        isSilent: isSilent,
        isScheduled: isScheduled,
        scheduledFor: scheduledFor,
      );
    }
    throw UnimplementedError();
  }

  @override
  Future<ChatPostResult> sendFileMessage({
    required String conversationId,
    required String filePath,
    String? content,
    String? replyToMessageId,
    String? customFileName,
    Map<String, dynamic>? metadata,
    void Function(int sent, int total)? onProgress,
  }) {
    if (sendFileMessageFn != null) {
      return sendFileMessageFn!(
        conversationId: conversationId,
        filePath: filePath,
        content: content,
        replyToMessageId: replyToMessageId,
        customFileName: customFileName,
        metadata: metadata,
        onProgress: onProgress,
      );
    }
    throw UnimplementedError();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ChatLocalCache cache;
  late ChatOutboxService outbox;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('chat_outbox_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    cache = ChatLocalCache();
    await cache.clearAll();
    outbox = ChatOutboxService(cache);
  });

  tearDown(() async {
    outbox.dispose();
    await cache.clearAll();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  ChatMessage buildMockMessage({
    required String id,
    required String convId,
    required String content,
  }) {
    return ChatMessage(
      id: id,
      conversationId: convId,
      senderId: 'user-1',
      sender: null,
      content: content,
      messageType: 'text',
      fileUrl: null,
      fileName: null,
      fileSize: null,
      mimeType: null,
      replyToMessageId: null,
      isDeleted: false,
      metadata: null,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      seenBy: const [],
      deliveredTo: const [],
    );
  }

  test('Enqueue persists items and isPending returns true', () async {
    final item = ChatOutboxItem(
      clientMessageId: 'client-1',
      conversationId: 'conv-1',
      content: 'Hello offline',
      messageType: 'text',
      createdAt: DateTime.now(),
    );

    await outbox.enqueue(item);

    expect(outbox.isPending('client-1'), isTrue);
    expect(outbox.isPending('temp_client-1'), isTrue);
    expect(outbox.isPending('non-existent'), isFalse);

    // Verify persistence across new service instance reading same cache
    final outbox2 = ChatOutboxService(cache);
    final pending = await outbox2.getPendingItems();
    expect(pending.length, equals(1));
    expect(pending.first.clientMessageId, equals('client-1'));
    expect(pending.first.content, equals('Hello offline'));
  });

  test('drainQueue sends items in FIFO order and removes them on success', () async {
    final sentOrder = <String>[];
    final repo = _FakeChatRepository(
      sendTextMessageFn: ({
        required String conversationId,
        required String content,
        String? clientMessageId,
        String? replyToMessageId,
        Map<String, dynamic>? metadata,
        String? messageType,
        String? fileUrl,
        bool isSilent = false,
        bool isScheduled = false,
        DateTime? scheduledFor,
      }) async {
        sentOrder.add(content);
        return ChatPostResult(
          message: buildMockMessage(
            id: 'server_$clientMessageId',
            convId: conversationId,
            content: content,
          ),
          conversation: ChatConversation.fromJson({
            'id': conversationId,
            'type': 'direct',
            'name': 'Test Chat',
          }),
        );
      },
    );

    final now = DateTime.now();
    await outbox.enqueue(ChatOutboxItem(
      clientMessageId: 'c1',
      conversationId: 'conv-1',
      content: 'First',
      messageType: 'text',
      createdAt: now.subtract(const Duration(seconds: 10)),
    ));
    await outbox.enqueue(ChatOutboxItem(
      clientMessageId: 'c2',
      conversationId: 'conv-1',
      content: 'Second',
      messageType: 'text',
      createdAt: now,
    ));

    final confirmed = <String>[];
    await outbox.drainQueue(
      repository: repo,
      onConfirmed: (item, msg) {
        confirmed.add(item.clientMessageId);
      },
    );

    expect(sentOrder, equals(['First', 'Second']));
    expect(confirmed, equals(['c1', 'c2']));
    expect(outbox.isPending('c1'), isFalse);
    expect(outbox.isPending('c2'), isFalse);
  });

  test('drainQueue halts and keeps items pending on SocketException (offline)', () async {
    var callCount = 0;
    final repo = _FakeChatRepository(
      sendTextMessageFn: ({
        required String conversationId,
        required String content,
        String? clientMessageId,
        String? replyToMessageId,
        Map<String, dynamic>? metadata,
        String? messageType,
        String? fileUrl,
        bool isSilent = false,
        bool isScheduled = false,
        DateTime? scheduledFor,
      }) async {
        callCount++;
        throw const SocketException('Network is unreachable');
      },
    );

    await outbox.enqueue(ChatOutboxItem(
      clientMessageId: 'c1',
      conversationId: 'conv-1',
      content: 'Will fail offline',
      messageType: 'text',
      createdAt: DateTime.now(),
    ));

    var failedCalled = false;
    await outbox.drainQueue(
      repository: repo,
      onFailed: (_, __) {
        failedCalled = true;
      },
    );

    // Call count was 1, then queue halted
    expect(callCount, equals(1));
    // onFailed should NOT be called for transient network offline
    expect(failedCalled, isFalse);
    // Message MUST stay pending in outbox for next reconnection!
    expect(outbox.isPending('c1'), isTrue);
  });

  test('drainQueue sends file messages successfully', () async {
    var sentFilePath = '';
    final repo = _FakeChatRepository(
      sendFileMessageFn: ({
        required String conversationId,
        required String filePath,
        String? content,
        String? replyToMessageId,
        String? customFileName,
        Map<String, dynamic>? metadata,
        void Function(int sent, int total)? onProgress,
      }) async {
        sentFilePath = filePath;
        return ChatPostResult(
          message: buildMockMessage(
            id: 'srv_file',
            convId: conversationId,
            content: content ?? '',
          ),
          conversation: ChatConversation.fromJson({
            'id': conversationId,
            'type': 'direct',
            'name': 'Test Chat',
          }),
        );
      },
    );

    await outbox.enqueue(ChatOutboxItem(
      clientMessageId: 'f1',
      conversationId: 'conv-1',
      content: 'file caption',
      filePath: '/path/to/test.pdf',
      messageType: 'file',
      createdAt: DateTime.now(),
    ));

    var confirmed = false;
    await outbox.drainQueue(
      repository: repo,
      onConfirmed: (item, _) {
        confirmed = true;
      },
    );

    expect(sentFilePath, equals('/path/to/test.pdf'));
    expect(confirmed, isTrue);
    expect(outbox.isPending('f1'), isFalse);
  });
}
