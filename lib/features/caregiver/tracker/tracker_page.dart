import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:neuroguard/core/services/location_service.dart';
import 'package:neuroguard/core/services/geofence_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

/// TrackerPage — Caregiver's Live Map View
///
/// ── BUGS FIXED ────────────────────────────────────────────────────────────
///
/// BUG 1 (Critical — patient marker never appears)
///   _patientDocStream was a computed getter, not a stored field:
///     Stream<DocumentSnapshot> get _patientDocStream => Firestore...snapshots()
///   Every call to .snapshots() inside a getter creates a BRAND NEW Firestore
///   listener. StreamBuilder calls the stream getter on every rebuild — so
///   the status card was tearing down and recreating its listener on every
///   setState(), causing a null gap on every reconnect. During that gap the
///   patient location data was null, which hid the marker.
///   Fix: store the stream as a `late final` field, initialised once in
///   initState().
///
/// BUG 2 (Critical — patient marker hidden when location is null)
///   The entire MarkerLayer for the patient was guarded by:
///     if (location != null) MarkerLayer(...)
///   During the Firestore stream reconnect gap (caused by BUG 1) or on
///   first load before data arrives, location is null and the layer
///   disappears completely. The caregiver sees an empty map with no
///   indication that the system is working.
///   Fix: always render the MarkerLayer. When location is null, show a
///   "Searching…" spinner marker at the map centre so the caregiver can
///   confirm the stream is wired and simply waiting for data.
///
/// BUG 3 (UX — loading overlay never cleared on stale Firestore data)
///   _isLoadingLocation was only cleared when location changed (latitude
///   comparison). If Firestore already had data from a previous session,
///   the first StreamBuilder emission had the same coordinates, the
///   comparison failed, and the loading overlay stayed visible forever.
///   Fix: clear _isLoadingLocation on the first emission that has data,
///   regardless of whether the coordinates differ from the cached value.
///
/// BUG 4 (UX — no visual indication of stale GPS on caregiver card)
///   The status card showed "Updated: Xm ago" but gave no warning when
///   the location data was flagged isStale:true (GPS unavailable, using
///   last-known position). Added a "STALE GPS" amber badge.
/// ──────────────────────────────────────────────────────────────────────────

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

  // ─── Streams ──────────────────────────────────────────────────────────────
  late StreamSubscription<GeofenceEvent> _geofenceSubscription;

  // FIX (BUG 1): Stored as a field initialised once in initState().
  // A getter recreates the stream on every build() call, causing
  // StreamBuilder to reconnect and flash null on every setState().
  late final Stream<DocumentSnapshot> _patientDocStream;

  // ─── State ────────────────────────────────────────────────────────────────
  LocationSnapshot? _patientLocation;
  SafeZoneModel?    _safeZone;
  bool _showBreachOverlay  = false;
  bool _isLoadingLocation  = true;

  // Caregiver's own GPS — shown as a distinct teal "YOU" dot
  LatLng? _caregiverPos;
  StreamSubscription<Position>? _caregiverLocSub;

  // ─── Animations ───────────────────────────────────────────────────────────
  late AnimationController _pulseController;
  late Animation<double>   _pulseAnimation;
  late AnimationController _overlayController;
  late Animation<Offset>   _overlaySlide;

  // ─── Palette ──────────────────────────────────────────────────────────────
  static const Color _purple      = Color(0xFF7B2FBE);
  static const Color _green       = Color(0xFF9BFF4F);
  static const Color _white       = Color(0xFFFFFFFF);
  static const Color _darkBg      = Color(0xFF0D0D1A);
  static const Color _cardBg      = Color(0xFF1A1A2E);
  static const Color _alertRed    = Color(0xFFFF3B3B);
  static const Color _safeGreen   = Color(0xFF2DD4BF);
  static const Color _warningAmber = Color(0xFFFFB84D);

  @override
  void initState() {
    super.initState();
    _setupAnimations();

    // FIX (BUG 1): Initialise ONCE here, not inside a getter.
    _patientDocStream = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.patientId)
        .snapshots();

    _startGeofenceListener();
    _startCaregiverLocationTracking();
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

  void _startGeofenceListener() {
    _geofenceSubscription = GeofenceService().eventStream.listen((event) {
      if (event.patientId != widget.patientId) return;
      if (event.isExitEvent) {
        setState(() => _showBreachOverlay = true);
        _overlayController.forward();
      } else if (event.isEnterEvent ||
          event.type == GeofenceEventType.acknowledgedSafe) {
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
                    fontSize: 14),
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
    _caregiverLocSub?.cancel();
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
          _buildMapLayer(),
          _buildTopBar(),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: _buildStatusCard(),
          ),
          if (_showBreachOverlay)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: SlideTransition(
                position: _overlaySlide,
                child: _buildBreachOverlay(),
              ),
            ),
          if (_isLoadingLocation) _buildLoadingOverlay(),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // MAP LAYER
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildMapLayer() {
    return StreamBuilder<LocationSnapshot?>(
      stream: LocationService.streamPatientLocation(widget.patientId),
      builder: (context, locationSnapshot) {
        return StreamBuilder<SafeZoneModel?>(
          stream: GeofenceService().streamSafeZone(widget.patientId),
          builder: (context, zoneSnapshot) {
            final location = locationSnapshot.data;
            final safeZone = zoneSnapshot.data;

            // FIX (BUG 3): Clear loading on the FIRST emission that carries
            // data, regardless of whether coordinates changed. The old code
            // used a latitude comparison and missed stale/unchanged data.
            if (locationSnapshot.hasData && _isLoadingLocation) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() {
                  _isLoadingLocation = false;
                  _patientLocation   = location;
                });
              });
            } else if (location != null &&
                location.latitude != _patientLocation?.latitude) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _patientLocation = location);
              });
            }

            // Map centre: use latest location, fall back to cached, then Mumbai
            final LatLng mapCenter = location != null
                ? LatLng(location.latitude, location.longitude)
                : (_patientLocation != null
                ? LatLng(_patientLocation!.latitude,
                _patientLocation!.longitude)
                : const LatLng(19.0760, 72.8777));

            return FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: mapCenter,
                initialZoom:   16.0,
                minZoom:       10.0,
                maxZoom:       20.0,
                onMapReady: () => setState(() => _mapReady = true),
              ),
              children: [
                // ── OSM base tiles ─────────────────────────────────────────
                TileLayer(
                  urlTemplate:
                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.yourteam.neuroguard',
                  maxNativeZoom: 19,
                ),

                // ── Safe zone fill + border ────────────────────────────────
                if (safeZone != null)
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: LatLng(
                            safeZone.centerLat, safeZone.centerLng),
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

                // ── Home / safe zone center pin (large, labelled) ─────────
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

                // ── GPS accuracy halo ──────────────────────────────────────
                if (location != null && location.accuracy > 0)
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: LatLng(
                            location.latitude, location.longitude),
                        radius: location.accuracy,
                        useRadiusInMeter: true,
                        color: _purple.withOpacity(0.1),
                        borderColor: _purple.withOpacity(0.4),
                        borderStrokeWidth: 1,
                      ),
                    ],
                  ),

                // ── Patient marker (name-badged, clearly labelled) ────────
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

                // ── Caregiver "YOU" dot ────────────────────────────────────
                if (_caregiverPos != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _caregiverPos!,
                        width: 72, height: 72,
                        child: _buildCaregiverMarker(),
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
  // MARKER WIDGETS
  // ──────────────────────────────────────────────────────────────────────────

  // ── Patient marker — large, pulsing, name-badged ─────────────────────────
  // Purple = inside safe zone   Red = outside safe zone
  // The name badge ("RAJ") makes it impossible to confuse with the caregiver.
  Widget _buildPatientMarker(SafeZoneModel? safeZone) {
    final bool  isOutside   = safeZone != null && !safeZone.isInsideZone;
    final Color dotColor    = isOutside ? _alertRed : _purple;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (_, __) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              // Pulsing outer ring
              Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color:  dotColor.withOpacity(0.18),
                    shape:  BoxShape.circle,
                    border: Border.all(color: dotColor.withOpacity(0.5), width: 1.5),
                  ),
                ),
              ),
              // Inner person circle
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color:  dotColor,
                  shape:  BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [BoxShadow(color: dotColor.withOpacity(0.65), blurRadius: 10, spreadRadius: 3)],
                ),
                child: const Icon(Icons.person_rounded, color: Colors.white, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 3),
          // ── Name badge ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color:        dotColor,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Text(
              widget.patientName.toUpperCase(),
              style: const TextStyle(
                color:      Colors.white,
                fontSize:   10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Home pin — tall, prominent, clearly labelled ───────────────────────────
  Widget _buildHomePin() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color:  _safeGreen,
            shape:  BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [BoxShadow(color: _safeGreen.withOpacity(0.55), blurRadius: 14, spreadRadius: 3)],
          ),
          child: const Icon(Icons.home_rounded, color: Colors.white, size: 26),
        ),
        // Pin tail
        Container(width: 3, height: 10, color: _safeGreen),
        // "HOME" label
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color:        _safeGreen,
            borderRadius: BorderRadius.circular(6),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 4, offset: const Offset(0, 2))],
          ),
          child: const Text('HOME', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
        ),
      ],
    );
  }

  // ── Caregiver "YOU" dot — teal, clearly distinct from patient ─────────────
  Widget _buildCaregiverMarker() {
    const Color teal = Color(0xFF00BCD4);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color:  teal,
            shape:  BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [BoxShadow(color: teal.withOpacity(0.6), blurRadius: 10, spreadRadius: 2)],
          ),
          child: const Icon(Icons.visibility_rounded, color: Colors.white, size: 20),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color:        teal,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text('YOU', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
        ),
      ],
    );
  }

  /// Shown while waiting for first location emission from Firestore.
  /// Confirms the layer is rendering and the stream is connected.
  Widget _buildSearchingMarker() {
    return Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color:  Colors.white10,
        shape:  BoxShape.circle,
        border: Border.all(color: Colors.white30, width: 1.5),
      ),
      child: const Padding(
        padding: EdgeInsets.all(8),
        child: CircularProgressIndicator(
          strokeWidth: 2, color: Colors.white54,
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // TOP BAR
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
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
                  onTap: _centreOnPatient,
                  color: _purple,
                ),
                const SizedBox(width: 8),
                _mapIconButton(
                  icon:  Icons.home_rounded,
                  onTap: _centreOnHome,
                  color: _safeGreen,
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

  Widget _buildStatusCard() {
    // FIX (BUG 1): Uses the field _patientDocStream (set once in initState)
    // instead of the old getter that recreated the stream on every rebuild.
    return StreamBuilder<DocumentSnapshot>(
      stream: _patientDocStream,
      builder: (context, snapshot) {
        final data         = snapshot.data?.data() as Map<String, dynamic>?;
        final locationData = data?['liveLocation']  as Map<String, dynamic>?;
        final safeZoneData = data?['safeZone']       as Map<String, dynamic>?;

        final bool   isInsideZone       = safeZoneData?['isInsideZone'] as bool? ?? true;
        final double distanceFromCenter = (safeZoneData?['distanceFromCenter'] as num?)?.toDouble() ?? 0.0;
        final double accuracy           = (locationData?['accuracy'] as num?)?.toDouble() ?? 0.0;
        final bool   isStale            = locationData?['isStale']   as bool? ?? false;
        final Timestamp? ts             = locationData?['timestamp'] as Timestamp?;
        final String timeLabel          = ts == null ? 'Fetching…' : _formatTimeAgo(ts.toDate());

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
                  // Status dot
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: isInsideZone ? _safeGreen : _alertRed,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: (isInsideZone ? _safeGreen : _alertRed)
                                .withOpacity(0.6),
                            blurRadius: 6,
                            spreadRadius: 1),
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
                  // FIX (BUG 4): Stale GPS warning badge
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
      },
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
                        color: Colors.white38,
                        fontSize: 10,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
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

  Widget _buildBreachOverlay() {
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
                            color: _alertRed,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3)),
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
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _alertActionButton(
                  label:    "✅  It's fine",
                  sublabel: 'Supervised outing',
                  color:    _safeGreen,
                  onTap: () =>
                      _handleBreachAcknowledgement(supervised: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _alertActionButton(
                  label:    '🚨  Not supervised',
                  sublabel: 'Escalate to red alert',
                  color:    _alertRed,
                  onTap: () =>
                      _handleBreachAcknowledgement(supervised: false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _alertActionButton({
    required String      label,
    required String      sublabel,
    required Color       color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
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
                    color: color, fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 2),
            Text(sublabel,
                style: const TextStyle(
                    color: Colors.white38, fontSize: 10)),
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
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48, height: 48,
              child: CircularProgressIndicator(
                  color: _purple, strokeWidth: 3),
            ),
            SizedBox(height: 20),
            Text('Locating patient…',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5)),
            SizedBox(height: 6),
            Text('Waiting for GPS signal',
                style:
                TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ACTIONS
  // ──────────────────────────────────────────────────────────────────────────

  // ── Caregiver live location (shown as teal "YOU" dot on map) ──────────────
  void _startCaregiverLocationTracking() {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // only update after 10m movement
    );
    _caregiverLocSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen((pos) {
      if (mounted) setState(() => _caregiverPos = LatLng(pos.latitude, pos.longitude));
    });
    // Get one immediate fix so the dot appears before the patient moves
    Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high)
        .then((pos) {
      if (mounted) setState(() => _caregiverPos = LatLng(pos.latitude, pos.longitude));
    }).catchError((_) {});
  }

  void _centreOnCaregiver() {
    if (_caregiverPos != null && _mapReady) {
      _mapController.move(_caregiverPos!, 17.0);
    }
  }

  void _centreOnHome() {
    if (_safeZone != null && _mapReady) {
      _mapController.move(
          LatLng(_safeZone!.centerLat, _safeZone!.centerLng), 17.0);
    }
  }

  void _centreOnPatient() {
    if (_patientLocation != null && _mapReady) {
      _mapController.move(
        LatLng(_patientLocation!.latitude, _patientLocation!.longitude),
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

  String _formatTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SAFE ZONE EDITOR PAGE
// ══════════════════════════════════════════════════════════════════════════════

class SafeZoneEditorPage extends StatefulWidget {
  final String patientId;
  const SafeZoneEditorPage({Key? key, required this.patientId}) : super(key: key);

  @override
  State<SafeZoneEditorPage> createState() => _SafeZoneEditorPageState();
}

class _SafeZoneEditorPageState extends State<SafeZoneEditorPage> {
  final MapController _mapController = MapController();

  LatLng? _centerPoint;
  double  _radiusMeters     = 300.0;
  bool    _isSaving         = false;
  bool    _isLoadingExisting = true;

  static const Color _purple    = Color(0xFF7B2FBE);
  static const Color _green     = Color(0xFF9BFF4F);
  static const Color _darkBg    = Color(0xFF0D0D1A);
  static const Color _cardBg    = Color(0xFF1A1A2E);
  static const Color _safeGreen = Color(0xFF2DD4BF);

  @override
  void initState() {
    super.initState();
    _loadExistingZone();
  }

  Future<void> _loadExistingZone() async {
    final zone = await GeofenceService().getSafeZone(widget.patientId);
    if (mounted) {
      setState(() {
        if (zone != null) {
          _centerPoint  = LatLng(zone.centerLat, zone.centerLng);
          _radiusMeters = zone.radiusMeters;
        }
        _isLoadingExisting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkBg,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _centerPoint ?? const LatLng(19.0760, 72.8777),
              initialZoom:   15.0,
              onTap: (_, latLng) => setState(() => _centerPoint = latLng),
            ),
            children: [
              TileLayer(
                urlTemplate:
                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.yourteam.neuroguard',
              ),
              if (_centerPoint != null)
                CircleLayer(circles: [
                  CircleMarker(
                    point: _centerPoint!,
                    radius: _radiusMeters,
                    useRadiusInMeter: true,
                    color:             _safeGreen.withOpacity(0.15),
                    borderColor:       _safeGreen,
                    borderStrokeWidth: 2.5,
                  ),
                ]),
              if (_centerPoint != null)
                MarkerLayer(markers: [
                  Marker(
                    point: _centerPoint!, width: 40, height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        color:  _safeGreen.withOpacity(0.2),
                        shape:  BoxShape.circle,
                        border: Border.all(color: _safeGreen, width: 2),
                      ),
                      child: const Icon(
                          Icons.home_rounded, color: _safeGreen, size: 20),
                    ),
                  ),
                ]),
            ],
          ),

          // Top bar
          Positioned(
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
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color:        _cardBg.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(12),
                            border:       Border.all(color: Colors.white12),
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
                            Text('TAP MAP TO SET CENTER',
                                style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 10,
                                    letterSpacing: 1.5,
                                    fontWeight: FontWeight.w600)),
                            Text('Edit Safe Zone',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom panel
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
              decoration: BoxDecoration(
                color:        _cardBg,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24)),
                border: Border.all(color: Colors.white10),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 30),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36, height: 4,
                      decoration: BoxDecoration(
                        color:        Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Safe Zone Radius',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color:  _safeGreen.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: _safeGreen.withOpacity(0.4)),
                        ),
                        child: Text('${_radiusMeters.round()}m',
                            style: const TextStyle(
                                color: _safeGreen,
                                fontSize: 14,
                                fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor:   _safeGreen,
                      inactiveTrackColor: Colors.white12,
                      thumbColor:         _safeGreen,
                      overlayColor:       _safeGreen.withOpacity(0.2),
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 10),
                      trackHeight: 4,
                    ),
                    child: Slider(
                      value:     _radiusMeters,
                      min:       50,
                      max:       1000,
                      divisions: 38,
                      onChanged: (v) => setState(() => _radiusMeters = v),
                    ),
                  ),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('50m',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 11)
                      ),
                      Text('1000m',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 11)
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_centerPoint == null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:        Colors.amber.withOpacity(0.1),
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
                  SizedBox(
                    width: double.infinity, height: 52,
                    child: ElevatedButton(
                      onPressed: _centerPoint == null || _isSaving
                          ? null
                          : _saveSafeZone,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:        _green,
                        foregroundColor:        _darkBg,
                        disabledBackgroundColor: Colors.white12,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: _isSaving
                          ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.black),
                      )
                          : const Text('Save Safe Zone',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5)),
                    ),
                  ),
                ],
              ),
            ),
          ),

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
        patientId:    widget.patientId,
        centerLat:    _centerPoint!.latitude,
        centerLng:    _centerPoint!.longitude,
        radiusMeters: _radiusMeters,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: _safeGreen,
            content: Text('✅  Safe zone saved successfully',
                style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.w700)),
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.pop(context);
      }
    } catch (_) {
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