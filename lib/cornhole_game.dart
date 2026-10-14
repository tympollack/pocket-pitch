import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart' show Canvas, Color, Offset, Paint, PaintingStyle, Rect;
import 'package:sensors_plus/sensors_plus.dart';

/// =====================================================================
/// ThrowData
/// =====================================================================
class ThrowData {
  /// Ground-plane velocity (px/s): x = left/right aim, y = downrange
  /// speed toward the board. Gravity does NOT act on this — it's pure
  /// top-down travel, like a bag sliding across a table.
  final Vector2 groundVelocity;

  /// Initial upward launch speed (px/s) for the altitude axis. Gravity
  /// acts on this alone, producing the classic rise-then-fall arc.
  final double launchSpeed;

  ThrowData({
    required this.groundVelocity,
    required this.launchSpeed,
  });
}

/// =====================================================================
/// ThrowResult / scoring
/// =====================================================================
enum ThrowResult { miss, onBoard, hole }

extension ThrowResultScoring on ThrowResult {
  int get points {
    switch (this) {
      case ThrowResult.hole:
        return 3;
      case ThrowResult.onBoard:
        return 1;
      case ThrowResult.miss:
        return 0;
    }
  }

  String get label {
    switch (this) {
      case ThrowResult.hole:
        return 'IN THE HOLE';
      case ThrowResult.onBoard:
        return 'on the board';
      case ThrowResult.miss:
        return 'missed (ground)';
    }
  }
}

/// =====================================================================
/// Telemetry
/// =====================================================================
/// Accumulated alongside scoring, per round. Lives on GameState (not
/// BagComponent) because it needs to survive across all 4 bags, not
/// reset per-throw.
class RoundTelemetry {
  final List<double> _throwSpeeds = [];
  double _maxLateralDrift = 0.0;

  double get averageThrowSpeed => _throwSpeeds.isEmpty
      ? 0.0
      : _throwSpeeds.reduce((a, b) => a + b) / _throwSpeeds.length;

  double get maxLateralDrift => _maxLateralDrift;

  /// Call once per throw, at launch, with the combined initial speed
  /// (ground-plane + altitude launch speed magnitude).
  void recordThrowSpeed(double speed) => _throwSpeeds.add(speed);

  /// Call every frame a bag is in flight with the current magnitude of
  /// gyro-driven lateral velocity nudge; only the peak is kept.
  void recordLateralDrift(double driftMagnitude) {
    if (driftMagnitude > _maxLateralDrift) {
      _maxLateralDrift = driftMagnitude;
    }
  }

  void reset() {
    _throwSpeeds.clear();
    _maxLateralDrift = 0.0;
  }
}

/// =====================================================================
/// GameState
/// =====================================================================
class GameState {
  static const int bagsPerRound = 4;

  int _totalScore = 0;
  int _bagsThrown = 0;
  final List<ThrowResult> _results = [];
  final RoundTelemetry telemetry = RoundTelemetry();

  int get totalScore => _totalScore;
  int get bagsThrown => _bagsThrown;
  int get bagsRemaining => bagsPerRound - _bagsThrown;
  bool get isRoundComplete => _bagsThrown >= bagsPerRound;
  List<ThrowResult> get results => List.unmodifiable(_results);

  /// Fired after every recorded throw (running score, bag count). Lets a
  /// UI layer (Riverpod/Provider/whatever) observe live progress without
  /// GameState depending on any state-management package.
  void Function(GameState state)? onScoreChanged;

  /// Fired exactly once, the moment the 4th bag's result is recorded.
  void Function(GameState state)? onRoundComplete;

  void recordThrow(ThrowResult result) {
    if (isRoundComplete) {
      print('[Cornhole] Round already complete — call startNewRound() '
          'before throwing again.');
      return;
    }

    _bagsThrown++;
    _totalScore += result.points;
    _results.add(result);

    print('[Cornhole] Bag $_bagsThrown/$bagsPerRound: ${result.label} '
        '(+${result.points} pts) — round score: $_totalScore');

    onScoreChanged?.call(this);

    if (isRoundComplete) {
      print('[Cornhole] Round complete! Final score: $_totalScore '
          '(${_results.map((r) => r.label).join(', ')})');
      onRoundComplete?.call(this);
    }
  }

  void startNewRound() {
    _totalScore = 0;
    _bagsThrown = 0;
    _results.clear();
    telemetry.reset();
    print('[Cornhole] New round started.');
    onScoreChanged?.call(this);
  }
}

/// =====================================================================
/// Theme / asset management
/// =====================================================================
/// Named GameTheme (not `Theme` — that name collides with Flutter's
/// material Theme class). Each value maps to a trio of image paths via
/// [kThemeAssets]; swapping themes just re-points the existing sprite
/// components at new images, no component restructuring needed.
enum GameTheme { moon, boat }

class ThemeAssetPaths {
  final String background;
  final String board;
  final String bag;

  const ThemeAssetPaths({
    required this.background,
    required this.board,
    required this.bag,
  });
}

/// Paths are relative to Flame's default image root: assets/images/.
/// Add the corresponding folders/files to pubspec.yaml under
/// flutter: assets: — e.g. assets/images/moon/, assets/images/boat/.
const Map<GameTheme, ThemeAssetPaths> kThemeAssets = {
  GameTheme.moon: ThemeAssetPaths(
    background: 'moon/background.png',
    board: 'moon/board.png',
    bag: 'moon/bag.png',
  ),
  GameTheme.boat: ThemeAssetPaths(
    background: 'boat/background.png',
    board: 'boat/board.png',
    bag: 'boat/bag.png',
  ),
};

/// =====================================================================
/// BackgroundComponent
/// =====================================================================
class BackgroundComponent extends SpriteComponent {
  BackgroundComponent({required Vector2 size})
      : super(position: Vector2.zero(), size: size, anchor: Anchor.topLeft) {
    priority = -100;
  }
}

/// =====================================================================
/// ShadowComponent
/// =====================================================================
/// Child of BagComponent. Positioned in the bag's LOCAL space at
/// (0, altitude) — since the parent (the bag) is already drawn at its
/// elevated arc position, offsetting the shadow downward by `altitude`
/// places it exactly on the ground track in world space. Shrinks and
/// lightens as altitude grows, the opposite as the bag descends.
class ShadowComponent extends PositionComponent {
  double _opacity = 0.45;

  ShadowComponent() : super(anchor: Anchor.center);

  /// [altitude] is in the same px units as screen position (0 = bag is
  /// on the ground track). [bagRadius] is the bag's CURRENT (already
  /// depth-scaled) radius, so the shadow shrinks with distance too.
  void updateForAltitude(double altitude, double bagRadius) {
    const maxAltitudeForFade = 220.0;
    final t = (altitude / maxAltitudeForFade).clamp(0.0, 1.0);

    _opacity = lerpDouble(0.45, 0.06, t)!;
    final widthScale = lerpDouble(1.0, 0.3, t)!;

    position = Vector2(0, altitude);
    final w = bagRadius * 2 * widthScale;
    size = Vector2(w, w * 0.4); // flattened ellipse, like a ground shadow
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()
      ..color = Color.fromRGBO(0, 0, 0, _opacity)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: width, height: height),
      paint,
    );
  }
}

/// =====================================================================
/// BoardComponent
/// =====================================================================
/// Now a SpriteComponent — the trapezoid perspective is baked into the
/// artwork itself rather than drawn in code. All the collision geometry
/// (edges, hole position, width-at-y) is kept as plain fields/getters so
/// physics/scoring logic is completely unaffected by the visual swap.
class BoardComponent extends SpriteComponent {
  final double topWidth;
  final double bottomWidth;
  final double boardHeight;
  final Vector2 holeOffset;
  final double holeRadius;

  /// Optional shear (px) applied to the top edge, so the hitbox can be a
  /// true angled quad rather than a symmetric trapezoid — e.g. for a
  /// board viewed at a slight side angle instead of dead-on.
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

  /// The board's hitbox as four world-space corners, near edge first:
  /// [nearLeft, nearRight, farRight, farLeft]. `topSkew` shifts the far
  /// edge sideways, giving a genuinely angled (non-rectangular,
  /// non-symmetric) quad rather than just a centered trapezoid.
  List<Vector2> get hitboxCorners {
    final cx = position.x;
    return [
      Vector2(cx - bottomWidth / 2, frontEdgeY), // near-left
      Vector2(cx + bottomWidth / 2, frontEdgeY), // near-right
      Vector2(cx + topWidth / 2 + topSkew, backEdgeY), // far-right
      Vector2(cx - topWidth / 2 + topSkew, backEdgeY), // far-left
    ];
  }

  /// Point-in-quad test (the angled hitbox), via the standard signed-area
  /// "same side of every edge" check — works for any convex quad,
  /// including a skewed one.
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

  /// True if a circle of the given radius centered at [point] is fully
  /// inside the hole (used for the "center fully inside hole" rule) —
  /// here interpreted as: the bag's center is within (holeRadius -
  /// bagRadius) of the hole's center, i.e. the whole bag fits inside.
  bool isFullyInsideHole(Vector2 point, double bagRadius) {
    final usableRadius = holeRadius - bagRadius;
    if (usableRadius <= 0) return false; // bag is bigger than the hole
    return point.distanceTo(holePosition) <= usableRadius;
  }
}

/// =====================================================================
/// BagComponent
/// =====================================================================
class BagComponent extends SpriteComponent with HasGameRef<CornholeGame> {
  final double baseRadius;
  final double gravity;
  final double minScale;
  final double maxAltitudeForScale;
  final double lateralDriftSensitivity;

  double radius;

  /// Ground-plane velocity (x = left/right, y = downrange). NOT affected
  /// by gravity — gravity only acts on [altitude].
  Vector2 velocity = Vector2.zero();

  /// Simulated height off the ground (px-equivalent units). Driven by
  /// [_verticalSpeed] and [gravity]; this is the bag's true Z-axis.
  double altitude = 0.0;
  double _verticalSpeed = 0.0;

  bool isFlying = false;
  bool _hasLanded = true; // starts "landed" at rest before the first throw

  final Vector2 launchPosition;
  late final ShadowComponent shadow;

  BagComponent({
    required Vector2 startPosition,
    this.baseRadius = 18,
    this.gravity = 900,
    this.minScale = 0.3,
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
    _hasLanded = false;

    // Telemetry: combined initial speed of this throw (ground-plane +
    // altitude kick), recorded once per throw at the moment of release.
    final initialSpeed =
        Vector2(data.groundVelocity.x, data.groundVelocity.y).length +
            data.launchSpeed;
    gameRef.gameState.telemetry.recordThrowSpeed(initialSpeed);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isFlying) return;

    // --- Altitude axis: gravity acts ONLY here ---
    _verticalSpeed -= gravity * dt;
    altitude += _verticalSpeed * dt;

    // --- Ground-plane travel (no gravity) ---
    final tilt = gameRef.currentTilt;
    final lateralDriftThisFrame = tilt.x * lateralDriftSensitivity * dt;
    velocity.x += lateralDriftThisFrame; // gyro drift
    position += velocity * dt;

    // Telemetry: track the peak per-frame lateral drift push over the
    // whole flight, in px/s-equivalent units (the per-frame nudge / dt).
    if (dt > 0) {
      gameRef.gameState.telemetry
          .recordLateralDrift((lateralDriftThisFrame / dt).abs());
    }

    // --- Perspective scale, driven by altitude (higher = smaller/farther-looking) ---
    final altitudeT = (altitude / maxAltitudeForScale).clamp(0.0, 1.0);
    radius = baseRadius * (1.0 - (1.0 - minScale) * altitudeT);
    size = Vector2.all(radius * 2);

    shadow.updateForAltitude(altitude.clamp(0.0, double.infinity), radius);

    // --- Landing: fires exactly once, the instant altitude returns to 0 ---
    if (!_hasLanded && altitude <= 0.0 && _verticalSpeed <= 0.0) {
      altitude = 0.0;
      velocity = Vector2.zero();
      isFlying = false;
      _hasLanded = true;
      shadow.updateForAltitude(0, radius);
      _resolveLanding(gameRef.board);
    }
  }

  void _resolveLanding(BoardComponent board) {
    final ThrowResult result;

    if (board.isFullyInsideHole(position, radius)) {
      result = ThrowResult.hole; // Cornhole — 3 pts
    } else if (board.containsPoint(position)) {
      result = ThrowResult.onBoard; // Woody — 1 pt
    } else {
      result = ThrowResult.miss; // touched the ground — 0 pts
    }

    gameRef.gameState.recordThrow(result);
  }
}

/// =====================================================================
/// CornholeGame
/// =====================================================================
class CornholeGame extends FlameGame with PanDetector {
  GameTheme _theme;
  GameTheme get theme => _theme;

  late BackgroundComponent background;
  late BoardComponent board;
  late BagComponent bag;

  final GameState gameState = GameState();

  Vector2 currentTilt = Vector2.zero();
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;

  Vector2? _panStartPosition;
  Vector2 _panLastPosition = Vector2.zero();
  double _panStartTime = 0;
  double _panLastTime = 0;

  CornholeGame({GameTheme initialTheme = GameTheme.moon}) : _theme = initialTheme;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    final centerX = size.x / 2;

    background = BackgroundComponent(size: size.clone());
    board = BoardComponent(position: Vector2(centerX, size.y * 0.18));
    bag = BagComponent(startPosition: Vector2(centerX, size.y * 0.92));

    await addAll([background, board, bag]);
    await setTheme(_theme);

    _gyroSubscription = gyroscopeEventStream().listen((event) {
      const smoothing = 0.15;
      currentTilt.x += (event.x - currentTilt.x) * smoothing;
      currentTilt.y += (event.y - currentTilt.y) * smoothing;
    });
  }

  @override
  void onRemove() {
    _gyroSubscription?.cancel();
    super.onRemove();
  }

  /// Swaps background/board/bag sprites for the given theme. Physics and
  /// scoring geometry (board edges, hole position, bag radius) are
  /// untouched — only the images change.
  Future<void> setTheme(GameTheme newTheme) async {
    final assets = kThemeAssets[newTheme];
    if (assets == null) {
      print('[Cornhole] No assets registered for theme $newTheme');
      return;
    }

    final bgImage = await images.load(assets.background);
    final boardImage = await images.load(assets.board);
    final bagImage = await images.load(assets.bag);

    background.sprite = Sprite(bgImage);
    board.sprite = Sprite(boardImage);
    bag.sprite = Sprite(bagImage);

    _theme = newTheme;
    print('[Cornhole] Theme switched to $newTheme');
  }

  // -------------------------------------------------------------------
  // PanDetector (flick input)
  // -------------------------------------------------------------------

  @override
  void onPanStart(DragStartInfo info) {
    if (gameState.isRoundComplete || bag.isFlying) return;
    _panStartPosition = info.eventPosition.widget.clone();
    _panLastPosition = _panStartPosition!.clone();
    _panStartTime = _nowSeconds();
    _panLastTime = _panStartTime;
  }

  @override
  void onPanUpdate(DragUpdateInfo info) {
    if (_panStartPosition == null) return;
    _panLastPosition = info.eventPosition.widget.clone();
    _panLastTime = _nowSeconds();
  }

  @override
  void onPanEnd(DragEndInfo info) {
    final start = _panStartPosition;
    if (start == null) return;

    final elapsed = (_panLastTime - _panStartTime).clamp(0.016, 1.0);
    final swipeVelocity = (_panLastPosition - start) / elapsed;

    bag.launch(_throwDataFromSwipe(swipeVelocity));
    _panStartPosition = null;
  }

  @override
  void onPanCancel() {
    _panStartPosition = null;
  }

  ThrowData _throwDataFromSwipe(Vector2 swipeVelocity) {
    const minSwipeSpeed = 200.0;
    const maxSwipeSpeed = 2500.0;

    final upwardSpeed =
        (swipeVelocity.y < 0 ? -swipeVelocity.y : 0.0).clamp(0.0, maxSwipeSpeed);
    final effectiveSpeed =
        upwardSpeed < minSwipeSpeed ? minSwipeSpeed : upwardSpeed;

    const downrangeScale = 0.5; // swipe px/s -> ground-plane downrange speed
    const horizontalScale = 0.35; // sideways swipe -> aim
    const launchSpeedScale = 0.6; // swipe px/s -> initial altitude kick

    return ThrowData(
      groundVelocity: Vector2(
        swipeVelocity.x * horizontalScale,
        -effectiveSpeed * downrangeScale, // negative = toward the board
      ),
      launchSpeed: effectiveSpeed * launchSpeedScale,
    );
  }

  double _nowSeconds() => DateTime.now().microsecondsSinceEpoch / 1e6;

  /// Debug/manual entry point, e.g. for a non-gesture "Throw" button.
  void throwBag() {
    if (gameState.isRoundComplete || bag.isFlying) return;
    bag.launch(ThrowData(
      groundVelocity: Vector2(0, -160),
      launchSpeed: 380,
    ));
  }

  void startNewRound() => gameState.startNewRound();
}
