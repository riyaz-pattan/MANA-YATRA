// lib/widgets/swipe_action.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SwipeAction extends StatefulWidget {
  final String text;
  final VoidCallback onSwipe;
  final Color baseColor;
  final Color activeColor;

  const SwipeAction({
    super.key,
    required this.text,
    required this.onSwipe,
    required this.baseColor,
    required this.activeColor,
  });

  @override
  State<SwipeAction> createState() => _SwipeActionState();
}

class _SwipeActionState extends State<SwipeAction> {
  double _dragProgress = 0.0;
  bool _completed = false;
  
  void _onHorizontalDragUpdate(DragUpdateDetails details, double maxWidth) {
    if (_completed) return;
    setState(() {
      _dragProgress += details.delta.dx / (maxWidth - 56);
      if (_dragProgress < 0.0) _dragProgress = 0.0;
      if (_dragProgress >= 1.0) {
        _dragProgress = 1.0;
        _completed = true;
        widget.onSwipe();
      }
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (!_completed) {
      setState(() => _dragProgress = 0.0); // Reset if not fully swiped
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final handleWidth = 56.0;
        final dragOffset = _dragProgress * (maxWidth - handleWidth);

        return Container(
          height: 56,
          decoration: BoxDecoration(
            color: widget.baseColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: widget.baseColor.withValues(alpha: 0.3)),
          ),
          child: Stack(
            children: [
              // Overlay as you swipe
              if (_dragProgress > 0)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: dragOffset + handleWidth - 8,
                  child: Container(
                    decoration: BoxDecoration(
                      color: widget.activeColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              // Background Text
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: Text(
                    widget.text,
                    style: GoogleFonts.inter(
                      color: widget.baseColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              // Draggable Handle
              Positioned(
                left: dragOffset,
                top: 0,
                bottom: 0,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) => _onHorizontalDragUpdate(details, maxWidth),
                  onHorizontalDragEnd: _onHorizontalDragEnd,
                  child: Container(
                    width: handleWidth,
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: widget.activeColor,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: widget.activeColor.withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
