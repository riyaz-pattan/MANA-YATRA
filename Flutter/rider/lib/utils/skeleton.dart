// lib/utils/skeleton.dart
// Pure-Dart animated shimmer skeleton — no external package needed.

import 'package:flutter/material.dart';

class SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE8E8E8);
    final shimmerColor =
        isDark ? const Color(0xFF3D3D3D) : const Color(0xFFF5F5F5);

    return AnimatedBuilder(
      animation: _animation,
      builder: (_, __) => ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(_animation.value - 1, 0),
                end: Alignment(_animation.value + 1, 0),
                colors: [baseColor, shimmerColor, baseColor],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A skeleton card that mimics the bid card layout.
class BidCardSkeleton extends StatelessWidget {
  const BidCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top label bar
          const SkeletonBox(height: 32, borderRadius: 10),
          const SizedBox(height: 12),
          Row(
            children: [
              // Avatar
              const SkeletonBox(width: 48, height: 48, borderRadius: 14),
              const SizedBox(width: 14),
              // Name + vehicle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonBox(height: 14, borderRadius: 6),
                    SizedBox(height: 6),
                    SkeletonBox(width: 100, height: 12, borderRadius: 6),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Price
              const SkeletonBox(width: 60, height: 28, borderRadius: 8),
            ],
          ),
          const SizedBox(height: 12),
          // ETA row
          const SkeletonBox(height: 36, borderRadius: 10),
          const SizedBox(height: 12),
          // Buttons row
          Row(
            children: const [
              Expanded(child: SkeletonBox(height: 44, borderRadius: 12)),
              SizedBox(width: 12),
              Expanded(child: SkeletonBox(height: 44, borderRadius: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

/// A skeleton for the route confirmation bottom panel.
class RoutePanelSkeleton extends StatelessWidget {
  const RoutePanelSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        SkeletonBox(height: 18, borderRadius: 6),
        SizedBox(height: 10),
        SkeletonBox(height: 56, borderRadius: 14),
        SizedBox(height: 14),
        Row(children: [
          Expanded(child: SkeletonBox(height: 48, borderRadius: 12)),
          SizedBox(width: 12),
          Expanded(child: SkeletonBox(height: 48, borderRadius: 12)),
        ]),
        SizedBox(height: 14),
        SkeletonBox(height: 52, borderRadius: 14),
      ],
    );
  }
}
