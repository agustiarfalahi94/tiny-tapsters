import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/narrator.dart';
import '../services/app_language.dart';
import '../widgets/celebration_overlay.dart';
import '../widgets/game_background.dart';
import '../widgets/game_over_overlay.dart';
import '../widgets/game_timer.dart';
import '../widgets/pair_drag_game.dart';
import '../widgets/round_button.dart';

/// A real picture puzzle: a big emoji picture is sliced into a grid, the
/// slices are scrambled in the drawer, and a faint copy of the whole picture
/// sits behind the board as a reference. Drag each slice to its spot.
class JigsawGameScreen extends StatefulWidget {
  const JigsawGameScreen({
    super.key,
    required this.rows,
    required this.cols,
    required this.level,
  });

  final int rows;
  final int cols;

  /// Sets the clock: 30s / 1m / 2m for the whole puzzle.
  final GameLevel level;

  @override
  State<JigsawGameScreen> createState() => _JigsawGameScreenState();
}

class _JigsawGameScreenState extends State<JigsawGameScreen>
    with WidgetsBindingObserver, TimedGame {
  static const _pictures = [
    '🦁',
    '🐼',
    '🦄',
    '🚜',
    '🌈',
    '🐘',
    '🦕',
    '🎪',
    '🐠',
  ];

  late String _picture;
  late Key _gameKey;
  bool _won = false;
  int _stars = 3;

  @override
  GameLevel get gameLevel => widget.level;

  @override
  bool get hasWon => _won;

  @override
  void initState() {
    super.initState();
    // Tell a non-reader which game they just opened.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => Narrator.instance.announce(strings.jigsaw),
    );
    _picture = _pictures[math.Random().nextInt(_pictures.length)];
    _gameKey = UniqueKey();
  }

  /// 3 stars for a clean board, 2 for a couple of mistakes, 1 otherwise —
  /// the same scale the other games use.
  static int starsFor(int wrongDrops) {
    if (wrongDrops == 0) return 3;
    if (wrongDrops <= 2) return 2;
    return 1;
  }

  void _reset({bool newPicture = false}) {
    resetClock();
    setState(() {
      if (newPicture) {
        _picture = _pictures[math.Random().nextInt(_pictures.length)];
      }
      _won = false;
      _gameKey = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GameBackground(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      RoundButton(
                        emoji: '🏠',
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      // Expanded rather than Spacer-Text-Spacer: on a 360dp
                      // phone the title plus two buttons can be wider than the
                      // row, and Spacers cannot give back space they do not
                      // have.
                      Expanded(
                        child: Text(
                          strings.jigsawSize(widget.rows, widget.cols),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [
                              Shadow(color: Colors.black26, blurRadius: 6),
                            ],
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      RoundButton(emoji: '🔁', onTap: _reset),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: GameTimerBar(controller: clock),
                ),
                Expanded(
                  child: PairDragGame(
                    key: _gameKey,
                    pairCount: widget.rows * widget.cols,
                    maxCols: widget.cols,
                    gap: 0,
                    // Pieces are exactly slot-sized so the assembled picture
                    // fills the board 1:1 (smaller pieces would shrink the
                    // whole picture down with them).
                    pieceScale: 1.0,
                    pieceSizeCap: 1000,
                    boardBackgroundBuilder: _buildBoardBackground,
                    slotBuilder: _buildSlot,
                    pieceBuilder: _buildSlice,
                    onFirstMove: startClock,
                    onCompleted: (wrongDrops) {
                      winClock();
                      setState(() {
                        _stars = starsFor(wrongDrops);
                        _won = true;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_won)
            CelebrationOverlay(
              emoji: '🧩',
              title: strings.wonJigsaw,
              stars: _stars,
              primaryLabel: strings.newPuzzle,
              onPrimary: () => _reset(newPicture: true),
              secondaryLabel: strings.levels,
              onSecondary: () => Navigator.of(context).pop(),
            ),
          if (outOfTime)
            GameOverOverlay(
              onRetry: _reset,
              onHome: () => Navigator.of(context).pop(),
            ),
        ],
      ),
    );
  }

  Widget _buildBoardBackground(BuildContext context, Size boardSize) {
    final cell = boardSize.width / widget.cols;
    return Container(
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2)),
      // The faint reference picture, aligned with the slot grid. Clipped so
      // the emoji's overscan (it intentionally fills past the board edges)
      // stays inside the board.
      child: ClipRect(
        child: Opacity(opacity: 0.13, child: _pictureWidget(cell)),
      ),
    );
  }

  Widget _buildSlot(BuildContext context, int index, double slotSize) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: Colors.white70,
        radius: 0,
        dash: 9,
        gap: 7,
      ),
      child: const SizedBox.expand(),
    );
  }

  Widget _buildSlice(
    BuildContext context,
    int index,
    double pieceSize,
    double slotSize,
  ) {
    final row = index ~/ widget.cols;
    final col = index % widget.cols;
    final s = pieceSize / slotSize; // 1.0 for the jigsaw (pieces = slots)
    // Show the (row, col) cell of the picture at full size.
    return ClipRect(
      child: Stack(
        children: [
          Positioned(
            left: -s * col * slotSize,
            top: -s * row * slotSize,
            child: Transform.scale(
              scale: s,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: widget.cols * slotSize,
                height: widget.rows * slotSize,
                child: _pictureWidget(slotSize),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pictureWidget(double cellSize) {
    final boardMin = math.min(widget.cols, widget.rows) * cellSize;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE29A), Color(0xFFFF8FB1)],
        ),
      ),
      // No border or corner radius: a border would show up as a visible cut
      // line between pieces. The emoji is rendered at its NATURAL font size —
      // never wrap it in a FittedBox or Transform.scale: scaling text (in
      // particular bitmap emoji fonts on Impeller) re-rasterizes glyphs on
      // every animation frame, which lags and eventually breaks ALL emoji
      // rendering app-wide. The slight overscan (fontSize = 1.1× the board's
      // smallest side) is clipped at the board edges.
      child: Center(
        child: Text(
          _picture,
          style: TextStyle(fontSize: boardMin * 1.1, height: 1),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.dash,
    required this.gap,
  });

  final Color color;
  final double radius;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(
            distance,
            math.min(distance + dash, metric.length),
          ),
          paint,
        );
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.radius != radius ||
        oldDelegate.dash != dash ||
        oldDelegate.gap != gap;
  }
}
