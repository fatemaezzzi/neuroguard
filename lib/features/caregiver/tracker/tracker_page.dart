// lib/features/tracker/tracker_page.dart
//
// TrackerPage — rewired to consume Riverpod providers.
//
// CHANGES FROM ORIGINAL
//   • Extends ConsumerStatefulWidget / ConsumerState (was StatefulWidget)
//   • ALL StreamBuilder nesting removed — replaced with ref.watch()
//   • _patientLocation / _safeZone / _showBreachOverlay / _isLoadingLocation
//     state fields REMOVED — driven by providers now
//   • _caregiverLocSub + _startCaregiverLocationTracking() REMOVED — replaced
//     by caregiverPositionProvider
//   • _geofenceSubscription REMOVED — replaced by ref.listen on
//     geofenceNotifierProvider (only animation side-effect stays in widget)
//   • _handleBreachAcknowledgement() now delegates to GeofenceNotifier
//   • Everything else (animations, markers, map, palette) is UNCHANGED
//
// SURGICAL SCOPE: no changes to services, models, or alert_dialog.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:neuroguard/core/providers/location_providers.dart';
import 'package:neuroguard/core/services/geofence_service.dart';
import 'package:neuroguard/core/services/location_service.dart';
import 'package:neuroguard/features/caregiver/tracker/safezone_editor.dart';

class TrackerPage extends ConsumerStatefulWidget {
  final String patientId;
  final String patientName;

  const TrackerPage({
    Key? key,
    required this.patientId,
    required this.patientName,
  }) : super(key: key);

  @override
  ConsumerState<TrackerPage> createState() => _TrackerPageState();
}

class _TrackerPageState extends ConsumerState<TrackerPage>
    with TickerProviderStateMixin {
  // ─── Map ──────────────────────────────────────────────────────────────────
  final MapController _mapController = MapController();
  bool _mapReady = false;

  // ─── Animations ───────────────────────────────────────────────────────────
  late AnimationController _pulseController;
  late Animation<double>   _pulseAnimation;
  late AnimationController _overlayController;
  late Animation<Offset>   _overlaySlide;

  // ─── Local overlay visibility (animation concern only) ────────────────────
  // All LOGIC is in GeofenceNotifier. This bool only controls whether the
  // breach overlay widget is in the tree during the slide animation.
  bool _overlayInTree = false;

  // ─── Palette ──────────────────────────────────────────────────────────────
  static const Color _purple       = Color(0xFF7B2FBE);
  static const Color _green        = Color(0xFF9BFF4F);
  static const Color _white        = Color(0xFFFFFFFF);
  static const Color _darkBg       = Color(0xFF0D0D1A);
  static const Color _cardBg       = Color(0xFF1A1A2E);
  static const Color _alertRed     = Color(0xFFFF3B3B);
  static const Color _safeGreen    = Color(0xFF2DD4BF);
  static const Color _warningAmber = Color(0xFFFFB84D);

  // ──────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _setupAnimations();
  }

  void _setupAnimations() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.4).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

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

  @override
  void dispose() {
    _pulseController.dispose();
    _overlayController.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // ── React to geofence state changes (animation side-effects only) ────────
    //
    // ref.listen fires whenever geofenceNotifierProvider emits a new state.
    // We only touch animation / overlay visibility here — no setState for
    // alert logic.
    ref.listen<GeofenceState>(
      geofenceNotifierProvider(widget.patientId),
          (previous, next) {
        if (previous?.alertLevel == next.alertLevel) return;

        if (next.alertLevel == AlertLevel.breach) {
          setState(() => _overlayInTree = true);
          _overlayController.forward();
        } else if (next.alertLevel == AlertLevel.resolved ||
            next.alertLevel == AlertLevel.none) {
          _dismissBreachOverlay();
        } else if (next.alertLevel == AlertLevel.red) {
          _dismissBreachOverlay();
          _showRedAlertSnackbar();
        }
      },
    );

    // ── Read providers ────────────────────────────────────────────────────────
    final locationAsync  = ref.watch(locationStreamProvider(widget.patientId));
    final zoneAsync      = ref.watch(safeZoneStreamProvider(widget.patientId));
    final caregiverAsync = ref.watch(caregiverPositionProvider);
    final geofenceState  = ref.watch(geofenceNotifierProvider(widget.patientId));

    final location      = locationAsync.valueOrNull;
    final safeZone      = zoneAsync.valueOrNull;
    final caregiverPos  = caregiverAsync.valueOrNull;
    final isLoading     = locationAsync.isLoading && location == null;

    return Scaffold(
      backgroundColor: _darkBg,
      body: Stack(
        children: [
          _buildMapLayer(location, safeZone, caregiverPos),
          _buildTopBar(location, safeZone),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: _buildStatusCard(location, safeZone),
          ),
          if (_overlayInTree)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: SlideTransition(
                position: _overlaySlide,
                child: _buildBreachOverlay(geofenceState),
              ),
            ),
          if (isLoading) _buildLoadingOverlay(),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // MAP LAYER
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildMapLayer(
      LocationSnapshot? location,
      SafeZoneModel? safeZone,
      LatLng? caregiverPos,
      ) {
    // Map centre: use patient location, fall back to Mumbai
    final LatLng mapCenter = location != null
        ? LatLng(location.latitude, location.longitude)
        : const LatLng(19.0760, 72.8777);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: mapCenter,
        initialZoom: 16.0,
        minZoom: 10.0,
        maxZoom: 20.0,
        onMapReady: () => setState(() => _mapReady = true),
      ),
      children: [
        // ── OSM base tiles ─────────────────────────────────────────────
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.yourteam.neuroguard',
          maxNativeZoom: 19,
        ),

        // ── Safe zone fill + border ────────────────────────────────────
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
                borderColor:
                safeZone.isInsideZone ? _safeGreen : _alertRed,
                borderStrokeWidth: 2.5,
              ),
            ],
          ),

        // ── Home / safe zone center pin ────────────────────────────────
        if (safeZone != null)
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(safeZone.centerLat, safeZone.centerLng),
                width: 64, height: 80,
                child: _buildHomePin(),
              ),
            ],
          ),

        // ── GPS accuracy halo ──────────────────────────────────────────
        if (location != null && location.accuracy > 0)
          CircleLayer(
            circles: [
              CircleMarker(
                point: LatLng(location.latitude, location.longitude),
                radius: location.accuracy,
                useRadiusInMeter: true,
                color: _purple.withOpacity(0.1),
                borderColor: _purple.withOpacity(0.4),
                borderStrokeWidth: 1,
              ),
            ],
          ),

        // ── Patient marker ─────────────────────────────────────────────
        MarkerLayer(
          markers: [
            Marker(
              point: location != null
                  ? LatLng(location.latitude, location.longitude)
                  : mapCenter,
              width: 80, height: 88,
              child: location != null
                  ? _buildPatientMarker(safeZone)
                  : _buildSearchingMarker(),
            ),
          ],
        ),

        // ── Caregiver "YOU" dot ────────────────────────────────────────
        if (caregiverPos != null)
          MarkerLayer(
            markers: [
              Marker(
                point: caregiverPos,
                width: 72, height: 72,
                child: _buildCaregiverMarker(),
              ),
            ],
          ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // MARKER WIDGETS  (unchanged from original)
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildPatientMarker(SafeZoneModel? safeZone) {
    final bool  isOutside = safeZone != null && !safeZone.isInsideZone;
    final Color dotColor  = isOutside ? _alertRed : _purple;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (_, __) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color:  dotColor.withOpacity(0.18),
                    shape:  BoxShape.circle,
                    border: Border.all(
                        color: dotColor.withOpacity(0.5), width: 1.5),
                  ),
                ),
              ),
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color:  dotColor,
                  shape:  BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                        color: dotColor.withOpacity(0.65),
                        blurRadius: 10,
                        spreadRadius: 3),
                  ],
                ),
                child: const Icon(Icons.person_rounded,
                    color: Colors.white, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: dotColor,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 4,
                    offset: const Offset(0, 2)),
              ],
            ),
            child: Text(
              widget.patientName.toUpperCase(),
              style: const TextStyle(
                color: Colors.white, fontSize: 10,
                fontWeight: FontWeight.w900, letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomePin() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: _safeGreen,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                  color: _safeGreen.withOpacity(0.55),
                  blurRadius: 14, spreadRadius: 3),
            ],
          ),
          child: const Icon(Icons.home_rounded, color: Colors.white, size: 26),
        ),
        Container(width: 3, height: 10, color: _safeGreen),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: _safeGreen,
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 4,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: const Text('HOME',
              style: TextStyle(
                  color: Colors.white, fontSize: 9,
                  fontWeight: FontWeight.w900, letterSpacing: 0.8)),
        ),
      ],
    );
  }

  Widget _buildCaregiverMarker() {
    const Color teal = Color(0xFF00BCD4);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: teal, shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                  color: teal.withOpacity(0.6),
                  blurRadius: 10, spreadRadius: 2),
            ],
          ),
          child: const Icon(Icons.visibility_rounded,
              color: Colors.white, size: 20),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: teal,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text('YOU',
              style: TextStyle(
                  color: Colors.white, fontSize: 9,
                  fontWeight: FontWeight.w900, letterSpacing: 0.8)),
        ),
      ],
    );
  }

  Widget _buildSearchingMarker() {
    return Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: Colors.white10, shape: BoxShape.circle,
        border: Border.all(color: Colors.white30, width: 1.5),
      ),
      child: const Padding(
        padding: EdgeInsets.all(8),
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TOP BAR
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildTopBar(LocationSnapshot? location, SafeZoneModel? safeZone) {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end:   Alignment.bottomCenter,
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
                _mapIconButton(
                  icon:  Icons.arrow_back_rounded,
                  onTap: () => Navigator.pop(context),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Live Location',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 11,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w500)),
                      Text(widget.patientName,
                          style: const TextStyle(
                              color: _white, fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3)),
                    ],
                  ),
                ),
                _mapIconButton(
                  icon:  Icons.my_location_rounded,
                  onTap: _centreOnCaregiver,
                ),
                const SizedBox(width: 8),
                _mapIconButton(
                  icon:  Icons.person_pin_circle_rounded,
                  onTap: () => _centreOnPatient(location),
                  color: _purple,
                ),
                const SizedBox(width: 8),
                _mapIconButton(
                  icon:  Icons.home_rounded,
                  onTap: () => _centreOnHome(safeZone),
                  color: _safeGreen,
                ),
                const SizedBox(width: 8),
                _mapIconButton(
                  icon:  Icons.edit_location_alt_rounded,
                  onTap: _openSafeZoneEditor,
                  color: _warningAmber,
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
        width: 40, height: 40,
        decoration: BoxDecoration(
          color:        _cardBg.withOpacity(0.9),
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(color: Colors.white12),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // STATUS CARD
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildStatusCard(LocationSnapshot? location, SafeZoneModel? safeZone) {
    final bool   isInsideZone       = safeZone?.isInsideZone ?? true;
    final double distanceFromCenter = safeZone?.distanceFromCenter ?? 0.0;
    final double accuracy           = location?.accuracy ?? 0.0;
    final bool   isStale            = location?.isStale ?? false;
    final String timeLabel          = location == null
        ? 'Fetching…'
        : location.freshnessLabel;

    return Container(
      margin:  const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        _cardBg,
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
              offset: const Offset(0, -4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  color: isInsideZone ? _safeGreen : _alertRed,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: (isInsideZone ? _safeGreen : _alertRed)
                            .withOpacity(0.6),
                        blurRadius: 6, spreadRadius: 1),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isInsideZone
                      ? 'Inside Safe Zone'
                      : 'Outside Safe Zone  •  '
                      '${GeofenceService.formatDistance(distanceFromCenter)} from home',
                  style: TextStyle(
                    color: isInsideZone ? _safeGreen : _alertRed,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              if (isStale)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color:  _warningAmber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: _warningAmber.withOpacity(0.4)),
                  ),
                  child: const Text(
                    'STALE GPS',
                    style: TextStyle(
                        color: _warningAmber,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _statChip(
                icon:  Icons.access_time_rounded,
                label: 'Updated',
                value: timeLabel,
              ),
              const SizedBox(width: 8),
              _statChip(
                icon:  Icons.gps_fixed_rounded,
                label: 'Accuracy',
                value: accuracy > 0
                    ? '±${accuracy.toStringAsFixed(0)}m'
                    : '—',
              ),
              const SizedBox(width: 8),
              _statChip(
                icon:  Icons.place_rounded,
                label: 'Distance',
                value: GeofenceService.formatDistance(distanceFromCenter),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statChip({
    required IconData icon,
    required String   label,
    required String   value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color:        Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border:       Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.white38, size: 11),
                const SizedBox(width: 4),
                Text(label,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 10,
                        letterSpacing: 0.5, fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(
                    color: Colors.white, fontSize: 12,
                    fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // BREACH OVERLAY
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildBreachOverlay(GeofenceState geofenceState) {
    return Container(
      margin:  const EdgeInsets.fromLTRB(12, 0, 12, 140),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color:        const Color(0xFF1A0A0A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _alertRed.withOpacity(0.7), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: _alertRed.withOpacity(0.25),
              blurRadius: 24, spreadRadius: 4),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color:        _alertRed.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    color: _alertRed, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Safe Zone Breach',
                        style: TextStyle(
                            color: _alertRed, fontSize: 15,
                            fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                    Text('Patient has moved outside the designated area',
                        style:
                        TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Is this a supervised outing?',
              style: TextStyle(
                  color: Colors.white, fontSize: 14,
                  fontWeight: FontWeight.w600, letterSpacing: 0.2)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _alertActionButton(
                  label:    "It's fine",
                  sublabel: 'Supervised outing',
                  color:    _safeGreen,
                  // Disabled while Firestore write in flight
                  onTap: geofenceState.isAcknowledging
                      ? null
                      : () => _handleBreachAcknowledgement(supervised: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _alertActionButton(
                  label:    'Not supervised',
                  sublabel: 'Escalate to red alert',
                  color:    _alertRed,
                  onTap: geofenceState.isAcknowledging
                      ? null
                      : () => _handleBreachAcknowledgement(supervised: false),
                ),
              ),
            ],
          ),
          if (geofenceState.isAcknowledging) ...[
            const SizedBox(height: 12),
            const Center(
              child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white54),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _alertActionButton({
    required String       label,
    required String       sublabel,
    required Color        color,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          decoration: BoxDecoration(
            color:        color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border:       Border.all(color: color.withOpacity(0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 2),
              Text(sublabel,
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 10)),
            ],
          ),
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
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48, height: 48,
              child: CircularProgressIndicator(color: _purple, strokeWidth: 3),
            ),
            SizedBox(height: 20),
            Text('Locating patient…',
                style: TextStyle(
                    color: Colors.white70, fontSize: 15,
                    fontWeight: FontWeight.w500, letterSpacing: 0.5)),
            SizedBox(height: 6),
            Text('Waiting for GPS signal',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ACTIONS
  // ──────────────────────────────────────────────────────────────────────────

  void _dismissBreachOverlay() {
    _overlayController.reverse().then((_) {
      if (mounted) setState(() => _overlayInTree = false);
    });
  }

  void _showRedAlertSnackbar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _alertRed,
        duration: const Duration(seconds: 6),
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
                    fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSpyCallSheet() {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (_) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A0A0A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _alertRed.withOpacity(0.6), width: 1.5),
          boxShadow: [
            BoxShadow(
                color: _alertRed.withOpacity(0.2),
                blurRadius: 24,
                spreadRadius: 4),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _alertRed.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.phone_in_talk_rounded,
                      color: _alertRed, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Emergency Alert Sent',
                          style: TextStyle(
                              color: _alertRed,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3)),
                      Text('Patient is unsupervised outside safe zone',
                          style: TextStyle(color: Colors.white54, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Do you want to initiate a Spy Call to listen in on the patient\'s surroundings?',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.4),
            ),
            const SizedBox(height: 6),
            const Text(
              'The call will connect silently — the patient\'s phone will auto-answer.',
              style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      // TODO: wire up SpyCallService.initiate(widget.patientId)
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 13, horizontal: 14),
                      decoration: BoxDecoration(
                        color: _alertRed.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: _alertRed.withOpacity(0.6)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.hearing_rounded,
                              color: _alertRed, size: 18),
                          SizedBox(width: 8),
                          Text('Start Spy Call',
                              style: TextStyle(
                                  color: _alertRed,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 13, horizontal: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.close_rounded,
                              color: Colors.white54, size: 18),
                          SizedBox(width: 8),
                          Text('Not now',
                              style: TextStyle(
                                  color: Colors.white54,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _centreOnCaregiver() {
    final caregiverPos = ref.read(caregiverPositionProvider).valueOrNull;
    if (caregiverPos != null && _mapReady) {
      _mapController.move(caregiverPos, 17.0);
    }
  }

  void _centreOnPatient(LocationSnapshot? location) {
    if (location != null && _mapReady) {
      _mapController.move(
        LatLng(location.latitude, location.longitude), 17.0,
      );
    }
  }

  void _centreOnHome(SafeZoneModel? safeZone) {
    if (safeZone != null && _mapReady) {
      _mapController.move(
          LatLng(safeZone.centerLat, safeZone.centerLng), 17.0);
    }
  }

  void _openSafeZoneEditor() {
    final location = ref.read(locationStreamProvider(widget.patientId)).valueOrNull;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SafeZoneEditorPage(
          patientId:   widget.patientId,
          patientName: widget.patientName,
        ),
      ),
    );
  }

  /// Delegates to GeofenceNotifier — no direct service calls from UI.
  void _handleBreachAcknowledgement({required bool supervised}) {
    final notifier = ref.read(geofenceNotifierProvider(widget.patientId).notifier);
    if (supervised) {
      // Dismiss the overlay immediately — the patient stays outside physically,
      // so isInsideZone never flips and the ref.listen resolved path won't fire.
      _dismissBreachOverlay();
      notifier.acknowledgeSupervisedOuting();
    } else {
      // escalate() will cause ref.listen to hit AlertLevel.red → dismiss + snackbar.
      // After that we show the spy call prompt.
      notifier.escalate();
      // Small delay so the overlay slide-out animation starts before the sheet appears.
      Future.delayed(const Duration(milliseconds: 400), _showSpyCallSheet);
    }
  }
}