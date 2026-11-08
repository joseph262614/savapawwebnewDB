import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/platform_picker.dart';

/// A high-performance, memoized image renderer for web and desktop.
///
/// Performance benefits:
/// 1. In-memory LRU cache: Base64 string cleaning and decoding runs exactly once per image,
///    eliminating UI-thread stutters, layout thrashing, and GC churn during list scrolling.
/// 2. Bounded GPU texture decoding: Uses [cacheWidth] / [cacheHeight] to prevent huge VRAM allocation.
/// 3. RepaintBoundary isolation: Keeps image repaints from dirtying the parent layout tree.
/// 4. Graceful Impeccable placeholders & error fallbacks with zero layout shift.
class AppOptimizedImage extends StatelessWidget {
  final String? imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final int? cacheHeight;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;

  const AppOptimizedImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.cacheWidth = 800,
    this.cacheHeight,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
  });

  // LRU in-memory cache for decoded bytes (max 150 entries to conserve memory)
  static final _LruCache<int, Uint8List> _decodedBytesCache = _LruCache(150);

  static Uint8List? _getOrDecode(String raw) {
    final key = raw.hashCode;
    final cached = _decodedBytesCache.get(key);
    if (cached != null) return cached;

    try {
      final commaIdx = raw.indexOf(',');
      final base64Str = commaIdx != -1 ? raw.substring(commaIdx + 1) : raw;
      String clean = base64Str.replaceAll(RegExp(r'\s+'), '').trim();
      // Replace URL-safe base64 characters
      clean = clean.replaceAll('-', '+').replaceAll('_', '/');
      // Normalize base64 padding
      final remainder = clean.length % 4;
      if (remainder == 2) {
        clean += '==';
      } else if (remainder == 3) {
        clean += '=';
      } else if (remainder == 1) {
        clean = clean.substring(0, clean.length - 1);
      }
      final bytes = base64Decode(clean);
      _decodedBytesCache.put(key, bytes);
      return bytes;
    } catch (e) {
      debugPrint("AppOptimizedImage decode error: $e");
      return null;
    }
  }

  static String _normalizeImageUrl(String raw) {
    final trimmed = raw.trim();
    // Convert Google Drive sharing links to direct image links
    final driveMatch = RegExp(r'drive\.google\.com\/file\/d\/([a-zA-Z0-9_-]+)').firstMatch(trimmed);
    if (driveMatch != null) {
      return 'https://lh3.googleusercontent.com/d/${driveMatch.group(1)}';
    }
    final driveIdMatch = RegExp(r'drive\.google\.com\/(?:open\?id=|uc\?id=)([a-zA-Z0-9_-]+)').firstMatch(trimmed);
    if (driveIdMatch != null) {
      return 'https://lh3.googleusercontent.com/d/${driveIdMatch.group(1)}';
    }
    if (trimmed.contains('dropbox.com') && trimmed.endsWith('?dl=0')) {
      return '${trimmed.substring(0, trimmed.length - 5)}?raw=1';
    }
    return trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final rawUrl = imageUrl;
    if (rawUrl == null || rawUrl.trim().isEmpty) {
      return _buildFallback(context);
    }
    final url = _normalizeImageUrl(rawUrl);

    Widget content;
    final isBase64 = url.startsWith('data:') ||
        (!url.startsWith('http://') && !url.startsWith('https://') && !url.startsWith('assets/'));

    if (isBase64) {
      final bytes = _getOrDecode(url);
      if (bytes == null) {
        return _buildFallback(context);
      }
      content = Image.memory(
        bytes,
        fit: fit,
        width: width,
        height: height,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        errorBuilder: (_, __, ___) => _buildFallback(context),
      );
    } else if (url.startsWith('assets/')) {
      content = Image.asset(
        url,
        fit: fit,
        width: width,
        height: height,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        errorBuilder: (_, __, ___) => _buildFallback(context),
      );
    } else {
      content = Image.network(
        url,
        fit: fit,
        width: width,
        height: height,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return placeholder ?? _buildPlaceholder(context);
        },
        errorBuilder: (_, __, ___) {
          if (kIsWeb) {
            return buildWebCorsFreeImage(
              url: url,
              fit: fit,
              width: width,
              height: height,
              fallback: _buildFallback(context),
            );
          }
          return _buildFallback(context);
        },
      );
    }

    if (borderRadius != null) {
      content = ClipRRect(
        borderRadius: borderRadius!,
        child: content,
      );
    }

    return RepaintBoundary(child: content);
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: borderRadius,
      ),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.primaryOrange.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }

  Widget _buildFallback(BuildContext context) {
    if (errorWidget != null) return errorWidget!;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: borderRadius,
      ),
      child: Center(
        child: Icon(
          Icons.pets_outlined,
          size: (width != null && width! < 40) ? 18 : 26,
          color: Colors.grey.shade400,
        ),
      ),
    );
  }
}

class _LruCache<K, V> {
  final int capacity;
  final LinkedHashMap<K, V> _map = LinkedHashMap<K, V>();

  _LruCache(this.capacity);

  V? get(K key) {
    final value = _map.remove(key);
    if (value != null) {
      _map[key] = value;
    }
    return value;
  }

  void put(K key, V value) {
    if (_map.containsKey(key)) {
      _map.remove(key);
    } else if (_map.length >= capacity) {
      _map.remove(_map.keys.first);
    }
    _map[key] = value;
  }
}

