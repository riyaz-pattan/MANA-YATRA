import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

abstract class AuthRepository {
  Stream<User?> get authStateChanges;
  User? get currentUser;
  Future<void> signOut();
  Future<void> deleteAccount();
  Stream<DocumentSnapshot> getDriverProfileStream(String uid);
}

class FirebaseAuthRepository implements AuthRepository {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  FirebaseAuthRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  @override
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  @override
  User? get currentUser => _auth.currentUser;

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user != null) {
      await _firestore.collection('account_deletion_requests').add({
        'uid': user.uid,
        'role': 'driver',
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  Stream<DocumentSnapshot> getDriverProfileStream(String uid) {
    return _firestore.collection('drivers').doc(uid).snapshots();
  }
}
