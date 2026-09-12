import 'dart:async';
import 'dart:collection';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/media_url_resolver.dart';
import '../../features/auth/data/auth_repository.dart';
import '../providers/providers.dart';
import '../services/web_platform_bridge.dart' as web_bridge;

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
  });

  final String imageUrl;
  final Map<String, String>? httpHeaders;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final bool clipOval;

  @override
  ConsumerState<AuthenticatedNetworkImage> createState() =>
      _AuthenticatedNetworkImageState();
}

class _AuthenticatedNetworkImageState
    extends ConsumerState<AuthenticatedNetworkImage> {
  static const int _maxEntries = 300;
  static const int _maxCacheBytes = 80 * 1024 * 1024;
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

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _revokeElectronObjectUrl();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AuthenticatedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.httpHeaders.toString() != widget.httpHeaders.toString()) {
      _activeKey = '';
      _resolvedHeaders = null;
      _bytes = null;
      _webImageUrl = null;
      _revokeElectronObjectUrl();
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final imageUrl = widget.imageUrl.trim();
    final explicitHeaders = widget.httpHeaders;
    final authRepository = explicitHeaders == null
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
          _error = StateError('Empty image URL.');
        });
      }
      return;
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

    if (keyChanged) {
      _revokeElectronObjectUrl();
      setState(() {
        _webImageUrl = null;
        _electronObjectUrl = null;
        _bytes = cachedBytes;
        _resolvedHeaders = null;
        _error = null;
      });
      if (cachedBytes != null && kIsWeb) {
        return;
      }
    }

    if (kIsWeb) {
      if (web_bridge.isElectron()) {
        if (mounted &&
            generation == _loadGeneration &&
            _electronObjectUrl == null) {
          setState(() => _error = null);
        }

        try {
          final objectUrl = await web_bridge.fetchElectronObjectUrl(
            url: url,
            headers: headers,
          );
          if (mounted &&
              generation == _loadGeneration &&
              _activeKey == cacheKey) {
            _revokeElectronObjectUrl();
            setState(() {
              _electronObjectUrl = objectUrl;
              _webImageUrl = objectUrl;
              _bytes = null;
              _error = null;
              _resolvedHeaders = null;
            });
          } else {
            web_bridge.revokeObjectUrl(objectUrl);
          }
        } catch (error) {
          debugPrint('Electron object-url image fetch failed: $url -> $error');
          try {
            final bytes = await _inFlight.putIfAbsent(
              cacheKey,
              () => _fetchWithAuthRetry(
                url,
                headers,
                authRepository,
              ).whenComplete(() => _inFlight.remove(cacheKey)),
            );
            _remember(cacheKey, bytes);
            if (mounted &&
                generation == _loadGeneration &&
                _activeKey == cacheKey) {
              _revokeElectronObjectUrl();
              setState(() {
                _bytes = bytes;
                _error = null;
                _webImageUrl = null;
                _resolvedHeaders = null;
              });
            }
          } catch (fallbackError) {
            debugPrint(
              'Electron memory image fetch failed: $url -> $fallbackError',
            );
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
              });
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
    final token = await authRepository?.getValidToken(
      refreshBefore: const Duration(minutes: 10),
    );
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
    try {
      return await _fetchBytes(url, headers);
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
      return _fetchBytes(url, {'Authorization': 'Bearer $token'});
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

  @override
  Widget build(BuildContext context) {
    final placeholder =
        widget.placeholder ??
        SizedBox(width: widget.width, height: widget.height);
    final errorWidget =
        widget.errorWidget ??
        SizedBox(width: widget.width, height: widget.height);

    if (kIsWeb) {
      if (_webImageUrl != null) {
        final image = Image.network(
          _webImageUrl!,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          gaplessPlayback: false,
          filterQuality: FilterQuality.medium,
          cacheWidth: _cacheExtent(context, widget.width),
          cacheHeight: _cacheExtent(context, widget.height),
          errorBuilder: (_, error, __) {
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
      imageUrl: resolvedUrl,
      httpHeaders: _resolvedHeaders,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      placeholder: (_, __) => placeholder,
      errorWidget: (_, __, ___) => errorWidget,
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
