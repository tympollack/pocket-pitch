import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Canonical `@digitalcanopy/assets` R2 CDN & Flame sprite adapter
/// for Pocket Pitch (`app_scope: 'pocket-pitch'`).
class PitchSpriteBounds {
  final double x;
  final double y;
  final double w;
  final double h;

  const PitchSpriteBounds({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });
}

class PitchAnchorPoint {
  final double ax;
  final double ay;

  const PitchAnchorPoint({required this.ax, required this.ay});
}

class PitchFlameSpriteData {
  final List<double> srcPosition;
  final List<double> srcSize;
  final List<double> anchor;

  const PitchFlameSpriteData({
    required this.srcPosition,
    required this.srcSize,
    required this.anchor,
  });
}

class PitchCatalogAsset {
  final String appScope;
  final String category;
  final String assetKey;
  final String cdnUrl;
  final Map<String, dynamic> metadata;

  const PitchCatalogAsset({
    required this.appScope,
    required this.category,
    required this.assetKey,
    required this.cdnUrl,
    this.metadata = const {},
  });
}

class PitchAssetOverride {
  final String url;
  final PitchSpriteBounds? frame;
  final PitchAnchorPoint? anchor;
  final Map<String, dynamic> metadata;

  const PitchAssetOverride({
    required this.url,
    this.frame,
    this.anchor,
    this.metadata = const {},
  });
}

class AssetRegistryService {
  AssetRegistryService._internal();

  static final AssetRegistryService instance = AssetRegistryService._internal();

  factory AssetRegistryService.create() => AssetRegistryService._internal();

  static const String cdnBaseUrl = 'https://cdn.sunshade.icu/assets/kenney';
  static const String appScope = 'pocket-pitch';

  /// Canonical UI sprite frames aligned with `@digitalcanopy/assets` `uiSpritesAtlas`.
  static const Map<String, PitchSpriteBounds> uiAtlasFrames = {
    'button-default': PitchSpriteBounds(x: 0, y: 0, w: 128, h: 128),
    'panel-wooden': PitchSpriteBounds(x: 1024, y: 0, w: 128, h: 128),
    'icon-arrow-up': PitchSpriteBounds(x: 1536, y: 0, w: 128, h: 128),
    'icon-arrow-down': PitchSpriteBounds(x: 1664, y: 0, w: 128, h: 128),
    'icon-star': PitchSpriteBounds(x: 384, y: 128, w: 128, h: 128),
    'bar-progress-bg': PitchSpriteBounds(x: 768, y: 128, w: 128, h: 128),
    'bar-progress-fill': PitchSpriteBounds(x: 896, y: 128, w: 128, h: 128),
  };

  /// Seed catalog entries aligned with `@digitalcanopy/assets` taxonomy.
  static const List<PitchCatalogAsset> seedCatalog = [
    PitchCatalogAsset(
      appScope: 'pocket-pitch',
      category: 'cornhole_board',
      assetKey: 'pitch-moon-board',
      cdnUrl: '$cdnBaseUrl/pocket-pitch/moon/board.png',
      metadata: {'format': 'png', 'width': 230, 'height': 70, 'license': 'CC0-Kenney'},
    ),
    PitchCatalogAsset(
      appScope: 'pocket-pitch',
      category: 'cornhole_bag',
      assetKey: 'pitch-moon-bag',
      cdnUrl: '$cdnBaseUrl/pocket-pitch/moon/bag.png',
      metadata: {'format': 'png', 'width': 64, 'height': 64, 'license': 'CC0-Kenney'},
    ),
    PitchCatalogAsset(
      appScope: 'pocket-pitch',
      category: 'cornhole_background',
      assetKey: 'pitch-moon-background',
      cdnUrl: '$cdnBaseUrl/pocket-pitch/moon/background.png',
      metadata: {'format': 'png', 'license': 'CC0-Kenney'},
    ),
    PitchCatalogAsset(
      appScope: 'pocket-pitch',
      category: 'cornhole_board',
      assetKey: 'pitch-boat-board',
      cdnUrl: '$cdnBaseUrl/pocket-pitch/boat/board.png',
      metadata: {'format': 'png', 'width': 230, 'height': 70, 'license': 'CC0-Kenney'},
    ),
    PitchCatalogAsset(
      appScope: 'pocket-pitch',
      category: 'cornhole_bag',
      assetKey: 'pitch-boat-bag',
      cdnUrl: '$cdnBaseUrl/pocket-pitch/boat/bag.png',
      metadata: {'format': 'png', 'width': 64, 'height': 64, 'license': 'CC0-Kenney'},
    ),
    PitchCatalogAsset(
      appScope: 'pocket-pitch',
      category: 'cornhole_background',
      assetKey: 'pitch-boat-background',
      cdnUrl: '$cdnBaseUrl/pocket-pitch/boat/background.png',
      metadata: {'format': 'png', 'license': 'CC0-Kenney'},
    ),
    PitchCatalogAsset(
      appScope: 'all',
      category: 'particle_fx',
      assetKey: 'fx-particle-starburst',
      cdnUrl: '$cdnBaseUrl/particles/starburst.png',
      metadata: {'format': 'png', 'width': 64, 'height': 64, 'license': 'CC0-Kenney'},
    ),
    PitchCatalogAsset(
      appScope: 'all',
      category: 'particle_fx',
      assetKey: 'fx-particle-dust-puff',
      cdnUrl: '$cdnBaseUrl/particles/dust_puff.png',
      metadata: {'format': 'png', 'width': 64, 'height': 64, 'license': 'CC0-Kenney'},
    ),
    PitchCatalogAsset(
      appScope: 'all',
      category: 'impact_audio',
      assetKey: 'audio-impact-wood-thud',
      cdnUrl: '$cdnBaseUrl/audio/impacts/wood_thud.ogg',
      metadata: {'format': 'ogg', 'duration_ms': 140, 'license': 'CC0-Kenney'},
    ),
  ];

  final Map<String, PitchAssetOverride> _overrides = {};
  final Map<String, String> _packOverrides = {};
  final ValueNotifier<int> swapRevision = ValueNotifier<int>(0);
  bool _hydrated = false;

  bool get isHydrated => _hydrated;

  void reset() {
    _overrides.clear();
    _packOverrides.clear();
    _hydrated = false;
    swapRevision.value++;
  }

  void registerOverride(String key, PitchAssetOverride override) {
    _overrides[key.trim()] = override;
    swapRevision.value++;
  }

  void registerPackOverride(String pack, String cdnBase) {
    final cleanPack = pack.replaceAll(RegExp(r'^/+|/+$'), '').toLowerCase();
    _packOverrides[cleanPack] = cdnBase.replaceAll(RegExp(r'/+$'), '');
    swapRevision.value++;
  }

  bool hasOverride(String key) => _overrides.containsKey(key.trim());

  void loadCatalog(List<PitchCatalogAsset> assets, {String? scope}) {
    final filtered = scope == null
        ? assets
        : assets.where((a) => a.appScope == scope || a.appScope == 'all');
    for (final asset in filtered) {
      final cleanKey = asset.assetKey.trim();
      if (cleanKey.isEmpty) continue;
      _overrides[cleanKey] = PitchAssetOverride(
        url: asset.cdnUrl,
        metadata: asset.metadata,
      );
    }
    _hydrated = true;
    swapRevision.value++;
  }

  List<PitchCatalogAsset> hydrateSeedCatalog({bool force = false}) {
    if (!_hydrated || force) {
      loadCatalog(seedCatalog, scope: appScope);
    }
    return seedCatalog;
  }

  String resolveUrl(String key, {String fallbackUrl = ''}) {
    return _overrides[key.trim()]?.url ?? fallbackUrl;
  }

  String resolveAssetUrl(String pack, String assetPath, {String ext = 'png'}) {
    final cleanPack = pack.replaceAll(RegExp(r'^/+|/+$'), '').toLowerCase();
    final cleanPath = assetPath.replaceAll(RegExp(r'^/+|/+$'), '');
    final bareKey = cleanPath.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');

    if (_overrides.containsKey(bareKey)) {
      return _overrides[bareKey]!.url;
    }
    if (_overrides.containsKey(cleanPath)) {
      return _overrides[cleanPath]!.url;
    }

    final cleanExt = ext.startsWith('.') ? ext.substring(1) : ext;
    final hasExt = RegExp(r'\.[a-zA-Z0-9]+$').hasMatch(cleanPath);
    final finalPath = hasExt ? cleanPath : '$cleanPath.$cleanExt';

    final packBase = _packOverrides[cleanPack];
    if (packBase != null) {
      return '$packBase/$finalPath';
    }
    return '$cdnBaseUrl/$cleanPack/$finalPath';
  }

  String resolveThemePartUrl(String themeName, String partName) {
    final cleanTheme = themeName.trim().toLowerCase();
    final cleanPart = partName.trim().toLowerCase();
    final catalogKey = 'pitch-$cleanTheme-$cleanPart';
    if (_overrides.containsKey(catalogKey)) {
      return _overrides[catalogKey]!.url;
    }
    return resolveAssetUrl('pocket-pitch', '$cleanTheme/$cleanPart');
  }

  PitchFlameSpriteData? resolveFlameUiSpriteData(String frameKey) {
    final cleanKey = frameKey.trim();
    final override = _overrides[cleanKey];
    final frame = override?.frame ?? uiAtlasFrames[cleanKey];
    if (frame == null) return null;

    final anchor = override?.anchor ?? const PitchAnchorPoint(ax: 0.5, ay: 0.5);
    return PitchFlameSpriteData(
      srcPosition: [frame.x, frame.y],
      srcSize: [frame.w, frame.h],
      anchor: [anchor.ax, anchor.ay],
    );
  }

  Future<ui.Image?> loadCdnImage(
    String url, {
    Future<ByteData> Function(String url)? byteLoader,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      final data = byteLoader != null
          ? await byteLoader(url).timeout(timeout)
          : await NetworkAssetBundle(Uri.parse(url)).load(url).timeout(timeout);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      if (bytes.isEmpty) return null;

      final completer = Completer<ui.Image>();
      ui.decodeImageFromList(bytes, (img) {
        if (!completer.isCompleted) completer.complete(img);
      });
      return await completer.future.timeout(timeout);
    } catch (_) {
      return null;
    }
  }
}
