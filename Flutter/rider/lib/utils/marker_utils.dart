import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MarkerGenerator {
  /// Generates a professional location marker with a stem (pinpoint).
  static Future<BitmapDescriptor> createDotMarker({
    required Color color,
    double radius = 18,
    double borderWidth = 2,
  }) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    
    // Canvas size needs to accommodate the circle and the stem
    final double stemHeight = 24;
    final double totalWidth = radius * 2.5;
    final double totalHeight = radius * 2.5 + stemHeight;
    final Offset center = Offset(totalWidth / 2, radius * 1.25);

    // 1. Draw shadow for the stem and circle
    final Paint shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    
    final Path shadowPath = Path()
      ..addOval(Rect.fromCircle(center: center.translate(0, 1), radius: radius))
      ..moveTo(center.dx - 1.0, center.dy + radius)
      ..lineTo(center.dx + 1.0, center.dy + radius)
      ..lineTo(center.dx, center.dy + radius + stemHeight + 0.5)
      ..close();
    canvas.drawPath(shadowPath, shadowPaint);

    // 2. Draw the stem (pinpoint line)
    final Paint stemPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
      
    canvas.drawLine(
      Offset(center.dx, center.dy + radius - 1),
      Offset(center.dx, center.dy + radius + stemHeight),
      stemPaint
    );

    // 3. Draw thin white outer border circle
    final Paint borderPaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, radius, borderPaint);

    // 4. Draw hollow colored circle (the ring)
    final Paint ringPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius - borderWidth, ringPaint);

    // 5. Draw white center dot
    final Paint centerDotPaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, radius * 0.4, centerDotPaint);

    final ui.Image image = await pictureRecorder.endRecording().toImage(
          totalWidth.toInt(),
          totalHeight.toInt(),
        );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(data!.buffer.asUint8List());
  }

  /// Generates a white pill label with text and a pencil icon.
  static Future<BitmapDescriptor> createLabelMarker({
    required String text,
    required bool isPickup,
  }) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);

    const double padding = 10.0;
    const double iconSize = 16.0;
    const double fontSize = 14.0;
    const double borderRadius = 20.0;

    // Measure text
    final textPainter = TextPainter(
      text: TextSpan(
        text: text.length > 25 ? '${text.substring(0, 22)}...' : text,
        style: const TextStyle(
          color: Colors.black,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          fontFamily: 'Inter',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final double width = textPainter.width + iconSize + (padding * 2.5);
    final double height = textPainter.height + (padding * 1.5);

    // Draw shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(2, 2, width, height),
        const Radius.circular(borderRadius),
      ),
      shadowPaint,
    );

    // Draw pill background
    final bgPaint = Paint()..color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, width, height),
        const Radius.circular(borderRadius),
      ),
      bgPaint,
    );

    // Draw text
    textPainter.paint(canvas, const Offset(padding, padding * 0.75));

    // Draw edit icon (pencil)
    final iconX = width - padding - iconSize;
    final iconY = height / 2 - iconSize / 2;

    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.edit.codePoint),
        style: TextStyle(
          fontSize: iconSize,
          fontFamily: Icons.edit.fontFamily,
          color: Colors.black,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    iconPainter.layout();
    iconPainter.paint(canvas, Offset(iconX, iconY));

    final ui.Image image = await pictureRecorder.endRecording().toImage(
          (width + 4).toInt(),
          (height + 4).toInt(),
        );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(data!.buffer.asUint8List());
  }
}
