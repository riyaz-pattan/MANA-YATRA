const admin = require('firebase-admin');
admin.initializeApp({ projectId: 'mana-yatra' });

async function check() {
  const db = admin.firestore();
  console.log("Fetching payments...");
  const snap = await db.collection("payments").orderBy("createdAt", "desc").limit(10).get();
  snap.forEach(doc => {
    console.log(doc.id, "=>", JSON.stringify(doc.data(), null, 2));
  });
  process.exit(0);
}
check().catch(e => {
  console.error(e);
  process.exit(1);
});
