import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PdfGenerator {
  static Future<void> generateAndPrintReceipt(Map<String, dynamic> ride) async {
    final pdf = pw.Document();

    final pickup = ride['pickup'] != null ? (ride['pickup']['display_name'] ?? ride['pickup']['short_name'] ?? 'Unknown Pickup') : 'Unknown Pickup';
    final dropoff = ride['drop'] != null ? (ride['drop']['display_name'] ?? ride['drop']['short_name'] ?? 'Unknown Dropoff') : 'Unknown Dropoff';
    final fare = ride['finalPrice']?.toString() ?? '0';
    final timestamp = (ride['completedAt'] ?? ride['createdAt']) as Timestamp?;
    final date = timestamp != null ? DateFormat('dd MMM yyyy, hh:mm a').format(timestamp.toDate()) : 'Unknown Date';
    final distance = ride['distanceKm']?.toStringAsFixed(1) ?? '0.0';
    final duration = ride['durationMin']?.toString() ?? '0';
    final driverName = ride['driverName'] ?? 'Unknown Driver';
    final vehicleNumber = ride['vehicleNumber'] ?? '';
    final rideId = ride['id'] ?? 'N/A';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(32),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('MANA YATRA', style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold, color: PdfColors.teal)),
                        pw.SizedBox(height: 4),
                        pw.Text('Ride Receipt', style: const pw.TextStyle(fontSize: 16, color: PdfColors.grey700)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Date: $date', style: const pw.TextStyle(fontSize: 12)),
                        pw.Text('Ride ID: $rideId', style: const pw.TextStyle(fontSize: 12)),
                      ],
                    ),
                  ],
                ),
                pw.Divider(height: 32, thickness: 1, color: PdfColors.grey400),
                pw.SizedBox(height: 16),
                pw.Text('Trip Details', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 12),
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Pickup: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.teal)),
                          pw.Expanded(child: pw.Text(pickup)),
                        ],
                      ),
                      pw.SizedBox(height: 12),
                      pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Drop: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.red)),
                          pw.Expanded(child: pw.Text(dropoff)),
                        ],
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 24),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _buildInfoBox('Distance', '$distance km'),
                    _buildInfoBox('Duration', '$duration min'),
                    _buildInfoBox('Driver', driverName),
                    _buildInfoBox('Vehicle', vehicleNumber),
                  ],
                ),
                pw.SizedBox(height: 32),
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8))),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Total Fare Paid', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Rs. $fare', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.teal)),
                    ],
                  ),
                ),
                pw.Spacer(),
                pw.Divider(height: 32, thickness: 1, color: PdfColors.grey400),
                pw.Center(
                  child: pw.Text('Thank you for riding with Mana Yatra!', style: const pw.TextStyle(fontSize: 14, color: PdfColors.grey600)),
                ),
                pw.SizedBox(height: 8),
                pw.Center(
                  child: pw.Text('Zero Commission. 100% Transparent.', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.teal)),
                ),
              ],
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'ManaYatra_Receipt_$rideId.pdf',
    );
  }

  static pw.Widget _buildInfoBox(String title, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title, style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey600)),
        pw.SizedBox(height: 4),
        pw.Text(value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }
}
