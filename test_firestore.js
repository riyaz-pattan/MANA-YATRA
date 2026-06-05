const admin = require('firebase-admin');
const serviceAccount = require('./firebase/service-account.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

async function run() {
  const snapshot = await admin.firestore().collection('rides').where('status', 'in', ['matched', 'started', 'payment_pending']).get();
  console.log('Found', snapshot.size, 'stuck rides:');
  snapshot.forEach(doc => {
    console.log(doc.id, '->', doc.data().status, '| created:', doc.data().createdAt?.toDate());
  });
  process.exit(0);
}
run();
