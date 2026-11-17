import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_app/core/network/api_client.dart';
import 'package:mobile_app/core/settings/user_preferences.dart';
import 'package:mobile_app/features/chat/data/chat_repository.dart';
import 'package:mobile_app/features/chat/models/chat_models.dart';
import 'package:mobile_app/shared/services/local_media_storage_service.dart';

class MockChatLocalMediaStorage extends LocalMediaStorageService {
  MockChatLocalMediaStorage(this.tempDir);
  final Directory tempDir;

  @override
  Future<Directory> chatDirectory({String? preferredPath}) async {
    final dir = Directory('${tempDir.path}/Chat');
    await dir.create(recursive: true);
    return dir;
  }

  @override
  Future<Directory> sentChatArchiveDirectory({String? preferredPath}) async {
    final dir = Directory('${tempDir.path}/Chat/sent');
    await dir.create(recursive: true);
    return dir;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('Chat Attachment Caching and Single Download Tests', () {
    late ApiClient apiClient;
    late Dio downloadDio;
    late ChatRepository repository;
    late Directory tempDir;
    int networkCallCount = 0;

    final dummyMessage = ChatMessage.fromJson({
      'id': 'msg_test_001',
      'conversationId': 'conv_001',
      'senderId': 'user_002',
      'content': 'Check this document',
      'messageType': 'file',
      'fileUrl': '/uploads/test_contract.pdf',
      'fileName': 'test_contract.pdf',
      'fileSize': 1024,
      'mimeType': 'application/pdf',
      'isDeleted': false,
      'createdAt': '2026-04-01T12:00:00.000Z',
      'updatedAt': '2026-04-01T12:00:00.000Z',
      'seenBy': [],
      'deliveredTo': [],
    });

    setUp(() {
      networkCallCount = 0;
      tempDir = Directory.systemTemp.createTempSync('chat_attach_test_');
      apiClient = ApiClient(baseUrl: 'http://localhost:8000');
      downloadDio = Dio(BaseOptions(baseUrl: 'http://localhost:8000'));

      downloadDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            networkCallCount++;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                headers: Headers.fromMap({
                  Headers.contentLengthHeader: ['4'],
                }),
                data: ResponseBody.fromBytes([65, 66, 67, 68], 200),
              ),
            );
          },
        ),
      );

      repository = ChatRepository(
        apiClient,
        MockChatLocalMediaStorage(tempDir),
        UserPreferences.defaults(),
        downloadDio: downloadDio,
      );
    });

    tearDown(() {
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    test('isAttachmentCached returns false when file has not been downloaded yet', () async {
      final isCached = await repository.isAttachmentCached(dummyMessage);
      expect(isCached, isFalse);

      final cachedPath = await repository.getCachedAttachmentPath(dummyMessage);
      expect(cachedPath, isNull);
    });

    test('downloadAttachment downloads once and subsequent calls return cached file without network', () async {
      // 1. First download
      final localPath = await repository.downloadAttachment(dummyMessage);
      expect(File(localPath).existsSync(), isTrue);
      expect(networkCallCount, equals(1));

      // 2. Verified cached
      final isCached = await repository.isAttachmentCached(dummyMessage);
      expect(isCached, isTrue);

      final cachedPath = await repository.getCachedAttachmentPath(dummyMessage);
      expect(cachedPath, equals(localPath));

      // 3. Second download call (tap again) must return cached path without hitting network
      final secondPath = await repository.downloadAttachment(dummyMessage);
      expect(secondPath, equals(localPath));
      expect(networkCallCount, equals(1)); // Still 1! No second network call.
    });

    test('downloadAttachment with forceRefresh re-downloads fresh content from network', () async {
      // 1. Initial download
      final path1 = await repository.downloadAttachment(dummyMessage);
      expect(networkCallCount, equals(1));

      // 2. Force re-download (long-press re-download)
      final path2 = await repository.downloadAttachment(dummyMessage, forceRefresh: true);
      expect(path2, equals(path1));
      expect(networkCallCount, equals(2)); // Re-downloaded!
    });

    test('isAttachmentCached recognizes locally existing localPath in message metadata', () async {
      final sampleFile = File('${tempDir.path}/sample_local.pdf');
      sampleFile.writeAsStringSync('sample content');

      final localMessage = ChatMessage.fromJson({
        'id': 'msg_local_001',
        'conversationId': 'conv_001',
        'senderId': 'user_me',
        'content': 'Local file',
        'messageType': 'file',
        'fileUrl': '/uploads/sample_local.pdf',
        'fileName': 'sample_local.pdf',
        'fileSize': 14,
        'metadata': {'localPath': sampleFile.path},
        'isDeleted': false,
        'createdAt': '2026-04-01T12:00:00.000Z',
        'updatedAt': '2026-04-01T12:00:00.000Z',
        'seenBy': [],
        'deliveredTo': [],
      });

      final isCached = await repository.isAttachmentCached(localMessage);
      expect(isCached, isTrue);

      final cachedPath = await repository.getCachedAttachmentPath(localMessage);
      expect(cachedPath, equals(sampleFile.path));
    });

    test('Concurrent downloads for the same attachment share a single network request', () async {
      final msg = ChatMessage.fromJson({
        'id': 'msg_voice_multi_01',
        'conversationId': 'conv_001',
        'senderId': 'user_002',
        'content': '',
        'messageType': 'audio',
        'fileUrl': '/uploads/voice_note_01.m4a',
        'fileName': 'voice_note_01.m4a',
        'fileSize': 2048,
        'mimeType': 'audio/mp4',
        'isDeleted': false,
        'createdAt': '2026-04-01T12:00:00.000Z',
        'updatedAt': '2026-04-01T12:00:00.000Z',
        'seenBy': [],
        'deliveredTo': [],
      });

      // Launch 3 simultaneous downloads (simulating multiple players or callbacks)
      final future1 = repository.downloadAttachment(msg);
      final future2 = repository.downloadAttachment(msg);
      final future3 = repository.downloadAttachment(msg);

      final results = await Future.wait([future1, future2, future3]);

      expect(results[0], equals(results[1]));
      expect(results[1], equals(results[2]));
      expect(File(results[0]).existsSync(), isTrue);
      expect(results[0].endsWith('.m4a'), isTrue);
      // Only 1 network request was made despite 3 concurrent calls
      expect(networkCallCount, equals(1));
    });
  });
}
