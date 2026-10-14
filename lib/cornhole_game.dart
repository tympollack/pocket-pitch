import 'dart:async';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'components/board.dart';
import 'components/beanbag.dart';
import 'components/gesture_guide.dart';

export 'components/board.dart';
export 'components/beanbag.dart';
export 'components/gesture_guide.dart';

/// =====================================================================
/// ThrowData
/// =====================================================================
class ThrowData {
  /// Ground-plane velocity (px/s): x = left/right aim, y = downrange speed.
  final Vector2 groundVelocity;

  /// Initial upward launch speed (px/s) for the parabolic altitude axis.
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
class RoundTelemetry {
  final List<double> _throwSpeeds = [];
  double _maxLateralDrift = 0.0;

  double get averageThrowSpeed => _throwSpeeds.isEmpty
      ? 0.0
      : _throwSpeeds.reduce((a, b) => a + b) / _throwSpeeds.length;

  double get maxLateralDrift => _maxLateralDrift;

  void recordThrowSpeed(double speed) => _throwSpeeds.add(speed);

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

  void Function(GameState state)? onScoreChanged;
  void Function(GameState state)? onRoundComplete;

  void recordThrow(ThrowResult result) {
    if (isRoundComplete) {
      return;
    }

    _bagsThrown++;
    _totalScore += result.points;
    _results.add(result);

    onScoreChanged?.call(this);

    if (isRoundComplete) {
      onRoundComplete?.call(this);
    }
  }

  void startNewRound() {
    _totalScore = 0;
    _bagsThrown = 0;
    _results.clear();
    telemetry.reset();
    onScoreChanged?.call(this);
  }
}

/// =====================================================================
/// Theme / asset management
/// =====================================================================
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
/// CornholeGame
/// =====================================================================
class CornholeGame extends FlameGame with PanDetector {
  GameTheme _theme;
  GameTheme get theme => _theme;
  final bool enableGyroscope;

  late BackgroundComponent background;
  late BoardComponent board;
  late BagComponent bag;
  late GestureGuideComponent gestureGuide;

  final GameState gameState = GameState();

  Vector2 currentTilt = Vector2.zero();
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;

  Vector2? _panStartPosition;
  Vector2 _panLastPosition = Vector2.zero();
  double _panStartTime = 0;
  double _panLastTime = 0;

  CornholeGame({
    GameTheme initialTheme = GameTheme.moon,
    this.enableGyroscope = true,
  }) : _theme = initialTheme;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    final centerX = size.x / 2;

    background = BackgroundComponent(size: size.clone());
    board = BoardComponent(position: Vector2(centerX, size.y * 0.18));
    bag = BagComponent(startPosition: Vector2(centerX, size.y * 0.92));
    gestureGuide = GestureGuideComponent()..priority = 50;

    await addAll([background, board, bag, gestureGuide]);
    await setTheme(_theme);

    if (enableGyroscope) {
      try {
        _gyroSubscription = gyroscopeEventStream().listen(
          (event) {
            const smoothing = 0.15;
            currentTilt.x += (event.x - currentTilt.x) * smoothing;
            currentTilt.y += (event.y - currentTilt.y) * smoothing;
          },
          onError: (_) {},
        );
      } catch (_) {}
    }
  }

  @override
  void onRemove() {
    _gyroSubscription?.cancel();
    super.onRemove();
  }

  Future<void> setTheme(GameTheme newTheme) async {
    final assets = kThemeAssets[newTheme];
    if (assets == null) {
      return;
    }

    try {
      final bgImage = await images.load(assets.background);
      final boardImage = await images.load(assets.board);
      final bagImage = await images.load(assets.bag);

      background.sprite = Sprite(bgImage);
      board.sprite = Sprite(boardImage);
      bag.sprite = Sprite(bagImage);
      _theme = newTheme;
    } catch (_) {
      // Clear sprites to ensure clean procedural fallback and preserve current theme
      background.sprite = null;
      board.sprite = null;
      bag.sprite = null;
    }
  }

  // -------------------------------------------------------------------
  // PanDetector (flick input & gesture trails)
  // -------------------------------------------------------------------

  @override
  void onPanStart(DragStartInfo info) {
    if (gameState.isRoundComplete || bag.isFlying) return;
    final pos = info.eventPosition.widget.clone();
    _panStartPosition = pos;
    _panLastPosition = pos.clone();
    _panStartTime = _nowSeconds();
    _panLastTime = _panStartTime;
    gestureGuide.onPanStart(pos, _panStartTime);
  }

  @override
  void onPanUpdate(DragUpdateInfo info) {
    if (_panStartPosition == null) return;
    final pos = info.eventPosition.widget.clone();
    _panLastPosition = pos;
    _panLastTime = _nowSeconds();
    gestureGuide.onPanUpdate(pos, _panLastTime);
  }

  @override
  void onPanEnd(DragEndInfo info) {
    final start = _panStartPosition;
    gestureGuide.onPanEnd();
    if (start == null) return;

    final elapsed = (_panLastTime - _panStartTime).clamp(0.016, 1.0);
    final swipeVelocity = (_panLastPosition - start) / elapsed;

    bag.launch(_throwDataFromSwipe(swipeVelocity));
    _panStartPosition = null;
  }

  @override
  void onPanCancel() {
    _panStartPosition = null;
    gestureGuide.onPanCancel();
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

  void throwBag() {
    if (gameState.isRoundComplete || bag.isFlying) return;
    bag.launch(ThrowData(
      groundVelocity: Vector2(0, -160),
      launchSpeed: 380,
    ));
  }

  void startNewRound() => gameState.startNewRound();
}
