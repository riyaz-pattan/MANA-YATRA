const admin = require("firebase-admin");
const serviceAccount = require("./firebase/functions/mana-yatra-firebase-adminsdk-m17d1-e9ed9b1287.json"); // Or default credentials
admin.initializeApp();
async function run() {
  const bids = await admin.firestore().collection("bids").orderBy("createdAt", "desc").limit(5).get();
  bids.forEach(doc => {
    console.log(doc.id, "=>", doc.data());
  });
}
run();
