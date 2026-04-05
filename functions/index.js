const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

const ALERT_TITLES = {
  geoFence:  "Patient outside safe zone",
  medicine:  "Medicine reminder",
  spyCall:   "Remote monitoring triggered",
  matSensor: "Bed alert",
};

// ─── Trigger: onReminderFired() writes here ────────────────────────────────
exports.onAlertCreated = functions
  .region("asia-south1")
  .firestore
  .document("pendingAlerts/{patientId}/entries/{alertId}")
  .onCreate(async (snap, context) => {
    const alert = snap.data();
    const { patientId } = context.params;

    const patientDoc = await admin.firestore()
      .collection("users")
      .doc(patientId)
      .get();

    const patientData = patientDoc.data();
    const caregiverId = patientData ? patientData.paired_caregiver_id : null;
    if (!caregiverId) return null;

    const caregiverDoc = await admin.firestore()
      .collection("users")
      .doc(caregiverId)
      .get();

    const caregiverData = caregiverDoc.data();
    const fcmToken = caregiverData ? caregiverData.fcmToken : null;
    if (!fcmToken) return null;

    const title = ALERT_TITLES[alert.type] ?? "NeuroGuard alert";

    await admin.messaging().send({
      token: fcmToken,
      notification: {
        title,
        body: alert.message,
      },
      data: {
        type:      alert.type     ?? "",
        severity:  alert.severity ?? "",
        patientId,
      },
      android: {
        priority: alert.severity === "critical" ? "high" : "normal",
        notification: {
          channelId: alert.type === "geoFence"
            ? "safezone_breach"
            : "medicine_alarm",
        },
      },
    });

    return null;
  });