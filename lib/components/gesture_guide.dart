import 'dart:math' as math;
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../cornhole_game.dart';

class TrailPoint {
  final Vector2 position;
  final double timestamp;

  TrailPoint({required this.position, required this.timestamp});
}

// ─────────────────────────────────────────────────────────────────────────────
// GestureGuideComponent — Kenney gesture arrows & swipe drag trails
// ─────────────────────────────────────────────────────────────────────────────
class GestureGuideComponent extends Component with HasGameReference<CornholeGame> {
  final List<TrailPoint> _trailPoints = [];
  Vector2? _dragStart;
  Vector2? _dragCurrent;
  double _dragStartTime = 0.0;
  double _dragLastTime = 0.0;
  bool _isDragging = false;
  double _idleTime = 0.0;

  void onPanStart(Vector2 position, [double? timestamp]) {
    final now = timestamp ?? (DateTime.now().millisecondsSinceEpoch / 1000.0);
    _isDragging = true;
    _dragStart = position.clone();
    _dragCurrent = position.clone();
    _dragStartTime = now;
    _dragLastTime = now;
    _trailPoints.clear();
    _addTrailPoint(position);
  }

  void onPanUpdate(Vector2 position, [double? timestamp]) {
    final now = timestamp ?? (DateTime.now().millisecondsSinceEpoch / 1000.0);
    _dragCurrent = position.clone();
    _dragLastTime = now;
    _addTrailPoint(position);
  }

  void onPanEnd() {
    _isDragging = false;
    _dragStart = null;
    _dragCurrent = null;
  }

  void onPanCancel() {
    _isDragging = false;
    _dragStart = null;
    _dragCurrent = null;
    _trailPoints.clear();
  }

  void _addTrailPoint(Vector2 position) {
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    _trailPoints.add(TrailPoint(position: position.clone(), timestamp: now));
  }

  @override
  void update(double dt) {
    super.update(dt);
    _idleTime += dt;

    // Prune stale trail points older than 0.35s
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    _trailPoints.removeWhere((p) => now - p.timestamp > 0.35);
  }

  @override
  void render(Canvas canvas) {
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;

    // 1. Swipe Drag Trails (fading glow ribbon connecting touch points)
    if (_trailPoints.length >= 2) {
      for (int i = 0; i < _trailPoints.length - 1; i++) {
        final p1 = _trailPoints[i];
        final p2 = _trailPoints[i + 1];
        final age = (now - p1.timestamp).clamp(0.0, 0.35);
        final opacity = (1.0 - (age / 0.35)).clamp(0.0, 1.0);
        final strokeWidth = (opacity * 10.0).clamp(2.0, 10.0);

        final trailPaint = Paint()
          ..color = const Color(0xFF00E5FF).withValues(alpha: opacity * 0.8)
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;

        canvas.drawLine(
          Offset(p1.position.x, p1.position.y),
          Offset(p2.position.x, p2.position.y),
          trailPaint,
        );
      }
    }

    // 2. Active Swipe Trajectory Arrow (predicts true launch angle and power)
    if (_isDragging && _dragStart != null && _dragCurrent != null) {
      final elapsed = (_dragLastTime - _dragStartTime).clamp(0.016, 1.0);
      final dragVector = _dragCurrent! - _dragStart!;
      final swipeVelocity = dragVector / elapsed;

      // The throw follows the forward flick toward the board (swipeVelocity.y < 0)
      final upwardSpeed =
          (swipeVelocity.y < 0 ? -swipeVelocity.y : 0.0).clamp(0.0, 2500.0);
      final effectiveSpeed =
          upwardSpeed < 200.0 ? 200.0 : upwardSpeed;

      final throwVector = Vector2(
        swipeVelocity.x * 0.35,
        -effectiveSpeed * 0.5,
      );

      final origin = game.bag.position;
      final dir = throwVector.normalized();
      final powerT = (effectiveSpeed / 2000.0).clamp(0.0, 1.0);
      final arrowLength = 50.0 + (powerT * 180.0);

      Color arrowColor;
      if (powerT < 0.4) {
        arrowColor = const Color(0xFF00E676); // Green (gentle)
      } else if (powerT < 0.75) {
        arrowColor = const Color(0xFFFFD600); // Yellow (medium)
      } else {
        arrowColor = const Color(0xFFFF1744); // Red (high power)
      }

      final target = origin + (dir * arrowLength);
      _drawKenneyArrow(canvas, origin, target, arrowColor, arrowWidth: 8.0 + powerT * 6.0);
    }

    // 3. Idle Prompt Gesture Arrow (Pulsing prompt: "SWIPE UP TO PITCH")
    if (!_isDragging && !game.bag.isFlying && !game.gameState.isRoundComplete) {
      final bagPos = game.bag.position;
      final bounce = math.sin(_idleTime * 4.0) * 12.0;
      final promptStart = Vector2(bagPos.x, bagPos.y - 45.0 + bounce);
      final promptEnd = Vector2(bagPos.x, bagPos.y - 95.0 + bounce);

      _drawKenneyArrow(
        canvas,
        promptStart,
        promptEnd,
        const Color(0xFFFFB300),
        arrowWidth: 6.0,
      );

      // Label text
      final textSpan = TextSpan(
        text: '▲ SWIPE TO PITCH ▲',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.85 + (bounce / 60.0)),
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
          shadows: [
            Shadow(color: Colors.black.withValues(alpha: 0.8), blurRadius: 4),
          ],
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(bagPos.x - (textPainter.width / 2), promptStart.y + 12),
      );
    }
  }

  void _drawKenneyArrow(
    Canvas canvas,
    Vector2 start,
    Vector2 end,
    Color color, {
    double arrowWidth = 6.0,
  }) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = arrowWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Stem
    canvas.drawLine(Offset(start.x, start.y), Offset(end.x, end.y), paint);

    // Chevron head
    final dir = (end - start).normalized();
    final normal = Vector2(-dir.y, dir.x);
    final headSize = arrowWidth * 2.8;

    final headLeft = end - (dir * headSize) + (normal * headSize * 0.7);
    final headRight = end - (dir * headSize) - (normal * headSize * 0.7);

    final headPath = Path()
      ..moveTo(end.x, end.y)
      ..lineTo(headLeft.x, headLeft.y)
      ..lineTo(headRight.x, headRight.y)
      ..close();

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawPath(headPath, fillPaint);
  }
}
