import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_performance/firebase_performance.dart';

class AnalyticsService {
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  final FirebasePerformance _performance = FirebasePerformance.instance;

  static final AnalyticsService _instance = AnalyticsService._internal();

  factory AnalyticsService() {
    return _instance;
  }

  AnalyticsService._internal();

  // Screen tracking
  Future<void> logScreenView(String screenName) async {
    await _analytics.logScreenView(screenName: screenName);
  }

  // Ride Funnel Events
  Future<void> logRideRequested(String pickup, String dropoff) async {
    await _analytics.logEvent(
      name: 'ride_requested',
      parameters: {
        'pickup': pickup,
        'dropoff': dropoff,
      },
    );
  }

  Future<void> logBidPlaced(String driverId, double amount) async {
    await _analytics.logEvent(
      name: 'bid_placed',
      parameters: {
        'driver_id': driverId,
        'amount': amount,
      },
    );
  }

  Future<void> logBidAccepted(String rideId) async {
    await _analytics.logEvent(
      name: 'bid_accepted',
      parameters: {
        'ride_id': rideId,
      },
    );
  }

  Future<void> logRideStarted(String rideId) async {
    await _analytics.logEvent(
      name: 'ride_started',
      parameters: {
        'ride_id': rideId,
      },
    );
  }

  Future<void> logRideCompleted(String rideId) async {
    await _analytics.logEvent(
      name: 'ride_completed',
      parameters: {
        'ride_id': rideId,
      },
    );
  }

  Future<void> logRideFailed(String reason) async {
    await _analytics.logEvent(
      name: 'ride_failed',
      parameters: {
        'reason': reason,
      },
    );
  }

  // Custom Performance Traces
  Future<Trace> startTrace(String traceName) async {
    final trace = _performance.newTrace(traceName);
    await trace.start();
    return trace;
  }

  Future<void> stopTrace(Trace trace) async {
    await trace.stop();
  }
}
