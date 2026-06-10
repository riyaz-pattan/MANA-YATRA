import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/audit_log_service.dart';

class DriverProfileScreen extends ConsumerStatefulWidget {
  final String driverId;

  const DriverProfileScreen({super.key, required this.driverId});

  @override
  ConsumerState<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends ConsumerState<DriverProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isEditing = false;
  bool _isSaving = false;

  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _vehicleTypeController;
  late TextEditingController _vehicleNumberController;
  late TextEditingController _upiIdController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _phoneController = TextEditingController();
    _vehicleTypeController = TextEditingController();
    _vehicleNumberController = TextEditingController();
    _upiIdController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _vehicleTypeController.dispose();
    _vehicleNumberController.dispose();
    _upiIdController.dispose();
    super.dispose();
  }

  static const List<String> _rejectionReasons = [
    'Selfie does not match Aadhaar/License photo',
    'Name does not match documents',
    'Documents are blurred or unreadable',
    'Incomplete or missing documents',
    'Vehicle number not clearly visible',
    'Aadhaar card details are invalid',
    'Driving license has expired',
  ];

  void _populateControllers(Map<String, dynamic> data) {
    if (!_isEditing) {
      _nameController.text = data['name'] ?? '';
      _phoneController.text = data['phone'] ?? '';
      _vehicleTypeController.text = data['vehicleType'] ?? '';
      _vehicleNumberController.text = data['vehicleNumber'] ?? '';
      _upiIdController.text = data['upiId'] ?? '';
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final admin = ref.read(adminUserProvider).valueOrNull;
      if (true) {
        await AuditLogService.logAction(
          action: 'updated_driver_profile',
          targetId: widget.driverId,
          admin: admin,
        );
      }
      await FirebaseFirestore.instance.collection('drivers').doc(widget.driverId).update({
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'vehicleType': _vehicleTypeController.text.trim(),
        'vehicleNumber': _vehicleNumberController.text.trim(),
        'upiId': _upiIdController.text.trim(),
      });
      if (mounted) {
        setState(() => _isEditing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully'), backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _updateStatus(bool approve, bool block) async {
    try {
      final Map<String, dynamic> updateData = {
        'isApproved': approve,
        'isBlocked': block,
      };
      
      // If we are approving, clear any previous rejection
      if (approve) {
        updateData['isRejected'] = false;
        updateData['rejectionReason'] = null; // Use FieldValue.delete() if preferred, but null works to clear text
      }

      final admin = ref.read(adminUserProvider).valueOrNull;
      if (true) {
        await AuditLogService.logAction(
          action: 'rejected_driver',
          targetId: widget.driverId,
          admin: admin,
          details: 'Reasons: ${_rejectionReasons.join(", ")}'
        );
      }
      await FirebaseFirestore.instance.collection('drivers').doc(widget.driverId).update(updateData);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Status updated successfully'), backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update status: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  void _showImagePreview(String title, String url) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            alignment: Alignment.center,
            children: [
              InteractiveViewer(
                panEnabled: true,
                minScale: 0.5,
                maxScale: 4.0,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {

                      if (loadingProgress == null) return child;

                      return Container(

                        color: AppTheme.darkSurface,

                        padding: const EdgeInsets.all(32),

                        child: const Center(child: CircularProgressIndicator()),

                      );

                    },
                    errorBuilder: (_, __, ___) => Container(
                      color: AppTheme.darkSurface,
                      padding: const EdgeInsets.all(32),
                      child: const Text('Failed to load image', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 32),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Positioned(
                bottom: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showRejectionSheet(String driverName, bool isDark) {
    List<String> selectedReasons = [];
    final customReasonController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isKeyboardOpen = MediaQuery.of(ctx).viewInsets.bottom > 0;
          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * (isKeyboardOpen ? 0.9 : 0.7),
            ),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Reject Documents', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? AppTheme.darkText : AppTheme.lightText)),
                          const SizedBox(height: 4),
                          Text('Select reasons to notify $driverName', style: GoogleFonts.inter(fontSize: 14, color: isDark ? AppTheme.darkText3 : AppTheme.lightText3)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: isDark ? AppTheme.darkText3 : AppTheme.lightText3),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Reasons List (Scrollable to prevent overflow)
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: _rejectionReasons.map((reason) {
                      final isSelected = selectedReasons.contains(reason);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isSelected 
                              ? AppTheme.brandBlue.withValues(alpha: 0.1) 
                              : (isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? AppTheme.brandBlue : Colors.transparent,
                          ),
                        ),
                        child: CheckboxListTile(
                          title: Text(reason, style: GoogleFonts.inter(fontSize: 14, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500, color: isDark ? AppTheme.darkText : AppTheme.lightText)),
                          value: isSelected,
                          activeColor: AppTheme.brandBlue,
                          checkColor: Colors.white,
                          side: BorderSide(color: isDark ? AppTheme.darkText3 : AppTheme.lightText3),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          onChanged: (val) {
                            setSheetState(() {
                              if (val == true) selectedReasons.add(reason);
                              else selectedReasons.remove(reason);
                            });
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Custom Reason Field
                TextField(
                  controller: customReasonController,
                  decoration: InputDecoration(
                    labelText: 'Other reason (optional)',
                    labelStyle: TextStyle(color: isDark ? AppTheme.darkText3 : AppTheme.lightText3),
                    filled: true,
                    fillColor: isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.brandBlue)),
                  ),
                  style: GoogleFonts.inter(color: isDark ? AppTheme.darkText : AppTheme.lightText),
                ),
                const SizedBox(height: 24),
                
                // Submit Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: selectedReasons.isEmpty && customReasonController.text.trim().isEmpty ? null : () {
                      final reasonStr = selectedReasons.join(', ') + (customReasonController.text.isNotEmpty ? ' - ${customReasonController.text}' : '');
                      final admin = ref.read(adminUserProvider).valueOrNull;
                      if (true) {
                        AuditLogService.logAction(
                          action: 'rejected_driver',
                          targetId: widget.driverId,
                          admin: admin,
                          details: 'Reason: $reasonStr'
                        );
                      }
                      FirebaseFirestore.instance.collection('drivers').doc(widget.driverId).update({
                        'isRejected': true, 
                        'isApproved': false, 
                        'rejectionReason': reasonStr
                      });
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.danger, 
                      disabledBackgroundColor: AppTheme.danger.withValues(alpha: 0.3),
                      foregroundColor: Colors.white, 
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Confirm Rejection', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text2Color = isDark ? AppTheme.darkText2 : AppTheme.lightText2;
    final surfaceColor = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    
    final adminState = ref.watch(adminUserProvider);
    final adminUser = adminState.valueOrNull;
    final isSuperAdmin = adminUser?.role == 'super_admin';

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        backgroundColor: surfaceColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Driver Profile',
          style: GoogleFonts.outfit(color: textColor, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (isSuperAdmin)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _isEditing
                  ? Row(
                      children: [
                        TextButton(
                          onPressed: () => setState(() => _isEditing = false),
                          child: const Text('Cancel', style: TextStyle(color: AppTheme.danger)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _isSaving ? null : _saveChanges,
                          icon: _isSaving
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.save, size: 18),
                          label: const Text('Save'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.brandBlue,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 40),
                          ),
                        ),
                      ],
                    )
                  : ElevatedButton.icon(
                      onPressed: () => setState(() => _isEditing = true),
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Edit Profile'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2,
                        foregroundColor: textColor,
                        minimumSize: const Size(0, 40),
                      ),
                    ),
            ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('drivers').doc(widget.driverId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error loading profile: ${snapshot.error}', style: TextStyle(color: AppTheme.danger)));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data == null) {
            return Center(child: Text('Driver not found.', style: TextStyle(color: textColor)));
          }

          _populateControllers(data);

          final docs = data['documents'] as Map<String, dynamic>? ?? {};
          final selfieUrl = docs['selfieUrl'] as String?;
          final aadharUrl = docs['aadharUrl'] as String?;
          final licenseUrl = docs['licenseUrl'] as String?;
          final vehicleUrl = docs['vehicleUrl'] as String?;

          final totalRides = data['totalAssignedRides'] ?? 0;
          final totalEarnings = data['totalEarnings'] ?? 0;

          final isAppr = data['isApproved'] == true || data['isApproved'] == 'true';
          final isBlk = data['isBlocked'] == true || data['isBlocked'] == 'true';
          final isRej = data['isRejected'] == true || data['isRejected'] == 'true';

          return LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 800;
              
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- PROFILE HEADER CARD ---
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: surfaceColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor),
                        ),
                        child: Flex(
                          direction: isMobile ? Axis.vertical : Axis.horizontal,
                          crossAxisAlignment: isMobile ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                          children: [
                            // Selfie
                            GestureDetector(
                              onTap: () {
                                if (selfieUrl != null && selfieUrl.isNotEmpty) {
                                  _showImagePreview('Profile Photo', selfieUrl);
                                }
                              },
                              child: Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: borderColor),
                                ),
                                child: (selfieUrl != null && selfieUrl.isNotEmpty)
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: Image.network(
                                          selfieUrl,
                                          fit: BoxFit.cover,
                                          loadingBuilder: (context, child, loadingProgress) {
                                            if (loadingProgress == null) return child;
                                            return const Center(child: CircularProgressIndicator());
                                          },
                                        ),
                                      )
                                    : Icon(Icons.person, size: 48, color: text2Color),
                              ),
                            ),
                            SizedBox(width: isMobile ? 0 : 24, height: isMobile ? 24 : 0),
                            // Details
                            Expanded(
                              flex: isMobile ? 0 : 1,
                              child: Column(
                                crossAxisAlignment: isMobile ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                                children: [
                                  _buildProfileField('Name', _nameController, textColor, isEditing: _isEditing),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 16,
                                    runSpacing: 12,
                                    children: [
                                      SizedBox(width: isMobile ? double.infinity : 200, child: _buildProfileField('Phone', _phoneController, textColor, isEditing: _isEditing)),
                                      SizedBox(width: isMobile ? double.infinity : 200, child: _buildProfileField('Vehicle Type', _vehicleTypeController, textColor, isEditing: _isEditing)),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 16,
                                    runSpacing: 12,
                                    children: [
                                      SizedBox(width: isMobile ? double.infinity : 200, child: _buildProfileField('Vehicle Number', _vehicleNumberController, textColor, isEditing: _isEditing)),
                                      SizedBox(width: isMobile ? double.infinity : 200, child: _buildProfileField('UPI ID', _upiIdController, textColor, isEditing: _isEditing)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
    
                      const SizedBox(height: 24),
    
                      // --- HISTORY AND STATUS ---
                      Flex(
                        direction: isMobile ? Axis.vertical : Axis.horizontal,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // History Card
                          Expanded(
                            flex: isMobile ? 0 : 1,
                            child: Container(
                              width: isMobile ? double.infinity : null,
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: surfaceColor,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: borderColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('History', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                                  const SizedBox(height: 16),
                                  Wrap(
                                    spacing: 32,
                                    runSpacing: 16,
                                    children: [
                                      _buildStatItem('Total Rides', totalRides.toString(), Icons.route, AppTheme.brandBlue, textColor, text2Color),
                                      _buildStatItem('Total Earnings', '₹$totalEarnings', Icons.account_balance_wallet, AppTheme.success, textColor, text2Color),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(width: isMobile ? 0 : 24, height: isMobile ? 24 : 0),
                          // Status Card
                          Expanded(
                            flex: isMobile ? 0 : 1,
                            child: Container(
                              width: isMobile ? double.infinity : null,
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: surfaceColor,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: borderColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Account Status', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                                  const SizedBox(height: 16),
                                  Wrap(
                                    spacing: 16,
                                    runSpacing: 16,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: isBlk || isRej
                                              ? AppTheme.danger.withValues(alpha: 0.1)
                                              : (isAppr ? AppTheme.success.withValues(alpha: 0.1) : AppTheme.warning.withValues(alpha: 0.1)),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          isBlk ? 'Blocked' : (isRej ? 'Rejected' : (isAppr ? 'Approved' : 'Pending')),
                                          style: TextStyle(
                                            color: isBlk || isRej ? AppTheme.danger : (isAppr ? AppTheme.success : AppTheme.warning),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      if (!isAppr && !isBlk && !isRej) ...[
                                        ElevatedButton.icon(
                                          onPressed: () => _showRejectionSheet(data['name'] ?? 'Driver', isDark),
                                          icon: const Icon(Icons.close, size: 18),
                                          label: const Text('Reject'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppTheme.danger,
                                            foregroundColor: Colors.white,
                                            minimumSize: const Size(0, 40),
                                          ),
                                        ),
                                        ElevatedButton.icon(
                                          onPressed: () => _updateStatus(true, false),
                                          icon: const Icon(Icons.check_circle_outline, size: 18),
                                          label: const Text('Approve'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppTheme.success,
                                            foregroundColor: Colors.white,
                                            minimumSize: const Size(0, 40),
                                          ),
                                        ),
                                      ],
                                      if (isRej && !isBlk && !isAppr) ...[
                                        ElevatedButton.icon(
                                          onPressed: () => _updateStatus(true, false),
                                          icon: const Icon(Icons.check_circle_outline, size: 18),
                                          label: const Text('Override Rejection & Approve'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppTheme.success,
                                            foregroundColor: Colors.white,
                                            minimumSize: const Size(0, 40),
                                          ),
                                        ),
                                      ],
                                      if (isAppr && !isBlk)
                                        ElevatedButton.icon(
                                          onPressed: () => _updateStatus(true, true),
                                          icon: const Icon(Icons.block, size: 18),
                                          label: const Text('Block'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppTheme.danger,
                                            foregroundColor: Colors.white,
                                            minimumSize: const Size(0, 40),
                                          ),
                                        ),
                                      if (isBlk)
                                        ElevatedButton.icon(
                                          onPressed: () => _updateStatus(true, false),
                                          icon: const Icon(Icons.lock_open, size: 18),
                                          label: const Text('Unblock'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppTheme.success,
                                            foregroundColor: Colors.white,
                                            minimumSize: const Size(0, 40),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
    
                      const SizedBox(height: 24),
    
                      // --- DOCUMENTS ---
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: surfaceColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Documents', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                            const SizedBox(height: 16),
                            _buildDocumentTile('Aadhaar Card', aadharUrl, Icons.badge_outlined, textColor, text2Color, borderColor),
                            _buildDocumentTile('Driving License', licenseUrl, Icons.fact_check_outlined, textColor, text2Color, borderColor),
                            _buildDocumentTile('Vehicle Photo', vehicleUrl, Icons.directions_car_outlined, textColor, text2Color, borderColor),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildProfileField(String label, TextEditingController controller, Color textColor, {required bool isEditing}) {
    if (!isEditing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(controller.text.isEmpty ? 'N/A' : controller.text, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
        ],
      );
    }
    return TextFormField(
      controller: controller,
      style: TextStyle(color: textColor),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color iconColor, Color textColor, Color text2Color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
            Text(label, style: GoogleFonts.inter(fontSize: 13, color: text2Color)),
          ],
        ),
      ],
    );
  }

  Widget _buildDocumentTile(String title, String? url, IconData icon, Color textColor, Color text2Color, Color borderColor) {
    final hasDoc = url != null && url.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: hasDoc ? AppTheme.brandBlue : text2Color),
        title: Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
        subtitle: Text(hasDoc ? 'Document available' : 'Not uploaded', style: TextStyle(color: text2Color, fontSize: 12)),
        trailing: hasDoc
            ? IconButton(
                icon: const Icon(Icons.open_in_full, color: AppTheme.brandBlue),
                tooltip: 'Preview Document',
                onPressed: () => _showImagePreview(title, url),
              )
            : const Icon(Icons.warning_amber, color: AppTheme.warning),
        onTap: hasDoc ? () => _showImagePreview(title, url) : null,
      ),
    );
  }
}
