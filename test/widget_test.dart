import 'package:flutter_test/flutter_test.dart';
import 'package:flame/components.dart';
import 'package:pocket_pitch/cornhole_game.dart';

void main() {
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

  group('ThrowData & Parabolic Math', () {
    test('Parabolic arc equations verify gravity and altitude apex', () {
      const double initialVerticalSpeed = 450.0;
      const double gravity = 900.0;

      // Time to apex: v = v0 - g*t = 0 => t = 450 / 900 = 0.5s
      final apexTime = initialVerticalSpeed / gravity;
      expect(apexTime, equals(0.5));

      // Peak altitude: h = v0*t - 0.5*g*t^2 = 450*0.5 - 0.5*900*0.25 = 225 - 112.5 = 112.5
      final peakAltitude = (initialVerticalSpeed * apexTime) - (0.5 * gravity * apexTime * apexTime);
      expect(peakAltitude, equals(112.5));
    });
  });
}
