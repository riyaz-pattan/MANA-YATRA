const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  databaseURL: 'https://mana-yatra-default-rtdb.asia-southeast1.firebasedatabase.app/'
});
admin.database().ref('liveLocations').once('value').then(snap => {
  console.log(JSON.stringify(snap.val(), null, 2));
  process.exit(0);
});
