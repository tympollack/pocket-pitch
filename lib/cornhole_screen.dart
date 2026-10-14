import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cornhole_game.dart';

/// =====================================================================
/// Riverpod state
/// =====================================================================
/// Plain data snapshot of a round, separate from GameState (which is
/// Flame/physics-side). This is what the rest of the Flutter app reads —
/// e.g. to post to a backend hub once isComplete flips to true.
@immutable
class RoundScore {
  final int totalScore;
  final int bagsThrown;
  final int bagsPerRound;
  final List<ThrowResult> results;
  final bool isComplete;

  /// Snapshot of this round's telemetry at the moment this RoundScore was
  /// captured. Zeroed out for an in-progress (not-yet-complete) round's
  /// initial state, populated for real once onRoundComplete fires.
  final double averageThrowSpeed;
  final double maxLateralDrift;

  const RoundScore({
    required this.totalScore,
    required this.bagsThrown,
    required this.bagsPerRound,
    required this.results,
    required this.isComplete,
    this.averageThrowSpeed = 0.0,
    this.maxLateralDrift = 0.0,
  });

  const RoundScore.initial()
      : totalScore = 0,
        bagsThrown = 0,
        bagsPerRound = GameState.bagsPerRound,
        results = const [],
        isComplete = false,
        averageThrowSpeed = 0.0,
        maxLateralDrift = 0.0;

  int get cornholes => results.where((r) => r == ThrowResult.hole).length;
  int get woodies => results.where((r) => r == ThrowResult.onBoard).length;
  int get misses => results.where((r) => r == ThrowResult.miss).length;

  factory RoundScore.fromGameState(GameState state) => RoundScore(
        totalScore: state.totalScore,
        bagsThrown: state.bagsThrown,
        bagsPerRound: GameState.bagsPerRound,
        results: state.results,
        isComplete: state.isRoundComplete,
        averageThrowSpeed: state.telemetry.averageThrowSpeed,
        maxLateralDrift: state.telemetry.maxLateralDrift,
      );
}

/// Notifier the UI reads/watches. Updated only via the GameState callbacks
/// wired up in [CornholeGameController], so Flame remains the single
/// source of truth for the score; this is just its Flutter-facing mirror.
class RoundScoreNotifier extends StateNotifier<RoundScore> {
  RoundScoreNotifier() : super(const RoundScore.initial());

  void updateFrom(GameState gameState) {
    state = RoundScore.fromGameState(gameState);
  }

  void reset() {
    state = const RoundScore.initial();
  }
}

final roundScoreProvider =
    StateNotifierProvider<RoundScoreNotifier, RoundScore>(
  (ref) => RoundScoreNotifier(),
);

/// =====================================================================
/// Backend submission (mock)
/// =====================================================================
enum SubmissionStatus { idle, sending, success, failure }

@immutable
class SubmissionState {
  final SubmissionStatus status;
  final String? message;

  const SubmissionState({this.status = SubmissionStatus.idle, this.message});

  const SubmissionState.idle() : this();
}

class SubmissionNotifier extends StateNotifier<SubmissionState> {
  SubmissionNotifier() : super(const SubmissionState.idle());

  void setSending() => state = const SubmissionState(status: SubmissionStatus.sending);

  void setSuccess(String message) =>
      state = SubmissionState(status: SubmissionStatus.success, message: message);

  void setFailure(String message) =>
      state = SubmissionState(status: SubmissionStatus.failure, message: message);
}

/// Mirrors the last submission's status, purely for optional UI feedback
/// (e.g. a small "Synced ✓" / "Sync failed" indicator). The round-over
/// flow doesn't block on this in any way.
final submissionStatusProvider =
    StateNotifierProvider<SubmissionNotifier, SubmissionState>(
  (ref) => SubmissionNotifier(),
);

/// =====================================================================
/// RoundPayload — the Player Hub data contract
/// =====================================================================
/// Exact wire shape the future Player Hub endpoint expects. This is the
/// ONLY thing ScoreSubmissionService sends — everything upstream (Riverpod
/// state, Flame's GameState) gets funneled into this shape first, the same
/// way ThrowData is the funnel point for the physics engine's input.
@immutable
class ScorePayload {
  final int totalPoints;
  final int cornholes;
  final int woodies;
  final int misses;

  const ScorePayload({
    required this.totalPoints,
    required this.cornholes,
    required this.woodies,
    required this.misses,
  });

  Map<String, dynamic> toJson() => {
        'total_points': totalPoints,
        'cornholes': cornholes,
        'woodies': woodies,
        'misses': misses,
      };
}

@immutable
class TelemetryPayload {
  final double averageThrowSpeed;
  final double maxLateralDrift;

  const TelemetryPayload({
    required this.averageThrowSpeed,
    required this.maxLateralDrift,
  });

  Map<String, dynamic> toJson() => {
        'average_throw_speed': averageThrowSpeed,
        'max_lateral_drift': maxLateralDrift,
      };
}

@immutable
class RoundPayload {
  final String matchId;
  final String playerId;

  /// Null when playing solo (no opponent for this match).
  final String? opponentId;

  final String themeUsed;
  final DateTime timestamp;
  final ScorePayload score;
  final TelemetryPayload telemetry;

  const RoundPayload({
    required this.matchId,
    required this.playerId,
    this.opponentId,
    required this.themeUsed,
    required this.timestamp,
    required this.score,
    required this.telemetry,
  });

  Map<String, dynamic> toJson() => {
        'match_id': matchId,
        'player_id': playerId,
        'opponent_id': opponentId, // null serializes as JSON null, not omitted
        'theme_used': themeUsed,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'score': score.toJson(),
        'telemetry': telemetry.toJson(),
      };

  factory RoundPayload.fromRound({
    required String matchId,
    required String playerId,
    String? opponentId,
    required GameTheme theme,
    required RoundScore round,
  }) {
    return RoundPayload(
      matchId: matchId,
      playerId: playerId,
      opponentId: opponentId,
      themeUsed: theme.name,
      timestamp: DateTime.now(),
      score: ScorePayload(
        totalPoints: round.totalScore,
        cornholes: round.cornholes,
        woodies: round.woodies,
        misses: round.misses,
      ),
      telemetry: TelemetryPayload(
        averageThrowSpeed: round.averageThrowSpeed,
        maxLateralDrift: round.maxLateralDrift,
      ),
    );
  }
}

/// Stand-in for a real backend client. The body of [submit] is shaped
/// exactly like a real `http.post` call (build payload -> encode JSON ->
/// await a Future -> inspect a "response") so swapping in package:http
/// tomorrow is a small, local change:
///
///   final response = await http.post(
///     Uri.parse('https://hub.example.com/api/rounds'),
///     headers: {'Content-Type': 'application/json'},
///     body: jsonEncode(payload.toJson()),
///   );
///
/// For now it just encodes + prints, with a simulated delay and an
/// unreachable-with-real-data failure branch so the failure path can be
/// exercised in development.
class ScoreSubmissionService {
  Future<void> submit(RoundPayload payload) async {
    final body = jsonEncode(payload.toJson());

    // Dummy "POST": this is the shape a real http.post call would have —
    // a single awaited Future standing in for the network round-trip.
    await _dummyPost(body);
  }

  Future<void> _dummyPost(String jsonBody) async {
    // Simulated network latency.
    await Future.delayed(const Duration(milliseconds: 600));

    // Simulated occasional failure, so the failure path is exercised too.
    final fakeFailure = jsonBody.contains('"total_points":-1'); // never true with real scores
    if (fakeFailure) {
      throw Exception('Mock backend rejected the submission');
    }

    // ignore: avoid_print
    print('[Backend] POST /api/rounds  body=$jsonBody');
  }
}

final scoreSubmissionServiceProvider =
    Provider<ScoreSubmissionService>((ref) => ScoreSubmissionService());

/// =====================================================================
/// Player / match identity (placeholders)
/// =====================================================================
/// TODO: replace with real values once auth/session and matchmaking
/// exist. For now each app run gets one stable player ID and a fresh
/// match ID per round, purely so RoundPayload has *something* well-formed
/// to send. opponentId stays null — solo play only, for now.
final playerIdProvider = Provider<String>((ref) => _generateUuidV4());

String _generateUuidV4() {
  final random = Random();
  // Minimal UUID v4 generator — good enough for a placeholder ID; swap
  // for the `uuid` package or a real backend-issued ID later.
  const chars = '0123456789abcdef';
  final segments = [8, 4, 4, 4, 12];
  return segments
      .map((len) => List.generate(len, (_) => chars[random.nextInt(16)]).join())
      .join('-');
}

/// =====================================================================
/// Theme state
/// =====================================================================
/// Single source of truth for the active skin. Change it from anywhere
/// in the widget tree (e.g. a settings menu) — cornholeGameProvider below
/// reacts to it and pushes the new sprites into the running game.
final themeProvider = StateProvider<GameTheme>((ref) => GameTheme.moon);

/// Holds the single CornholeGame instance for this screen, wires its
/// GameState callbacks into Riverpod, fires the (non-blocking) backend
/// submission on round completion, and keeps the game's sprites in sync
/// with [themeProvider].
final cornholeGameProvider = Provider<CornholeGame>((ref) {
  final initialTheme = ref.read(themeProvider);
  final game = CornholeGame(initialTheme: initialTheme);

  game.gameState.onScoreChanged = (gameState) {
    ref.read(roundScoreProvider.notifier).updateFrom(gameState);
  };

  game.gameState.onRoundComplete = (gameState) {
    ref.read(roundScoreProvider.notifier).updateFrom(gameState);

    final round = RoundScore.fromGameState(gameState);
    final activeTheme = ref.read(themeProvider);

    // Fire-and-forget: deliberately NOT awaited here. onRoundComplete is
    // invoked synchronously from inside BagComponent.update(), which runs
    // on Flame's game loop — awaiting a network call here would stall
    // physics ticks until the response arrives. unawaited() makes that
    // intentional instead of looking like a missed `await`.
    unawaited(_submitRoundScore(ref, round, activeTheme));
  };

  // React to theme changes made anywhere in the app (e.g. a settings
  // screen) for as long as this game instance is alive.
  ref.listen<GameTheme>(themeProvider, (previous, next) {
    if (previous != next) {
      unawaited(game.setTheme(next));
    }
  });

  return game;
});

/// Builds the RoundPayload for a completed round and posts it without
/// letting failures propagate anywhere that could crash the app or the
/// game loop. Status is mirrored into [submissionStatusProvider] purely
/// for optional UI.
Future<void> _submitRoundScore(
  Ref ref,
  RoundScore round,
  GameTheme theme,
) async {
  final service = ref.read(scoreSubmissionServiceProvider);
  final statusNotifier = ref.read(submissionStatusProvider.notifier);

  final payload = RoundPayload.fromRound(
    matchId: _generateUuidV4(), // TODO: real match ID once matchmaking exists
    playerId: ref.read(playerIdProvider),
    opponentId: null, // solo play; populate once multiplayer exists
    theme: theme,
    round: round,
  );

  statusNotifier.setSending();
  try {
    await service.submit(payload);
    statusNotifier.setSuccess('Score submitted');
  } catch (e) {
    // Swallowed deliberately: a failed background sync should never
    // interrupt gameplay. Surface it via submissionStatusProvider only.
    statusNotifier.setFailure('Submission failed: $e');
  }
}

/// =====================================================================
/// Widget tree
/// =====================================================================
/// Top-level screen: GameWidget underneath, a thin score readout while
/// playing, and a 'Round Over' overlay once isComplete flips to true.
class CornholeScreen extends ConsumerWidget {
  const CornholeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(cornholeGameProvider);
    final round = ref.watch(roundScoreProvider);

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: GameWidget(game: game)),
          Positioned(
            top: 16,
            left: 16,
            child: _LiveScoreBadge(round: round),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: Row(
              children: const [
                _SubmissionStatusBadge(),
                SizedBox(width: 8),
                _ThemeSwitcher(),
              ],
            ),
          ),
          if (round.isComplete)
            Positioned.fill(
              child: RoundOverOverlay(
                round: round,
                onPlayAgain: () => _playAgain(ref),
              ),
            ),
        ],
      ),
    );
  }

  void _playAgain(WidgetRef ref) {
    final game = ref.read(cornholeGameProvider);
    game.startNewRound(); // resets Flame's GameState
    ref.read(roundScoreProvider.notifier).reset(); // mirrors it immediately
  }
}

/// Small toggle so the new theme-swap wiring is actually reachable from
/// the UI. Reading/writing themeProvider here is what cornholeGameProvider
/// listens for in order to call game.setTheme().
class _ThemeSwitcher extends ConsumerWidget {
  const _ThemeSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButton<GameTheme>(
        value: theme,
        dropdownColor: const Color(0xFF1E1E24),
        underline: const SizedBox.shrink(),
        style: const TextStyle(color: Colors.white, fontSize: 13),
        items: GameTheme.values
            .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
            .toList(),
        onChanged: (newTheme) {
          if (newTheme != null) {
            ref.read(themeProvider.notifier).state = newTheme;
          }
        },
      ),
    );
  }
}

/// Tiny, optional indicator for the background score-submission status.
/// Purely cosmetic — gameplay never waits on this.
class _SubmissionStatusBadge extends ConsumerWidget {
  const _SubmissionStatusBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final submission = ref.watch(submissionStatusProvider);

    if (submission.status == SubmissionStatus.idle) {
      return const SizedBox.shrink();
    }

    final (icon, color) = switch (submission.status) {
      SubmissionStatus.sending => (Icons.sync, Colors.amberAccent),
      SubmissionStatus.success => (Icons.check_circle, Colors.greenAccent),
      SubmissionStatus.failure => (Icons.error, Colors.redAccent),
      SubmissionStatus.idle => (Icons.circle, Colors.transparent),
    };

    return Tooltip(
      message: submission.message ?? '',
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }
}

/// Small always-visible readout while a round is in progress.
class _LiveScoreBadge extends StatelessWidget {
  final RoundScore round;

  const _LiveScoreBadge({required this.round});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Score: ${round.totalScore}   •   Bag ${round.bagsThrown}/${round.bagsPerRound}',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    );
  }
}

/// =====================================================================
/// RoundOverOverlay
/// =====================================================================
class RoundOverOverlay extends StatelessWidget {
  final RoundScore round;
  final VoidCallback onPlayAgain;

  const RoundOverOverlay({
    super.key,
    required this.round,
    required this.onPlayAgain,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.65),
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E24),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 8)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Round Over',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${round.totalScore}',
              style: const TextStyle(
                color: Color(0xFFFFC857),
                fontSize: 56,
                fontWeight: FontWeight.w800,
                height: 1.0,
              ),
            ),
            const Text(
              'points',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: round.results
                  .map((r) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _ResultChip(result: r),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onPlayAgain,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFC857),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Play Again',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultChip extends StatelessWidget {
  final ThrowResult result;

  const _ResultChip({required this.result});

  @override
  Widget build(BuildContext context) {
    final Color color;
    switch (result) {
      case ThrowResult.hole:
        color = const Color(0xFF4CAF50);
        break;
      case ThrowResult.onBoard:
        color = const Color(0xFF42A5F5);
        break;
      case ThrowResult.miss:
        color = const Color(0xFF757575);
        break;
    }

    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// =====================================================================
/// App entry point example
/// =====================================================================
/// void main() {
///   runApp(const ProviderScope(child: MaterialApp(home: CornholeScreen())));
/// }
