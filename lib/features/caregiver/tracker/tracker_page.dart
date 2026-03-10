import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:neuroguard/core/services/location_service.dart';
import 'package:neuroguard/core/services/geofence_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// TrackerPage — Caregiver's Live Map View
///
/// Opened when caregiver presses the LOCATE button on CaregiverHome.
/// Shows:
///   • OpenStreetMap base layer (free, no API key)
///   • Live patient marker (auto-updates via Firestore stream)
///   • Safe zone circle (blue ring around home)
///   • Status bar at the bottom (inside/outside zone, accuracy, time)
///   • Breach alert overlay (with "It's fine" / "Not supervised" buttons)
///   • "Edit Safe Zone" button

class TrackerPage extends StatefulWidget {
  final String patientId;
  final String patientName;

  const TrackerPage({
    Key? key,
    required this.patientId,
    required this.patientName,
  }) : super(key: key);

  @override
  State<TrackerPage> createState() => _TrackerPageState();
}

class _TrackerPageState extends State<TrackerPage>
    with TickerProviderStateMixin {
  // ─── Map Controller ────────────────────────────────────────────────────────
  final MapController _mapController = MapController();
  bool _mapReady = false;

  // ─── Stream Subscriptions ─────────────────────────────────────────────────
  late StreamSubscription<GeofenceEvent> _geofenceSubscription;

  // ─── State ────────────────────────────────────────────────────────────────
  LocationSnapshot? _patientLocation;
  SafeZoneModel? _safeZone;
  bool _showBreachOverlay = false;
  bool _isLoadingLocation = true;
  String? _errorMessage;

  // Animation for the pulsing patient marker
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Animation for breach overlay slide-in
  late AnimationController _overlayController;
  late Animation<Offset> _overlaySlide;

  // ─── NeuroGuard Colour Palette ─────────────────────────────────────────────
  static const Color _purple = Color(0xFF7B2FBE);
  static const Color _green = Color(0xFF9BFF4F);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _darkBg = Color(0xFF0D0D1A);
  static const Color _cardBg = Color(0xFF1A1A2E);
  static const Color _alertRed = Color(0xFFFF3B3B);
  static const Color _safeGreen = Color(0xFF2DD4BF);
  static const Color _warningAmber = Color(0xFFFFB84D);

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startGeofenceListener();
  }

  void _setupAnimations() {
    // Pulsing ring around patient marker
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.4).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Breach overlay slides up from bottom
    _overlayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _overlaySlide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _overlayController, curve: Curves.easeOutCubic),
    );
  }

  void _startGeofenceListener() {
    _geofenceSubscription = GeofenceService().eventStream.listen((event) {
      if (event.patientId != widget.patientId) return;

      if (event.isExitEvent) {
        setState(() => _showBreachOverlay = true);
        _overlayController.forward();
      } else if (event.isEnterEvent || event.type == GeofenceEventType.acknowledgedSafe) {
        _dismissBreachOverlay();
      } else if (event.isEscalated) {
        _dismissBreachOverlay();
        _showRedAlertSnackbar();
      }
    });
  }

  void _dismissBreachOverlay() {
    _overlayController.reverse().then((_) {
      if (mounted) setState(() => _showBreachOverlay = false);
    });
  }

  void _showRedAlertSnackbar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _alertRed,
        duration: const Duration(seconds: 8),
        content: const Row(
          children: [
            Icon(Icons.warning_rounded, color: Colors.white),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'RED ALERT: Unsupervised patient outside safe zone',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _overlayController.dispose();
    _geofenceSubscription.cancel();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkBg,
      body: Stack(
        children: [
          // ── Main Map (full screen) ──────────────────────────────────────
          _buildMapLayer(),

          // ── Top Bar (back button + title) ──────────────────────────────
          _buildTopBar(),

          // ── Bottom Status Card ──────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildStatusCard(),
          ),

          // ── Breach Alert Overlay (slides up when patient exits zone) ───
          if (_showBreachOverlay)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SlideTransition(
                position: _overlaySlide,
                child: _buildBreachOverlay(),
              ),
            ),

          // ── Loading overlay ─────────────────────────────────────────────
          if (_isLoadingLocation) _buildLoadingOverlay(),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // MAP LAYER
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildMapLayer() {
    // We use TWO streams combined:
    //   Stream 1 → patient location (moves the marker)
    //   Stream 2 → safe zone data (draws the circle)
    return StreamBuilder<LocationSnapshot?>(
      stream: LocationService.streamPatientLocation(widget.patientId),
      builder: (context, locationSnapshot) {
        return StreamBuilder<SafeZoneModel?>(
          stream: GeofenceService().streamSafeZone(widget.patientId),
          builder: (context, zoneSnapshot) {
            // Update state from streams
            final location = locationSnapshot.data;
            final safeZone = zoneSnapshot.data;

            // On first data received, stop loading
            if (_isLoadingLocation && location != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _isLoadingLocation = false);
              });
            }

            // Default center (Mumbai) if no location yet
            final LatLng patientLatLng = location != null
                ? LatLng(location.latitude, location.longitude)
                : const LatLng(19.0760, 72.8777);

            // If map is ready and we have a new location, animate to it
            if (_mapReady && location != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _mapController.move(patientLatLng, _mapController.camera.zoom);
              });
            }

            return FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: patientLatLng,
                initialZoom: 16.0,
                minZoom: 10.0,
                maxZoom: 20.0,
                onMapReady: () => setState(() => _mapReady = true),
              ),
              children: [
                // ── OpenStreetMap base tiles ──────────────────────────────
                TileLayer(
                  urlTemplate:
                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.yourteam.neuroguard',
                  // Caches tiles for offline use
                  maxNativeZoom: 19,
                ),

                // ── Safe Zone Circle ─────────────────────────────────────
                if (safeZone != null)
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: LatLng(safeZone.centerLat, safeZone.centerLng),
                        radius: safeZone.radiusMeters,
                        useRadiusInMeter: true,
                        color: safeZone.isInsideZone
                            ? _safeGreen.withOpacity(0.12)
                            : _alertRed.withOpacity(0.15),
                        borderColor: safeZone.isInsideZone
                            ? _safeGreen
                            : _alertRed,
                        borderStrokeWidth: 2.5,
                      ),
                    ],
                  ),

                // ── Safe Zone Center Pin ──────────────────────────────────
                if (safeZone != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(safeZone.centerLat, safeZone.centerLng),
                        width: 32,
                        height: 32,
                        child: Container(
                          decoration: BoxDecoration(
                            color: _safeGreen.withOpacity(0.2),
                            shape: BoxShape.circle,
                            border: Border.all(color: _safeGreen, width: 1.5),
                          ),
                          child: const Icon(
                            Icons.home_rounded,
                            color: _safeGreen,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),

                // ── GPS Accuracy Ring ─────────────────────────────────────
                if (location != null && location.accuracy > 0)
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: patientLatLng,
                        radius: location.accuracy,
                        useRadiusInMeter: true,
                        color: _purple.withOpacity(0.1),
                        borderColor: _purple.withOpacity(0.4),
                        borderStrokeWidth: 1,
                      ),
                    ],
                  ),

                // ── Patient Marker (pulsing dot) ──────────────────────────
                if (location != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: patientLatLng,
                        width: 56,
                        height: 56,
                        child: _buildPatientMarker(safeZone),
                      ),
                    ],
                  ),
              ],
            );
          },
        );
      },
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PATIENT MARKER WIDGET
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildPatientMarker(SafeZoneModel? safeZone) {
    final bool isOutside = safeZone != null && !safeZone.isInsideZone;
    final Color markerColor = isOutside ? _alertRed : _purple;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Pulsing outer ring
            Transform.scale(
              scale: _pulseAnimation.value,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: markerColor.withOpacity(0.2),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: markerColor.withOpacity(0.5),
                    width: 1.5,
                  ),
                ),
              ),
            ),
            // Inner solid dot
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: markerColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: markerColor.withOpacity(0.6),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.person,
                color: Colors.white,
                size: 13,
              ),
            ),
          ],
        );
      },
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TOP BAR
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        // Gradient overlay so buttons are readable over map
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _darkBg.withOpacity(0.95),
              _darkBg.withOpacity(0.0),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 32),
            child: Row(
              children: [
                // Back button
                _mapIconButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => Navigator.pop(context),
                ),

                const SizedBox(width: 12),

                // Title
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Live Location',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        widget.patientName,
                        style: const TextStyle(
                          color: _white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),

                // Centre map on patient button
                _mapIconButton(
                  icon: Icons.my_location_rounded,
                  onTap: _centreOnPatient,
                ),

                const SizedBox(width: 8),

                // Edit safe zone button
                _mapIconButton(
                  icon: Icons.edit_location_alt_rounded,
                  onTap: _openSafeZoneEditor,
                  color: _green,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _mapIconButton({
    required IconData icon,
    required VoidCallback onTap,
    Color color = Colors.white,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _cardBg.withOpacity(0.9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // BOTTOM STATUS CARD
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildStatusCard() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _patientDocStream,
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final locationData = data?['liveLocation'] as Map<String, dynamic>?;
        final safeZoneData = data?['safeZone'] as Map<String, dynamic>?;

        final bool isInsideZone = safeZoneData?['isInsideZone'] ?? true;
        final double distanceFromCenter =
            (safeZoneData?['distanceFromCenter'] as num?)?.toDouble() ?? 0.0;
        final double accuracy =
            (locationData?['accuracy'] as num?)?.toDouble() ?? 0.0;
        final Timestamp? ts = locationData?['timestamp'] as Timestamp?;
        final DateTime? lastUpdated = ts?.toDate();

        final String timeLabel = lastUpdated == null
            ? 'Fetching...'
            : _formatTimeAgo(lastUpdated);

        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isInsideZone
                  ? _safeGreen.withOpacity(0.3)
                  : _alertRed.withOpacity(0.5),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Zone Status Row ─────────────────────────────────────────
              Row(
                children: [
                  // Status indicator dot
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: isInsideZone ? _safeGreen : _alertRed,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (isInsideZone ? _safeGreen : _alertRed)
                              .withOpacity(0.6),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isInsideZone
                          ? 'Inside Safe Zone'
                          : 'Outside Safe Zone  •  ${GeofenceService.formatDistance(distanceFromCenter)} from home',
                      style: TextStyle(
                        color: isInsideZone ? _safeGreen : _alertRed,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // ── Stats Row ────────────────────────────────────────────────
              Row(
                children: [
                  _statChip(
                    icon: Icons.access_time_rounded,
                    label: 'Updated',
                    value: timeLabel,
                  ),
                  const SizedBox(width: 8),
                  _statChip(
                    icon: Icons.gps_fixed_rounded,
                    label: 'Accuracy',
                    value: accuracy > 0
                        ? '±${accuracy.toStringAsFixed(0)}m'
                        : '—',
                  ),
                  const SizedBox(width: 8),
                  _statChip(
                    icon: Icons.place_rounded,
                    label: 'Distance',
                    value: GeofenceService.formatDistance(distanceFromCenter),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.white38, size: 11),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // BREACH ALERT OVERLAY
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildBreachOverlay() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 140),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0A0A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _alertRed.withOpacity(0.7), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _alertRed.withOpacity(0.25),
            blurRadius: 24,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Alert Header ────────────────────────────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _alertRed.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: _alertRed,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Safe Zone Breach',
                      style: TextStyle(
                        color: _alertRed,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    Text(
                      'Patient has moved outside the designated area',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Question ─────────────────────────────────────────────────────
          const Text(
            'Is this a supervised outing?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),

          const SizedBox(height: 12),

          // ── Action Buttons ────────────────────────────────────────────────
          Row(
            children: [
              // "It's fine" button
              Expanded(
                child: _alertActionButton(
                  label: "✅  It's fine",
                  sublabel: 'Supervised outing',
                  color: _safeGreen,
                  onTap: () => _handleBreachAcknowledgement(supervised: true),
                ),
              ),
              const SizedBox(width: 10),
              // "Not supervised" button
              Expanded(
                child: _alertActionButton(
                  label: '🚨  Not supervised',
                  sublabel: 'Escalate to red alert',
                  color: _alertRed,
                  onTap: () => _handleBreachAcknowledgement(supervised: false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _alertActionButton({
    required String label,
    required String sublabel,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sublabel,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // LOADING OVERLAY
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildLoadingOverlay() {
    return Container(
      color: _darkBg.withOpacity(0.85),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                color: _purple,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Locating patient...',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Waiting for GPS signal',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ACTIONS
  // ──────────────────────────────────────────────────────────────────────────

  void _centreOnPatient() async {
    final location =
    await LocationService.getPatientLocation(widget.patientId);
    if (location != null && _mapReady) {
      _mapController.move(
        LatLng(location.latitude, location.longitude),
        17.0,
      );
    }
  }

  void _openSafeZoneEditor() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SafeZoneEditorPage(patientId: widget.patientId),
      ),
    );
  }

  void _handleBreachAcknowledgement({required bool supervised}) {
    if (supervised) {
      GeofenceService()
          .acknowledgeBreachAsSafe(widget.patientId)
          .then((_) => _dismissBreachOverlay());
    } else {
      GeofenceService()
          .escalateToRedAlert(widget.patientId)
          .then((_) => _dismissBreachOverlay());
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ──────────────────────────────────────────────────────────────────────────

  Stream<DocumentSnapshot> get _patientDocStream => FirebaseFirestore.instance
      .collection('users')
      .doc(widget.patientId)
      .snapshots();

  String _formatTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}

// ─── Firestore import (needed for DocumentSnapshot in status card) ────────────


// ══════════════════════════════════════════════════════════════════════════════
// SAFE ZONE EDITOR PAGE
// ══════════════════════════════════════════════════════════════════════════════

/// SafeZoneEditorPage
/// Caregiver taps on the map to place the zone center,
/// then uses a slider to set the radius.

class SafeZoneEditorPage extends StatefulWidget {
  final String patientId;

  const SafeZoneEditorPage({Key? key, required this.patientId})
      : super(key: key);

  @override
  State<SafeZoneEditorPage> createState() => _SafeZoneEditorPageState();
}

class _SafeZoneEditorPageState extends State<SafeZoneEditorPage> {
  final MapController _mapController = MapController();

  LatLng? _centerPoint;
  double _radiusMeters = 300.0;
  bool _isSaving = false;
  bool _isLoadingExisting = true;

  static const Color _purple = Color(0xFF7B2FBE);
  static const Color _green = Color(0xFF9BFF4F);
  static const Color _darkBg = Color(0xFF0D0D1A);
  static const Color _cardBg = Color(0xFF1A1A2E);
  static const Color _safeGreen = Color(0xFF2DD4BF);

  @override
  void initState() {
    super.initState();
    _loadExistingZone();
  }

  Future<void> _loadExistingZone() async {
    final zone = await GeofenceService().getSafeZone(widget.patientId);
    if (zone != null && mounted) {
      setState(() {
        _centerPoint = LatLng(zone.centerLat, zone.centerLng);
        _radiusMeters = zone.radiusMeters;
        _isLoadingExisting = false;
      });
    } else {
      if (mounted) setState(() => _isLoadingExisting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkBg,
      body: Stack(
        children: [
          // ── Map ──────────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _centerPoint ?? const LatLng(19.0760, 72.8777),
              initialZoom: 15.0,
              // When caregiver taps the map, place zone center
              onTap: (tapPosition, latLng) {
                setState(() => _centerPoint = latLng);
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.yourteam.neuroguard',
              ),
              // Safe zone preview circle
              if (_centerPoint != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _centerPoint!,
                      radius: _radiusMeters,
                      useRadiusInMeter: true,
                      color: _safeGreen.withOpacity(0.15),
                      borderColor: _safeGreen,
                      borderStrokeWidth: 2.5,
                    ),
                  ],
                ),
              // Center pin
              if (_centerPoint != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _centerPoint!,
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _safeGreen.withOpacity(0.2),
                          shape: BoxShape.circle,
                          border:
                          Border.all(color: _safeGreen, width: 2),
                        ),
                        child: const Icon(
                          Icons.home_rounded,
                          color: _safeGreen,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // ── Top Bar ──────────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _darkBg.withOpacity(0.95),
                    _darkBg.withOpacity(0.0),
                  ],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _cardBg.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: const Icon(Icons.arrow_back_rounded,
                              color: Colors.white, size: 20),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'TAP MAP TO SET CENTER',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 10,
                                letterSpacing: 1.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Edit Safe Zone',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Bottom Panel ──────────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: Colors.white10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 30,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Radius label
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Safe Zone Radius',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: _safeGreen.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: _safeGreen.withOpacity(0.4)),
                        ),
                        child: Text(
                          '${_radiusMeters.round()}m',
                          style: const TextStyle(
                            color: _safeGreen,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Radius slider (50m to 1000m)
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: _safeGreen,
                      inactiveTrackColor: Colors.white12,
                      thumbColor: _safeGreen,
                      overlayColor: _safeGreen.withOpacity(0.2),
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 10),
                      trackHeight: 4,
                    ),
                    child: Slider(
                      value: _radiusMeters,
                      min: 50,
                      max: 1000,
                      divisions: 38,
                      onChanged: (value) =>
                          setState(() => _radiusMeters = value),
                    ),
                  ),

                  // Range labels
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('50m',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 11)),
                      Text('1000m',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 11)),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Instruction if no center set
                  if (_centerPoint == null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: Colors.amber.withOpacity(0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.touch_app_rounded,
                              color: Colors.amber, size: 18),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Tap anywhere on the map to place the safe zone center',
                              style: TextStyle(
                                  color: Colors.amber, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _centerPoint == null || _isSaving
                          ? null
                          : _saveSafeZone,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: _darkBg,
                        disabledBackgroundColor: Colors.white12,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: _isSaving
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.black),
                      )
                          : const Text(
                        'Save Safe Zone',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Loading overlay
          if (_isLoadingExisting)
            Container(
              color: _darkBg.withOpacity(0.7),
              child: const Center(
                child: CircularProgressIndicator(color: _purple),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _saveSafeZone() async {
    if (_centerPoint == null) return;

    setState(() => _isSaving = true);

    try {
      await GeofenceService().saveSafeZone(
        patientId: widget.patientId,
        centerLat: _centerPoint!.latitude,
        centerLng: _centerPoint!.longitude,
        radiusMeters: _radiusMeters,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: _safeGreen,
            content: const Text(
              '✅  Safe zone saved successfully',
              style: TextStyle(
                  color: Colors.black, fontWeight: FontWeight.w700),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFFFF3B3B),
            content: Text('Failed to save. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}