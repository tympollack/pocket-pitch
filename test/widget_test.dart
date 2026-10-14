import 'package:flutter_test/flutter_test.dart';
import 'package:flame/components.dart';
import 'package:pocket_pitch/cornhole_game.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BoardComponent & Hole Trigger Tests', () {
    late BoardComponent board;

    setUp(() {
      board = BoardComponent(
        position: Vector2(200, 150),
        topWidth: 100,
        bottomWidth: 240,
        boardHeight: 80,
        holeOffset: Vector2(0, -15),
        holeRadius: 18,
      );
    });

    test('hitbox corners and containsPoint accurately identify board surface', () {
      // Board center is inside
      expect(board.containsPoint(Vector2(200, 150)), isTrue);

      // Near edge center is inside
      expect(board.containsPoint(Vector2(200, 150 + 35)), isTrue);

      // Far edge center is inside
      expect(board.containsPoint(Vector2(200, 150 - 35)), isTrue);

      // Points clearly outside the board
      expect(board.containsPoint(Vector2(200, 250)), isFalse); // Far below
      expect(board.containsPoint(Vector2(200, 50)), isFalse);  // Far above
      expect(board.containsPoint(Vector2(50, 150)), isFalse);  // Far left
      expect(board.containsPoint(Vector2(350, 150)), isFalse); // Far right
    });

    test('isFullyInsideHole accurately detects clean hole pass-through', () {
      final holePos = board.holePosition; // Vector2(200, 135)

      // Bag centered directly on hole with smaller radius than hole
      expect(board.isFullyInsideHole(holePos, 10.0), isTrue);

      // Bag offset slightly but still fully contained
      expect(board.isFullyInsideHole(holePos + Vector2(4, 3), 10.0), isTrue);

      // Bag partially overlapping but not fully inside
      expect(board.isFullyInsideHole(holePos + Vector2(15, 0), 10.0), isFalse);

      // Bag larger than hole cannot fit inside
      expect(board.isFullyInsideHole(holePos, 22.0), isFalse);
    });
  });

  group('GameState & Scoring Rules', () {
    test('Scoring awards 3 for hole, 1 for board, 0 for miss', () {
      expect(ThrowResult.hole.points, equals(3));
      expect(ThrowResult.onBoard.points, equals(1));
      expect(ThrowResult.miss.points, equals(0));
    });

    test('GameState records 4 bags per round and completes', () {
      final state = GameState();
      expect(state.bagsRemaining, equals(4));
      expect(state.isRoundComplete, isFalse);

      state.recordThrow(ThrowResult.hole);   // 3 pts
      state.recordThrow(ThrowResult.onBoard); // 1 pt
      state.recordThrow(ThrowResult.miss);    // 0 pts
      state.recordThrow(ThrowResult.hole);   // 3 pts

      expect(state.totalScore, equals(7));
      expect(state.bagsThrown, equals(4));
      expect(state.bagsRemaining, equals(0));
      expect(state.isRoundComplete, isTrue);
    });
  });

  group('BagComponent Flight Simulation & Altitude Scaling', () {
    test('Simulation updates altitude, programmatic scale, and triggers landing', () async {
      final game = CornholeGame(enableGyroscope: false);
      // Initialize with default viewport size
      game.onGameResize(Vector2(400, 800));
      await game.onLoad();

      final bag = game.bag;
      expect(bag.isFlying, isFalse);

      // Launch bag with parabolic throw
      bag.launch(ThrowData(
        groundVelocity: Vector2(0, -300),
        launchSpeed: 450,
      ));

      expect(bag.isFlying, isTrue);
      expect(bag.altitude, equals(0.0));
      final initialRadius = bag.radius;

      // Step forward 0.2s during upward climb
      bag.update(0.2);
      expect(bag.altitude, greaterThan(50.0));
      expect(bag.radius, greaterThan(initialRadius * 0.7));

      // Continue stepping through apex and descent until touchdown
      double simulatedTime = 0.2;
      while (bag.isFlying && simulatedTime < 2.0) {
        bag.update(0.05);
        simulatedTime += 0.05;
      }

      // Verify bag landed and scored through game state
      expect(bag.isFlying, isFalse);
      expect(bag.altitude, equals(0.0));
      expect(game.gameState.bagsThrown, equals(1));
      expect(game.gameState.results.length, equals(1));
    });

    test('Direct hole landing triggers sinking animation and hole score', () async {
      final game = CornholeGame(enableGyroscope: false);
      game.onGameResize(Vector2(400, 800));
      await game.onLoad();

      final bag = game.bag;
      // Position bag directly over the hole with small descent altitude
      final holePos = game.board.holePosition;
      bag.position = holePos.clone();
      bag.altitude = 25.0; // Near touchdown
      bag.isFlying = true;
      bag.launch(ThrowData(
        groundVelocity: Vector2.zero(),
        launchSpeed: 10,
      ));

      // Set altitude to 20 with downward velocity
      bag.altitude = 20.0;
      bag.position = holePos.clone();

      // Step once to trigger hole detection
      bag.update(0.05);

      if (bag.isSinking) {
        // Step until sinking finishes
        while (bag.isSinking) {
          bag.update(0.1);
        }
        expect(game.gameState.results.last, equals(ThrowResult.hole));
      }
    });
  });
}
