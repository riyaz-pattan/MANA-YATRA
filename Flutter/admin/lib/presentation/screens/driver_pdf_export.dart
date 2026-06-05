import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class DriverPdfExport {
  static Future<void> generateAndPrint(List<Map<String, dynamic>> drivers) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Driver Export Report', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Date: ${DateTime.now().toString().split(' ')[0]}', style: const pw.TextStyle(fontSize: 14)),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Table.fromTextArray(
              headers: ['Name', 'Phone', 'Vehicle', 'Status', 'Rides', 'Earnings'],
              data: drivers.map((d) {
                final name = d['name'] ?? 'Unknown';
                final phone = d['phone'] ?? 'No Phone';
                final vehicle = (d['vehicleType'] ?? 'auto').toString().toUpperCase();
                
                final isAppr = d['isApproved'] == true || d['isApproved'] == 'true';
                final isBlk = d['isBlocked'] == true || d['isBlocked'] == 'true';
                String status = 'Pending';
                if (isBlk) status = 'Blocked';
                else if (isAppr) status = 'Approved';

                final rides = (d['totalAssignedRides'] ?? 0).toString();
                final earnings = 'Rs. ${d['totalEarnings'] ?? 0}';

                return [name, phone, vehicle, status, rides, earnings];
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
      name: 'Driver_Export_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }
}
