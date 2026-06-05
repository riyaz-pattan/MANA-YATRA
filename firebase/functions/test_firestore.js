const admin = require('firebase-admin');
const serviceAccount = require('../service-account.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

async function run() {
  const snapshot = await admin.firestore().collection('rides').where('status', 'in', ['matched', 'started', 'payment_pending']).get();
  console.log('Found', snapshot.size, 'stuck rides:');
  snapshot.forEach(doc => {
    console.log(doc.id, '->', doc.data().status, '| created:', doc.data().createdAt?.toDate());
  });
  
  // Cleanup logic
  if (snapshot.size > 0) {
    const batch = admin.firestore().batch();
    snapshot.forEach(doc => {
      batch.update(doc.ref, { status: 'cancelled' });
    });
    await batch.commit();
    console.log('Cleaned up stuck rides!');
  }
  process.exit(0);
}
run();
