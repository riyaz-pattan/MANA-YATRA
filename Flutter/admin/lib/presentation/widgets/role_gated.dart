// lib/presentation/widgets/role_gated.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/rbac.dart';
import '../../core/providers/auth_provider.dart';

/// A wrapper widget that only displays its [child] if the current
/// admin user has the [requiredPermission].
///
/// If they don't have permission, it shows [fallback] (default: SizedBox.shrink).
class RoleGated extends ConsumerWidget {
  final Permission requiredPermission;
  final Widget child;
  final Widget fallback;

  const RoleGated({
    super.key,
    required this.requiredPermission,
    required this.child,
    this.fallback = const SizedBox.shrink(),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPermission = ref.watch(hasPermissionProvider(requiredPermission));

    if (hasPermission) {
      return child;
    }

    return fallback;
  }
}
