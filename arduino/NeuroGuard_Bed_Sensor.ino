/*
 * ╔══════════════════════════════════════════════════════════════╗
 * ║         NeuroGuard — Sleep Sensor Module v4.0               ║
 * ║  DOIT ESP32 DevKit V1 + Velostat → Firebase Firestore       ║
 * ║  Window: 3 minutes | Hypersomnia: 13 hrs                    ║
 * ║  v4.0 changes:                                              ║
 * ║    • Boots cleanly from wall adapter (no laptop needed)     ║
 * ║    • Watchdog timer auto-restarts on WiFi failure           ║
 * ║    • Heartbeat field written every window for Flutter       ║
 * ║    • WiFiManager timeout so adapter boot never hangs        ║
 * ╚══════════════════════════════════════════════════════════════╝
 *
 * Hardware:  3.3V → Velostat mat → GPIO34 → 10kΩ → GND
 * Window:    5 Hz × 900 samples = 3 minutes per window
 * Libraries: ArduinoJson (v6.x), WiFiManager by tzapu
 *
 * ADAPTER BOOT BEHAVIOUR:
 *   First boot (no saved WiFi):
 *     → Opens NeuroGuard_Setup hotspot for 3 minutes
 *     → If no one configures it within 3 min, restarts and tries again
 *     → Once WiFi is saved it never opens the portal again
 *   Subsequent boots (WiFi saved):
 *     → Connects automatically within ~5 seconds
 *     → If WiFi fails 3 times in a row, wipes saved credentials and
 *       opens portal again so you can reconfigure
 */

#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <WiFiManager.h>
#include <esp_task_wdt.h>   // Hardware watchdog — auto-resets ESP32 if it hangs
#include <time.h>

// ════════════════════════════════════════════════════════════════
//  CONFIGURATION
// ════════════════════════════════════════════════════════════════

#define FIREBASE_PROJECT_ID  "neuroguard-1f865"
#define PATIENT_ID           "vMfJTTYdt5hytjvLQsNSsHuahLv1"

// ════════════════════════════════════════════════════════════════
//  HARDWARE
// ════════════════════════════════════════════════════════════════

#define SENSOR_PIN           34

// ════════════════════════════════════════════════════════════════
//  SAMPLING  —  3-minute window
// ════════════════════════════════════════════════════════════════

#define SAMPLE_RATE_HZ       10
#define WINDOW_SAMPLES       20      // 5 Hz × 180 s = 3 min
#define SAMPLE_INTERVAL_MS   100     // 1000 / 5 Hz

#define THRESHOLD_ON_BED     350
#define MICRO_MOVEMENT_DELTA 30

// ════════════════════════════════════════════════════════════════
//  ALERT THRESHOLDS  (in windows)
//  Hypersomnia  = 13 hr  = 46800 s / 180 s = 260 windows
//  Unresponsive = 60 min = 3600 s  / 180 s = 20 windows
// ════════════════════════════════════════════════════════════════

#define HYPERSOMNIA_WINDOWS  260
#define UNRESPONSIVE_WINDOWS 20

// ════════════════════════════════════════════════════════════════
//  WIFI / BOOT SETTINGS
// ════════════════════════════════════════════════════════════════

// How long (seconds) to wait for someone to configure WiFi via the
// NeuroGuard_Setup portal before giving up and restarting.
// 180 s = 3 minutes — enough time to grab your phone and configure.
#define WIFI_PORTAL_TIMEOUT_S   180

// How many consecutive WiFi reconnect failures before wiping saved
// credentials and re-opening the portal for fresh configuration.
#define WIFI_MAX_FAIL_COUNT     3

// Hardware watchdog timeout in seconds.
// If the ESP32 hangs for this long without feeding the watchdog,
// it resets itself automatically. Set to 4 minutes (longer than one
// full 3-min window + upload time so normal operation never triggers it).
#define WATCHDOG_TIMEOUT_S      240

// ════════════════════════════════════════════════════════════════
//  FIRESTORE URLs
// ════════════════════════════════════════════════════════════════

#define FIRESTORE_BASE \
  "https://firestore.googleapis.com/v1/projects/" \
  FIREBASE_PROJECT_ID \
  "/databases/(default)/documents"

#define WINDOWS_URL  FIRESTORE_BASE "/sleepSessions/" PATIENT_ID "/windows"
#define SUMMARY_URL  FIRESTORE_BASE "/sleepSessions/" PATIENT_ID "/dailySummaries"
#define STATUS_URL   FIRESTORE_BASE "/users/" PATIENT_ID

// ════════════════════════════════════════════════════════════════
//  NTP
// ════════════════════════════════════════════════════════════════

#define NTP_SERVER      "pool.ntp.org"
#define NTP_GMT_OFFSET  19800   // IST UTC+5:30
#define NTP_DST_OFFSET  0

// ════════════════════════════════════════════════════════════════
//  DATA STRUCTURES
// ════════════════════════════════════════════════════════════════

struct WindowResult {
  float  mean;
  float  variance;
  int    peakAmplitude;
  int    microMovementCount;
  float  bedOccupancyRatio;
  String state;
  long   epochTimestamp;
};

struct ImmobilityTracker {
  long  stillSinceEpoch  = 0;
  bool  tracking         = false;
  int   prolongedMinutes = 0;
  int   stillWindowCount = 0;
};
ImmobilityTracker immobility;

struct HypersomiaTracker {
  int  onBedWindowCount = 0;
  bool active           = false;
};
HypersomiaTracker hypersomnia;

struct DailyAccum {
  int    bedWindowCount   = 0;
  float  totalMovementSum = 0;
  int    longestStillRun  = 0;
  int    currentStillRun  = 0;
  String date             = "";
};
DailyAccum daily;

bool wasOnBed             = false;
bool locationCheckPending = false;
int  wifiFailCount        = 0;      // consecutive WiFi reconnect failures

// ════════════════════════════════════════════════════════════════
//  WATCHDOG
//  Feed the watchdog at the end of every loop iteration.
//  If the ESP32 hangs (network deadlock, heap exhaustion, etc.)
//  the watchdog fires after WATCHDOG_TIMEOUT_S and resets the chip.
// ════════════════════════════════════════════════════════════════

void initWatchdog() {
  esp_task_wdt_config_t wdt_config = {
    .timeout_ms     = WATCHDOG_TIMEOUT_S * 1000,
    .idle_core_mask = 0,
    .trigger_panic  = true,
  };
  esp_task_wdt_reconfigure(&wdt_config);
  esp_task_wdt_add(NULL);
  Serial.printf("[WDT] Watchdog armed — %d s timeout\n", WATCHDOG_TIMEOUT_S);
}

void feedWatchdog() {
  esp_task_wdt_reset();
}

// ════════════════════════════════════════════════════════════════
//  WIFI
//
//  ensureWiFi() is called before every Firestore upload.
//  If WiFi is connected it returns immediately (fast path).
//  If disconnected it attempts reconnect up to WIFI_MAX_FAIL_COUNT
//  times; after that it wipes saved credentials and reboots into
//  portal mode so the user can reconfigure with a fresh network.
// ════════════════════════════════════════════════════════════════

void ensureWiFi() {
  if (WiFi.status() == WL_CONNECTED) {
    wifiFailCount = 0;  // reset failure counter on success
    return;
  }

  Serial.println("[WiFi] Disconnected — attempting reconnect...");
  WiFi.disconnect();
  delay(1000);
  WiFi.reconnect();

  int tries = 0;
  while (WiFi.status() != WL_CONNECTED && tries < 20) {
    delay(500);
    tries++;
    feedWatchdog(); // keep watchdog happy during reconnect wait
  }

  if (WiFi.status() == WL_CONNECTED) {
    wifiFailCount = 0;
    Serial.println("[WiFi] Reconnected OK");
  } else {
    wifiFailCount++;
    Serial.printf("[WiFi] Reconnect FAILED (%d/%d)\n",
      wifiFailCount, WIFI_MAX_FAIL_COUNT);

    if (wifiFailCount >= WIFI_MAX_FAIL_COUNT) {
      Serial.println("[WiFi] Max failures reached — wiping credentials & restarting");
      WiFiManager wm;
      wm.resetSettings();   // wipe saved SSID/password
      delay(500);
      ESP.restart();        // reboot into portal mode for fresh setup
    }
  }
}

// ════════════════════════════════════════════════════════════════
//  NTP
// ════════════════════════════════════════════════════════════════

void syncNTP() {
  configTime(NTP_GMT_OFFSET, NTP_DST_OFFSET, NTP_SERVER);
  Serial.print("[NTP] Syncing");
  struct tm t;
  int tries = 0;
  while (!getLocalTime(&t) && tries < 20) {
    delay(500);
    Serial.print(".");
    feedWatchdog();
    tries++;
  }
  Serial.println(tries < 20 ? "\n[NTP] Synced" : "\n[NTP] Failed — using millis()");
}

long getEpoch() {
  time_t now;
  time(&now);
  return (now < 1000000000L) ? (long)(millis() / 1000) : (long)now;
}

String getDateString() {
  struct tm t;
  if (!getLocalTime(&t)) return "1970-01-01";
  char buf[12];
  sprintf(buf, "%04d-%02d-%02d", t.tm_year+1900, t.tm_mon+1, t.tm_mday);
  return String(buf);
}

// ════════════════════════════════════════════════════════════════
//  SIGNAL PROCESSING  —  3-minute window
// ════════════════════════════════════════════════════════════════

WindowResult analyseWindow() {
  int* samples = new int[WINDOW_SAMPLES];

  Serial.printf("[Sensor] Collecting %d samples (3 min)...\n", WINDOW_SAMPLES);

  for (int i = 0; i < WINDOW_SAMPLES; i++) {
    samples[i] = analogRead(SENSOR_PIN);
    delay(SAMPLE_INTERVAL_MS);

    // Feed watchdog every 100 samples (~20 seconds) during collection
    if (i % 100 == 0) feedWatchdog();
  }

  // Mean
  long sum = 0;
  for (int i = 0; i < WINDOW_SAMPLES; i++) sum += samples[i];
  float mean = (float)sum / WINDOW_SAMPLES;

  // Variance
  float varSum = 0;
  for (int i = 0; i < WINDOW_SAMPLES; i++) {
    float d = samples[i] - mean;
    varSum += d * d;
  }
  float variance = varSum / WINDOW_SAMPLES;

  // Peak amplitude
  int peak = 0;
  for (int i = 0; i < WINDOW_SAMPLES; i++)
    if (samples[i] > peak) peak = samples[i];

  // Bed occupancy
  int aboveThresh = 0;
  for (int i = 0; i < WINDOW_SAMPLES; i++)
    if (samples[i] > THRESHOLD_ON_BED) aboveThresh++;
  float occupancy = (float)aboveThresh / WINDOW_SAMPLES;

  // Micro-movements
  int movements = 0;
  if (occupancy >= 0.5) {
    for (int i = 1; i < WINDOW_SAMPLES; i++) {
      if (abs(samples[i] - samples[i-1]) > MICRO_MOVEMENT_DELTA)
        movements++;
    }
  }

  delete[] samples;

  String state;
  if      (occupancy < 0.5)   state = "OFF_BED";
  else if (movements == 0)    state = "ON_BED_STILL";
  else if (movements <= 20)   state = "ON_BED_LIGHT";
  else                        state = "ON_BED_ACTIVE";

  WindowResult r;
  r.mean               = mean;
  r.variance           = variance;
  r.peakAmplitude      = peak;
  r.microMovementCount = movements;
  r.bedOccupancyRatio  = occupancy;
  r.state              = state;
  r.epochTimestamp     = getEpoch();
  return r;
}

// ════════════════════════════════════════════════════════════════
//  EXTENDED STATE CLASSIFIER
// ════════════════════════════════════════════════════════════════

void applyExtendedStates(WindowResult& r) {
  bool onBed = (r.state != "OFF_BED");
  bool still = (r.state == "ON_BED_STILL");

  if (still) {
    immobility.stillWindowCount++;
    if (!immobility.tracking) {
      immobility.tracking        = true;
      immobility.stillSinceEpoch = r.epochTimestamp;
    }
    immobility.prolongedMinutes =
      (int)((r.epochTimestamp - immobility.stillSinceEpoch) / 60);

    if (immobility.stillWindowCount >= UNRESPONSIVE_WINDOWS) {
      r.state = "UNRESPONSIVE";
      Serial.printf("[ALERT] RED — Unresponsive %d min\n",
        immobility.prolongedMinutes);
    }
  } else {
    immobility.stillWindowCount = 0;
    immobility.tracking         = false;
    immobility.prolongedMinutes = 0;
    immobility.stillSinceEpoch  = 0;
  }

  if (onBed) {
    hypersomnia.onBedWindowCount++;
    if (hypersomnia.onBedWindowCount >= HYPERSOMNIA_WINDOWS
        && r.state != "UNRESPONSIVE") {
      r.state            = "HYPERSOMNIA";
      hypersomnia.active = true;
      Serial.printf("[ALERT] YELLOW — Hypersomnia %.1f hrs\n",
        hypersomnia.onBedWindowCount * 3.0 / 60.0);
    }
  } else {
    hypersomnia.onBedWindowCount = 0;
    hypersomnia.active           = false;
  }
}

// ════════════════════════════════════════════════════════════════
//  BED TRANSITION
// ════════════════════════════════════════════════════════════════

void checkBedTransition(WindowResult& r) {
  bool currentlyOnBed = (r.state != "OFF_BED");
  if (wasOnBed && !currentlyOnBed) {
    locationCheckPending = true;
    Serial.println("[Trigger] Patient left bed — location check pending");
  }
  wasOnBed = currentlyOnBed;
}

// ════════════════════════════════════════════════════════════════
//  DAILY ACCUMULATOR
// ════════════════════════════════════════════════════════════════

void updateDaily(WindowResult& r) {
  String today = getDateString();
  if (daily.date != today) {
    daily      = DailyAccum();
    daily.date = today;
  }
  bool onBed = (r.state != "OFF_BED");
  bool still = (r.state == "ON_BED_STILL" || r.state == "UNRESPONSIVE");
  if (onBed) {
    daily.bedWindowCount++;
    daily.totalMovementSum += r.microMovementCount;
  }
  if (still) {
    daily.currentStillRun++;
    if (daily.currentStillRun > daily.longestStillRun)
      daily.longestStillRun = daily.currentStillRun;
  } else {
    daily.currentStillRun = 0;
  }
}

// ════════════════════════════════════════════════════════════════
//  SERIAL PRINT
// ════════════════════════════════════════════════════════════════

void printWindow(int num, WindowResult& r) {
  Serial.printf("\n========== WINDOW %d ==========\n", num);
  Serial.printf("State:           %s\n",     r.state.c_str());
  Serial.printf("Mean:            %.2f\n",   r.mean);
  Serial.printf("Variance:        %.2f\n",   r.variance);
  Serial.printf("Peak amplitude:  %d\n",     r.peakAmplitude);
  Serial.printf("Micro-movements: %d\n",     r.microMovementCount);
  Serial.printf("Bed occupancy:   %.1f%%\n", r.bedOccupancyRatio * 100.0);
  Serial.printf("Still windows:   %d / %d\n",
    immobility.stillWindowCount, UNRESPONSIVE_WINDOWS);
  Serial.printf("OnBed windows:   %d / %d\n",
    hypersomnia.onBedWindowCount, HYPERSOMNIA_WINDOWS);
  Serial.printf("Epoch:           %ld\n",    r.epochTimestamp);
  Serial.println("================================\n");
}

// ════════════════════════════════════════════════════════════════
//  FIRESTORE HELPERS
// ════════════════════════════════════════════════════════════════

bool firestorePost(const String& url, const String& body) {
  ensureWiFi();
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[POST] Skipped — no WiFi");
    return false;
  }
  HTTPClient http;
  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  http.setTimeout(15000); // 15 second HTTP timeout
  int code = http.POST(body);
  bool ok  = (code == 200);
  Serial.printf("[POST] %s (%d)\n", ok ? "OK" : "FAIL", code);
  if (!ok) Serial.println(http.getString().substring(0, 300));
  http.end();
  return ok;
}

bool firestorePatch(const String& url, const String& body) {
  ensureWiFi();
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[PATCH] Skipped — no WiFi");
    return false;
  }
  HTTPClient http;
  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  http.setTimeout(15000);
  int code = http.PATCH(body);
  bool ok  = (code == 200);
  Serial.printf("[PATCH] %s (%d)\n", ok ? "OK" : "FAIL", code);
  if (!ok) Serial.println(http.getString().substring(0, 300));
  http.end();
  return ok;
}

// ════════════════════════════════════════════════════════════════
//  BUILD JSON DOCUMENTS
// ════════════════════════════════════════════════════════════════

String buildWindowJson(WindowResult& r) {
  StaticJsonDocument<1024> doc;
  JsonObject f = doc.createNestedObject("fields");

  f["epochTimestamp"]["integerValue"]             = String(r.epochTimestamp);
  f["mean"]["doubleValue"]                        = r.mean;
  f["variance"]["doubleValue"]                    = r.variance;
  f["peakAmplitude"]["integerValue"]              = String(r.peakAmplitude);
  f["microMovementCount"]["integerValue"]         = String(r.microMovementCount);
  f["bedOccupancyRatio"]["doubleValue"]           = r.bedOccupancyRatio;
  f["state"]["stringValue"]                       = r.state;
  f["patientId"]["stringValue"]                   = PATIENT_ID;
  f["prolongedImmobilityMinutes"]["integerValue"] = String(immobility.prolongedMinutes);
  f["isHypersomnia"]["booleanValue"]              = (r.state == "HYPERSOMNIA");
  f["isUnresponsive"]["booleanValue"]             = (r.state == "UNRESPONSIVE");
  f["isOffBed"]["booleanValue"]                   = (r.state == "OFF_BED");

  String out;
  serializeJson(doc, out);
  return out;
}

String buildDailySummaryJson() {
  float totalBedMin  = daily.bedWindowCount * 3.0;
  float avgMovPerHr  = (totalBedMin > 0)
    ? (daily.totalMovementSum / (totalBedMin / 60.0)) : 0.0;
  int   longestStill = daily.longestStillRun * 3;

  StaticJsonDocument<512> doc;
  JsonObject f = doc.createNestedObject("fields");

  f["date"]["stringValue"]                       = daily.date;
  f["totalBedMinutes"]["doubleValue"]             = totalBedMin;
  f["avgMovementPerHour"]["doubleValue"]          = avgMovPerHr;
  f["prolongedImmobilityFlag"]["booleanValue"]    = (daily.longestStillRun * 3 >= 60);
  f["longestStillStretchMinutes"]["integerValue"] = String(longestStill);
  f["patientId"]["stringValue"]                   = PATIENT_ID;
  f["hypersomniaActive"]["booleanValue"]          = hypersomnia.active;

  String out;
  serializeJson(doc, out);
  return out;
}

String buildLiveStatusJson(WindowResult& r) {
  // ── HEARTBEAT FIELD ────────────────────────────────────────────────────
  // esp32LastSeen is written every window.
  // Flutter reads this timestamp and compares it to current time.
  // If the gap exceeds one window + buffer (4.5 min), Flutter treats
  // the ESP32 as disconnected and resets the UI to NOT CONNECTED.
  // This is the core mechanism for requirement 2.
  long nowEpoch = getEpoch();

  StaticJsonDocument<1024> doc;
  JsonObject fields  = doc.createNestedObject("fields");
  JsonObject sensors = fields["sensors"]
                         .createNestedObject("mapValue")
                         .createNestedObject("fields");

  sensors["bed_status"]["stringValue"]          = r.state;
  sensors["sensor_raw"]["integerValue"]         = String(r.peakAmplitude);
  sensors["mean"]["doubleValue"]                = r.mean;
  sensors["variance"]["doubleValue"]            = r.variance;
  sensors["microMovementCount"]["integerValue"] = String(r.microMovementCount);
  sensors["peakAmplitude"]["integerValue"]      = String(r.peakAmplitude);
  sensors["isHypersomnia"]["booleanValue"]      = (r.state == "HYPERSOMNIA");
  sensors["isUnresponsive"]["booleanValue"]     = (r.state == "UNRESPONSIVE");
  sensors["checkLocationNow"]["booleanValue"]   = locationCheckPending;
  sensors["lastUpdated"]["integerValue"]        = String(r.epochTimestamp);

  // ← KEY FIELD: Flutter watches this to detect ESP32 going offline
  sensors["esp32LastSeen"]["integerValue"]      = String(nowEpoch);

  String body;
  serializeJson(doc, body);
  return body;
}

// ════════════════════════════════════════════════════════════════
//  UPLOAD FUNCTIONS
// ════════════════════════════════════════════════════════════════

void uploadWindow(WindowResult& r) {
  Serial.println("[Firestore] Uploading window...");
  firestorePost(String(WINDOWS_URL), buildWindowJson(r));
}

void uploadDailySummary() {
  Serial.println("[Firestore] Updating daily summary...");
  String url = String(SUMMARY_URL) + "/" + daily.date;
  firestorePatch(url, buildDailySummaryJson());
}

void uploadLiveStatus(WindowResult& r) {
  Serial.println("[Firestore] Updating live status...");
  String url  = String(STATUS_URL) + "?updateMask.fieldPaths=sensors";
  String body = buildLiveStatusJson(r);
  firestorePatch(url, body);
  if (locationCheckPending) locationCheckPending = false;
}

// ════════════════════════════════════════════════════════════════
//  SETUP
// ════════════════════════════════════════════════════════════════

void setup() {
  Serial.begin(115200);
  delay(1000); // small delay so Serial Monitor can connect before output starts

  Serial.println("\n╔══════════════════════════════════╗");
  Serial.println("║   NeuroGuard v4.0  Booting...    ║");
  Serial.println("║   Window: 3 min | Hyp: 13 hr     ║");
  Serial.println("╚══════════════════════════════════╝\n");

  // ── Hardware watchdog ────────────────────────────────────────
  // Must be initialised before WiFi so even a WiFi hang gets caught.
  initWatchdog();

  // ── WiFiManager ──────────────────────────────────────────────
  // setConfigPortalTimeout: if no one configures WiFi within this
  // many seconds, give up and restart. On the next boot it tries
  // again. This prevents the ESP32 hanging forever on an adapter
  // with no one around to configure it.
  WiFi.begin("Redmi 13C 5G", "fatemaezzi2710");

Serial.print("[WiFi] Connecting to hotspot");

int attempts = 0;
while (WiFi.status() != WL_CONNECTED && attempts < 20) {
  delay(500);
  Serial.print(".");
  attempts++;
}

if (WiFi.status() == WL_CONNECTED) {
  Serial.println("\n[WiFi] Connected instantly!");
} else {
  Serial.println("\n[WiFi] Failed — starting portal");

  WiFiManager wm;
  wm.setConfigPortalTimeout(60);
  wm.autoConnect("NeuroGuard_Setup");
}
 if (WiFi.status() != WL_CONNECTED) {
  Serial.println("[WiFi] Could not connect — restarting in 5 s");
  delay(5000);
  ESP.restart();
}

  Serial.printf("[WiFi] Connected — IP: %s\n",
    WiFi.localIP().toString().c_str());

  // ── Sensor pin ───────────────────────────────────────────────
  pinMode(SENSOR_PIN, INPUT);

  // ── NTP time sync ────────────────────────────────────────────
  syncNTP();

  daily.date = getDateString();
  Serial.printf("[Daily] Today: %s\n", daily.date.c_str());
  Serial.printf("[System] Patient: %s\n", PATIENT_ID);
  Serial.println("[System] Monitoring loop started\n");

  feedWatchdog();
}

// ════════════════════════════════════════════════════════════════
//  MAIN LOOP  —  one iteration = one 3-minute window
// ════════════════════════════════════════════════════════════════

int windowNumber = 1;

void loop() {
  // Feed watchdog at start of loop
  feedWatchdog();

  // 1. Collect 900 samples over 3 minutes
  //    (watchdog is fed inside analyseWindow every 100 samples)
  WindowResult r = analyseWindow();

  // 2. Upgrade state if needed
  applyExtendedStates(r);

  // 3. Bed exit → location check flag
  checkBedTransition(r);

  // 4. Print to Serial
  printWindow(windowNumber++, r);

  // 5. Update daily totals
  updateDaily(r);

  // 6. Upload to Firestore
  //    Each upload feeds the watchdog via ensureWiFi internally.
  uploadWindow(r);
  feedWatchdog();

  uploadDailySummary();
  feedWatchdog();

  uploadLiveStatus(r);
  feedWatchdog();

  Serial.println("[Loop] Window complete — starting next\n");
}
