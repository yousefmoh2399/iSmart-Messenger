import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:desktop_app/core/network/api_client.dart';
import 'package:desktop_app/features/files/data/document_repository.dart';
import 'package:desktop_app/features/auth/data/auth_repository.dart';
import 'package:desktop_app/features/auth/data/session_store.dart';
import 'package:desktop_app/features/auth/data/auth_session_manager.dart';
import 'package:desktop_app/shared/services/local_media_storage_service.dart';
import 'package:desktop_app/core/settings/user_preferences.dart';
import 'package:desktop_app/shared/models/remote_document.dart';

class MockLocalMediaStorage extends LocalMediaStorageService {
  @override
  Future<Directory> documentsDirectory({String? preferredPath}) async {
    return Directory.systemTemp.createTempSync('docs_test');
  }
}

class DummySessionStore extends SessionStore {}

class MockAuthRefreshService extends AuthRefreshService {
  MockAuthRefreshService() : super(baseUrl: 'http://localhost:8000');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('Document Download Deduplication and Multicast Tests', () {
    late ApiClient apiClient;
    late DocumentRepository repository;
    int networkCallCount = 0;

    setUp(() {
      networkCallCount = 0;
      apiClient = ApiClient(baseUrl: 'http://localhost:8000');
      final mockStore = DummySessionStore();
      final mockSessionManager = AuthSessionManager(
        tokenStorage: mockStore,
        refreshService: MockAuthRefreshService(),
      );
      repository = DocumentRepository(
        apiClient,
        AuthRepository(
          apiClient,
          mockStore,
          sessionManager: mockSessionManager,
        ),
        MockLocalMediaStorage(),
        UserPreferences.defaults(),
      );

      apiClient.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            networkCallCount++;
            await Future<void>.delayed(const Duration(milliseconds: 20));
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: ResponseBody.fromBytes([1, 2, 3, 4], 200),
              ),
            );
          },
        ),
      );
    });

    test(
      'Multiple concurrent calls to downloadDocument share same Future and receive progress updates',
      () async {
        final doc = RemoteDocument(
          id: 'doc-123',
          fileName: 'test.pdf',
          originalName: 'test.pdf',
          mimeType: 'application/pdf',
          pageCount: 1,
          fileSize: 4,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          ownerId: 'user-1',
          ownerUsername: 'user-1',
          ownerFullName: 'User 1',
          downloadUrl: '/api/documents/doc-123/download',
        );

        final List<double> progress1 = [];
        final List<double> progress2 = [];

        final f1 = repository.downloadDocument(
          doc,
          onProgress: (received, total) {
            progress1.add(received / total);
          },
        );

        final f2 = repository.downloadDocument(
          doc,
          onProgress: (received, total) {
            progress2.add(received / total);
          },
        );

        final result1 = await f1;
        final result2 = await f2;

        expect(networkCallCount, equals(1));
        expect(result1, equals(result2));
      },
    );
  });
}
