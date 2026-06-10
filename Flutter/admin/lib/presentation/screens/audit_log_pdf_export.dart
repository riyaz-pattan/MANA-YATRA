import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuditLogPdfExport {
  static Future<void> generateAndPrint(List<Map<String, dynamic>> logs) async {
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
                  pw.Text('Audit Log Report', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 14)),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Table.fromTextArray(
              headers: ['Timestamp', 'Action', 'Target ID', 'Performed By', 'Role', 'Details'],
              data: logs.map((log) {
                final action = (log['action'] ?? 'Unknown').toString().toUpperCase();
                final targetId = (log['targetUid'] ?? log['targetId'] ?? '').toString();
                final performedBy = (log['performedBy'] ?? 'System').toString();
                final role = (log['performedByRole'] ?? '').toString();
                final details = (log['details'] ?? '').toString();
                
                final timestamp = log['timestamp'] as Timestamp?;
                final dateStr = timestamp != null ? DateFormat('MMM d, yyyy h:mm a').format(timestamp.toDate()) : 'N/A';

                return [dateStr, action, targetId, performedBy, role, details];
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.teal800),
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
      name: 'Audit_Logs_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }
}
