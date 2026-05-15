import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/sync_engine.dart';
import '../models/queue_item.dart';

abstract class RideRepository {
  Future<void> placeBid(Map<String, dynamic> payload, String operationId);
  Future<void> startRide(String rideId, String operationId);
  Future<void> completeRide(String rideId, String operationId);
  Future<void> cancelRide(String rideId, String operationId, {String reason = 'driver_cancelled'});
  Stream<DocumentSnapshot> getRideStream(String rideId);
  Stream<QuerySnapshot> getActiveBidsStream(String driverId);
}

class FirestoreRideRepository implements RideRepository {
  final FirebaseFirestore _firestore;
  final SyncEngine _syncEngine;

  FirestoreRideRepository({
    FirebaseFirestore? firestore,
    required SyncEngine syncEngine,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _syncEngine = syncEngine;

  @override
  Future<void> placeBid(Map<String, dynamic> payload, String operationId) async {
    final item = QueueItem(
      id: operationId,
      type: 'PLACE_BID',
      payload: payload,
    );
    await _syncEngine.enqueue(item);
  }

  @override
  Future<void> startRide(String rideId, String operationId) async {
    final item = QueueItem(
      id: operationId,
      type: 'START_RIDE',
      payload: {
        'rideId': rideId,
      },
    );
    await _syncEngine.enqueue(item);
  }

  @override
  Future<void> completeRide(String rideId, String operationId) async {
    final item = QueueItem(
      id: operationId,
      type: 'COMPLETE_RIDE',
      payload: {
        'rideId': rideId,
      },
    );
    await _syncEngine.enqueue(item);
  }

  @override
  Future<void> cancelRide(String rideId, String operationId, {String reason = 'driver_cancelled'}) async {
    final item = QueueItem(
      id: operationId,
      type: 'CANCEL_RIDE',
      payload: {
        'rideId': rideId,
        'reason': reason,
      },
    );
    await _syncEngine.enqueue(item);
  }

  @override
  Stream<DocumentSnapshot> getRideStream(String rideId) {
    return _firestore.collection('rides').doc(rideId).snapshots();
  }

  @override
  Stream<QuerySnapshot> getActiveBidsStream(String driverId) {
    return _firestore
        .collection('bids')
        .where('driverId', isEqualTo: driverId)
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }
}
