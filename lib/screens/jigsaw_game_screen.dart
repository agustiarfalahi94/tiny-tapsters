import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/celebration_overlay.dart';
import '../widgets/game_background.dart';
import '../widgets/pair_drag_game.dart';
import '../widgets/round_button.dart';

/// A real picture puzzle: a big emoji picture is sliced into a grid, the
/// slices are scrambled in the drawer, and a faint copy of the whole picture
/// sits behind the board as a reference. Drag each slice to its spot.
class JigsawGameScreen extends StatefulWidget {
  const JigsawGameScreen({super.key, required this.rows, required this.cols});

  final int rows;
  final int cols;

  @override
  State<JigsawGameScreen> createState() => _JigsawGameScreenState();
}

class _JigsawGameScreenState extends State<JigsawGameScreen> {
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

  /// The emoji is rendered at this moderate font size and enlarged with a
  /// transform. Huge font sizes (300px+) can exhaust the glyph atlas on
  /// Android and make ALL text/emoji in the app stop painting until the app
  /// restarts — that is what made icons vanish app-wide.
  static const _pictureFontSize = 128.0;

  late String _picture;
  late Key _gameKey;
  bool _won = false;

  @override
  void initState() {
    super.initState();
    _picture = _pictures[math.Random().nextInt(_pictures.length)];
    _gameKey = UniqueKey();
  }

  void _reset({bool newPicture = false}) {
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
                      const Spacer(),
                      Text(
                        'Jigsaw ${widget.rows}×${widget.cols}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          shadows: [
                            Shadow(color: Colors.black26, blurRadius: 6),
                          ],
                        ),
                      ),
                      const Spacer(),
                      RoundButton(emoji: '🔁', onTap: _reset),
                    ],
                  ),
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
                    onCompleted: () => setState(() => _won = true),
                  ),
                ),
              ],
            ),
          ),
          if (_won)
            CelebrationOverlay(
              emoji: '🧩',
              title: 'Jigsaw done!',
              primaryLabel: 'New puzzle 🧩',
              onPrimary: () => _reset(newPicture: true),
              secondaryLabel: 'Levels 🏠',
              onSecondary: () => Navigator.of(context).pop(),
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
      // line between pieces.
      child: Center(
        // Moderate font size + transform scale (GPU-scaled, cheap and safe).
        // The 1.15 factor compensates for the emoji glyph's internal padding
        // so it visually fills the board; the tiny overscan is clipped at the
        // board edges.
        child: Transform.scale(
          scale: boardMin / _pictureFontSize * 1.15,
          child: Text(
            _picture,
            style: const TextStyle(fontSize: _pictureFontSize),
          ),
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
