// lib/core/providers/config_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Fetches and caches the pricing configuration exactly once.
/// Can be manually invalidated using ref.invalidate(pricingConfigProvider).
final pricingConfigProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final doc = await FirebaseFirestore.instance.collection('config').doc('pricing').get(const GetOptions(source: Source.serverAndCache));
  return doc.data() ?? {};
});

/// Fetches and caches the notification alerts template exactly once.
/// Can be manually invalidated using ref.invalidate(notificationConfigProvider).
final notificationConfigProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final doc = await FirebaseFirestore.instance.collection('admin_settings').doc('alerts').get(const GetOptions(source: Source.serverAndCache));
  return doc.data() ?? {};
});
