import 'dart:ui' show lerpDouble;
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../cornhole_game.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ShadowComponent — Ground contact shadow for the beanbag
// Offsets downward in local space by `altitude` to stay on the ground plane.
// ─────────────────────────────────────────────────────────────────────────────
class ShadowComponent extends PositionComponent {
  double _opacity = 0.45;

  ShadowComponent() : super(anchor: Anchor.center);

  void updateForAltitude(double altitude, double bagRadius) {
    const maxAltitudeForFade = 240.0;
    final t = (altitude / maxAltitudeForFade).clamp(0.0, 1.0);

    _opacity = lerpDouble(0.45, 0.08, t)!;
    final widthScale = lerpDouble(1.0, 0.4, t)!;

    position = Vector2.zero();
    final w = bagRadius * 2 * widthScale;
    size = Vector2(w, w * 0.45);
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()
      ..color = Color.fromRGBO(0, 0, 0, _opacity)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(width / 2, height / 2), width: width, height: height),
      paint,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BagComponent — Parabolic beanbag with Z-axis altitude scaling
// ─────────────────────────────────────────────────────────────────────────────
class BagComponent extends SpriteComponent with HasGameReference<CornholeGame> {
  final double baseRadius;
  final double gravity;
  final double minScale;
  final double maxAltitudeForScale;
  final double lateralDriftSensitivity;

  double radius;

  /// Ground-plane velocity (px/s)
  Vector2 velocity = Vector2.zero();

  /// Simulated height off the ground (px-equivalent Z-axis)
  double altitude = 0.0;
  double _verticalSpeed = 0.0;

  bool isFlying = false;
  bool isSinking = false; // Hole sink animation in progress
  double sinkProgress = 0.0;
  bool _hasLanded = true;

  final Vector2 launchPosition;
  late final ShadowComponent shadow;

  BagComponent({
    required Vector2 startPosition,
    this.baseRadius = 18,
    this.gravity = 900,
    this.minScale = 0.45,
    this.maxAltitudeForScale = 260,
    this.lateralDriftSensitivity = 40,
  })  : launchPosition = startPosition.clone(),
        radius = baseRadius,
        super(
          position: startPosition.clone(),
          anchor: Anchor.center,
          size: Vector2.all(baseRadius * 2),
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    shadow = ShadowComponent()..priority = -1;
    await add(shadow);
  }

  void launch(ThrowData data) {
    position = launchPosition.clone();
    velocity = data.groundVelocity.clone();
    _verticalSpeed = data.launchSpeed;
    altitude = 0.0;
    radius = baseRadius;
    size = Vector2.all(radius * 2);
    isFlying = true;
    isSinking = false;
    sinkProgress = 0.0;
    _hasLanded = false;

    final initialSpeed =
        Vector2(data.groundVelocity.x, data.groundVelocity.y).length +
            data.launchSpeed;
    game.gameState.telemetry.recordThrowSpeed(initialSpeed);
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Hole sink animation (bag drops cleanly through the hole cutout)
    if (isSinking) {
      sinkProgress += dt * 3.5;
      altitude -= 120 * dt;
      radius = baseRadius * (1.0 - sinkProgress.clamp(0.0, 1.0) * 0.7);
      size = Vector2.all(radius * 2);
      if (sinkProgress >= 1.0) {
        isSinking = false;
        isFlying = false;
        _hasLanded = true;
        game.gameState.recordThrow(ThrowResult.hole);
      }
      return;
    }

    if (!isFlying) return;

    // --- Parabolic Altitude Arc: Gravity acts on vertical speed ---
    _verticalSpeed -= gravity * dt;
    altitude += _verticalSpeed * dt;

    // --- Ground-plane travel with lateral gyro drift ---
    final tilt = game.currentTilt;
    final lateralDriftThisFrame = tilt.x * lateralDriftSensitivity * dt;
    velocity.x += lateralDriftThisFrame;
    position += velocity * dt;

    if (dt > 0) {
      game.gameState.telemetry
          .recordLateralDrift((lateralDriftThisFrame / dt).abs());
    }

    // --- Programmatic Dimension Scaling Simulating Z-Axis Height & Depth ---
    // 1. Depth scale: Downrange distance to board (distant objects are smaller)
    final boardY = game.board.position.y;
    final totalDownrange = (launchPosition.y - boardY).abs();
    final currentDistanceToBoard = (position.y - boardY).abs();
    final distanceRatio = (currentDistanceToBoard / totalDownrange).clamp(0.0, 1.2);
    final depthScale = minScale + (1.0 - minScale) * distanceRatio;

    // 2. Altitude scale: Higher projectile expands to simulate 3D arc apex
    final altitudeT = (altitude / maxAltitudeForScale).clamp(0.0, 1.5);
    final altitudeScale = 1.0 + (altitudeT * 0.45);

    // Combined programmatic dimensions
    radius = baseRadius * depthScale * altitudeScale;
    size = Vector2.all(radius * 2);

    shadow.updateForAltitude(altitude.clamp(0.0, double.infinity), radius);

    // Ground touchdown & scoring resolution
    if (!_hasLanded && altitude <= 0.0 && _verticalSpeed <= 0.0) {
      altitude = 0.0;
      velocity = Vector2.zero();
      _hasLanded = true;
      shadow.updateForAltitude(0, radius);

      if (game.board.isFullyInsideHole(position, radius)) {
        isSinking = true;
        sinkProgress = 0.0;
        game.particleEmitter.emitStarburst(game.board.holePosition);
        return;
      }

      isFlying = false;
      _resolveLanding(game.board);
    }
  }

  void _resolveLanding(BoardComponent board) {
    final ThrowResult result;

    if (board.isFullyInsideHole(position, radius)) {
      result = ThrowResult.hole; // In the hole — 3 pts
      game.particleEmitter.emitStarburst(board.holePosition);
    } else if (board.containsPoint(position)) {
      result = ThrowResult.onBoard; // On the board — 1 pt
    } else {
      result = ThrowResult.miss; // Touched ground — 0 pts
      game.particleEmitter.emitTurfPuff(position);
    }

    game.gameState.recordThrow(result);
  }

  @override
  void render(Canvas canvas) {
    if (sprite != null) {
      super.render(canvas);
      return;
    }

    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);

    // Procedural Kenney CC0 Red Fabric Beanbag
    final r = radius;
    final bagPaint = Paint()
      ..color = const Color(0xFFD32F2F) // Rich red canvas fabric
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = const Color(0xFFB71C1C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: r * 2, height: r * 2),
      Radius.circular(r * 0.35),
    );

    canvas.drawRRect(rect, bagPaint);
    canvas.drawRRect(rect, borderPaint);

    // Cross-stitch corner accents (Kenney Tabletop style)
    final stitchPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..strokeWidth = 1.5;

    canvas.drawLine(Offset(-r * 0.5, -r * 0.5), Offset(-r * 0.3, -r * 0.3), stitchPaint);
    canvas.drawLine(Offset(r * 0.5, -r * 0.5), Offset(r * 0.3, -r * 0.3), stitchPaint);
    canvas.drawLine(Offset(-r * 0.5, r * 0.5), Offset(-r * 0.3, r * 0.3), stitchPaint);
    canvas.drawLine(Offset(r * 0.5, r * 0.5), Offset(r * 0.3, r * 0.3), stitchPaint);

    canvas.restore();
  }
}
