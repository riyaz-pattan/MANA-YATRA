// lib/presentation/screens/role_management_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/constants/rbac.dart';

class RoleManagementScreen extends ConsumerWidget {
  const RoleManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1024;
    
    final bg = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final text3Color = isDark ? AppTheme.darkText3 : AppTheme.lightText3;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('admin_users').orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // Fallback to non-ordered query in case the index is missing or createdAt is null
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('admin_users').snapshots(),
            builder: (context, fallbackSnapshot) {
              if (fallbackSnapshot.hasError) {
                return Center(child: Text('Error loading admins: ${fallbackSnapshot.error}', style: const TextStyle(color: Colors.red)));
              }
              if (!fallbackSnapshot.hasData) return const Center(child: CircularProgressIndicator());
              return _buildContent(context, fallbackSnapshot.data!.docs, isDesktop, isDark, textColor, text3Color, bg, border, ref);
            },
          );
        }
        
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        return _buildContent(context, snapshot.data!.docs, isDesktop, isDark, textColor, text3Color, bg, border, ref);
      },
    );
  }

  Widget _buildContent(
    BuildContext context, 
    List<QueryDocumentSnapshot> docs, 
    bool isDesktop, 
    bool isDark, 
    Color textColor, 
    Color text3Color, 
    Color bg, 
    Color border,
    WidgetRef ref
  ) {
    final allAdmins = docs.map((d) {
      final data = d.data() as Map<String, dynamic>? ?? {};
      data['id'] = d.id;
      return data;
    }).toList();

    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 32 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Admin Access & Roles', style: GoogleFonts.inter(fontSize: isDesktop ? 24 : 20, fontWeight: FontWeight.w700, color: textColor)),
                    const SizedBox(height: 8),
                    Text('Manage admin users and their RBAC permissions.', style: GoogleFonts.inter(fontSize: 14, color: text3Color)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () => _showAddAdminDialog(context, ref, isDark),
                icon: const Icon(Icons.add),
                label: const Text('Add Admin'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.brandBlue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16)),
              ),
            ],
          ),
          const SizedBox(height: 32),

          if (allAdmins.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Text('No admin users found.', style: TextStyle(color: text3Color, fontSize: 16)),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: allAdmins.length,
                separatorBuilder: (_, __) => Divider(color: border, height: 1),
                itemBuilder: (context, index) {
                  final admin = allAdmins[index];
                  final email = admin['email']?.toString() ?? '';
                  final name = admin['displayName']?.toString() ?? 'Unknown';
                  final roleStr = admin['role']?.toString() ?? 'viewer';
                  final isActive = admin['isActive'] ?? true;
                  
                  final role = AdminRole.values.firstWhere((r) => r.value == roleStr, orElse: () => AdminRole.viewer);

                  return Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2,
                          child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'U', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name.isNotEmpty ? name : 'Unnamed Admin', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15, color: textColor)),
                              const SizedBox(height: 4),
                              Text(email, style: GoogleFonts.inter(color: text3Color, fontSize: 13)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: AppTheme.brandBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                          child: Text(role.displayName, style: GoogleFonts.inter(color: AppTheme.brandBlue, fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 24),
                        Switch(
                          value: isActive == true,
                          onChanged: (val) {
                            FirebaseFirestore.instance.collection('admin_users').doc(admin['id']).update({'isActive': val});
                          },
                          activeColor: AppTheme.success,
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          color: text3Color,
                          onPressed: () {},
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  void _showAddAdminDialog(BuildContext context, WidgetRef ref, bool isDark) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    AdminRole selectedRole = AdminRole.viewer;
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
          final bg = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
          
          return AlertDialog(
            backgroundColor: bg,
            title: Text('Add New Admin', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: textColor)),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder()), style: TextStyle(color: textColor)),
                  const SizedBox(height: 16),
                  TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email Address', border: OutlineInputBorder()), style: TextStyle(color: textColor)),
                  const SizedBox(height: 16),
                  TextField(controller: passwordCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Temporary Password', border: OutlineInputBorder()), style: TextStyle(color: textColor)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<AdminRole>(
                    value: selectedRole,
                    dropdownColor: bg,
                    decoration: const InputDecoration(labelText: 'Assign Role', border: OutlineInputBorder()),
                    items: AdminRole.values.map((r) => DropdownMenuItem(value: r, child: Text(r.displayName, style: TextStyle(color: textColor)))).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => selectedRole = val);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: AppTheme.danger)),
              ),
              ElevatedButton(
                onPressed: isLoading ? null : () async {
                  if (nameCtrl.text.isEmpty || emailCtrl.text.isEmpty || passwordCtrl.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
                    return;
                  }
                  setState(() => isLoading = true);
                  try {
                    final functions = FirebaseFirestore.instance.app.options.projectId != null 
                        ? FirebaseFunctions.instance // TODO: Ensure functions is imported
                        : null; // Fallback handled via direct call usually. Actually, let's just use FirebaseFunctions.instance

                    await FirebaseFunctions.instance.httpsCallable('createAdminUser').call({
                      'email': emailCtrl.text.trim(),
                      'password': passwordCtrl.text,
                      'displayName': nameCtrl.text.trim(),
                      'role': selectedRole.value,
                    });
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Admin created successfully!')));
                    }
                  } catch (e) {
                    setState(() => isLoading = false);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: AppTheme.danger));
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.brandBlue, foregroundColor: Colors.white),
                child: isLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Create Admin'),
              ),
            ],
          );
        },
      ),
    );
  }
}
