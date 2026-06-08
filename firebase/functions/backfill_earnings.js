const admin = require('firebase-admin');
admin.initializeApp({
  projectId: "manayatra-86561"
}); // We can use the default or explicitly set it. Wait, the project is manayatra. If we don't pass credentials it might fail if not emulated.

async function run() {
  const db = admin.firestore();
  console.log("Fetching drivers...");
  const driversSnap = await db.collection('drivers').get();
  console.log(`Found ${driversSnap.size} drivers`);
  
  for (const driverDoc of driversSnap.docs) {
    const driverId = driverDoc.id;
    const ridesSnap = await db.collection('rides')
      .where('driverId', '==', driverId)
      .where('status', '==', 'completed')
      .get();
      
    let totalEarnings = 0;
    ridesSnap.docs.forEach(doc => {
      const data = doc.data();
      const price = Number(data.finalPrice) || 0;
      totalEarnings += price;
    });
    
    await driverDoc.ref.update({
      totalEarnings: totalEarnings
    });
    console.log(`Updated driver ${driverId} with totalEarnings: ${totalEarnings}`);
  }
  console.log("Done");
}

run().catch(console.error);
