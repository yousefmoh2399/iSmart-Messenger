import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../../shared/providers/providers.dart';

final snipeitRefreshEventProvider = StateProvider<int>((ref) => 0);

class SnipeitScreen extends ConsumerStatefulWidget {
  const SnipeitScreen({super.key, this.isWrapped = false});
  final bool isWrapped;

  @override
  ConsumerState<SnipeitScreen> createState() => _SnipeitScreenState();
}

class _SnipeitScreenState extends ConsumerState<SnipeitScreen> {
  final _webViewController = WebviewController();
  bool _isWebviewInitialized = false;

  Future<void>? _initFuture;
  Future<void>? _urlProcessingFuture;

  String? _pendingUrl;
  String? _loadedUrl;

  ProviderSubscription<String>? _urlSubscription;
  ProviderSubscription<int>? _refreshSubscription;

  @override
  void initState() {
    super.initState();

    _urlSubscription = ref.listenManual<String>(
      appServerDefaultsProvider.select(
        (value) => value.valueOrNull?.snipeitUrl ?? "http://localhost:8000",
      ),
      (previous, next) {
        handleUrl(next);
      },
      fireImmediately: true,
    );

    _refreshSubscription = ref.listenManual<int>(snipeitRefreshEventProvider, (
      previous,
      next,
    ) {
      if (next != previous && _isWebviewInitialized) {
        _webViewController.reload();
      }
    });
  }

  void handleUrl(String url) {
    final normalized = url.trim();
    if (normalized.isEmpty || !mounted) return;

    _pendingUrl = normalized;

    if (_urlProcessingFuture != null) return;

    late final Future<void> processingFuture;

    processingFuture = _processPendingUrls()
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint('WebView URL processing failed: $error\n$stackTrace');
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
        if (mounted) {
          setState(() {
            _isWebviewInitialized = true;
          });
        }
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

  @override
  void dispose() {
    _urlSubscription?.close();
    _refreshSubscription?.close();
    _webViewController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.isWrapped
          ? null
          : AppBar(
              title: const Text('Snipe-IT'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    if (_isWebviewInitialized) {
                      _webViewController.reload();
                    }
                  },
                ),
              ],
            ),
      body: !_isWebviewInitialized
          ? const Center(child: CircularProgressIndicator())
          : Webview(_webViewController),
    );
  }
}
