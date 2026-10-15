import 'dart:math' as math;
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PitchParticleEmitter
//
// High-performance particle engine with zero-allocation pooling for Pocket Pitch.
// Features:
//   1. Starburst celebration bursts on cornhole hole sinks (radiant stars/sparks)
//   2. Turf puffs on ground impacts (fluffy grass & dust smoke clouds)
//
// Invariants:
//   • Fixed pre-allocated pool prevents GC churn & memory leaks
//   • Immediate auto-disposal upon particle expiration
// ─────────────────────────────────────────────────────────────────────────────

enum PitchParticleType { starburst, turfPuff }

class PitchParticle {
  Vector2 position = Vector2.zero();
  Vector2 velocity = Vector2.zero();
  double life = 0.0;
  double maxLife = 0.45;
  double startSize = 4.0;
  double endSize = 12.0;
  Color startColor = Colors.white;
  Color endColor = Colors.transparent;
  bool active = false;
  PitchParticleType type = PitchParticleType.starburst;

  void reset() {
    active = false;
    life = 0.0;
    position.setZero();
    velocity.setZero();
  }
}

class PitchParticleEmitter extends Component {
  final int capacity;
  late final List<PitchParticle> _pool;
  final math.Random _random = math.Random();

  final Paint _fillPaint = Paint()..style = PaintingStyle.fill;
  final Paint _strokePaint = Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;

  PitchParticleEmitter({this.capacity = 120}) {
    _pool = List<PitchParticle>.generate(capacity, (_) => PitchParticle());
  }

  int get activeCount => _pool.where((p) => p.active).length;
  int get poolSize => _pool.length;

  void clear() {
    for (final p in _pool) {
      p.reset();
    }
  }

  PitchParticle? _acquire() {
    for (var i = 0; i < capacity; i++) {
      if (!_pool[i].active) return _pool[i];
    }
    // Recycle oldest if pool is fully saturated
    PitchParticle? oldest;
    double maxRatio = -1;
    for (var i = 0; i < capacity; i++) {
      final ratio = _pool[i].life / _pool[i].maxLife;
      if (ratio > maxRatio) {
        maxRatio = ratio;
        oldest = _pool[i];
      }
    }
    oldest?.reset();
    return oldest;
  }

  /// Emit vibrant celebration starburst on hole sinks
  void emitStarburst(Vector2 holeCenter, {int count = 18}) {
    const starburstColors = [
      Color(0xFFFFD700), // Gold
      Color(0xFFFFA000), // Amber
      Color(0xFF00E5FF), // Cyan spark
      Color(0xFFFFFFFF), // Pure white
      Color(0xFFFF4081), // Neon pink
    ];

    for (var i = 0; i < count; i++) {
      final p = _acquire();
      if (p == null) break;

      p.position.setFrom(holeCenter);

      // Radial 360-degree starburst distribution
      final angle = (i / count) * 2 * math.pi + (_random.nextDouble() - 0.5) * 0.4;
      final speed = 120.0 + _random.nextDouble() * 220.0;
      p.velocity.setValues(math.cos(angle) * speed, math.sin(angle) * speed);

      p.life = 0.0;
      p.maxLife = 0.38 + _random.nextDouble() * 0.22;
      p.startSize = 3.5 + _random.nextDouble() * 3.0;
      p.endSize = 0.5;

      final col = starburstColors[_random.nextInt(starburstColors.length)];
      p.startColor = col;
      p.endColor = col.withValues(alpha: 0.0);
      p.type = PitchParticleType.starburst;
      p.active = true;
    }
  }

  /// Emit turf puffs on ground impacts (beanbag hitting lawn/ground outside board)
  void emitTurfPuff(Vector2 impactPosition, {int count = 10}) {
    const turfColors = [
      Color(0xFF4CAF50), // Lawn green
      Color(0xFF81C784), // Light turf
      Color(0xFF66BB6A), // Emerald grass
      Color(0xFF8D6E63), // Turf soil/dust
      Color(0xFFA1887F), // Light earth
    ];

    for (var i = 0; i < count; i++) {
      final p = _acquire();
      if (p == null) break;

      p.position.setFrom(impactPosition);

      // Billow outward and slightly upward
      final angle = -math.pi / 2 + (_random.nextDouble() - 0.5) * 2.2;
      final speed = 40.0 + _random.nextDouble() * 90.0;
      p.velocity.setValues(math.cos(angle) * speed, math.sin(angle) * speed);

      p.life = 0.0;
      p.maxLife = 0.32 + _random.nextDouble() * 0.18;
      p.startSize = 4.0 + _random.nextDouble() * 3.0;
      p.endSize = 14.0 + _random.nextDouble() * 8.0; // expand into puffy smoke

      final col = turfColors[_random.nextInt(turfColors.length)];
      p.startColor = col.withValues(alpha: 0.75);
      p.endColor = col.withValues(alpha: 0.0);
      p.type = PitchParticleType.turfPuff;
      p.active = true;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);

    for (var i = 0; i < capacity; i++) {
      final p = _pool[i];
      if (!p.active) continue;

      p.life += dt;
      if (p.life >= p.maxLife) {
        // Automatic disposal upon completion
        p.active = false;
        continue;
      }

      p.position.add(p.velocity * dt);
      if (p.type == PitchParticleType.turfPuff) {
        p.velocity.scale(0.85); // High air friction for smoke puffs
      } else {
        p.velocity.scale(0.93); // Low friction for sparks
      }
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    for (var i = 0; i < capacity; i++) {
      final p = _pool[i];
      if (!p.active) continue;

      final progress = (p.life / p.maxLife).clamp(0.0, 1.0);
      final color = Color.lerp(p.startColor, p.endColor, progress) ?? p.startColor;
      final size = p.startSize + (p.endSize - p.startSize) * progress;

      if (p.type == PitchParticleType.turfPuff) {
        _fillPaint.color = color;
        canvas.drawCircle(Offset(p.position.x, p.position.y), size, _fillPaint);
      } else {
        // Kenney 4-point star / radiant sparkle ray
        _strokePaint
          ..color = color
          ..strokeWidth = size.clamp(1.0, 4.0);

        final tail = p.position - (p.velocity * 0.02);
        canvas.drawLine(
          Offset(p.position.x, p.position.y),
          Offset(tail.x, tail.y),
          _strokePaint,
        );

        _fillPaint.color = color;
        canvas.drawCircle(Offset(p.position.x, p.position.y), size * 0.7, _fillPaint);
      }
    }
  }
}
