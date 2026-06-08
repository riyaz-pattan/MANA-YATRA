import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RidePdfExport {
  static Future<void> generateAndPrint(List<Map<String, dynamic>> rides, List<String> ids) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Ride Export Report', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Date: ${DateTime.now().toString().split(' ')[0]}', style: const pw.TextStyle(fontSize: 14)),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              headers: ['Ride ID', 'Date & Time', 'Rider / Driver', 'Pickup / Drop', 'Status', 'Fare'],
              data: rides.asMap().entries.map((entry) {
                final idx = entry.key;
                final d = entry.value;
                final id = ids[idx];

                final createdAt = d['createdAt'] as Timestamp?;
                final dateStr = createdAt != null 
                    ? DateFormat('MMM dd, HH:mm').format(createdAt.toDate())
                    : 'Unknown';
                
                final driverName = d['driverName'] ?? 'No Driver';
                final riderId = (d['riderId'] ?? '').toString();
                final riderStr = riderId.length > 4 ? riderId.substring(riderId.length - 4) : riderId;
                
                final pickup = d['pickup']?['short_name'] ?? 'Unknown';
                final drop = d['drop']?['short_name'] ?? 'Unknown';
                
                final status = d['status'] ?? 'unknown';
                final fare = d['finalPrice']?.toString() ?? '-';

                return [
                  id.substring(0, 8).toUpperCase(),
                  dateStr,
                  'D: $driverName\nR: ...$riderStr',
                  'P: $pickup\nD: $drop',
                  status.toUpperCase(),
                  status == 'completed' ? 'INR $fare' : 'INR 0',
                ];
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blue800),
              rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300))),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.all(8),
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Ride_Export_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }
}
