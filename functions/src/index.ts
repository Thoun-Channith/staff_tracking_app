import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();

// This is a callable function. It can be invoked directly from your web app.
export const createStaffUser = functions
  .region("asia-southeast1") // Deployed in your region for lower latency
  .https.onCall(async (data, context) => {

    // 1. Authentication Check: Ensure the user calling this function is an admin.
    const uid = context.auth?.uid;
    if (!uid) {
        throw new functions.https.HttpsError(
            "unauthenticated",
            "You must be logged in to create a user."
        );
    }

    const adminUserDoc = await admin.firestore().collection("users").doc(uid).get();
    if (adminUserDoc.data()?.role !== "admin") {
      throw new functions.https.HttpsError(
        "permission-denied",
        "You do not have permission to perform this action."
      );
    }

    // 2. Data Validation: Ensure all required fields are present.
    const { email, password, displayName, employeeId, position }. = data;
    if (!email || !password || !displayName || !employeeId || !position) {
        throw new functions.https.HttpsError(
            "invalid-argument",
            "Please fill out all required fields."
        );
    }

    try {
      // 3. Create the user in Firebase Authentication
      const userRecord = await admin.auth().createUser({
        email: email,
        password: password,
        displayName: displayName,
        disabled: false,
      });

      // 4. Create the corresponding user document in Firestore
      await admin.firestore().collection("users").doc(userRecord.uid).set({
        email: email,
        displayName: displayName,
        employeeId: employeeId,
        position: position,
        role: "staff",
        accountEnabled: true,
        isClockedIn: false,
        lastSeen: null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {
        uid: userRecord.uid,
        message: `Successfully created user: ${displayName}`,
      };
    } catch (error: any) {
      console.error("Error creating new user:", error);
      if (error.code === 'auth/email-already-exists') {
           throw new functions.https.HttpsError(
            "already-exists",
            "This email is already in use by another account."
           );
      }
      throw new functions.https.HttpsError(
        "internal",
        "An unexpected error occurred."
      );
    }
  });