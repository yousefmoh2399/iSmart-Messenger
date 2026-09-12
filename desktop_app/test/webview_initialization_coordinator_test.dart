import 'package:flutter_test/flutter_test.dart';

class MockWebviewController {
  int initializeCalls = 0;
  int loadUrlCalls = 0;
  List<String> loadedUrls = [];
  bool failInitializeOnce = false;

  Future<void> initialize() async {
    initializeCalls++;
    if (failInitializeOnce) {
      failInitializeOnce = false; // succeed next time
      throw Exception('Mock initialization failed');
    }
  }

  Future<void> loadUrl(String url) async {
    loadUrlCalls++;
    loadedUrls.add(url);
    await Future.delayed(const Duration(milliseconds: 10));
  }
}

class TestWebViewCoordinator {
  TestWebViewCoordinator(this._webViewController);

  final MockWebviewController _webViewController;
  bool _isWebviewInitialized = false;
  bool mounted = true;

  Future<void>? _initFuture;
  Future<void>? _urlProcessingFuture;

  String? _pendingUrl;
  String? _loadedUrl;

  void handleUrl(String url) {
    final normalized = url.trim();
    if (normalized.isEmpty || !mounted) return;

    _pendingUrl = normalized;

    if (_urlProcessingFuture != null) return;

    late final Future<void> processingFuture;

    processingFuture = _processPendingUrls()
        .catchError((Object error, StackTrace stackTrace) {
          // Catch silently for tests
        })
        .whenComplete(() {
          if (identical(_urlProcessingFuture, processingFuture)) {
            _urlProcessingFuture = null;
          }

          if (mounted && _pendingUrl != null && _pendingUrl != _loadedUrl) {
            handleUrl(_pendingUrl!);
          }
        });

    _urlProcessingFuture = processingFuture;
  }

  Future<void> _processPendingUrls() async {
    try {
      await _ensureControllerInitialized();
    } catch (_) {
      _pendingUrl = null;
      rethrow;
    }

    while (mounted) {
      final targetUrl = _pendingUrl;

      if (targetUrl == null || targetUrl == _loadedUrl) {
        return;
      }

      try {
        await _webViewController.loadUrl(targetUrl);
      } catch (_) {
        if (_pendingUrl == targetUrl) {
          _pendingUrl = null;
        }
        rethrow;
      }

      if (!mounted) return;

      _loadedUrl = targetUrl;

      if (_pendingUrl == targetUrl) {
        return;
      }
    }
  }

  Future<void> _ensureControllerInitialized() {
    final existing = _initFuture;
    if (existing != null) return existing;

    final future = () async {
      if (!_isWebviewInitialized) {
        await _webViewController.initialize();
        _isWebviewInitialized = true;
      }
    }();
    _initFuture = future;

    return future.catchError((Object error, StackTrace stackTrace) {
      if (identical(_initFuture, future)) {
        _initFuture = null;
      }
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  void dispose() {
    mounted = false;
  }
}

void main() {
  group('WebView Initialization Coordinator Tests', () {
    late MockWebviewController mockWebViewController;
    late TestWebViewCoordinator coordinator;

    setUp(() {
      mockWebViewController = MockWebviewController();
      coordinator = TestWebViewCoordinator(mockWebViewController);
    });

    test(
      'Loads final URL skipping intermediate ones during initialization',
      () async {
        coordinator.handleUrl('http://url-a.com');
        coordinator.handleUrl('http://url-b.com');
        coordinator.handleUrl('http://url-c.com');

        // Wait for async processing
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(mockWebViewController.initializeCalls, equals(1));
        // Only final URL (url-c) should be loaded, skipping url-a and url-b
        expect(mockWebViewController.loadedUrls, contains('http://url-c.com'));
        expect(mockWebViewController.loadedUrls.length, equals(1));
      },
    );

    test(
      'Queue manages URL changes that arrive during active loading',
      () async {
        coordinator.handleUrl('http://url-a.com');

        // Wait slightly so url-a starts loading
        await Future<void>.delayed(const Duration(milliseconds: 2));
        coordinator.handleUrl('http://url-b.com');

        // Wait for complete processing
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          mockWebViewController.loadedUrls,
          equals(['http://url-a.com', 'http://url-b.com']),
        );
      },
    );

    test('Allows retrying initialization after failure', () async {
      mockWebViewController.failInitializeOnce = true;

      coordinator.handleUrl('http://url-a.com');
      await Future<void>.delayed(const Duration(milliseconds: 15));

      // Should have failed initialize once, loadedUrls is empty
      expect(mockWebViewController.initializeCalls, equals(1));
      expect(mockWebViewController.loadedUrls, isEmpty);

      // Try again, should succeed
      coordinator.handleUrl('http://url-a.com');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(mockWebViewController.initializeCalls, equals(2));
      expect(mockWebViewController.loadedUrls, equals(['http://url-a.com']));
    });

    test('Does not load any URL after coordinator is disposed', () async {
      coordinator.dispose();
      coordinator.handleUrl('http://url-a.com');

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(mockWebViewController.initializeCalls, equals(0));
      expect(mockWebViewController.loadedUrls, isEmpty);
    });
  });
}
