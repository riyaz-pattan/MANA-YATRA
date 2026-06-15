// lib/widgets/swipe_action.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _SwipeActionState extends State<SwipeAction> with TickerProviderStateMixin {
  late AnimationController _positionController;
  late AnimationController _shimmerController;
  
  bool _completed = false;
  double _lastHapticValue = 0.0;
  
  @override
  void initState() {
    super.initState();
    _positionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _positionController.addListener(() {
      setState(() {});
      
      // Haptic feedback during drag (every ~10%)
      if (!_completed && _positionController.value - _lastHapticValue > 0.1) {
        HapticFeedback.selectionClick();
        _lastHapticValue = _positionController.value;
      } else if (!_completed && _lastHapticValue - _positionController.value > 0.1) {
        HapticFeedback.selectionClick();
        _lastHapticValue = _positionController.value;
      }
    });

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _positionController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }
  
  void _onHorizontalDragUpdate(DragUpdateDetails details, double maxWidth) {
    if (_completed) return;
    final handleWidth = 56.0;
    _positionController.value += details.delta.dx / (maxWidth - handleWidth);
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_completed) return;
    
    // Forgiving Threshold Snap
    if (_positionController.value > 0.75) {
      _positionController.animateTo(
        1.0, 
        curve: Curves.easeOutBack,
      ).then((_) {
        if (!mounted) return;
        setState(() {
          _completed = true;
        });
        HapticFeedback.heavyImpact();
        widget.onSwipe();
      });
    } else {
      // Advanced Spring Physics when snapping back
      _positionController.animateTo(
        0.0,
        curve: Curves.easeOutBack,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final handleWidth = 56.0;
        final progress = _positionController.value;
        final dragOffset = progress * (maxWidth - handleWidth);

        // Dynamic Color Gradient Morphing
        final trackColor = Color.lerp(
          widget.baseColor.withValues(alpha: 0.1),
          widget.activeColor.withValues(alpha: 0.2),
          progress,
        );
        
        final thumbColor = Color.lerp(
          widget.activeColor,
          widget.activeColor, 
          progress,
        ) ?? widget.activeColor;

        return Container(
          height: 56,
          decoration: BoxDecoration(
            color: trackColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Color.lerp(
                widget.baseColor.withValues(alpha: 0.3),
                widget.activeColor.withValues(alpha: 0.3),
                progress,
              )!,
            ),
          ),
          child: Stack(
            children: [
              // Overlay as you swipe
              if (progress > 0)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: dragOffset + handleWidth - 8,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          widget.activeColor.withValues(alpha: 0.1),
                          widget.activeColor.withValues(alpha: 0.3),
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                
              // Background Text with Micro-Animations
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: Transform.translate(
                    offset: Offset(progress * 30, 0), // Slide right
                    child: Opacity(
                      opacity: (1.0 - (progress * 1.5)).clamp(0.0, 1.0), // Fade out
                      child: AnimatedBuilder(
                        animation: _shimmerController,
                        builder: (context, child) {
                          return ShaderMask(
                            shaderCallback: (bounds) {
                              return LinearGradient(
                                colors: [
                                  widget.baseColor.withValues(alpha: 0.5),
                                  widget.baseColor,
                                  widget.baseColor.withValues(alpha: 0.5),
                                ],
                                stops: const [0.0, 0.5, 1.0],
                                begin: Alignment(-1.0 + (_shimmerController.value * 3), 0),
                                end: Alignment(0.0 + (_shimmerController.value * 3), 0),
                              ).createShader(bounds);
                            },
                            child: child,
                          );
                        },
                        child: Text(
                          widget.text,
                          style: GoogleFonts.inter(
                            color: Colors.white, 
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
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
                      color: thumbColor,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: widget.activeColor.withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, animation) {
                          return ScaleTransition(
                            scale: animation,
                            child: FadeTransition(
                              opacity: animation,
                              child: child,
                            ),
                          );
                        },
                        // Icon morphing based on completion/threshold
                        child: (_completed || progress > 0.95)
                            ? const Icon(
                                Icons.check_rounded,
                                key: ValueKey('check'),
                                color: Colors.white,
                                size: 24,
                              )
                            : const Icon(
                                Icons.arrow_forward_ios_rounded,
                                key: ValueKey('arrow'),
                                color: Colors.white,
                                size: 20,
                              ),
                      ),
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
