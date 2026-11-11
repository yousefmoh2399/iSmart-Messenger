import 'dart:async';
import 'dart:typed_data';

import 'package:desktop_app/features/auth/data/auth_repository.dart';
import 'package:desktop_app/features/chat/data/chat_socket_service.dart';
import 'package:desktop_app/shared/providers/providers.dart';
import 'package:desktop_app/shared/widgets/authenticated_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Valid 1x1 transparent PNG bytes for Image.memory decoding in widget tests.
final Uint8List _kValid1x1Png = Uint8List.fromList(const <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class _FakeChatSocketService implements ChatSocketService {
  final StreamController<ChatSocketEvent> controller =
      StreamController<ChatSocketEvent>.broadcast();

  @override
  Stream<ChatSocketEvent> get events => controller.stream;

  void emitConnected() {
    controller.add(const ChatSocketEvent(type: 'socket_connected', payload: {}));
  }

  Future<void> closeController() => controller.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthRepository implements AuthRepository {
  String? validToken = 'token-1';
  String? cachedToken = 'token-cached';
  bool throwOnGetValidToken = false;

  @override
  Future<String?> getValidToken({
    Duration refreshBefore = const Duration(minutes: 2),
  }) async {
    if (throwOnGetValidToken) {
      throw Exception('Network unavailable while refreshing token');
    }
    return validToken;
  }

  @override
  Future<String?> getToken() async => cachedToken;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('shouldReloadAuthenticatedImage', () {
    test('returns true in Electron/web fallback state when bytes are null and image did not render even if error is null', () {
      expect(
        shouldReloadAuthenticatedImage(
          usesMemoryOrWebFallback: true,
          error: null,
          fallbackFailed: false,
          hasRenderedImage: false,
          hasBytes: false,
          hasResolvedHeaders: false,
        ),
        isTrue,
      );
    });

    test('returns true when fallback Image.network failed even without outer error', () {
      expect(
        shouldReloadAuthenticatedImage(
          usesMemoryOrWebFallback: true,
          error: null,
          fallbackFailed: true,
          hasRenderedImage: false,
          hasBytes: false,
          hasResolvedHeaders: false,
        ),
        isTrue,
      );
    });

    test('returns false when memory bytes exist or fallback image rendered cleanly', () {
      expect(
        shouldReloadAuthenticatedImage(
          usesMemoryOrWebFallback: true,
          error: null,
          fallbackFailed: false,
          hasRenderedImage: true,
          hasBytes: true,
          hasResolvedHeaders: false,
        ),
        isFalse,
      );
      expect(
        shouldReloadAuthenticatedImage(
          usesMemoryOrWebFallback: true,
          error: null,
          fallbackFailed: false,
          hasRenderedImage: true,
          hasBytes: false,
          hasResolvedHeaders: false,
        ),
        isFalse,
      );
    });

    test('checks headers and rendered state on native platform', () {
      expect(
        shouldReloadAuthenticatedImage(
          usesMemoryOrWebFallback: false,
          error: null,
          fallbackFailed: false,
          hasRenderedImage: false,
          hasBytes: false,
          hasResolvedHeaders: true,
        ),
        isTrue,
      );
      expect(
        shouldReloadAuthenticatedImage(
          usesMemoryOrWebFallback: false,
          error: null,
          fallbackFailed: false,
          hasRenderedImage: true,
          hasBytes: false,
          hasResolvedHeaders: true,
        ),
        isFalse,
      );
    });
  });

  group('AuthenticatedNetworkImage offline recovery', () {
    testWidgets('reloads failed avatar automatically when socket_connected fires', (tester) async {
      final fakeSocket = _FakeChatSocketService();
      final fakeAuth = _FakeAuthRepository();
      addTearDown(fakeSocket.closeController);

      bool isOnline = false;
      int fetchCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatSocketServiceProvider.overrideWithValue(fakeSocket),
            authRepositoryProvider.overrideWithValue(fakeAuth),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: AuthenticatedNetworkImage(
                imageUrl: 'http://127.0.0.1:5000/api/users/u-offline-1/avatar',
                width: 48,
                height: 48,
                placeholder: const Text('LOADING'),
                errorWidget: const Text('OFFLINE'),
                byteLoaderOverride: (url, headers) async {
                  fetchCount++;
                  if (!isOnline) {
                    throw Exception('Offline');
                  }
                  return _kValid1x1Png;
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(fetchCount, 1);
      expect(find.text('OFFLINE'), findsOneWidget);
      expect(find.byType(Image), findsNothing);

      // Network comes back and socket reconnects.
      isOnline = true;
      fakeSocket.emitConnected();

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(fetchCount, 2);
      expect(find.text('OFFLINE'), findsNothing);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('recovers via serverRecoveryRevisionProvider and handles one transient post-reconnect failure via follow-up retry', (tester) async {
      final fakeSocket = _FakeChatSocketService();
      final fakeAuth = _FakeAuthRepository();
      addTearDown(fakeSocket.closeController);

      int fetchCount = 0;
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatSocketServiceProvider.overrideWithValue(fakeSocket),
            authRepositoryProvider.overrideWithValue(fakeAuth),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  capturedRef = ref;
                  return AuthenticatedNetworkImage(
                    imageUrl: 'http://127.0.0.1:5000/api/users/u-offline-2/avatar',
                    width: 48,
                    height: 48,
                    placeholder: const Text('LOADING'),
                    errorWidget: const Text('OFFLINE'),
                    byteLoaderOverride: (url, headers) async {
                      fetchCount++;
                      // Fail at offline boot (#1) AND on initial recovery (#2 before VPN/DNS settles); succeed on #3.
                      if (fetchCount < 3) {
                        throw Exception('VPN route not ready');
                      }
                      return _kValid1x1Png;
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(fetchCount, 1);
      expect(find.text('OFFLINE'), findsOneWidget);

      capturedRef.read(serverRecoveryRevisionProvider.notifier).state++;

      // First jittered attempt (#2) fires within 1.5s and fails transiently.
      await tester.pump(const Duration(seconds: 2));
      expect(fetchCount, 2);

      // Bounded follow-up retry (#3) fires within ~3.5s and succeeds.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      expect(fetchCount, 3);
      expect(find.byType(Image), findsOneWidget);

      // Confirm no extra polling after image has loaded.
      await tester.pump(const Duration(seconds: 10));
      expect(fetchCount, 3);
    });

    testWidgets('recovers when getValidToken threw offline at boot and authCredentialsRevisionProvider updates', (tester) async {
      final fakeSocket = _FakeChatSocketService();
      final fakeAuth = _FakeAuthRepository()..throwOnGetValidToken = true;
      addTearDown(fakeSocket.closeController);

      bool isOnline = false;
      int fetchCount = 0;
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatSocketServiceProvider.overrideWithValue(fakeSocket),
            authRepositoryProvider.overrideWithValue(fakeAuth),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  capturedRef = ref;
                  return AuthenticatedNetworkImage(
                    imageUrl: 'http://127.0.0.1:5000/api/users/u-offline-3/avatar',
                    width: 48,
                    height: 48,
                    placeholder: const Text('LOADING'),
                    errorWidget: const Text('OFFLINE'),
                    byteLoaderOverride: (url, headers) async {
                      fetchCount++;
                      if (!isOnline) {
                        throw Exception('Offline');
                      }
                      return _kValid1x1Png;
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(fetchCount, 1);
      expect(find.text('OFFLINE'), findsOneWidget);

      fakeAuth.throwOnGetValidToken = false;
      fakeAuth.validToken = 'fresh-token-after-online';
      isOnline = true;
      capturedRef.read(authCredentialsRevisionProvider.notifier).state++;

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(fetchCount, 2);
      expect(find.byType(Image), findsOneWidget);
    });
  });
}
