import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';

class MovingVehicleLoader extends StatefulWidget {
  final String text;

  const MovingVehicleLoader({
    super.key,
    this.text = 'Getting your location...',
  });

  @override
  State<MovingVehicleLoader> createState() => _MovingVehicleLoaderState();
}

class _MovingVehicleLoaderState extends State<MovingVehicleLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  late Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _animation = Tween<double>(begin: -1.2, end: 1.2).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.linear, // Constant speed
      ),
    );

    // subtle bounce for a driving effect
    _bounceAnimation = Tween<double>(begin: 0.0, end: -4.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeInOut),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 150,
          height: 50,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Road
              Positioned(
                bottom: 8,
                left: 10,
                right: 10,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              // Moving Vehicle
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Align(
                    alignment: Alignment(_animation.value, 0.0),
                    child: Transform.translate(
                      offset: Offset(
                          0,
                          _bounceAnimation.value *
                              (_controller.value > 0.5 ? -1 : 1)), // Bounce effect
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary.withValues(alpha: 0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.electric_rickshaw,
                          color: AppTheme.primary,
                          size: 28,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          widget.text,
          style: GoogleFonts.inter(
            color: AppTheme.text2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
