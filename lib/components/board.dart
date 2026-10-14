import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BoardComponent — 2.5D Angled Cornhole Board with hole cutout
// Built with Kenney CC0 tabletop board game aesthetic.
// ─────────────────────────────────────────────────────────────────────────────
class BoardComponent extends SpriteComponent {
  final double topWidth;
  final double bottomWidth;
  final double boardHeight;
  final Vector2 holeOffset;
  final double holeRadius;
  final double topSkew;

  BoardComponent({
    required Vector2 position,
    this.topWidth = 90,
    this.bottomWidth = 230,
    this.boardHeight = 70,
    Vector2? holeOffset,
    this.holeRadius = 16,
    this.topSkew = 0,
  })  : holeOffset = holeOffset ?? Vector2(0, -10),
        super(
          position: position,
          anchor: Anchor.center,
          size: Vector2(bottomWidth, boardHeight),
        );

  double get frontEdgeY => position.y + boardHeight / 2;
  double get backEdgeY => position.y - boardHeight / 2;
  Vector2 get holePosition => position + holeOffset;

  /// Hitbox quad in world space: [nearLeft, nearRight, farRight, farLeft]
  List<Vector2> get hitboxCorners {
    final cx = position.x;
    return [
      Vector2(cx - bottomWidth / 2, frontEdgeY), // near-left
      Vector2(cx + bottomWidth / 2, frontEdgeY), // near-right
      Vector2(cx + topWidth / 2 + topSkew, backEdgeY), // far-right
      Vector2(cx - topWidth / 2 + topSkew, backEdgeY), // far-left
    ];
  }

  /// Point-in-quad test for the angled cornhole surface
  @override
  bool containsPoint(Vector2 point) {
    final corners = hitboxCorners;
    var sign = 0;
    for (var i = 0; i < corners.length; i++) {
      final a = corners[i];
      final b = corners[(i + 1) % corners.length];
      final edge = b - a;
      final toPoint = point - a;
      final cross = edge.x * toPoint.y - edge.y * toPoint.x;
      final thisSign = cross > 0 ? 1 : (cross < 0 ? -1 : 0);
      if (thisSign == 0) continue;
      if (sign == 0) {
        sign = thisSign;
      } else if (thisSign != sign) {
        return false;
      }
    }
    return true;
  }

  /// True if a beanbag of given radius is completely inside the hole trigger box
  bool isFullyInsideHole(Vector2 point, double bagRadius) {
    final usableRadius = holeRadius - bagRadius;
    if (usableRadius <= 0) return false;
    return point.distanceTo(holePosition) <= usableRadius;
  }

  /// Overlapping/near hole test (for hole sink animation triggers)
  bool isNearHole(Vector2 point, double threshold) {
    return point.distanceTo(holePosition) <= (holeRadius + threshold);
  }

  @override
  void render(Canvas canvas) {
    if (sprite != null) {
      super.render(canvas);
      return;
    }

    // ── Procedural 2.5D Kenney Wooden Cornhole Board Render ──────────────
    final halfW = bottomWidth / 2;
    final halfTopW = topWidth / 2;
    final halfH = boardHeight / 2;

    // 1. Board Stand / Legs (perspective elevation)
    final legPaint = Paint()..color = const Color(0xFF3E2723);
    final leftLeg = Path()
      ..moveTo(-halfTopW, -halfH)
      ..lineTo(-halfTopW - 12, -halfH - 18)
      ..lineTo(-halfTopW + 2, -halfH - 18)
      ..lineTo(-halfTopW + 8, -halfH)
      ..close();
    final rightLeg = Path()
      ..moveTo(halfTopW - 8, -halfH)
      ..lineTo(halfTopW - 2, -halfH - 18)
      ..lineTo(halfTopW + 12, -halfH - 18)
      ..lineTo(halfTopW, -halfH)
      ..close();
    canvas.drawPath(leftLeg, legPaint);
    canvas.drawPath(rightLeg, legPaint);

    // 2. Board Side Frame Drop-Shadow & Thickness (Bevel)
    final sideBevel = Path()
      ..moveTo(-halfW, halfH)
      ..lineTo(-halfW, halfH + 8)
      ..lineTo(halfW, halfH + 8)
      ..lineTo(halfW, halfH)
      ..close();
    final bevelPaint = Paint()..color = const Color(0xFF5D4037);
    canvas.drawPath(sideBevel, bevelPaint);

    // 3. Angled Wooden Board Face (Kenney Tabletop Warm Birch/Oak Tone)
    final boardPath = Path()
      ..moveTo(-halfW, halfH)
      ..lineTo(halfW, halfH)
      ..lineTo(halfTopW + topSkew, -halfH)
      ..lineTo(-halfTopW + topSkew, -halfH)
      ..close();

    final boardPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, halfH),
        Offset(0, -halfH),
        const [
          Color(0xFFE0A96D), // Warm golden oak (foreground)
          Color(0xFFC78C4E), // Amber birch (depth)
        ],
      );
    canvas.drawPath(boardPath, boardPaint);

    // Wood Plank Seam Lines
    final seamPaint = Paint()
      ..color = const Color(0xFF8D5B29).withValues(alpha: 0.35)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(-halfW * 0.35, halfH), Offset(-halfTopW * 0.35, -halfH), seamPaint);
    canvas.drawLine(Offset(halfW * 0.35, halfH), Offset(halfTopW * 0.35, -halfH), seamPaint);

    // Target Border Stripe (Classic American Cornhole Red/Blue Border)
    final stripePaint = Paint()
      ..color = const Color(0xFF1976D2).withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    final innerPath = Path()
      ..moveTo(-halfW + 6, halfH - 4)
      ..lineTo(halfW - 6, halfH - 4)
      ..lineTo(halfTopW - 4, -halfH + 4)
      ..lineTo(-halfTopW + 4, -halfH + 4)
      ..close();
    canvas.drawPath(innerPath, stripePaint);

    // 4. Hole Cutout (Dark Depth Void + Highlight Rim)
    final hx = holeOffset.x;
    final hy = holeOffset.y;

    // Hole Ground Shadow underneath
    final holeShadowPaint = Paint()..color = const Color(0xFF1B1B1B);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(hx, hy + 2), width: holeRadius * 2.1, height: holeRadius * 1.5),
      holeShadowPaint,
    );

    // Hole Void Interior
    final holeInteriorPaint = Paint()..color = const Color(0xFF000000);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(hx, hy), width: holeRadius * 2.0, height: holeRadius * 1.4),
      holeInteriorPaint,
    );

    // Contrasting White/Grey Hole Rim (Kenney Target Style)
    final holeRimPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(hx, hy), width: holeRadius * 2.0, height: holeRadius * 1.4),
      holeRimPaint,
    );
  }
}
