import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pitch/components/pitch_particle_emitter.dart';
import 'package:pocket_pitch/cornhole_game.dart';

void main() {
  group('PitchParticleEmitter Tests', () {
    test('initializes with pre-allocated pool and zero active particles', () {
      final emitter = PitchParticleEmitter(capacity: 60);
      expect(emitter.poolSize, equals(60));
      expect(emitter.activeCount, equals(0));
    });

    test('emitStarburst activates starburst particles on hole sink and auto-disposes', () {
      final emitter = PitchParticleEmitter(capacity: 60);
      final holeCenter = Vector2(100, 150);

      emitter.emitStarburst(holeCenter, count: 18);
      expect(emitter.activeCount, equals(18));

      // Update past lifetime
      emitter.update(0.65);
      expect(emitter.activeCount, equals(0));
    });

    test('emitTurfPuff activates turf particles on ground impact and auto-disposes', () {
      final emitter = PitchParticleEmitter(capacity: 60);
      final impactPoint = Vector2(50, 400);

      emitter.emitTurfPuff(impactPoint, count: 10);
      expect(emitter.activeCount, equals(10));

      // Advance physics time
      emitter.update(0.15);
      expect(emitter.activeCount, equals(10));

      // Advance past completion
      emitter.update(0.5);
      expect(emitter.activeCount, equals(0));
    });

    test('recycles oldest particles when pool capacity is exceeded', () {
      const poolCapacity = 12;
      final emitter = PitchParticleEmitter(capacity: poolCapacity);

      emitter.emitStarburst(Vector2.zero(), count: 12);
      expect(emitter.activeCount, equals(12));
      expect(emitter.poolSize, equals(12));

      // Emit more particles than pool size
      emitter.emitTurfPuff(Vector2.zero(), count: 6);
      expect(emitter.poolSize, equals(12));
      expect(emitter.activeCount, equals(12));
    });

    test('clear resets all active particles back to inactive', () {
      final emitter = PitchParticleEmitter(capacity: 30);
      emitter.emitStarburst(Vector2.zero(), count: 10);
      expect(emitter.activeCount, equals(10));

      emitter.clear();
      expect(emitter.activeCount, equals(0));
    });

    test('CornholeGame can startNewRound before onLoad without throwing', () {
      final game = CornholeGame(enableGyroscope: false);
      expect(() => game.startNewRound(), returnsNormally);
      expect(game.particleEmitter.activeCount, equals(0));
    });
  });
}
