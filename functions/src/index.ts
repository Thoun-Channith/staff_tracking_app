import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();
const db = admin.firestore();

// This is our scheduled "alarm clock" function.
export const sendCheckInReminders = functions
  .region("asia-southeast2") // A good server location for you
  .pubsub.schedule("every day 09:00")
  .timeZone("Asia/Phnom_Penh") // IMPORTANT: Use your local timezone
  .onRun(async () => { // The unused "context" variable has been removed.
    // 1. Find all users who are NOT checked in.
    const usersSnapshot = await db
      .collection("users")
      .where("isCheckedIn", "==", false)
      .get();

    if (usersSnapshot.empty) {
      console.log("No users to remind.");
      return null;
    }

    // 2. Collect their device tokens.
    const tokens: string[] = [];
    usersSnapshot.forEach((doc) => {
      const user = doc.data();
      if (user.fcmToken) {
        tokens.push(user.fcmToken);
      }
    });

    if (tokens.length === 0) {
      console.log("Found users but no device tokens.");
      return null;
    }

    // 3. Create the notification message.
    const payload = {
      notification: {
        title: "Check-In Reminder",
        body: "Good morning! Please remember to check in for your shift.",
      },
    };

    // 4. Send the message.
    console.log(`Sending reminder to ${tokens.length} device(s).`);
    try {
      await admin.messaging().sendToDevice(tokens, payload);
      console.log("Successfully sent messages.");
    } catch (error) {
      console.error("Error sending messages:", error);
    }

    return null;
  });