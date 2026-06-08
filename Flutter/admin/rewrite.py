import re

with open('lib/presentation/screens/driver_profile_screen.dart', 'r') as f:
    content = f.read()

# 1. Add loadingBuilder to _showImagePreview
preview_pattern = r"(\s*)fit: BoxFit\.contain,(\s*)errorBuilder"
preview_replace = r"""\1fit: BoxFit.contain,\1loadingBuilder: (context, child, loadingProgress) {
\1  if (loadingProgress == null) return child;
\1  return Container(
\1    color: AppTheme.darkSurface,
\1    padding: const EdgeInsets.all(32),
\1    child: const Center(child: CircularProgressIndicator()),
\1  );
\1},\2errorBuilder"""
content = re.sub(preview_pattern, preview_replace, content)

# 2. Replace the main build body starting from the SingleChildScrollView
# Find where the form starts
form_start = content.find('          return SingleChildScrollView(')
form_end = content.find('Widget _buildProfileField') - 6 # before the next method

new_body = """          return LayoutBuilder(
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
                                          color: isBlk
                                              ? AppTheme.danger.withValues(alpha: 0.1)
                                              : (isAppr ? AppTheme.success.withValues(alpha: 0.1) : AppTheme.warning.withValues(alpha: 0.1)),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          isBlk ? 'Blocked' : (isAppr ? 'Approved' : 'Pending'),
                                          style: TextStyle(
                                            color: isBlk ? AppTheme.danger : (isAppr ? AppTheme.success : AppTheme.warning),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      if (!isAppr && !isBlk)
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
"""

content = content[:form_start] + new_body + content[form_end:]

with open('lib/presentation/screens/driver_profile_screen.dart', 'w') as f:
    f.write(content)
