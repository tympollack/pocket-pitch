import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pitch/services/asset_registry_service.dart';

void main() {
  group('TASK-PKG-APP-PITCH: @digitalcanopy/assets Registry & CDN Adapter', () {
    test('hydrates pocket-pitch and shared FX/audio seed catalog assets', () {
      final registry = AssetRegistryService.create();
      final assets = registry.hydrateSeedCatalog();

      expect(assets.any((a) => a.assetKey == 'pitch-moon-board'), isTrue);
      expect(assets.any((a) => a.assetKey == 'pitch-boat-bag'), isTrue);
      expect(assets.any((a) => a.assetKey == 'fx-particle-starburst'), isTrue);
      expect(assets.any((a) => a.assetKey == 'audio-impact-wood-thud'), isTrue);

      expect(
        registry.resolveThemePartUrl('moon', 'board'),
        '${AssetRegistryService.cdnBaseUrl}/pocket-pitch/moon/board.png',
      );
      expect(
        registry.resolveThemePartUrl('boat', 'bag'),
        '${AssetRegistryService.cdnBaseUrl}/pocket-pitch/boat/bag.png',
      );
    });

    test('supports pack-level and single-key hot-swapping for themes and guides', () {
      final registry = AssetRegistryService.create();
      registry.hydrateSeedCatalog();
      final revBefore = registry.swapRevision.value;

      registry.registerPackOverride('ui-pack', 'https://custom-ip.sunshade.icu/ui');
      expect(
        registry.resolveAssetUrl('ui-pack', 'icon-arrow-up'),
        'https://custom-ip.sunshade.icu/ui/icon-arrow-up.png',
      );

      registry.registerPackOverride('pocket-pitch', 'https://custom-ip.sunshade.icu/pp');
      expect(
        registry.resolveThemePartUrl('moon', 'bag'),
        'https://custom-ip.sunshade.icu/pp/moon/bag.png',
      );

      registry.registerOverride(
        'pitch-moon-board',
        const PitchAssetOverride(url: 'https://custom-ip.sunshade.icu/moon-board-hd.png'),
      );
      expect(
        registry.resolveThemePartUrl('moon', 'board'),
        'https://custom-ip.sunshade.icu/moon-board-hd.png',
      );
      expect(registry.swapRevision.value, greaterThan(revBefore));
    });

    test('resolves Flame sprite coordinates for trajectory guide arrows', () {
      final registry = AssetRegistryService.create();
      final arrow = registry.resolveFlameUiSpriteData('icon-arrow-up');
      expect(arrow, isNotNull);
      expect(arrow!.srcPosition, [1536.0, 0.0]);
      expect(arrow.srcSize, [128.0, 128.0]);
      expect(arrow.anchor, [0.5, 0.5]);
    });

    test('fails fast returning null on empty or invalid image bytes', () async {
      final registry = AssetRegistryService.create();
      final empty = await registry.loadCdnImage(
        'https://cdn.sunshade.icu/assets/kenney/empty.png',
        byteLoader: (_) async => ByteData(0),
      );
      final corrupt = await registry.loadCdnImage(
        'https://cdn.sunshade.icu/assets/kenney/corrupt.png',
        byteLoader: (_) async => ByteData.sublistView(Uint8List.fromList([9, 8, 7])),
        timeout: const Duration(seconds: 5),
      );
      expect(empty, isNull);
      expect(corrupt, isNull);
    });
  });
}
