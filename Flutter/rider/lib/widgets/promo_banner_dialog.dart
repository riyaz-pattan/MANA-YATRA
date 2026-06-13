import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/theme.dart';

class PromoBannerDialog extends StatefulWidget {
  final Map<String, dynamic> promoData;

  const PromoBannerDialog({super.key, required this.promoData});

  static Future<void> showIfEligible(BuildContext context, Map<String, dynamic> promoData) async {
    final prefs = await SharedPreferences.getInstance();
    final campaignId = promoData['campaignId']?.toString();
    
    if (campaignId == null) return;

    final hasSeen = prefs.getBool('seen_promo_$campaignId') ?? false;
    if (hasSeen) return;

    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PromoBannerDialog(promoData: promoData),
    );
  }

  @override
  State<PromoBannerDialog> createState() => _PromoBannerDialogState();
}

class _PromoBannerDialogState extends State<PromoBannerDialog> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    final campaignId = widget.promoData['campaignId']?.toString();
    if (campaignId != null) {
      await prefs.setBool('seen_promo_$campaignId', true);
    }
    await _controller.reverse();
    if (mounted) Navigator.pop(context);
  }

  void _onAdClicked() async {
    final actionUrl = widget.promoData['actionUrl'];
    if (actionUrl != null && actionUrl.toString().isNotEmpty) {
      try {
        final url = Uri.parse(actionUrl);
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('Could not launch url: $e');
      }
    }
    _dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.promoData['title'] ?? 'Special Offer';
    final imageUrl = widget.promoData['imageUrl'];

    return ScaleTransition(
      scale: _scaleAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: GestureDetector(
            onTap: _onAdClicked,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 30, offset: const Offset(0, 15))
                ],
              ),
              clipBehavior: Clip.hardEdge,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.2),
                        Colors.white.withValues(alpha: 0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1.5),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Image Section
                      if (imageUrl != null && imageUrl.toString().isNotEmpty)
                        Stack(
                          children: [
                            Image.network(
                              imageUrl,
                              height: 220,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (ctx, err, stack) => Container(
                                height: 120,
                                color: Colors.black12,
                                child: const Center(child: Icon(Icons.image_not_supported, color: Colors.white70)),
                              ),
                            ),
                            // Close Button
                            Positioned(
                              top: 12,
                              right: 12,
                              child: GestureDetector(
                                onTap: () => _dismiss(),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                                  ),
                                  child: const Icon(Icons.close, color: Colors.white, size: 18),
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: IconButton(
                              icon: const Icon(Icons.close, color: Colors.white),
                              onPressed: _dismiss,
                            ),
                          ),
                        ),

                      // Content Section
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Text(
                              title,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                shadows: [
                                  Shadow(color: Colors.black.withValues(alpha: 0.3), offset: const Offset(0, 2), blurRadius: 4),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Tap to view offer',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white.withValues(alpha: 0.9),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 12),
                                ],
                              ),
                            )
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
