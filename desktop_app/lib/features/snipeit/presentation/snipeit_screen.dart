import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher_string.dart';
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
  late final WebviewController _webViewController;
  bool _isWebviewInitialized = false;
  String? _initError;

  Future<void>? _initFuture;
  Future<void>? _urlProcessingFuture;

  String? _pendingUrl;
  String? _loadedUrl;

  ProviderSubscription<String>? _urlSubscription;
  ProviderSubscription<int>? _refreshSubscription;

  @override
  void initState() {
    super.initState();
    
    if (!kIsWeb) {
      _webViewController = WebviewController();
    }

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
      if (next != previous) {
        if (kIsWeb && _loadedUrl != null) {
          launchUrlString(_loadedUrl!);
        } else if (!kIsWeb && _isWebviewInitialized) {
          _webViewController.reload();
        }
      }
    });
  }

  void handleUrl(String url) {
    String normalized = url.trim();
    if (normalized.isEmpty || !mounted) return;

    if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }

    _pendingUrl = normalized;

    if (kIsWeb) {
      setState(() {
        _loadedUrl = normalized;
        _pendingUrl = null;
      });
      return;
    }

    if (_urlProcessingFuture != null) return;

    late final Future<void> processingFuture;

    processingFuture = _processPendingUrls()
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint('WebView URL processing failed: $error\n$stackTrace');
          if (mounted) {
            setState(() {
              _initError = error.toString();
            });
          }
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
        try {
          await _webViewController.initialize();
          if (mounted) {
            setState(() {
              _isWebviewInitialized = true;
              _initError = null;
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _initError = e.toString();
            });
          }
          rethrow;
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
    if (!kIsWeb) {
      _webViewController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        appBar: widget.isWrapped
            ? null
            : AppBar(
                title: const Text('Snipe-IT'),
              ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.open_in_browser, size: 64, color: Colors.blueGrey),
              const SizedBox(height: 16),
              const Text(
                'يتم عرض Snipe-IT في نافذة منفصلة.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  final target = _loadedUrl ?? _pendingUrl;
                  if (target != null && target.isNotEmpty) {
                    launchUrlString(target);
                  }
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('فتح السيرفر'),
              ),
            ],
          ),
        ),
      );
    }

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
                    } else if (_initError != null) {
                      _initFuture = null;
                      _urlProcessingFuture = null;
                      if (_loadedUrl != null) handleUrl(_loadedUrl!);
                    }
                  },
                ),
              ],
            ),
      body: _initError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'حدث خطأ أثناء تحميل السيرفر:\n$_initError',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _initError = null;
                        });
                        _initFuture = null;
                        _urlProcessingFuture = null;
                        if (_pendingUrl != null || _loadedUrl != null) {
                          handleUrl(_pendingUrl ?? _loadedUrl!);
                        }
                      },
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            )
          : !_isWebviewInitialized
              ? const Center(child: CircularProgressIndicator())
              : Webview(_webViewController),
    );
  }
}
