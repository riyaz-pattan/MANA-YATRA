// lib/core/constants/rbac.dart

/// Role-Based Access Control definitions for the Admin Console.
///
/// Each role has a set of permissions that determine what modules
/// and actions are accessible.

enum AdminRole {
  superAdmin('super_admin', 'Super Admin'),
  operationsManager('operations_manager', 'Operations Manager'),
  financeManager('finance_manager', 'Finance Manager'),
  supportExecutive('support_executive', 'Support Executive'),
  businessAnalyst('business_analyst', 'Business Analyst'),
  viewer('viewer', 'Viewer');

  const AdminRole(this.value, this.displayName);
  final String value;
  final String displayName;

  static AdminRole fromString(String value) {
    return AdminRole.values.firstWhere(
      (r) => r.value == value,
      orElse: () => AdminRole.viewer,
    );
  }
}

enum Permission {
  // Dashboard
  dashboardView,

  // Drivers
  driversRead,
  driversWrite,
  driversApprove,
  driversBlock,

  // Riders / Users
  usersRead,
  usersWrite,
  usersBlock,

  // Rides
  ridesRead,
  ridesWrite,
  ridesIntervene,

  // Financials
  financialsRead,
  financialsWrite,
  financialsApprovePayouts,
  financialsConfigPricing,

  // Operations
  operationsRead,
  operationsWrite,
  sosAlertsView,
  sosAlertsAct,
  zonesManage,
  notificationsBroadcast,
  announcementsManage,

  // Support
  supportRead,
  supportWrite,
  supportAssign,
  moderationManage,

  // Analytics
  analyticsView,
  analyticsExport,

  // System / Admin
  adminUsersManage,
  auditLogView,
  featureFlagsManage,
  appConfigManage,
  accountDeletionManage,
}

/// Maps each role to the set of permissions it has.
class RBACConfig {
  RBACConfig._();

  static const Map<AdminRole, Set<Permission>> rolePermissions = {
    AdminRole.superAdmin: {
      // Super admin has ALL permissions
      ...Permission.values,
    },

    AdminRole.operationsManager: {
      Permission.dashboardView,
      // Drivers
      Permission.driversRead,
      Permission.driversWrite,
      Permission.driversApprove,
      Permission.driversBlock,
      // Users
      Permission.usersRead,
      Permission.usersWrite,
      Permission.usersBlock,
      // Rides
      Permission.ridesRead,
      Permission.ridesWrite,
      Permission.ridesIntervene,
      // Financials (read only)
      Permission.financialsRead,
      // Operations
      Permission.operationsRead,
      Permission.operationsWrite,
      Permission.sosAlertsView,
      Permission.sosAlertsAct,
      Permission.zonesManage,
      Permission.notificationsBroadcast,
      Permission.announcementsManage,
      // Support (read only)
      Permission.supportRead,
      // Analytics
      Permission.analyticsView,
      Permission.analyticsExport,
      // Admin
      Permission.auditLogView,
      Permission.accountDeletionManage,
    },

    AdminRole.financeManager: {
      Permission.dashboardView,
      // Drivers (read)
      Permission.driversRead,
      // Users (read)
      Permission.usersRead,
      // Rides (read)
      Permission.ridesRead,
      // Financials (full)
      Permission.financialsRead,
      Permission.financialsWrite,
      Permission.financialsApprovePayouts,
      Permission.financialsConfigPricing,
      // Analytics
      Permission.analyticsView,
      Permission.analyticsExport,
      // Admin
      Permission.auditLogView,
    },

    AdminRole.supportExecutive: {
      Permission.dashboardView,
      // Drivers (read)
      Permission.driversRead,
      // Users (read)
      Permission.usersRead,
      // Rides (read)
      Permission.ridesRead,
      // Support (full)
      Permission.supportRead,
      Permission.supportWrite,
      Permission.supportAssign,
      Permission.moderationManage,
      // Operations (limited)
      Permission.sosAlertsView,
      // Analytics (read)
      Permission.analyticsView,
      // Admin
      Permission.auditLogView,
    },

    AdminRole.businessAnalyst: {
      Permission.dashboardView,
      // Read-only on data
      Permission.driversRead,
      Permission.usersRead,
      Permission.ridesRead,
      Permission.financialsRead,
      Permission.operationsRead,
      Permission.supportRead,
      Permission.sosAlertsView,
      // Analytics (full)
      Permission.analyticsView,
      Permission.analyticsExport,
      // Admin
      Permission.auditLogView,
    },

    AdminRole.viewer: {
      Permission.dashboardView,
      Permission.driversRead,
      Permission.usersRead,
      Permission.ridesRead,
      Permission.financialsRead,
      Permission.analyticsView,
      Permission.auditLogView,
    },
  };

  /// Check if a role has a specific permission.
  static bool hasPermission(AdminRole role, Permission permission) {
    // Super admin always has all permissions
    if (role == AdminRole.superAdmin) return true;
    return rolePermissions[role]?.contains(permission) ?? false;
  }

  /// Get all permissions for a role.
  static Set<Permission> getPermissions(AdminRole role) {
    if (role == AdminRole.superAdmin) return Permission.values.toSet();
    return rolePermissions[role] ?? {};
  }
}
