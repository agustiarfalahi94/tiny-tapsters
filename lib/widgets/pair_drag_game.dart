import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A generic "drag each piece to its own slot" board used by the jigsaw and
/// animal-food games.
///
/// Piece [i] belongs to slot [i]. Pieces start in a drawer at the bottom (in
/// shuffled order); dropping a piece close enough to its slot snaps it into
/// place with a pop, and dropping it anywhere else returns it to the drawer
/// instantly. Pieces always move instantly — no animated slide-backs, so a
/// piece can never be seen "trailing" on its own.
class PairDragGame extends StatefulWidget {
  const PairDragGame({
    super.key,
    required this.pairCount,
    required this.maxCols,
    required this.slotBuilder,
    required this.pieceBuilder,
    required this.onCompleted,
    this.onFirstMove,
    this.boardBackgroundBuilder,
    this.slotCaption,
    this.gap = 12,
    this.pieceScale = 0.85,
    this.pieceSizeCap = 76,
    this.snapTolerance = 0.5,
  });

  final int pairCount;
  final int maxCols;

  /// Builds the visual for slot [slotIndex] at the given size. The widget
  /// should fill the box it is given.
  final Widget Function(BuildContext context, int slotIndex, double slotSize)
  slotBuilder;

  /// Builds the visual for the piece that belongs in slot [slotIndex].
  final Widget Function(
    BuildContext context,
    int slotIndex,
    double pieceSize,
    double slotSize,
  )
  pieceBuilder;

  /// Called shortly after every piece is placed.
  final VoidCallback onCompleted;

  /// Fired once, on the first piece the child picks up. The games use it to
  /// start their clock, so staring at a fresh board costs no time.
  final VoidCallback? onFirstMove;

  /// Optional widget drawn behind the whole slot board (e.g. the faint
  /// reference picture of a jigsaw).
  final Widget Function(BuildContext context, Size boardSize)?
  boardBackgroundBuilder;

  /// Optional short word for slot [slotIndex], shown across the bottom of the
  /// slot **only after its piece is correctly placed** — a reward for getting
  /// it right and something a grown-up can read aloud, rather than a hint
  /// that would let a reader shortcut the puzzle. Return null for no caption.
  /// The jigsaw leaves this unset; its pieces have no names.
  final String? Function(int slotIndex)? slotCaption;

  final double gap;
  final double pieceScale;
  final double pieceSizeCap;
  final double snapTolerance;

  @override
  State<PairDragGame> createState() => _PairDragGameState();
}

class _PairDragGameState extends State<PairDragGame> {
  final List<GlobalKey> _slotKeys = [];
  final List<GlobalKey> _pieceKeys = [];
  final GlobalKey _stackKey = GlobalKey();

  /// Drawer position index for each piece (shuffled on start).
  late final List<int> _pieceDrawerPos;
  final List<Offset?> _pos = [];
  final List<bool> _placed = [];

  int? _dragIndex;
  Offset _dragStart = Offset.zero;
  Offset _pieceStart = Offset.zero;
  bool _done = false;

  // Layout values computed during build, used by drag callbacks.
  double _slotSize = 100;
  double _pieceSize = 60;
  List<Offset> _slotPositions = [];
  List<Offset> _drawerPositions = [];

  @override
  void initState() {
    super.initState();
    final order = List.generate(widget.pairCount, (i) => i)..shuffle();
    _pieceDrawerPos = List.filled(widget.pairCount, 0);
    for (var j = 0; j < widget.pairCount; j++) {
      _pieceDrawerPos[order[j]] = j;
    }
    _slotKeys.addAll([for (var i = 0; i < widget.pairCount; i++) GlobalKey()]);
    _pieceKeys.addAll([for (var i = 0; i < widget.pairCount; i++) GlobalKey()]);
    _pos.addAll([for (var i = 0; i < widget.pairCount; i++) null]);
    _placed.addAll([for (var i = 0; i < widget.pairCount; i++) false]);
  }

  bool _moved = false;

  void _onPanStart(int index, Offset globalPosition) {
    if (!_moved) {
      _moved = true;
      widget.onFirstMove?.call();
    }
    if (_done) return;
    // Grab the piece where it currently is — even if it is still sliding
    // back to the drawer — so re-grabbing never makes it jump.
    Offset start;
    final box =
        _pieceKeys[index].currentContext?.findRenderObject() as RenderBox?;
    if (box != null && _pos[index] == null) {
      final stackBox =
          _stackKey.currentContext!.findRenderObject()! as RenderBox;
      start = stackBox.globalToLocal(box.localToGlobal(Offset.zero));
    } else {
      start = _pos[index] ?? _drawerPositions[_pieceDrawerPos[index]];
    }
    setState(() {
      _dragIndex = index;
      _dragStart = globalPosition;
      _pieceStart = start;
      _pos[index] = start;
    });
    HapticFeedback.selectionClick();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final index = _dragIndex;
    if (index == null) return;
    setState(() {
      _pos[index] = _pieceStart + (details.globalPosition - _dragStart);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    final index = _dragIndex;
    if (index == null) return;
    _dragIndex = null;

    final stackBox = _stackKey.currentContext!.findRenderObject()! as RenderBox;
    final pieceCenter = stackBox.localToGlobal(
      _pos[index]! + Offset(_pieceSize / 2, _pieceSize / 2),
    );

    // Snap if the piece is close enough to its own slot.
    final slotBox =
        _slotKeys[index].currentContext?.findRenderObject() as RenderBox?;
    if (slotBox != null) {
      final slotCenter = slotBox.localToGlobal(
        slotBox.size.center(Offset.zero),
      );
      if ((pieceCenter - slotCenter).distance <
          _slotSize * widget.snapTolerance) {
        setState(() {
          _placed[index] = true;
          _pos[index] = stackBox.globalToLocal(
            slotCenter - Offset(_pieceSize / 2, _pieceSize / 2),
          );
        });
        HapticFeedback.mediumImpact();
        if (_placed.every((p) => p)) {
          Future.delayed(const Duration(milliseconds: 100), () {
            if (!mounted) return;
            _done = true;
            widget.onCompleted();
          });
        }
        return;
      }
    }

    // No slot nearby: back to the drawer instantly (never animate the return
    // — an animated slide-back is what reads as a "trail" on screen).
    setState(() => _pos[index] = null);
    HapticFeedback.lightImpact();
  }

  /// A drag that got interrupted (system gesture, second finger, …): put the
  /// piece back so it is never left stranded mid-screen.
  void _cancelDrag() {
    final index = _dragIndex;
    if (index == null) return;
    setState(() {
      _dragIndex = null;
      _pos[index] = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final W = constraints.maxWidth;
        final H = constraints.maxHeight;
        final boardRows =
            (widget.pairCount + widget.maxCols - 1) ~/ widget.maxCols;

        double slotSize = math.min(
          math.min((W - 32) / widget.maxCols, (H * 0.52) / boardRows),
          140.0,
        );
        var pieceSize = math.min(
          slotSize * widget.pieceScale,
          widget.pieceSizeCap,
        );
        final drawerRows =
            (widget.pairCount + widget.maxCols - 1) ~/ widget.maxCols;
        var drawerHeight =
            drawerRows * pieceSize + (drawerRows - 1) * widget.gap + 20;
        final boardHeight = boardRows * slotSize + (boardRows - 1) * widget.gap;
        // Shrink everything if the board + drawer would overflow the screen.
        final total = 16 + boardHeight + 16 + drawerHeight + 12;
        if (total > H) {
          final shrink = (H - 28) / (boardHeight + drawerHeight);
          slotSize *= shrink;
          pieceSize = math.min(
            slotSize * widget.pieceScale,
            widget.pieceSizeCap,
          );
          drawerHeight =
              drawerRows * pieceSize + (drawerRows - 1) * widget.gap + 20;
        }
        _slotSize = slotSize;
        _pieceSize = pieceSize;

        final boardWidth =
            widget.maxCols * slotSize + (widget.maxCols - 1) * widget.gap;
        final boardLeft = (W - boardWidth) / 2;
        final boardTop = 16.0;
        final drawerTop = H - drawerHeight - 12;

        _slotPositions = [
          for (var i = 0; i < widget.pairCount; i++)
            Offset(
              boardLeft + (i % widget.maxCols) * (slotSize + widget.gap),
              boardTop + (i ~/ widget.maxCols) * (slotSize + widget.gap),
            ),
        ];
        final drawerRowWidth =
            widget.maxCols * pieceSize + (widget.maxCols - 1) * widget.gap;
        final drawerLeft = (W - drawerRowWidth) / 2;
        _drawerPositions = [
          for (var i = 0; i < widget.pairCount; i++)
            Offset(
              drawerLeft + (i % widget.maxCols) * (pieceSize + widget.gap),
              drawerTop + 10 + (i ~/ widget.maxCols) * (pieceSize + widget.gap),
            ),
        ];

        return Stack(
          key: _stackKey,
          children: [
            if (widget.boardBackgroundBuilder != null)
              Positioned(
                left: boardLeft,
                top: boardTop,
                width: boardWidth,
                height: boardHeight,
                child: widget.boardBackgroundBuilder!(
                  context,
                  Size(boardWidth, boardHeight),
                ),
              ),
            // Slots.
            for (var i = 0; i < widget.pairCount; i++)
              Positioned(
                left: _slotPositions[i].dx,
                top: _slotPositions[i].dy,
                child: SizedBox(
                  key: _slotKeys[i],
                  width: slotSize,
                  height: slotSize,
                  child: widget.slotBuilder(context, i, slotSize),
                ),
              ),
            // Drawer backdrop.
            Positioned(
              left: 12,
              right: 12,
              top: drawerTop - 6,
              height: drawerHeight + 12,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
            // Unplaced pieces (draggable).
            for (var i = 0; i < widget.pairCount; i++)
              if (!_placed[i]) _buildDraggablePiece(i),
            // Captions for solved slots. They sit in the gap below the slot,
            // which is why a caller that wants them must leave a gap big
            // enough to hold one.
            if (widget.slotCaption != null)
              for (var i = 0; i < widget.pairCount; i++)
                if (_placed[i] && widget.slotCaption!(i) != null)
                  Positioned(
                    left: _slotPositions[i].dx,
                    top: _slotPositions[i].dy + slotSize,
                    width: slotSize,
                    height: widget.gap,
                    child: _SlotCaption(text: widget.slotCaption!(i)!),
                  ),
            // Placed pieces. No scale pop: animating a transform on a piece
            // that contains text re-rasterizes glyphs every frame (lag + can
            // break all emoji rendering), so placement is instant and clean.
            for (var i = 0; i < widget.pairCount; i++)
              if (_placed[i])
                Positioned(
                  left: _pos[i]!.dx,
                  top: _pos[i]!.dy,
                  child: SizedBox(
                    width: _pieceSize,
                    height: _pieceSize,
                    child: widget.pieceBuilder(
                      context,
                      i,
                      _pieceSize,
                      _slotSize,
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }

  Widget _buildDraggablePiece(int index) {
    final pos = _pos[index] ?? _drawerPositions[_pieceDrawerPos[index]];
    // Plain Positioned with instant updates: no animation between states, so
    // only the piece under the finger ever moves. (AnimatedPositioned here was
    // the source of visible "trails".)
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        key: _pieceKeys[index],
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) => _onPanStart(index, d.globalPosition),
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        onPanCancel: _cancelDrag,
        // Caches the static pieces so dragging only repaints the one piece
        // under the finger (the others keep their last painted layer).
        child: RepaintBoundary(
          child: SizedBox(
            width: _pieceSize,
            height: _pieceSize,
            child: widget.pieceBuilder(context, index, _pieceSize, _slotSize),
          ),
        ),
      ),
    );
  }
}

/// The short word shown under a solved slot. Sized to the space it is given
/// rather than to a fixed font size, so it stays inside the board's gap on
/// every screen — a caption that grew past the gap would collide with the
/// next row of slots.
class _SlotCaption extends StatelessWidget {
  const _SlotCaption({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          maxLines: 1,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            shadows: [Shadow(color: Colors.black38, blurRadius: 4)],
          ),
        ),
      ),
    );
  }
}
