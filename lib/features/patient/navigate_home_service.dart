import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

/// NavigateHomeService — Patient Side
///
/// Called when the patient taps the LOCATION button on PatientHome.
/// Reads the safe zone set by the caregiver (same Firestore path that
/// GeofenceService and LocationService already use), speaks a calm TTS
/// message, opens walking directions to home, and logs the event so the
/// caregiver is notified instantly via their existing Firestore listener.

class NavigateHomeService {
  // ─── Singleton ────────────────────────────────────────────────────────────
  static final NavigateHomeService _instance = NavigateHomeService._internal();
  factory NavigateHomeService() => _instance;
  NavigateHomeService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FlutterTts _tts = FlutterTts();

  // ──────────────────────────────────────────────────────────────────────────
  // PUBLIC ENTRY POINT
  // Called from PatientHome when the LOCATION button is tapped.
  // ──────────────────────────────────────────────────────────────────────────

  Future<NavigateHomeResult> triggerNavigateHome({
    required String patientId,
  }) async {
    // 1. Get current GPS position.
    //    LocationService.startTracking() already requested permissions on app
    //    start, so we just do a one-time fetch here — no duplicate dialog.
    final Position? position = await _getCurrentPosition();
    if (position == null) {
      return NavigateHomeResult.failure(
        'Could not get your location.\nPlease make sure GPS is turned on.',
      );
    }

    // 2. Read safe zone center from Firestore.
    //    Uses the exact same path GeofenceService.saveSafeZone() writes to:
    //    users/{patientId}/safeZone.centerLat & centerLng
    final _HomeCoords? home = await _readHomeCoords(patientId);
    if (home == null) {
      return NavigateHomeResult.failure(
        'Home location is not set yet.\nAsk your caregiver to set your Safe Zone.',
      );
    }

    // 3. Calculate distance for a meaningful TTS message
    final double distanceMeters = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      home.lat,
      home.lng,
    );

    // 4. Speak a calming message to the patient
    await _speak(distanceMeters);

    // 5. Write event to Firestore — caregiver is notified via their existing
    //    snapshot listener on users/{patientId} (GeofenceService / TrackerPage)
    await _notifyCaregiver(
      patientId: patientId,
      patientLat: position.latitude,
      patientLng: position.longitude,
      homeLat: home.lat,
      homeLng: home.lng,
      distanceMeters: distanceMeters,
    );

    // 6. Short wait so TTS starts speaking before the map launches
    await Future.delayed(const Duration(seconds: 3));

    // 7. Open walking directions (Google Maps, falls back to OpenStreetMap)
    await _openDirections(home.lat, home.lng);

    return NavigateHomeResult.success(distanceMeters: distanceMeters);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PRIVATE HELPERS
  // ──────────────────────────────────────────────────────────────────────────

  Future<Position?> _getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (_) {
      // If GPS times out (e.g. indoors), fall back to last known fix
      return Geolocator.getLastKnownPosition();
    }
  }

  /// Reads safe zone center from the same Firestore document path that
  /// GeofenceService.saveSafeZone() and LocationService._checkSafeZone() use.
  Future<_HomeCoords?> _readHomeCoords(String patientId) async {
    try {
      final doc = await _db.collection('users').doc(patientId).get();
      final data = doc.data();
      if (data == null || data['safeZone'] == null) return null;
      final sz = data['safeZone'] as Map<String, dynamic>;
      return _HomeCoords(
        lat: (sz['centerLat'] as num).toDouble(),
        lng: (sz['centerLng'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _speak(double distanceMeters) async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.42); // Slower for elderly comprehension
    await _tts.setVolume(1.0);

    final String message;
    if (distanceMeters < 200) {
      message = 'You are very close to home. Keep going, you are almost there.';
    } else if (distanceMeters < 1000) {
      message = "Don't worry. I will help you get home. "
          "You are about ${distanceMeters.round()} metres away. "
          "Opening directions for you now.";
    } else {
      final String km = (distanceMeters / 1000).toStringAsFixed(1);
      message = "Don't worry. I will help you get home. "
          "You are about $km kilometres away. "
          "Opening directions for you now.";
    }

    await _tts.speak(message);
  }

  /// Writes a navigateHomeEvent field to the patient's Firestore document.
  /// The caregiver's existing stream on users/{patientId} picks this up
  /// immediately — no extra listener setup needed on the caregiver side.
  Future<void> _notifyCaregiver({
    required String patientId,
    required double patientLat,
    required double patientLng,
    required double homeLat,
    required double homeLng,
    required double distanceMeters,
  }) async {
    final Map<String, dynamic> payload = {
      'patientLat': patientLat,
      'patientLng': patientLng,
      'homeLat': homeLat,
      'homeLng': homeLng,
      'distanceFromHomeMeters': distanceMeters,
      'triggeredAt': FieldValue.serverTimestamp(),
      'status': 'NAVIGATING',
    };

    // A) Overwrite the latest event field on the patient document.
    //    GeofenceService / TrackerPage already stream this document,
    //    so the caregiver sees this the moment it's written.
    await _db.collection('users').doc(patientId).update({
      'navigateHomeEvent': payload,
    });

    // B) Append to history sub-collection for the caregiver's alert feed.
    await _db
        .collection('users')
        .doc(patientId)
        .collection('navigateHomeHistory')
        .add(payload);
  }

  Future<void> _openDirections(double destLat, double destLng) async {
    final Uri googleMaps = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
          '&destination=$destLat,$destLng&travelmode=walking',
    );
    final Uri osm = Uri.parse(
      'https://www.openstreetmap.org/directions?to=$destLat,$destLng',
    );

    if (await canLaunchUrl(googleMaps)) {
      await launchUrl(googleMaps, mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(osm, mode: LaunchMode.externalApplication);
    }
  }
}

// ─── Internal coord holder ────────────────────────────────────────────────────
class _HomeCoords {
  final double lat;
  final double lng;
  const _HomeCoords({required this.lat, required this.lng});
}

// ─── Result model ─────────────────────────────────────────────────────────────
class NavigateHomeResult {
  final bool success;
  final String? errorMessage;
  final double? distanceMeters;

  const NavigateHomeResult._({
    required this.success,
    this.errorMessage,
    this.distanceMeters,
  });

  factory NavigateHomeResult.success({required double distanceMeters}) =>
      NavigateHomeResult._(success: true, distanceMeters: distanceMeters);

  factory NavigateHomeResult.failure(String message) =>
      NavigateHomeResult._(success: false, errorMessage: message);
}