import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:desktop_app/core/network/in_flight_coalescer.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/media_url_resolver.dart';
import '../../features/auth/data/auth_repository.dart';
import '../providers/providers.dart';
import '../services/web_platform_bridge.dart' as web_bridge;

/// Evaluates whether [AuthenticatedNetworkImage] failed or has not yet rendered
/// a valid image frame and should therefore reload once connectivity recovers.
@visibleForTesting
bool shouldReloadAuthenticatedImage({
  required bool usesMemoryOrWebFallback,
  required Object? error,
  required bool fallbackFailed,
  required bool hasRenderedImage,
  required bool hasBytes,
  required bool hasResolvedHeaders,
  bool terminalHttpError = false,
}) {
  if (terminalHttpError) {
    return false;
  }
  if (error != null || fallbackFailed) {
    return true;
  }
  if (usesMemoryOrWebFallback) {
    if (hasBytes) {
      return false;
    }
    return !hasRenderedImage;
  }
  return !hasResolvedHeaders || !hasRenderedImage;
}

bool isTerminalMissingHttpError(Object? error) {
  if (error == null) return false;
  final text = error.toString().toLowerCase();
  return text.contains('status 404') ||
      text.contains('statuscode: 404') ||
      text.contains('status 403') ||
      text.contains('statuscode: 403') ||
      text.contains('status 410') ||
      text.contains('statuscode: 410');
}

String _redactUrlTokenForLog(String rawUrl) {
  final uri = Uri.tryParse(rawUrl);
  if (uri == null || !uri.queryParameters.containsKey('accessToken')) {
    return rawUrl;
  }
  final redacted = Map<String, String>.from(uri.queryParameters)
    ..['accessToken'] = '[redacted]';
  return uri.replace(queryParameters: redacted).toString();
}

class AuthenticatedNetworkImage extends ConsumerStatefulWidget {
  const AuthenticatedNetworkImage({
    super.key,
    required this.imageUrl,
    this.httpHeaders,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.clipOval = false,
    @visibleForTesting this.byteLoaderOverride,
  });

  final String imageUrl;
  final Map<String, String>? httpHeaders;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final bool clipOval;
  @visibleForTesting
  final Future<Uint8List> Function(String url, Map<String, String> headers)?
  byteLoaderOverride;

  @override
  ConsumerState<AuthenticatedNetworkImage> createState() =>
      _AuthenticatedNetworkImageState();
}

class _AuthenticatedNetworkImageState
    extends ConsumerState<AuthenticatedNetworkImage> {
  static const int _maxEntries = 300;
  static const int _maxCacheBytes = 80 * 1024 * 1024;
  static const int _maxPostReconnectRetries = 2;
  static final Dio _dio = Dio();
  static final LinkedHashMap<String, Uint8List> _memoryCache =
      LinkedHashMap<String, Uint8List>();
  static final Map<String, Future<Uint8List>> _inFlight =
      <String, Future<Uint8List>>{};
  static int _cacheBytes = 0;

  Uint8List? _bytes;
  Object? _error;
  String? _webImageUrl;
  String? _electronObjectUrl;
  Map<String, String>? _resolvedHeaders;
  String _activeKey = '';
  int _loadGeneration = 0;
  int _reloadNonce = 0;
  int _reconnectRetryCount = 0;
  bool _hasRenderedImage = false;
  bool _networkFallbackFailed = false;
  bool _hasSeenReconnectSignal = false;
  StreamSubscription? _socketSub;
  StreamSubscription? _windowOnlineSub;
  ProviderSubscription<int>? _serverRecoverySub;
  ProviderSubscription<int>? _authCredsSub;
  Timer? _reconnectTimer;

  bool get _usesMemoryOrWebFallback =>
      kIsWeb || widget.byteLoaderOverride != null;

  bool get _needsReload => shouldReloadAuthenticatedImage(
    usesMemoryOrWebFallback: _usesMemoryOrWebFallback,
    error: _error,
    fallbackFailed: _networkFallbackFailed,
    hasRenderedImage: _hasRenderedImage,
    hasBytes: _bytes != null,
    hasResolvedHeaders: _resolvedHeaders != null,
    terminalHttpError: isTerminalMissingHttpError(_error),
  );

  @override
  void initState() {
    super.initState();
    _subscribeToReconnection();
    unawaited(_load());
  }

  void _onConnectivityRestored() {
    if (!mounted || !_needsReload) {
      return;
    }
    _hasSeenReconnectSignal = true;
    _reconnectRetryCount = 0;
    _scheduleReconnectedLoad(delayMs: 150 + Random().nextInt(1051));
  }

  void _scheduleFollowUpRetryIfNeeded() {
    if (!mounted ||
        !_hasSeenReconnectSignal ||
        !_needsReload ||
        _reconnectRetryCount >= _maxPostReconnectRetries) {
      return;
    }
    _reconnectRetryCount++;
    final baseMs = _reconnectRetryCount == 1 ? 2200 : 5500;
    _scheduleReconnectedLoad(
      delayMs: baseMs + Random().nextInt(900),
      resetTimer: false,
    );
  }

  void _scheduleReconnectedLoad({int delayMs = 250, bool resetTimer = true}) {
    if (!mounted) {
      return;
    }
    if (!resetTimer && (_reconnectTimer?.isActive ?? false)) {
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      _reconnectTimer = null;
      if (!mounted) {
        return;
      }
      if (_needsReload) {
        unawaited(_load(fromReconnect: true));
      }
    });
  }

  void _subscribeToReconnection() {
    try {
      final socketService = ref.read(chatSocketServiceProvider);
      _socketSub = socketService.events.listen((event) {
        if (event.type == 'socket_connected' && mounted) {
          _onConnectivityRestored();
        }
      });
    } catch (_) {}

    final onOnline = web_bridge.onWindowOnline;
    if (onOnline != null) {
      _windowOnlineSub = onOnline.listen((_) {
        if (mounted) {
          _onConnectivityRestored();
        }
      });
    }

    try {
      _serverRecoverySub = ref.listenManual<int>(
        serverRecoveryRevisionProvider,
        (previous, next) {
          if (previous != next && mounted) {
            _onConnectivityRestored();
          }
        },
      );
    } catch (_) {}

    try {
      _authCredsSub = ref.listenManual<int>(
        authCredentialsRevisionProvider,
        (previous, next) {
          if (previous != next && mounted) {
            _onConnectivityRestored();
          }
        },
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _socketSub?.cancel();
    _windowOnlineSub?.cancel();
    _serverRecoverySub?.close();
    _authCredsSub?.close();
    _revokeElectronObjectUrl();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AuthenticatedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.httpHeaders.toString() != widget.httpHeaders.toString()) {
      _reconnectTimer?.cancel();
      _activeKey = '';
      _resolvedHeaders = null;
      _bytes = null;
      _webImageUrl = null;
      _error = null;
      _hasRenderedImage = false;
      _networkFallbackFailed = false;
      _reconnectRetryCount = 0;
      _hasSeenReconnectSignal = false;
      _revokeElectronObjectUrl();
      unawaited(_load());
    }
  }

  Future<void> _load({bool fromReconnect = false}) async {
    final generation = ++_loadGeneration;
    final imageUrl = widget.imageUrl.trim();
    final explicitHeaders = widget.httpHeaders;
    final authRepository = widget.byteLoaderOverride == null
        ? ref.read(authRepositoryProvider)
        : null;
    final url = resolveApiUrl(imageUrl);
    if (url.isEmpty) {
      if (mounted) {
        setState(() {
          _webImageUrl = null;
          _revokeElectronObjectUrl();
          _bytes = null;
          _resolvedHeaders = null;
          _hasRenderedImage = false;
          _networkFallbackFailed = false;
          _error = StateError('Empty image URL.');
        });
      }
      return;
    }

    if (fromReconnect) {
      final staleWebUrl = _webImageUrl;
      if (staleWebUrl != null) {
        unawaited(NetworkImage(staleWebUrl).evict().catchError((_) => false));
      }
      if (!kIsWeb && _networkFallbackFailed) {
        unawaited(
          CachedNetworkImageProvider(url).evict().catchError((_) => false),
        );
      }
      if (mounted) {
        setState(() {
          _networkFallbackFailed = false;
          _hasRenderedImage = false;
          _webImageUrl = null;
          _error = null;
          _reloadNonce++;
        });
      } else {
        _networkFallbackFailed = false;
        _hasRenderedImage = false;
        _webImageUrl = null;
        _error = null;
        _reloadNonce++;
      }
    }

    final headers = await _headers(
      explicitHeaders: explicitHeaders,
      authRepository: authRepository,
    );
    if (!mounted || generation != _loadGeneration) {
      return;
    }
    final cacheKey = _cacheKey(url, headers);
    final keyChanged = _activeKey != cacheKey;
    _activeKey = cacheKey;
    final cachedBytes = _memoryCache[cacheKey];

    if (keyChanged || (_usesMemoryOrWebFallback && _bytes == null && cachedBytes != null)) {
      _revokeElectronObjectUrl();
      setState(() {
        _webImageUrl = null;
        _electronObjectUrl = null;
        _bytes = cachedBytes;
        _resolvedHeaders = null;
        _error = null;
        _networkFallbackFailed = false;
        _hasRenderedImage = cachedBytes != null;
        if (cachedBytes != null) {
          _reconnectRetryCount = 0;
        }
      });
      if (cachedBytes != null && _usesMemoryOrWebFallback) {
        return;
      }
    }

    if (_usesMemoryOrWebFallback) {
      if (web_bridge.isElectron() || widget.byteLoaderOverride != null) {
        if (mounted && generation == _loadGeneration && _bytes == null) {
          setState(() => _error = null);
        }

        try {
          final bytes = await runCoalescedInFlight(
            _inFlight,
            cacheKey,
            () => _fetchWithAuthRetry(url, headers, authRepository),
          );
          _remember(cacheKey, bytes);
          if (mounted &&
              generation == _loadGeneration &&
              _activeKey == cacheKey) {
            _revokeElectronObjectUrl();
            _reconnectRetryCount = 0;
            setState(() {
              _bytes = bytes;
              _error = null;
              _webImageUrl = null;
              _resolvedHeaders = null;
              _networkFallbackFailed = false;
              _hasRenderedImage = true;
            });
          }
        } catch (fallbackError) {
          final isElectronRuntime = web_bridge.isElectron();
          debugPrint(
            'Electron memory image fetch failed: ${_redactUrlTokenForLog(url)} -> $fallbackError',
          );
          if (widget.byteLoaderOverride != null || isElectronRuntime) {
            if (mounted &&
                generation == _loadGeneration &&
                _activeKey == cacheKey) {
              setState(() {
                _bytes = null;
                _webImageUrl = null;
                _error = fallbackError;
                _hasRenderedImage = false;
                _networkFallbackFailed = true;
              });
              if (fromReconnect && !isTerminalMissingHttpError(fallbackError)) {
                _scheduleFollowUpRetryIfNeeded();
              }
            }
            return;
          }
          final webUrl = _urlWithAccessToken(url, headers);
          if (mounted &&
              generation == _loadGeneration &&
              _activeKey == cacheKey) {
            _revokeElectronObjectUrl();
            setState(() {
              _webImageUrl = webUrl;
              _bytes = null;
              _error = null;
              _resolvedHeaders = null;
              _hasRenderedImage = false;
              _networkFallbackFailed = false;
            });
            if (fromReconnect) {
              _scheduleFollowUpRetryIfNeeded();
            }
          }
        }
      } else {
        final webUrl = _urlWithAccessToken(url, headers);
        if (mounted &&
            generation == _loadGeneration &&
            _activeKey == cacheKey) {
          _revokeElectronObjectUrl();
          setState(() {
            _webImageUrl = webUrl;
            _bytes = null;
            _resolvedHeaders = null;
            _error = null;
            _hasRenderedImage = false;
            _networkFallbackFailed = false;
          });
        }
      }
      return;
    }

    // Native Platform: Use CachedNetworkImage
    if (mounted && generation == _loadGeneration && _activeKey == cacheKey) {
      _revokeElectronObjectUrl();
      setState(() {
        _resolvedHeaders = headers;
        _bytes = null;
        _webImageUrl = null;
        _error = null;
        _hasRenderedImage = false;
        _networkFallbackFailed = false;
      });
    }
  }

  void _revokeElectronObjectUrl() {
    final objectUrl = _electronObjectUrl;
    if (objectUrl == null) {
      return;
    }
    _electronObjectUrl = null;
    web_bridge.revokeObjectUrl(objectUrl);
  }

  Future<Map<String, String>> _headers({
    required Map<String, String>? explicitHeaders,
    required AuthRepository? authRepository,
  }) async {
    if (explicitHeaders != null) {
      return explicitHeaders;
    }
    String? token;
    try {
      token = await authRepository?.getValidToken(
        refreshBefore: const Duration(minutes: 10),
      );
    } catch (_) {
      try {
        token = await authRepository?.getToken();
      } catch (_) {
        token = null;
      }
    }
    if (token == null || token.isEmpty) {
      return const <String, String>{};
    }
    return <String, String>{'Authorization': 'Bearer $token'};
  }

  Future<Uint8List> _fetchWithAuthRetry(
    String url,
    Map<String, String> headers,
    AuthRepository? authRepository,
  ) async {
    Future<Uint8List> load(Map<String, String> reqHeaders) {
      final override = widget.byteLoaderOverride;
      if (override != null) {
        return override(url, reqHeaders);
      }
      return _fetchBytes(url, reqHeaders);
    }

    try {
      return await load(headers);
    } catch (error) {
      if (!headers.containsKey('Authorization')) {
        rethrow;
      }
      final message = error.toString();
      if (!message.contains('401') && !message.contains('403')) {
        rethrow;
      }
      final token = await authRepository?.getValidToken(
        refreshBefore: const Duration(minutes: 10),
      );
      if (token == null || token.isEmpty) {
        rethrow;
      }
      return load({'Authorization': 'Bearer $token'});
    }
  }

  static String _cacheKey(String url, Map<String, String> headers) {
    final auth = headers['Authorization'] ?? '';
    return '$url\n$auth';
  }

  static String _urlWithAccessToken(String url, Map<String, String> headers) {
    final auth = headers['Authorization'] ?? '';
    final token = auth.startsWith('Bearer ') ? auth.substring(7).trim() : '';
    if (token.isEmpty) {
      return url;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return url;
    }
    final query = Map<String, String>.from(uri.queryParameters);
    query['accessToken'] = token;
    return uri.replace(queryParameters: query).toString();
  }

  static Future<Uint8List> _fetchBytes(
    String url,
    Map<String, String> headers,
  ) async {
    if (web_bridge.isElectron()) {
      try {
        return await web_bridge.fetchElectronBytes(url: url, headers: headers);
      } catch (error) {
        debugPrint('Electron image fetch failed: $url -> $error');
        rethrow;
      }
    }
    final response = await _dio.get<Object>(
      url,
      options: Options(
        headers: headers,
        responseType: ResponseType.bytes,
        followRedirects: true,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
    );
    final data = response.data;
    if (data is Uint8List) {
      return data;
    }
    if (data is List<int>) {
      return Uint8List.fromList(data);
    }
    throw StateError('Invalid image response.');
  }

  static void _remember(String key, Uint8List bytes) {
    final previous = _memoryCache.remove(key);
    if (previous != null) {
      _cacheBytes -= previous.lengthInBytes;
    }
    _memoryCache[key] = bytes;
    _cacheBytes += bytes.lengthInBytes;
    while (_memoryCache.length > _maxEntries || _cacheBytes > _maxCacheBytes) {
      final oldestKey = _memoryCache.keys.first;
      final removed = _memoryCache.remove(oldestKey);
      if (removed != null) {
        _cacheBytes -= removed.lengthInBytes;
      }
    }
  }

  void _handleFallbackLoadError(String failedUrl, {bool isNative = false}) {
    _hasRenderedImage = false;
    _networkFallbackFailed = true;
    unawaited(
      (isNative
              ? CachedNetworkImageProvider(failedUrl).evict()
              : NetworkImage(failedUrl).evict())
          .catchError((_) => false),
    );
    if (_hasSeenReconnectSignal &&
        _reconnectRetryCount < _maxPostReconnectRetries) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduleFollowUpRetryIfNeeded();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final placeholder =
        widget.placeholder ??
        SizedBox(width: widget.width, height: widget.height);
    final errorWidget =
        widget.errorWidget ??
        SizedBox(width: widget.width, height: widget.height);

    if (_usesMemoryOrWebFallback) {
      if (_webImageUrl != null) {
        final activeWebUrl = _webImageUrl!;
        final image = Image.network(
          activeWebUrl,
          key: ValueKey<String>('web_$_activeKey#$_reloadNonce'),
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          gaplessPlayback: false,
          filterQuality: FilterQuality.medium,
          cacheWidth: _cacheExtent(context, widget.width),
          cacheHeight: _cacheExtent(context, widget.height),
          frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) {
              _hasRenderedImage = true;
              _networkFallbackFailed = false;
              _reconnectRetryCount = 0;
              return child;
            }
            return placeholder;
          },
          errorBuilder: (_, error, __) {
            debugPrint(
              'Image.network decode failed: ${_redactUrlTokenForLog(activeWebUrl)} -> $error',
            );
            _handleFallbackLoadError(activeWebUrl);
            return errorWidget;
          },
        );

        if (!widget.clipOval) {
          return image;
        }
        return ClipOval(child: image);
      }

      if (_bytes == null) {
        return _error == null ? placeholder : errorWidget;
      }

      final image = Image.memory(
        _bytes!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        gaplessPlayback: false,
        filterQuality: FilterQuality.medium,
        cacheWidth: _cacheExtent(context, widget.width),
        cacheHeight: _cacheExtent(context, widget.height),
        errorBuilder: (_, error, __) {
          debugPrint(
            'Image.memory decode failed (${_bytes?.length ?? 0} bytes): $error',
          );
          _hasRenderedImage = false;
          _networkFallbackFailed = true;
          return errorWidget;
        },
      );

      if (!widget.clipOval) {
        return image;
      }
      return ClipOval(child: image);
    }

    // Native Platform: Use CachedNetworkImage
    if (_resolvedHeaders == null) {
      return _error == null ? placeholder : errorWidget;
    }

    final resolvedUrl = resolveApiUrl(widget.imageUrl);
    final image = CachedNetworkImage(
      key: ValueKey<String>('native_$_activeKey#$_reloadNonce'),
      imageUrl: resolvedUrl,
      httpHeaders: _resolvedHeaders,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      memCacheWidth: _cacheExtent(context, widget.width),
      memCacheHeight: _cacheExtent(context, widget.height),
      imageBuilder: (_, imageProvider) {
        _hasRenderedImage = true;
        _networkFallbackFailed = false;
        _reconnectRetryCount = 0;
        return Image(
          image: imageProvider,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          filterQuality: FilterQuality.medium,
        );
      },
      placeholder: (_, __) => placeholder,
      errorWidget: (_, __, ___) {
        _handleFallbackLoadError(resolvedUrl, isNative: true);
        return errorWidget;
      },
    );

    if (!widget.clipOval) {
      return image;
    }
    return ClipOval(child: image);
  }

  int? _cacheExtent(BuildContext context, double? logicalSize) {
    if (logicalSize == null || logicalSize <= 0) {
      return null;
    }
    final ratio = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 2.0);
    return (logicalSize * ratio).round();
  }
}
