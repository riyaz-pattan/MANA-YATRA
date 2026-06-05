const fs = require('fs');
const path = require('path');

const newFunction = `

// --- Daily Stats Function ---
exports.updateDailyStats = functions.firestore
  .document("rides/{rideId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    // Only proceed if status changed to 'completed'
    if (before.status !== "completed" && after.status === "completed") {
      const db = admin.firestore();
      
      // Calculate date in IST (+05:30) since the user is based in India
      const date = new Date();
      date.setHours(date.getHours() + 5);
      date.setMinutes(date.getMinutes() + 30);
      
      const yyyy = date.getUTCFullYear();
      const mm = String(date.getUTCMonth() + 1).padStart(2, '0');
      const dd = String(date.getUTCDate()).padStart(2, '0');
      const dateStr = \`\${yyyy}-\${mm}-\${dd}\`;
      
      const statsRef = db.collection('admin_stats').doc(\`daily_stats_\${dateStr}\`);
      const price = Number(after.finalPrice) || 0;
      
      try {
        await statsRef.set({
          date: dateStr,
          ridesCount: admin.firestore.FieldValue.increment(1),
          revenue: admin.firestore.FieldValue.increment(price),
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });
        console.log(\`Updated daily stats for \${dateStr}: +1 ride, +\${price} revenue\`);
      } catch (err) {
        console.error("Error updating daily stats:", err);
      }
    }
    return null;
  });
`;

fs.appendFileSync(path.join(__dirname, 'index.js'), newFunction);
console.log('Successfully appended function to index.js');
