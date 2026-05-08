const admin = require('firebase-admin');
admin.initializeApp({ projectId: "mana-yatra" });
async function run() {
  try {
    const list = await admin.auth().listUsers(10);
    for (const u of list.users) {
      console.log(u.email, u.uid, u.customClaims);
    }
  } catch (e) { console.error(e); }
}
run();
