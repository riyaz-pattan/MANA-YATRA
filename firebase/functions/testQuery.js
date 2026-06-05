const admin = require('firebase-admin');

// Initialize with application default credentials, assuming it works or use dummy if local emulator
admin.initializeApp({
  projectId: "mana-yatra" // Use the project id
});

const db = admin.firestore();

async function test() {
  try {
    const res1 = await db.collection('admin_stats').orderBy('date', 'desc').limit(7).get();
    console.log('admin_stats success', res1.docs.length);
  } catch(e) {
    console.log('admin_stats error', e.message);
  }

  try {
    const res2 = await db.collection('rides').where('status', '==', 'completed').aggregate({
      totalRevenue: admin.firestore.AggregateField.sum('finalPrice')
    }).get();
    console.log('aggregate sum success');
  } catch(e) {
    console.log('aggregate sum error', e.message);
  }
}

test();
