import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/sync_engine.dart';
import '../models/queue_item.dart';

abstract class RideRepository {
  Future<void> createRide(Map<String, dynamic> payload);
  Future<void> acceptBid(String rideId, String bidId, String operationId);
  Future<void> cancelRide(String rideId, String operationId, {String reason = 'user_cancelled'});
  Stream<DocumentSnapshot> getRideStream(String rideId);
  Stream<QuerySnapshot> getBidsStream(String rideId);
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
  Future<void> createRide(Map<String, dynamic> payload) async {
    final item = QueueItem(
      id: payload['operationId'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      type: 'CREATE_RIDE',
      payload: payload,
    );
    await _syncEngine.enqueue(item);
  }

  @override
  Future<void> acceptBid(String rideId, String bidId, String operationId) async {
    final item = QueueItem(
      id: operationId,
      type: 'ACCEPT_BID',
      payload: {
        'rideId': rideId,
        'bidId': bidId,
        'operationId': operationId,
      },
    );
    await _syncEngine.enqueue(item);
  }

  @override
  Future<void> cancelRide(String rideId, String operationId, {String reason = 'user_cancelled'}) async {
    final item = QueueItem(
      id: operationId,
      type: 'CANCEL_RIDE',
      payload: {
        'rideId': rideId,
        'reason': reason,
        'operationId': operationId,
      },
    );
    await _syncEngine.enqueue(item);
  }

  @override
  Stream<DocumentSnapshot> getRideStream(String rideId) {
    return _firestore.collection('rides').doc(rideId).snapshots();
  }

  @override
  Stream<QuerySnapshot> getBidsStream(String rideId) {
    return _firestore
        .collection('bids')
        .where('rideId', isEqualTo: rideId)
        .snapshots();
  }
}
