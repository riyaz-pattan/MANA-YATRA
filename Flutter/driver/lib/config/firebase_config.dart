// lib/config/firebase_config.dart
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';

class FirebaseConfig {
  static FirebaseOptions get firebaseOptions {
    if (kIsWeb) {
      return const FirebaseOptions(
        apiKey: 'AIzaSyDRloeiEXNpuMPOS-M2iOorGxsw3jTAwPc',
        authDomain: 'mana-yatra.firebaseapp.com',
        projectId: 'mana-yatra',
        storageBucket: 'mana-yatra.firebasestorage.app',
        messagingSenderId: '141180839977',
        appId: '1:141180839977:web:2991594e316391c4fbd438',
        databaseURL:
            'https://mana-yatra-default-rtdb.asia-southeast1.firebasedatabase.app',
      );
    }
    
    return const FirebaseOptions(
      apiKey: 'AIzaSyD74iRYE09G52rL9dq6RYFj5WTWMGGqBfk',
      authDomain: 'mana-yatra.firebaseapp.com',
      projectId: 'mana-yatra',
      storageBucket: 'mana-yatra.firebasestorage.app',
      messagingSenderId: '141180839977',
      appId: '1:141180839977:android:15eabb961e03ab1bfbd438',
      databaseURL:
          'https://mana-yatra-default-rtdb.asia-southeast1.firebasedatabase.app',
    );
  }
}
