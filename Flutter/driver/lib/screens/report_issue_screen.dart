import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/custom_toast.dart';

class ReportIssueScreen extends StatefulWidget {
  final String? initialRideId;
  const ReportIssueScreen({super.key, this.initialRideId});

  @override
  State<ReportIssueScreen> createState() => _ReportIssueScreenState();
}

class _ReportIssueScreenState extends State<ReportIssueScreen> {
  final _subjectCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _category = 'Payout Issue';
  bool _isLoading = false;
  String? _selectedRideId;
  List<Map<String, dynamic>> _recentRides = [];
  bool _isLoadingRides = false;

  final categories = [
    'Payout Issue',
    'Rider Behavior',
    'Navigation Issue',
    'App Bug',
    'Other'
  ];

  @override
  void initState() {
    super.initState();
    _selectedRideId = widget.initialRideId;
    _loadRecentRides();
  }

  Future<void> _loadRecentRides() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoadingRides = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('rides')
          .where('driverId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get();
      
      final rides = snap.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
      
      if (widget.initialRideId != null && !rides.any((r) => r['id'] == widget.initialRideId)) {
        rides.insert(0, {
          'id': widget.initialRideId,
          'createdAt': Timestamp.now(),
          'pickup': {'short_name': 'Selected Ride'}
        });
      }

      if (mounted) {
        setState(() {
          _recentRides = rides;
          _isLoadingRides = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingRides = false);
    }
  }

  String _formatDate(DateTime dt) {
    return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  Future<void> _submitTicket() async {
    if (_subjectCtrl.text.trim().isEmpty || _descCtrl.text.trim().isEmpty) {
      CustomToast.show(context: context, message: 'Please fill all fields', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      String name = 'Unknown Driver';
      String phone = '';

      if (user != null) {
        final doc = await FirebaseFirestore.instance.collection('drivers').doc(user.uid).get();
        if (doc.exists) {
          name = doc.data()?['name'] ?? 'Unknown Driver';
          phone = doc.data()?['phone'] ?? '';
        }
      }

      final isRideRelated = ['Payout Issue', 'Rider Behavior', 'Navigation Issue'].contains(_category);

      await FirebaseFirestore.instance.collection('support_tickets').add({
        'role': 'driver',
        'name': name,
        'phone': phone,
        'uid': user?.uid ?? '',
        'category': _category,
        'rideId': isRideRelated ? _selectedRideId : null,
        'subject': _subjectCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'status': 'open',
        'priority': 'medium',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context);
        CustomToast.show(context: context, message: 'Issue reported successfully. Support will contact you.');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      CustomToast.show(context: context, message: 'Failed to submit: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRideRelated = ['Payout Issue', 'Rider Behavior', 'Navigation Issue'].contains(_category);

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        title: Text('Report an Issue', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppTheme.text)),
        iconTheme: const IconThemeData(color: AppTheme.text),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Driver Support', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.text)),
            const SizedBox(height: 24),
            Text('Category', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _category = val);
              },
            ),
            if (isRideRelated) ...[
              const SizedBox(height: 24),
              Text('Select Ride', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (_isLoadingRides)
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                )
              else if (_recentRides.isEmpty)
                Text('No recent rides found.', style: GoogleFonts.inter(color: AppTheme.text2))
              else
                DropdownButtonFormField<String>(
                  value: _selectedRideId,
                  hint: Text('Select a past ride', style: GoogleFonts.inter(color: AppTheme.text3)),
                  isExpanded: true,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppTheme.bg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  items: _recentRides.map((r) {
                    final date = r['createdAt'] != null ? _formatDate((r['createdAt'] as Timestamp).toDate()) : '';
                    final p = r['pickup'] != null ? (r['pickup']['short_name'] ?? 'Unknown') : 'Unknown';
                    return DropdownMenuItem<String>(
                      value: r['id'],
                      child: Text('$date - $p', overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 14)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedRideId = val);
                  },
                ),
            ],
            const SizedBox(height: 24),
            Text('Subject', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _subjectCtrl,
              decoration: InputDecoration(
                hintText: 'Briefly describe the issue',
                filled: true,
                fillColor: AppTheme.bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 24),
            Text('Details', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _descCtrl,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: 'Provide as much detail as possible...',
                filled: true,
                fillColor: AppTheme.bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submitTicket,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text('Submit Ticket', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
