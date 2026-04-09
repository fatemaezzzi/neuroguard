// functions/index.js
//
// NeuroGuard — Cloud Functions (Merged)
// ─────────────────────────────────────────────────────────────────────────────
// Functions:
//   onAlertCreated     — Firestore trigger: fires FCM when pendingAlerts entry is written
//   createEscalation   — HTTPS callable: Dart calls this at T+0 to start escalation engine
//   runEscalationTick  — Scheduled every minute: drives Tier 1 / 2 / 3 escalation
//   acknowledgeAlert   — HTTPS callable: caregiver taps "Acknowledge"
//   cancelEscalation   — HTTPS callable: cancels a specific or all escalations for a patient
//
// Environment / Secrets:
//   FAST2SMS_API_KEY   — set via: firebase functions:secrets:set FAST2SMS_API_KEY
//
// Deploy:
//   cd functions && npm install
//   firebase deploy --only functions
// ─────────────────────────────────────────────────────────────────────────────

const functions              = require("firebase-functions");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule }         = require("firebase-functions/v2/scheduler");
const { initializeApp }      = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging }       = require("firebase-admin/messaging");
const { defineSecret }       = require("firebase-functions/params");
const axios                  = require("axios");

initializeApp();
const db  = getFirestore();
const fcm = getMessaging();

const fast2smsKey = defineSecret("FAST2SMS_API_KEY");

// ── Alert titles (shared) ────────────────────────────────────────────────────
const ALERT_TITLES = {
  geoFence:  "Patient outside safe zone",
  medicine:  "Medicine reminder",
  spyCall:   "Remote monitoring triggered",
  matSensor: "Bed alert",
};

// ── Tier delays (seconds after createdAt) ────────────────────────────────────
const TIER1_DELAY_S = 120;   // 2 min  — FCM push
const TIER2_DELAY_S = 300;   // 5 min  — FCM (urgent) + SMS to caregiver
const TIER3_DELAY_S = 600;   // 10 min — SMS to secondary contacts

// ─────────────────────────────────────────────────────────────────────────────
// 1. onAlertCreated — Firestore trigger
//    Fires immediately when any entry lands in pendingAlerts/{patientId}/entries
//    Sends an instant FCM push to the paired caregiver
// ─────────────────────────────────────────────────────────────────────────────
exports.onAlertCreated = functions
  .region("asia-south1")
  .firestore
  .document("pendingAlerts/{patientId}/entries/{alertId}")
  .onCreate(async (snap, context) => {
    const alert = snap.data();
    const { patientId } = context.params;

    const patientDoc  = await db.collection("users").doc(patientId).get();
    const patientData = patientDoc.data();
    const caregiverId = patientData?.paired_caregiver_id ?? null;
    if (!caregiverId) return null;

    const caregiverDoc  = await db.collection("users").doc(caregiverId).get();
    const caregiverData = caregiverDoc.data();
    const fcmToken      = caregiverData?.fcmToken ?? null;
    if (!fcmToken) return null;

    const title = ALERT_TITLES[alert.type] ?? "NeuroGuard alert";

    await fcm.send({
      token: fcmToken,
      notification: { title, body: alert.message },
      data: {
        type:      alert.type     ?? "",
        severity:  alert.severity ?? "",
        patientId,
      },
      android: {
        priority: alert.severity === "critical" ? "high" : "normal",
        notification: {
          channelId: alert.type === "geoFence" ? "safezone_breach" : "medicine_alarm",
        },
      },
    });

    console.log(`[onAlertCreated] FCM sent for patient ${patientId}, type: ${alert.type}`);
    return null;
  });

// ─────────────────────────────────────────────────────────────────────────────
// 2. createEscalation — HTTPS callable
//    Called from Dart at T+0. Creates an escalation document that
//    runEscalationTick will drive through Tier 1 → 2 → 3.
// ─────────────────────────────────────────────────────────────────────────────
exports.createEscalation = onCall(
  { region: "asia-south1" },
  async (request) => {
    const { patientId, alertType, message, severity, escalationId } = request.data;

    if (!patientId || !alertType || !escalationId) {
      throw new HttpsError("invalid-argument", "patientId, alertType, escalationId required");
    }

    await db.collection("escalations").doc(escalationId).set({
      patientId,
      alertType,
      message:        message  ?? "",
      severity:       severity ?? "warning",
      createdAt:      FieldValue.serverTimestamp(),
      acknowledgedAt: null,
      tier1SentAt:    null,
      tier2SentAt:    null,
      tier3SentAt:    null,
      status:         "active",
    });

    console.log(`[Escalation] Created: ${escalationId} for patient ${patientId}`);
    return { success: true, escalationId };
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// 3. runEscalationTick — runs every minute
//    Checks all active escalations and fires the appropriate tier.
// ─────────────────────────────────────────────────────────────────────────────
exports.runEscalationTick = onSchedule(
  { schedule: "every 1 minutes", secrets: [fast2smsKey], region: "asia-south1" },
  async () => {
    const now    = Date.now();
    const apiKey = fast2smsKey.value();

    const snap = await db.collection("escalations")
      .where("status", "==", "active")
      .get();

    if (snap.empty) return;

    console.log(`[Escalation] Tick — ${snap.size} active escalation(s)`);
    await Promise.allSettled(snap.docs.map(doc => _processEscalation(doc, now, apiKey)));
  }
);

async function _processEscalation(doc, nowMs, apiKey) {
  const esc       = doc.data();
  const id        = doc.id;
  const createdMs = esc.createdAt?.toMillis?.() ?? 0;
  const ageS      = (nowMs - createdMs) / 1000;

  console.log(`[Escalation] ${id} — age: ${Math.round(ageS)}s`);

  const patientDoc  = await db.collection("users").doc(esc.patientId).get();
  const patientData = patientDoc.data() ?? {};
  const caregiverId = patientData.paired_caregiver_id;

  let caregiverData = {};
  if (caregiverId) {
    const cgDoc = await db.collection("users").doc(caregiverId).get();
    caregiverData = cgDoc.data() ?? {};
  }

  const fcmToken        = caregiverData.fcmToken ?? null;
  const caregiverPhone  = caregiverData.phone     ?? null;
  const secondaryPhones = (patientData.escalationConfig?.secondaryContacts ?? [])
    .map(c => c.phone)
    .filter(p => p && p.length >= 10);

  const updates = {};

  // ── Tier 1: FCM push ──────────────────────────────────────────────────────
  if (ageS >= TIER1_DELAY_S && !esc.tier1SentAt) {
    console.log(`[Escalation] ${id} — Tier 1 FCM`);
    if (fcmToken) {
      await _sendFcm(fcmToken, {
        title: _titleFor(esc.alertType),
        body:  esc.message,
        data:  { escalationId: id, escalationTier: "1", patientId: esc.patientId },
      });
    }
    updates.tier1SentAt = FieldValue.serverTimestamp();
  }

  // ── Tier 2: FCM urgent + SMS to caregiver ────────────────────────────────
  if (ageS >= TIER2_DELAY_S && !esc.tier2SentAt) {
    console.log(`[Escalation] ${id} — Tier 2 FCM + SMS`);
    if (fcmToken) {
      await _sendFcm(fcmToken, {
        title:    `URGENT: ${_titleFor(esc.alertType)}`,
        body:     `URGENT: ${esc.message}`,
        data:     { escalationId: id, escalationTier: "2", patientId: esc.patientId },
        priority: "high",
      });
    }
    if (caregiverPhone) {
      await _sendSms(
        [caregiverPhone],
        `URGENT ALERT - NeuroGuard\n${_featureName(esc.alertType)}: ${esc.message}\nPlease check on your loved one immediately.`,
        apiKey
      );
    } else {
      console.warn(`[Escalation] ${id} — Tier 2: no caregiver phone in Firestore`);
    }
    updates.tier2SentAt = FieldValue.serverTimestamp();
  }

  // ── Tier 3: SMS to secondary contacts ────────────────────────────────────
  if (ageS >= TIER3_DELAY_S && !esc.tier3SentAt) {
    console.log(`[Escalation] ${id} — Tier 3 secondary contacts`);
    if (secondaryPhones.length > 0) {
      await _sendSms(
        secondaryPhones,
        `CRITICAL ALERT - NeuroGuard\n${_featureName(esc.alertType)}: ${esc.message}\nPlease check on your loved one immediately.`,
        apiKey
      );
    } else {
      console.warn(`[Escalation] ${id} — Tier 3: no secondary contacts configured`);
    }

    // Escalate severity on the original alert entry
    const alertSnap = await db.collection("alerts").doc(esc.patientId)
      .collection("entries")
      .where("metadata.escalationId", "==", id)
      .limit(1).get();
    if (!alertSnap.empty) {
      await alertSnap.docs[0].ref.update({
        severity:          "critical",
        escalatedAt:       FieldValue.serverTimestamp(),
        escalationReached: 3,
      });
    }

    updates.tier3SentAt = FieldValue.serverTimestamp();
    updates.status      = "completed";
  }

  if (Object.keys(updates).length > 0) {
    await doc.ref.update(updates);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. acknowledgeAlert — HTTPS callable
//    Called from Dart when caregiver taps "Acknowledge". Stops escalation.
// ─────────────────────────────────────────────────────────────────────────────
exports.acknowledgeAlert = onCall(
  { region: "asia-south1" },
  async (request) => {
    const { escalationId } = request.data;
    if (!escalationId) {
      throw new HttpsError("invalid-argument", "escalationId required");
    }

    await db.collection("escalations").doc(escalationId).update({
      acknowledgedAt: FieldValue.serverTimestamp(),
      status:         "acknowledged",
    });

    console.log(`[Escalation] Acknowledged: ${escalationId}`);
    return { success: true };
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// 5. cancelEscalation — HTTPS callable
//    Called from Dart (e.g. EscalationService.cancelAll() in onDestroy).
//    Pass escalationId to cancel one, or patientId to cancel all active ones.
// ─────────────────────────────────────────────────────────────────────────────
exports.cancelEscalation = onCall(
  { region: "asia-south1" },
  async (request) => {
    const { escalationId, patientId } = request.data;

    if (escalationId) {
      await db.collection("escalations").doc(escalationId).update({
        status:      "cancelled",
        cancelledAt: FieldValue.serverTimestamp(),
      });
      console.log(`[Escalation] Cancelled: ${escalationId}`);
    } else if (patientId) {
      const snap = await db.collection("escalations")
        .where("patientId", "==", patientId)
        .where("status", "==", "active")
        .get();
      const batch = db.batch();
      snap.docs.forEach(doc => batch.update(doc.ref, {
        status:      "cancelled",
        cancelledAt: FieldValue.serverTimestamp(),
      }));
      await batch.commit();
      console.log(`[Escalation] Cancelled ${snap.size} escalation(s) for patient ${patientId}`);
    } else {
      throw new HttpsError("invalid-argument", "escalationId or patientId required");
    }

    return { success: true };
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

async function _sendFcm(token, { title, body, data = {}, priority = "normal" }) {
  try {
    await fcm.send({
      token,
      notification: { title, body },
      data,
      android: {
        priority: priority === "high" ? "high" : "normal",
        notification: { channelId: "safezone_breach" },
      },
    });
    console.log(`[FCM] Sent: "${title}"`);
  } catch (e) {
    console.error(`[FCM] Failed: ${e.message}`);
  }
}

async function _sendSms(phones, message, apiKey) {
  if (!apiKey) {
    console.error("[SMS] API key not set — skipping SMS");
    return;
  }
  try {
    const response = await axios.post(
      "https://www.fast2sms.com/dev/bulkV2",
      {
        route:    "q",
        message,
        language: "english",
        flash:    0,
        numbers:  phones.join(","),
      },
      {
        headers: {
          authorization: apiKey,
          "Content-Type": "application/json",
        },
      }
    );
    console.log(`[SMS] Fast2SMS response: ${JSON.stringify(response.data)}`);
  } catch (e) {
    console.error(`[SMS] Failed: ${e.message}`);
  }
}

function _titleFor(alertType) {
  return ALERT_TITLES[alertType] ?? "NeuroGuard Alert";
}

function _featureName(alertType) {
  const map = {
    geoFence:  "Safe Zone Breach",
    medicine:  "Medicine Reminder",
    spyCall:   "Spy Call",
    matSensor: "Bed Sensor",
  };
  return map[alertType] ?? "Alert";
}