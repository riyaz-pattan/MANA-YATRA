import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapUtils {
  static Future<BitmapDescriptor> getBytesFromAsset(String path, int width) async {
    ByteData data = await rootBundle.load(path);
    ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: width);
    ui.FrameInfo fi = await codec.getNextFrame();
    final bytes = (await fi.image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    return BitmapDescriptor.bytes(bytes);
  }

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

  /// Creates a text label marker (e.g. "Driver is here")
  static Future<BitmapDescriptor> createLabelMarker(String text) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final Paint paint = Paint()..color = Colors.black87;

    final TextPainter textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    textPainter.text = TextSpan(
      text: text,
      style: const TextStyle(
        fontSize: 20.0,
        color: Colors.white,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    );
    textPainter.layout();

    final double padding = 12.0;
    final double textWidth = textPainter.width;
    final double textHeight = textPainter.height;

    final double width = textWidth + padding * 2;
    final double height = textHeight + padding * 2;
    final double triangleHeight = 10.0;

    final RRect rRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, width, height),
      const Radius.circular(8.0),
    );
    canvas.drawRRect(rRect, paint);

    final Path path = Path();
    path.moveTo(width / 2 - 8, height);
    path.lineTo(width / 2, height + triangleHeight);
    path.lineTo(width / 2 + 8, height);
    path.close();
    canvas.drawPath(path, paint);

    textPainter.paint(canvas, Offset(padding, padding));

    final ui.Image image = await pictureRecorder.endRecording().toImage(
      width.toInt(),
      (height + triangleHeight).toInt(),
    );

    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  /// Creates a person icon marker (for rider location)
  static Future<BitmapDescriptor> createPersonMarker() async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);

    final double size = 70.0;

    final Paint outerPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2, outerPaint);

    final Paint innerPaint = Paint()..color = const Color(0xFF2563EB);
    canvas.drawCircle(Offset(size / 2, size / 2), (size / 2) - 4, innerPaint);

    final TextPainter textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: String.fromCharCode(Icons.person.codePoint),
      style: TextStyle(
        fontSize: size * 0.6,
        fontFamily: Icons.person.fontFamily,
        package: Icons.person.fontPackage,
        color: Colors.white,
      ),
    );
    textPainter.layout();

    textPainter.paint(
      canvas,
      Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2),
    );

    final ui.Image image = await pictureRecorder.endRecording().toImage(size.toInt(), size.toInt());
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  /// Creates a location marker for the rider on the driver's map.
  /// Draws a teardrop pin with a person icon inside, attached to a 'Rider is here' label.
  static Future<BitmapDescriptor> createRiderLocationMarker() async {
    const Color pinColor = Color(0xFFEA4335); // Google Red for high visibility
    const String label = 'Rider is here';

    final double scale = 1.0;
    const double pinRadius = 18.0;
    const double pinHeight = 46.0;
    const double pillHeight = 26.0;
    const double pillPadding = 8.0;

    final TextPainter labelTP = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        ),
      )
      ..layout();

    final double pillWidth = labelTP.width + pillPadding * 2;
    const double effectivePad = 8.0;
    final double canvasW = (pinRadius * 2 + pillWidth + 8 + effectivePad * 2) * scale;
    final double canvasH = (pinHeight + effectivePad * 2) * scale;

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    canvas.scale(scale);

    final double cx = effectivePad + pinRadius;
    final double cy = effectivePad + pinRadius;

    final Paint shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    // Pin shape
    final Path pinPath = Path();
    pinPath.moveTo(cx - pinRadius * 0.866, cy + pinRadius * 0.5);
    pinPath.lineTo(cx, cy + pinHeight - pinRadius);
    pinPath.lineTo(cx + pinRadius * 0.866, cy + pinRadius * 0.5);
    pinPath.close();

    // Shadow
    canvas.drawCircle(Offset(cx, cy), pinRadius, shadowPaint);
    canvas.drawPath(pinPath, shadowPaint);

    final double pillX = cx + pinRadius + 6;
    final double pillY = cy - pillHeight / 2;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pillX, pillY, pillWidth, pillHeight),
        const Radius.circular(pillHeight / 2),
      ),
      shadowPaint,
    );

    // Draw Pin
    final Paint pinPaint = Paint()..color = pinColor;
    canvas.drawCircle(Offset(cx, cy), pinRadius, pinPaint);
    canvas.drawPath(pinPath, pinPaint);

    // White hollow circle inside pin
    canvas.drawCircle(Offset(cx, cy), pinRadius * 0.6, Paint()..color = Colors.white);

    // Draw person icon inside
    final TextPainter iconTP = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(Icons.person.codePoint),
        style: TextStyle(
          fontSize: 20,
          fontFamily: Icons.person.fontFamily,
          package: Icons.person.fontPackage,
          color: pinColor,
        ),
      )
      ..layout();

    iconTP.paint(
      canvas,
      Offset(cx - iconTP.width / 2, cy - iconTP.height / 2),
    );

    // Draw Pill
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pillX, pillY, pillWidth, pillHeight),
        const Radius.circular(pillHeight / 2),
      ),
      Paint()..color = Colors.white,
    );

    labelTP.paint(
      canvas,
      Offset(
        pillX + (pillWidth - labelTP.width) / 2,
        pillY + (pillHeight - labelTP.height) / 2,
      ),
    );

    final ui.Image img = await recorder.endRecording().toImage(canvasW.ceil(), canvasH.ceil());
    final ByteData? bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  /// Creates a premium fare-bubble map marker for a ride request.
  ///
  /// Draws a bold ₹<fare> pill with a numbered badge in the top-right corner.
  /// When [isActive] is true, the pill glows with a pulse ring — this
  /// corresponds to the card currently centred in the snap carousel.
  ///
  /// [index]    1-based position (shown in the badge)
  /// [fare]     rider's offered fare in ₹
  /// [isActive] whether this is the focused/centred card
  static Future<BitmapDescriptor> createFareBubbleMarker({
    required int index,
    required int fare,
    required bool isActive,
  }) async {
    // ── Colours ──────────────────────────────────────────────────────
    const Color activeColor = Color(0xFFEA4335); // Google red
    const Color inactiveColor = Color(0xFF9CA3AF); // muted grey
    final Color pinColor = isActive ? activeColor : inactiveColor;

    // ── Dimensions ───────────────────────────────────────────────────
    final double scale = isActive ? 1.0 : 0.85;
    const double pinRadius = 18.0;
    const double pinHeight = 46.0; // Total height of the teardrop pin
    const double pillHeight = 26.0;
    const double pillPadding = 8.0;

    // ── Fare text layout ──────────────────────────────────────────────
    final TextPainter fareTP = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: '₹$fare',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: isActive ? Colors.black87 : Colors.black54,
        ),
      )
      ..layout();

    final double pillWidth = fareTP.width + pillPadding * 2;

    // ── Canvas setup ──────────────────────────────────────────────────
    final double effectivePad = 8.0; // padding for drop shadow
    final double canvasW = (pinRadius * 2 + pillWidth + 8 + effectivePad * 2) * scale;
    final double canvasH = (pinHeight + effectivePad * 2) * scale;

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    canvas.scale(scale);

    final double cx = effectivePad + pinRadius;
    final double cy = effectivePad + pinRadius;

    // ── Drop shadow ───────────────────────────────────────────────────
    final Paint shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    // Pin shape
    final Path pinPath = Path();
    pinPath.moveTo(cx - pinRadius * 0.866, cy + pinRadius * 0.5);
    pinPath.lineTo(cx, cy + pinHeight - pinRadius); // Bottom Tip
    pinPath.lineTo(cx + pinRadius * 0.866, cy + pinRadius * 0.5);
    pinPath.close();

    // Draw Pin Shadow
    canvas.drawCircle(Offset(cx, cy), pinRadius, shadowPaint);
    canvas.drawPath(pinPath, shadowPaint);

    // ── Pill shadow ───────────────────────────────────────────────────
    final double pillX = cx + pinRadius + 6;
    final double pillY = cy - pillHeight / 2;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pillX, pillY, pillWidth, pillHeight),
        const Radius.circular(pillHeight / 2),
      ),
      shadowPaint,
    );

    // ── Draw Pin ──────────────────────────────────────────────────────
    final Paint pinPaint = Paint()..color = pinColor;
    canvas.drawCircle(Offset(cx, cy), pinRadius, pinPaint);
    canvas.drawPath(pinPath, pinPaint);

    // White hollow circle inside pin
    canvas.drawCircle(Offset(cx, cy), pinRadius * 0.4, Paint()..color = Colors.white);

    // ── Draw Fare Pill ────────────────────────────────────────────────
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pillX, pillY, pillWidth, pillHeight),
        const Radius.circular(pillHeight / 2),
      ),
      Paint()..color = Colors.white,
    );

    fareTP.paint(
      canvas,
      Offset(
        pillX + (pillWidth - fareTP.width) / 2,
        pillY + (pillHeight - fareTP.height) / 2,
      ),
    );
    // ── Render ────────────────────────────────────────────────────────
    final ui.Image img = await recorder
        .endRecording()
        .toImage(canvasW.ceil(), canvasH.ceil());
    final ByteData? bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }
}
