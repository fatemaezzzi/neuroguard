// lib/core/providers/location_providers.dart
//
// Riverpod state layer for NeuroGuard location + geofence features.
//
// PROVIDERS
//   locationStreamProvider       — StreamProvider<LocationSnapshot?>
//   safeZoneStreamProvider       — StreamProvider<SafeZoneModel?>
//   caregiverPositionProvider    — StreamProvider<LatLng?>
//   geofenceNotifierProvider     — NotifierProvider<GeofenceNotifier, GeofenceState>
//
// DESIGN RULES (matches existing NeuroGuard conventions)
//   • Services (LocationService, GeofenceService) are NOT replaced — providers
//     wrap them. No service logic is duplicated here.
//   • .set(merge:true) and singleton patterns inside services are preserved.
//   • Every provider is a family variant keyed by patientId so the same
//     provider works for any patient without extra plumbing.
//   • GeofenceNotifier owns ALL mutable geofence state so TrackerPage never
//     calls setState() for alert/breach logic — only for map animation.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:neuroguard/core/services/geofence_service.dart';
import 'package:neuroguard/core/services/location_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 1.  LOCATION STREAM  (patient side → caregiver reads)
// ─────────────────────────────────────────────────────────────────────────────

/// Live patient location from Firestore.
///
/// Replaces the nested StreamBuilder<LocationSnapshot?> in TrackerPage.
/// Keyed by patientId so the same provider family works for any patient.
///
/// Usage:
///   final locationAsync = ref.watch(locationStreamProvider('patient_01'));
///   locationAsync.when(
///     data: (loc) { /* loc is LocationSnapshot? */ },
///     loading: () => CircularProgressIndicator(),
///     error: (e, _) => Text('Error: $e'),
///   );
final locationStreamProvider =
StreamProvider.family<LocationSnapshot?, String>((ref, patientId) {
  return LocationService.streamPatientLocation(patientId);
});

// ─────────────────────────────────────────────────────────────────────────────
// 2.  SAFE ZONE STREAM
// ─────────────────────────────────────────────────────────────────────────────

/// Live safe zone config + inside/outside status from Firestore.
///
/// Replaces the nested StreamBuilder<SafeZoneModel?> in TrackerPage.
/// Keyed by patientId.
///
/// Usage:
///   final zoneAsync = ref.watch(safeZoneStreamProvider('patient_01'));
final safeZoneStreamProvider =
StreamProvider.family<SafeZoneModel?, String>((ref, patientId) {
  return GeofenceService().streamSafeZone(patientId);
});

// ─────────────────────────────────────────────────────────────────────────────
// 3.  CAREGIVER POSITION STREAM
// ─────────────────────────────────────────────────────────────────────────────

/// Caregiver's own live GPS position for the "YOU" dot on the map.
///
/// Replaces _startCaregiverLocationTracking() + _caregiverLocSub in TrackerPage.
/// Not keyed — there is only one caregiver device.
///
/// The provider cancels the stream subscription automatically when disposed.
///
/// Usage:
///   final caregiverAsync = ref.watch(caregiverPositionProvider);
///   final latLng = caregiverAsync.valueOrNull;   // LatLng? — null until first fix
final caregiverPositionProvider = StreamProvider<LatLng?>((ref) async* {
  const settings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 10,
  );

  // Emit an immediate fix first so the dot appears before movement
  try {
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    yield LatLng(pos.latitude, pos.longitude);
  } catch (_) {
    yield null;
  }

  // Then stream ongoing updates
  await for (final pos in Geolocator.getPositionStream(
    locationSettings: settings,
  )) {
    yield LatLng(pos.latitude, pos.longitude);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// 4.  GEOFENCE STATE  (mutable — NotifierProvider.family)
// ─────────────────────────────────────────────────────────────────────────────

/// All mutable geofence/alert state for a single patient.
///
/// Replaces:
///   • _geofenceSubscription + _showBreachOverlay in TrackerPage
///   • Direct GeofenceService().acknowledgeBreachAsSafe() calls in UI
///   • Direct GeofenceService().escalateToRedAlert() calls in UI
///
/// TrackerPage watches this notifier and reacts to state changes without
/// holding any alert state locally. Map animation (which needs a
/// TickerProvider) stays in the widget as a side-effect triggered by
/// [ref.listen].

class GeofenceState {
  final AlertLevel alertLevel;
  final GeofenceEvent? lastEvent;
  final bool isAcknowledging; // true while Firestore write is in flight

  const GeofenceState({
    this.alertLevel = AlertLevel.none,
    this.lastEvent,
    this.isAcknowledging = false,
  });

  GeofenceState copyWith({
    AlertLevel? alertLevel,
    GeofenceEvent? lastEvent,
    bool clearLastEvent = false,
    bool? isAcknowledging,
  }) {
    return GeofenceState(
      alertLevel: alertLevel ?? this.alertLevel,
      lastEvent: clearLastEvent ? null : (lastEvent ?? this.lastEvent),
      isAcknowledging: isAcknowledging ?? this.isAcknowledging,
    );
  }
}

enum AlertLevel {
  none,       // Patient is inside safe zone — all clear
  breach,     // Patient left safe zone — awaiting caregiver response
  red,        // Caregiver confirmed unsupervised — red alert active
  resolved,   // Caregiver acknowledged as supervised OR patient returned
}

// Family keyed by patientId so each patient gets an independent notifier.
final geofenceNotifierProvider =
NotifierProvider.family<GeofenceNotifier, GeofenceState, String>(
  GeofenceNotifier.new,
);

class GeofenceNotifier extends FamilyNotifier<GeofenceState, String> {
  // patientId is available as [arg] from FamilyNotifier
  late final GeofenceService _service;

  @override
  GeofenceState build(String patientId) {
    _service = GeofenceService();

    // Start watching Firestore for breach events on behalf of this patient.
    // GeofenceService.startWatching() already handles duplicate-start guard.
    _service.startWatching(patientId: patientId);

    // Forward GeofenceService stream events into Riverpod state.
    // The subscription is cancelled automatically when this notifier
    // is disposed (ref.onDispose).
    final sub = _service.eventStream
        .where((event) => event.patientId == patientId)
        .listen(_handleEvent);

    ref.onDispose(() {
      sub.cancel();
      _service.stopWatching();
    });

    return const GeofenceState();
  }

  // ── Event handler ──────────────────────────────────────────────────────────

  void _handleEvent(GeofenceEvent event) {
    switch (event.type) {
      case GeofenceEventType.exit:
        state = state.copyWith(
          alertLevel: AlertLevel.breach,
          lastEvent: event,
        );
        break;

      case GeofenceEventType.enter:
        state = state.copyWith(
          alertLevel: AlertLevel.resolved,
          lastEvent: event,
        );
        break;

      case GeofenceEventType.acknowledgedSafe:
        state = state.copyWith(
          alertLevel: AlertLevel.resolved,
          lastEvent: event,
          isAcknowledging: false,
        );
        break;

      case GeofenceEventType.escalatedToRedAlert:
        state = state.copyWith(
          alertLevel: AlertLevel.red,
          lastEvent: event,
          isAcknowledging: false,
        );
        break;
    }
  }

  // ── Public actions (called by UI) ──────────────────────────────────────────

  /// Caregiver tapped "It's fine — supervised outing".
  /// Marks breach acknowledged, clears alert.
  Future<void> acknowledgeSupervisedOuting() async {
    if (state.isAcknowledging) return;
    state = state.copyWith(isAcknowledging: true);
    try {
      await _service.acknowledgeBreachAsSafe(arg);
      // State will be updated by the eventStream listener when Firestore
      // emits acknowledgedSafe — no manual state.copyWith needed here.
    } catch (_) {
      // Firestore write failed — roll back the in-progress flag
      state = state.copyWith(isAcknowledging: false);
    }
  }

  /// Caregiver tapped "Not supervised — escalate".
  /// Sets red alert in Firestore and locally.
  Future<void> escalate() async {
    if (state.isAcknowledging) return;
    state = state.copyWith(isAcknowledging: true);
    try {
      await _service.escalateToRedAlert(arg);
      // State will be updated by the eventStream listener.
    } catch (_) {
      state = state.copyWith(isAcknowledging: false);
    }
  }

  /// Manually clears the local alert (e.g. after caregiver dismisses UI).
  /// Does NOT write to Firestore — use acknowledgeSupervisedOuting/escalate
  /// for those paths.
  void clearAlert() {
    state = state.copyWith(
      alertLevel: AlertLevel.none,
      clearLastEvent: true,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5.  SAFE ZONE EDITOR STATE  (for SafeZoneEditorPage)
// ─────────────────────────────────────────────────────────────────────────────

/// Holds the caregiver's in-progress edits while SafeZoneEditorPage is open.
///
/// Separate from geofenceNotifierProvider — this is local edit state, not
/// live-monitoring state. Disposed when the editor closes.

class SafeZoneEditorState {
  final LatLng? centerPoint;
  final double radiusMeters;
  final bool isLoadingExisting;
  final bool isSaving;
  final bool isFetchingGPS;
  final bool hasUnsavedChanges;

  const SafeZoneEditorState({
    this.centerPoint,
    this.radiusMeters = 300.0,
    this.isLoadingExisting = true,
    this.isSaving = false,
    this.isFetchingGPS = false,
    this.hasUnsavedChanges = false,
  });

  SafeZoneEditorState copyWith({
    LatLng? centerPoint,
    bool clearCenter = false,
    double? radiusMeters,
    bool? isLoadingExisting,
    bool? isSaving,
    bool? isFetchingGPS,
    bool? hasUnsavedChanges,
  }) {
    return SafeZoneEditorState(
      centerPoint: clearCenter ? null : (centerPoint ?? this.centerPoint),
      radiusMeters: radiusMeters ?? this.radiusMeters,
      isLoadingExisting: isLoadingExisting ?? this.isLoadingExisting,
      isSaving: isSaving ?? this.isSaving,
      isFetchingGPS: isFetchingGPS ?? this.isFetchingGPS,
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
    );
  }
}

// Family keyed by patientId — one editor instance per patient.
final safeZoneEditorProvider =
NotifierProvider.family<SafeZoneEditorNotifier, SafeZoneEditorState, String>(
  SafeZoneEditorNotifier.new,
);

class SafeZoneEditorNotifier
    extends FamilyNotifier<SafeZoneEditorState, String> {
  @override
  SafeZoneEditorState build(String patientId) {
    // Kick off async load immediately; state starts with isLoadingExisting:true
    _loadExistingZone(patientId);
    return const SafeZoneEditorState();
  }

  Future<void> _loadExistingZone(String patientId) async {
    try {
      final zone = await GeofenceService().getSafeZone(patientId);
      if (zone != null) {
        state = state.copyWith(
          centerPoint: LatLng(zone.centerLat, zone.centerLng),
          radiusMeters: zone.radiusMeters,
          isLoadingExisting: false,
        );
      } else {
        state = state.copyWith(isLoadingExisting: false);
      }
    } catch (_) {
      state = state.copyWith(isLoadingExisting: false);
    }
  }

  // ── Edit actions ───────────────────────────────────────────────────────────

  void setCenter(LatLng point) {
    state = state.copyWith(centerPoint: point, hasUnsavedChanges: true);
  }

  void setRadius(double meters) {
    state = state.copyWith(radiusMeters: meters, hasUnsavedChanges: true);
  }

  void setFetchingGPS(bool value) {
    state = state.copyWith(isFetchingGPS: value);
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  /// Persists the current center+radius to Firestore.
  /// Returns true on success, false on failure.
  Future<bool> save() async {
    final center = state.centerPoint;
    if (center == null || state.isSaving) return false;

    state = state.copyWith(isSaving: true);
    try {
      await GeofenceService().saveSafeZone(
        patientId: arg,
        centerLat: center.latitude,
        centerLng: center.longitude,
        radiusMeters: state.radiusMeters,
      );
      state = state.copyWith(isSaving: false, hasUnsavedChanges: false);
      return true;
    } catch (_) {
      state = state.copyWith(isSaving: false);
      return false;
    }
  }
}