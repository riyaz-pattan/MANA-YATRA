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
    
    // Draw rounded rect
    final RRect rRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, width, height),
      const Radius.circular(8.0),
    );
    canvas.drawRRect(rRect, paint);
    
    // Draw triangle at bottom center
    final Path path = Path();
    path.moveTo(width / 2 - 8, height);
    path.lineTo(width / 2, height + triangleHeight);
    path.lineTo(width / 2 + 8, height);
    path.close();
    canvas.drawPath(path, paint);
    
    // Draw text
    textPainter.paint(canvas, Offset(padding, padding));
    
    // Convert to Image
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
    
    // Draw outer white circle
    final Paint outerPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2, outerPaint);
    
    // Draw inner primary-color circle
    final Paint innerPaint = Paint()..color = const Color(0xFF2563EB); 
    canvas.drawCircle(Offset(size / 2, size / 2), (size / 2) - 4, innerPaint);
    
    // Draw Person Icon using TextPainter
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
      Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2)
    );
    
    final ui.Image image = await pictureRecorder.endRecording().toImage(size.toInt(), size.toInt());
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  /// Creates a stickman marker for the rider's location on the driver's map.
  /// Shows a classic stick-figure person standing on a green circular base.
  static Future<BitmapDescriptor> createStickmanMarker() async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);

    const double w = 80.0;
    const double h = 100.0;
    final cx = w / 2;

    final Paint greenPaint = Paint()
      ..color = const Color(0xFF10B981) // success green
      ..style = PaintingStyle.fill;

    final Paint whitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final Paint whiteFill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // --- Base circle ---
    canvas.drawCircle(Offset(cx, h - 16), 16, greenPaint);

    // --- Stickman body proportions ---
    const double headR = 10.0;
    const double headY = 18.0;
    const double neckY = headY + headR;
    const double bodyLen = 22.0;
    const double hipY = neckY + bodyLen;
    const double legLen = 20.0;

    // Head
    canvas.drawCircle(Offset(cx, headY), headR, whiteFill);
    // Neck / body
    canvas.drawLine(Offset(cx, neckY), Offset(cx, hipY), whitePaint);
    // Arms
    canvas.drawLine(Offset(cx - 14, neckY + 6), Offset(cx + 14, neckY + 6), whitePaint);
    // Left leg
    canvas.drawLine(Offset(cx, hipY), Offset(cx - 10, hipY + legLen), whitePaint);
    // Right leg
    canvas.drawLine(Offset(cx, hipY), Offset(cx + 10, hipY + legLen), whitePaint);

    final ui.Image image = await recorder.endRecording().toImage(w.toInt(), h.toInt());
    final ByteData? bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }
}
