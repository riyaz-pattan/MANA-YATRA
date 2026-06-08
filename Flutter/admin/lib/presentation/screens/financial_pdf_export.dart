import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

class FinancialPdfExport {
  static Future<void> generateAndPrint(List<Map<String, dynamic>> transactions) async {
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
                  pw.Text('Financial Export Report', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Date: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 14)),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Table.fromTextArray(
              headers: ['Transaction ID', 'Date', 'Type', 'Method', 'Status', 'Amount'],
              data: transactions.map((t) {
                final id = (t['id'] as String? ?? 'Unknown').toUpperCase();
                final shortId = id.length > 10 ? id.substring(0, 10) : id;
                
                final createdAt = t['createdAt'];
                String dateStr = 'Unknown';
                if (createdAt != null) {
                  // createdAt could be Timestamp from firestore or DateTime. 
                  // In the export function, we'll pass DateTime objects
                  if (createdAt is DateTime) {
                    dateStr = DateFormat('MMM dd, yyyy HH:mm').format(createdAt);
                  }
                }
                
                final type = 'Subscription';
                final method = t['method'] ?? 'UPI';
                final status = 'SUCCESS';
                final amount = 'Rs. ${(t['amount'] ?? 0).toString()}';

                return [shortId, dateStr, type, method, status, amount];
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
      name: 'Financial_Export_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }
}
